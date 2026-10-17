import Foundation

/// A conservative, deterministic fitness heuristic. Not a metabolic measurement, a
/// validated dynamic body-composition model, or a medical prescription. All data stays local.
enum MaintenanceEngine {
    static let minimumDays = 21
    static let maximumDays = 42
    static let reviewCooldownDays = 14
    static let energyPerKG = 7700.0 // Short-window approximation; NOT exact tissue energy.

    static func evaluate(state: AppState, points: [BodyPoint], now: Date = Date(), calendar: Calendar = .current) -> MaintenanceReport {
        var r = MaintenanceReport()
        let coverage = CoverageMath.latestRun(state.dayReviews, now: now)
        if coverage.conflict {
            r.title = "Review overlapping food coverage"
            r.message = "Some confirmations cover the same real hours twice, often after a timezone change. Open Travel & food coverage to replace them with reviewed, non-overlapping intervals. No totals are added twice."
            return r
        }
        guard let covered = coverage.interval else { return r }
        let run = coverage.reviews
        r.completedDays = run.count; r.start = covered.start; r.end = covered.end
        r.elapsedDays = covered.duration / CoverageMath.day
        let usable = points.filter { $0.date.timeIntervalSince1970.isFinite && $0.date <= now }
        let window = usable.filter { $0.metric == .weight && $0.date >= max(covered.start, covered.end.addingTimeInterval(-Double(maximumDays) * CoverageMath.day)) && $0.date <= covered.end }
        let selected: [BodyPoint]
        if let id = state.maintenanceScaleLocationID {
            selected = window.filter { $0.scaleLocationID == id }
            r.scaleContext = "Selected scale: " + ScaleMath.locationName(id, locations: state.scaleLocations)
        } else if window.contains(where: { $0.scaleLocationID != nil && !$0.excludedFromTrend }) {
            selected = window.filter { $0.scaleLocationID != nil }
            let untagged = window.filter { $0.scaleLocationID == nil && !$0.excludedFromTrend }.count
            if untagged > 0 { r.scaleNotice = "\(untagged) untagged readings are not used alongside tagged scales. Tag them in Body to include them." }
        } else {
            selected = window
            r.scaleNotice = "Untagged data assumes one scale per method/source. If you switched scales, tag those readings in Body before relying on the estimate."
        }
        let series = ScaleWeightFit.elapsedSeries(selected, locations: state.scaleLocations)
        let eligibleIDs = Set(series.map(\.id))
        if selected.contains(where: { !$0.excludedFromTrend && !eligibleIDs.contains(ScaleMath.seriesID($0)) }) {
            r.scaleNotice += (r.scaleNotice.isEmpty ? "" : " ") + "Some readings need more same-scale history (3 measured days spanning a week)."
        }
        var scaleDays = ScaleMath.days(series)
        guard var fitted = ScaleWeightFit.fitElapsed(scaleDays) else {
            r.message = "Need repeated same-scale weigh-ins and at least 21 elapsed days of complete intake coverage. Each included scale needs at least 3 measured days spanning a week."
            return r
        }
        var candidates = fitted.daily
        r.weightDays = candidates.count
        let reference = series.first { $0.id == fitted.referenceID }?.label ?? "Selected scale"
        r.scaleContext = "Within-scale comparisons · \(series.count) scale/source series · weight reference: \(reference)"
        guard let first = candidates.first, let last = candidates.last else { return r }
        var from = first.date, through = last.date
        // Legacy daily snapshots have no timestamps for their calories. Keep them
        // whole instead of assuming those calories were eaten uniformly all day.
        for review in run where review.intakeEvents == nil {
            guard let interval = review.coverageInterval else { continue }
            if from > interval.start && from < interval.end { from = interval.end }
            if through > interval.start && through < interval.end { through = interval.start }
        }
        let intervalDays = through.timeIntervalSince(from) / CoverageMath.day
        r.start = from; r.end = through; r.elapsedDays = max(0, intervalDays)
        let intervalReviews = run.filter { $0.coverageInterval.map { $0.end > from && $0.start < through } == true }
        r.completedDays = intervalReviews.count
        guard intervalDays >= Double(minimumDays) - 0.000001,
              let intake = CoverageMath.total(run, from: from, to: through) else {
            r.message = "Need 21 elapsed days of confirmed food coverage bracketed by comparable weigh-ins. This window covers \(String(format: "%.1f", max(0, intervalDays))) days. Review flight-day gaps; missing hours are never treated as fasting."
            return r
        }
        // Legacy coverage may have moved the food boundaries inward. Refit the
        // weights in that same interval rather than retaining discarded days.
        scaleDays = scaleDays.filter { $0.date >= from && $0.date <= through }
        guard let matched = ScaleWeightFit.fitElapsed(scaleDays) else { return r }
        fitted = matched
        candidates = matched.daily
        r.weightDays = candidates.count
        guard let last = candidates.last else { return r }
        let matchedIDs = Set(scaleDays.map(\.seriesID))
        let matchedReference = series.first { $0.id == fitted.referenceID }?.label ?? "Selected scale"
        r.scaleContext = "Within-scale comparisons · \(matchedIDs.count) scale/source series · weight reference: \(matchedReference)"
        let requiredWeights = Int(ceil(intervalDays * 3 / 7 - 0.000001))
        let gaps = zip(candidates, candidates.dropFirst()).map { $1.date.timeIntervalSince($0.date) / CoverageMath.day } +
            [candidates[0].date.timeIntervalSince(from) / CoverageMath.day, through.timeIntervalSince(last.date) / CoverageMath.day]
        guard candidates.count >= requiredWeights, (gaps.max() ?? 0) <= 4.05 else {
            r.message = "Need at least \(requiredWeights) measured days with no gap longer than about 4 days. Found \(candidates.count). Multiple readings within one UTC date bucket count once; slopes use actual timestamps."
            return r
        }
        let longestSpan = Dictionary(grouping: scaleDays, by: \.seriesID).values.compactMap { rows -> Double? in
            let ordered = rows.sorted { $0.date < $1.date }
            guard let first = ordered.first, let last = ordered.last else { return nil }
            return last.date.timeIntervalSince(first.date) / CoverageMath.day
        }.max() ?? 0
        guard longestSpan >= Double(minimumDays) - 0.000001 else {
            r.message = "Need at least one scale with readings spanning 21 days of elapsed time. Separate short visits do not establish a common trend just by comparing their raw weights."
            return r
        }
        let fit = fitted.fit
        let avg = intake.nutrition.scaled(by: 1 / intervalDays)
        let lastWeek = candidates.filter { $0.date >= last.date.addingTimeInterval(-6 * CoverageMath.day) }
        let weight = BodyMath.median(lastWeek.map(\.value)) ?? last.value
        let weekly = fit.slope * 7, weeklyPercent = weekly / weight * 100
        r.averageIntake = avg; r.weightKG = weight; r.kgPerWeek = weekly
        // Use absolute grouping for analysis; plotting uses the original civil labels.
        var absolutePoints = usable
        for i in absolutePoints.indices { absolutePoints[i].clock = nil }
        r.waistChangeCM = waistChange(points: absolutePoints.filter { $0.date >= from && $0.date <= through }, from: from, through: through, calendar: EntryClock.utc)
        let estimate = avg.calories - fit.slope * energyPerKG
        guard estimate.isFinite, (1200...6000).contains(estimate), avg.calories >= max(1200, weight * 15), avg.calories <= 6000 else {
            r.title = "Review the inputs"
            r.message = "The records imply an implausible or very low value for this general fitness estimator. Check food, units, coverage and changes in health before using it."
            r.recommendation = "No calorie or macro change is suggested from these inputs."
            return r
        }
        let recent = scaleDays.filter { $0.date >= last.date.addingTimeInterval(-14 * CoverageMath.day) }
        let recentFit = ScaleWeightFit.fitElapsed(recent)
        let recentWeekly = (recentFit?.fit.slope ?? fit.slope) * 7
        let estimateShare = intake.estimated / max(1, intake.nutrition.calories)
        let foodAllowance = avg.calories * (0.10 + 0.10 * estimateShare)
        let trendAllowance = energyPerKG * max(abs(fit.slope - fit.lowerSlope), abs(fit.upperSlope - fit.slope))
        let tissueAllowance = abs(fit.slope) * 2000
        let recentAllowance = abs(recentWeekly / 7 - fit.slope) * energyPerKG
        let margin = max(150, foodAllowance + max(trendAllowance, recentAllowance) + tissueAllowance)
        r.estimate = round50(estimate); r.lower = max(0, floor((estimate - margin) / 50) * 50); r.upper = ceil((estimate + margin) / 50) * 50
        r.title = intervalDays >= 28 ? "Trend-based maintenance" : "Early maintenance estimate"
        r.message = "Based on \(String(format: "%.1f", intervalDays)) elapsed days and \(candidates.count) measured days. Calories are normalized per 24 hours, regardless of timezone names or flight-day length. This is a window average, not a measurement of today's metabolism."
        r.caveats = [
            "Range is a sensitivity illustration, not a confidence interval. Food errors, water changes and recomposition can move true maintenance outside it.",
            "Body fat and exercise calories are not inputs. Do not add workout calories again.",
            "Food coverage uses actual start/end times. An uncertain flight interval should be reviewed or excluded; a phone timezone change does not restart the baseline."
        ]
        if estimateShare > 0.5 { r.caveats.append("Most calories are estimates; restaurant and portion errors can shift the result.") }
        if series.count > 1 { r.caveats.append("Only same-scale weight differences are compared; differing constant baselines are not used as weight changes. Calibration drift, different weighing conditions and incorrect tags can still distort results.") }
        let scalesDisagree = fitted.groupSlopes.contains { abs($0 - fit.slope) * 7 > weight * 0.003 }
        let staleDays = now.timeIntervalSince(through) / CoverageMath.day
        let unstable = fit.residualSpread > max(0.7, weight * 0.01) ||
            abs(recentWeekly - weekly) > weight * 0.003 ||
            abs(last.value - fit.lastPrediction) > weight * 0.015 || margin > estimate * 0.30
        r.recommendationTitle = "Hold your current targets"
        if staleDays > 4 || now.timeIntervalSince(covered.end) > 4 * CoverageMath.day {
            r.recommendation = "This estimate is stale. Add recent complete food logs and weigh-ins before making a new adjustment."
            return r
        }
        if recentFit == nil || scalesDisagree {
            r.recommendationTitle = "Check comparable scale history"
            r.recommendation = "Recent same-scale history is insufficient or the scales disagree. No target change is proposed. Check tags and conditions, or select one trusted scale."
            return r
        }
        if unstable {
            r.recommendationTitle = "Trend is too uncertain to adjust"
            r.recommendation = "Recent and longer-term weights disagree or fluctuate substantially. Check hydration, travel, illness, creatine and measuring conditions. Keep collecting data rather than treating the change as tissue."
            return r
        }
        if abs(weeklyPercent) > 1 {
            r.recommendationTitle = "Review the rapid weight change"
            r.recommendation = "The trend exceeds 1% of body weight per week. This general fitness tool will not prescribe a correction. Review logs and seek clinical advice for unexplained rapid changes or symptoms."
            return r
        }
        if !state.adaptive.guidanceEnabled {
            r.recommendationTitle = "Review settings to enable suggestions"
            r.recommendation = "Enable adult fitness suggestions to review a proposed calorie/macro change. Nothing is applied automatically."
            return r
        }
        let latestChange = ([state.adaptive.lastChangedAt].compactMap { $0 } + state.targetRevisions.map(\.date)).max()
        if let changed = latestChange, now.timeIntervalSince(changed) < Double(reviewCooldownDays) * CoverageMath.day {
            r.recommendation = "Targets or coaching settings changed within the last 14 days. Let the new plan settle before another adjustment."
            return r
        }
        // Whole recent intervals: no uniform prorating of legacy food snapshots.
        var recentStart = through.addingTimeInterval(-14 * CoverageMath.day)
        for review in run where review.intakeEvents == nil {
            if let interval = review.coverageInterval, recentStart > interval.start && recentStart < interval.end { recentStart = interval.end }
        }
        let recentHours = through.timeIntervalSince(recentStart) / CoverageMath.day
        let recentTotal = CoverageMath.total(run, from: recentStart, to: through)
        let recentIntake = (recentTotal?.nutrition.calories ?? 0) / max(1, recentHours)
        if recentHours < 10 || abs(recentIntake - state.targets.calories) > max(200, state.targets.calories * 0.10) {
            r.recommendationTitle = "Review intake versus the target first"
            r.recommendation = "Recent confirmed intake is insufficient or differs substantially from the target. Review completeness and practicality before changing the target again."
            return r
        }
        let goal = state.adaptive.goal
        let waistImproving = (r.waistChangeCM ?? 0) <= -0.5
        let inBand = goal.weeklyPercentBand.contains(weeklyPercent)
        let recompProgress = goal == .recomp && waistImproving && weeklyPercent >= -0.35 && weeklyPercent <= 0.3
        var proposedCalories = state.targets.calories
        if inBand || recompProgress {
            r.recommendation = recompProgress
                ? "Waist measurements are decreasing while weight is stable or slowly changing. Keep calories steady; these signals support staying the course but do not prove muscle gain."
                : "Your weight trend is within the selected goal's tolerance. Keep calories steady; a flat scale is not automatically a recomp plateau."
        } else {
            let wantIncrease = weeklyPercent < goal.weeklyPercentBand.lowerBound
            let recentPercent = recentWeekly / weight * 100
            guard wantIncrease ? recentPercent < goal.weeklyPercentBand.lowerBound : recentPercent > goal.weeklyPercentBand.upperBound else {
                r.recommendation = "The recent two-week trend is already closer to your goal. Keep targets steady rather than reacting to older data."
                return r
            }
            let impliedTarget = estimate + weight * goal.desiredWeeklyPercent / 100 / 7 * energyPerKG
            let difference = impliedTarget - state.targets.calories
            guard wantIncrease ? difference >= 75 : difference <= -75 else {
                r.recommendation = "Weight direction and the estimated intake adjustment do not agree clearly. Hold the target and review your logs rather than making a contradictory change."
                return r
            }
            let change = min(150, max(100, abs(round50(difference)))) * (wantIncrease ? 1 : -1)
            proposedCalories = state.targets.calories + change
            r.recommendationTitle = wantIncrease ? "Consider a small calorie increase" : "Consider a small calorie reduction"
            r.recommendation = "Both the full-window and recent trends are outside your goal's tolerance. Review a \(Int(abs(change))) kcal/day \(wantIncrease ? "increase" : "reduction"), then hold it for at least 14 days. This is a heuristic suggestion, not a prescription."
        }
        // Product guardrails, not individual energy-availability or safety thresholds.
        guard proposedCalories >= max(1800, weight * 23), proposedCalories <= 5000 else {
            r.recommendationTitle = "Manual review needed"
            r.recommendation = "A proposed target falls outside this tool's conservative operating range. No change is offered; use individual guidance rather than extrapolating this heuristic."
            return r
        }
        let protein = (weight * state.adaptive.proteinPerKG / 5).rounded() * 5
        let fat = max(state.adaptive.fatGrams, ceil(weight * 0.6 / 5) * 5)
        let carbs = ((proposedCalories - 4 * protein - 9 * fat) / 4).rounded()
        guard carbs >= 75, let proposal = checkedTargets(calories: proposedCalories, protein: protein, carbs: carbs, fat: fat) else { return r }
        let needsMacroChange = abs(proposal.protein - state.targets.protein) >= 10 || abs(proposal.fat - state.targets.fat) >= 10
        if proposedCalories != state.targets.calories || needsMacroChange {
            r.proposal = proposal
            if proposedCalories == state.targets.calories {
                r.recommendationTitle = "Keep calories; review macro targets"
                r.recommendation += " The proposed macros use your recent weight and chosen protein/fat preferences; carbohydrates take the remaining calories."
            }
        }
        if let avgProtein = r.averageIntake?.protein, avgProtein < protein * 0.85 {
            r.caveats.append("Average protein intake is below your proposed protein target. Improving consistency may be more useful than changing calories.")
        }
        return r
    }

    struct Fit { var slope: Double; var lowerSlope: Double; var upperSlope: Double; var residualSpread: Double; var lastPrediction: Double }
    static func slope(_ points: [DailyBodyPoint], calendar: Calendar) -> Fit? {
        guard let first = points.first, points.count >= 3 else { return nil }
        let xy = points.map { (x: Double(calendar.dateComponents([.day], from: first.date, to: $0.date).day ?? 0), y: $0.value) }
        var slopes: [Double] = []
        for i in xy.indices {
            for j in xy.indices where j > i && xy[j].x - xy[i].x >= 7 {
                slopes.append((xy[j].y - xy[i].y) / (xy[j].x - xy[i].x))
            }
        }
        slopes.sort()
        guard let m = BodyMath.median(slopes),
              let b = BodyMath.median(xy.map { $0.y - m * $0.x }),
              let last = xy.last else { return nil }
        let spread = (BodyMath.median(xy.map { abs($0.y - (m * $0.x + b)) }) ?? 0) * 1.4826
        return Fit(slope: m, lowerSlope: slopes[Int(Double(slopes.count - 1) * 0.25)],
                   upperSlope: slopes[Int(Double(slopes.count - 1) * 0.75)], residualSpread: spread,
                   lastPrediction: m * last.x + b)
    }
    static func waistChange(points: [BodyPoint], from: Date, through: Date, calendar: Calendar) -> Double? {
        let waist = points.filter { $0.metric == .waist && !$0.excludedFromTrend && $0.date >= from && $0.date < add(1, to: through, calendar: calendar) }
        // Don't compare different scales/tape methods as if their calibration matched.
        let groups = Dictionary(grouping: waist, by: ScaleMath.seriesID)
        var changes: [(latest: Date, value: Double)] = []
        for group in groups.values {
            let daily = BodyMath.daily(group, metric: .waist, calendar: calendar)
            let early = daily.filter { $0.date < add(7, to: from, calendar: calendar) }
            let late = daily.filter { $0.date >= add(-6, to: through, calendar: calendar) }
            guard early.count >= 2, late.count >= 2,
                  let a = BodyMath.median(early.map(\.value)),
                  let b = BodyMath.median(late.map(\.value)),
                  let lastDate = late.last?.date else { continue }
            changes.append((lastDate, b - a))
        }
        return changes.sorted { $0.latest > $1.latest }.first?.value
    }
    static func checkedTargets(calories: Double, protein: Double, carbs: Double, fat: Double) -> Nutrition? {
        let n = Nutrition(calories: calories, protein: protein, carbs: carbs, fat: fat)
        return n.isValid && calories > 0 && abs(n.macroCalories - calories) <= 3 ? n : nil
    }
    static func round50(_ value: Double) -> Double { (value / 50).rounded() * 50 }
    static func add(_ days: Int, to date: Date, calendar: Calendar) -> Date {
        calendar.date(byAdding: .day, value: days, to: date) ?? date.addingTimeInterval(Double(days) * 86400)
    }
}
