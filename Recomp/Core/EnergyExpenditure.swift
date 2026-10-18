import Foundation

/// Optional inputs, not a diagnosis or a new food target. Defaults are labelled
/// product assumptions until sufficient comparable history supports calibration.
struct EnergySettings: Codable, Equatable, Sendable {
    var manualRestingKcal: Double?
    var manualRestingDate: Date?
    var manualRestingIsMeasured = false
    var untrackedMovementKcal = 150.0
    var usualDailySteps = 5000.0
    var updatedAt: Date?
    var isValid: Bool {
        (manualRestingKcal == nil) == (manualRestingDate == nil) &&
        (manualRestingKcal.map { $0.isFinite && (500...4500).contains($0) } ?? true) &&
        (manualRestingDate.map { $0.timeIntervalSince1970.isFinite } ?? true) &&
        untrackedMovementKcal.isFinite && (0...1500).contains(untrackedMovementKcal) &&
        usualDailySteps.isFinite && (0...50000).contains(usualDailySteps) &&
        (updatedAt.map { $0.timeIntervalSince1970.isFinite } ?? true)
    }
}

struct RestingEnergyEstimate: Equatable, Sendable {
    var kcalPerDay: Double
    var date: Date
    var source: String
    var fatFreeMassKG: Double?
    var isMeasured = false
    var isValid: Bool { kcalPerDay.isFinite && (500...4500).contains(kcalPerDay) && date.timeIntervalSince1970.isFinite }
}

enum RestingEnergyCalculator {
    // Cunningham 1991, REE = 370 + 21.6 × FFM. This predicts resting, not measured basal, energy.
    static func predicted(fatFreeMassKG: Double) -> Double? {
        guard fatFreeMassKG.isFinite, (10...190).contains(fatFreeMassKG) else { return nil }
        let value = 370 + 21.6 * fatFreeMassKG
        return (500...4500).contains(value) ? value : nil
    }
    static func resolve(settings: EnergySettings, points: [BodyPoint], scans: [DXAScan],
                        asOf date: Date, calendar: Calendar = .current) -> RestingEnergyEstimate? {
        guard settings.isValid else { return nil }
        if let kcal = settings.manualRestingKcal, let recorded = settings.manualRestingDate, recorded <= date {
            return RestingEnergyEstimate(kcalPerDay: kcal, date: recorded,
                source: settings.manualRestingIsMeasured ? "User-entered measured RMR" : "Manual resting-energy value",
                isMeasured: settings.manualRestingIsMeasured)
        }
        let earliest = date.addingTimeInterval(-90 * CoverageMath.day)
        var candidates: [RestingEnergyEstimate] = []
        for scan in scans where scan.isValid {
            guard let day = EntryClock.displayDate(scan.scanDay, calendar: calendar), day >= earliest, day <= date,
                  let mass = DXAHealthMapping.plan(scan).candidates.first(where: { $0.metric == .leanBodyMass }),
                  let kcal = predicted(fatFreeMassKG: mass.value) else { continue }
            candidates.append(RestingEnergyEstimate(kcalPerDay: kcal, date: day,
                source: "Cunningham 1991 · reviewed whole-body DXA", fatFreeMassKG: mass.value))
        }
        let eligible = points.filter { !$0.excludedFromTrend && $0.date >= earliest && $0.date <= date && $0.metric.accepts($0.value) }
        for fat in eligible where fat.metric == .bodyFat {
            // Pair contemporaneous values from the same scale/method. Never apply
            // an old percentage to a new weight or silently mix different scales.
            guard let weight = eligible.filter({ $0.metric == .weight &&
                $0.scaleLocationID == fat.scaleLocationID && $0.source == fat.source && $0.method == fat.method &&
                abs($0.date.timeIntervalSince(fat.date)) <= 7 * CoverageMath.day
            }).min(by: { abs($0.date.timeIntervalSince(fat.date)) < abs($1.date.timeIntervalSince(fat.date)) }) else { continue }
            let ffm = weight.value * (1 - fat.value / 100)
            guard let kcal = predicted(fatFreeMassKG: ffm) else { continue }
            candidates.append(RestingEnergyEstimate(kcalPerDay: kcal, date: max(weight.date, fat.date),
                source: "Cunningham 1991 · paired weight/body-fat estimate", fatFreeMassKG: ffm))
        }
        // Keep the reviewed DXA candidate first when dates are equal.
        return candidates.enumerated().sorted {
            $0.element.date == $1.element.date ? $0.offset < $1.offset : $0.element.date > $1.element.date
        }.first?.element
    }
}

struct DigestionEvent: Equatable, Sendable {
    var date: Date
    var kcal: Double
    var isValid: Bool { date.timeIntervalSince1970.isFinite && kcal.isFinite && kcal >= 0 }
}

enum ThermicEffect {
    /// Midpoints of the published nutrient ranges, not measured absorption.
    /// Calorie/macro discrepancies do not silently create extra food energy.
    static func calories(_ nutrition: Nutrition) -> Double {
        guard nutrition.isValid else { return 0 }
        let energy = nutrition.macroCalories
        guard nutrition.calories > 0 else { return 0 }
        guard energy > 0 else { return nutrition.calories * 0.10 }
        let known = nutrition.protein * 4 * 0.25 + nutrition.carbs * 4 * 0.075 + nutrition.fat * 9 * 0.015
        return known * min(1, nutrition.calories / energy) + max(0, nutrition.calories - energy) * 0.10
    }
    /// Eight-hour uniform release is an explicit chart-timing assumption, not an
    /// individually validated digestion curve. Integrate differences at day edges
    /// so an overnight meal is never charged its full thermogenesis twice.
    static let duration: TimeInterval = 8 * 3600
    static func accumulated(_ events: [DigestionEvent], from start: Date, through end: Date) -> Double {
        guard end > start else { return 0 }
        func fraction(_ time: Date, _ meal: Date) -> Double { min(1, max(0, time.timeIntervalSince(meal) / duration)) }
        return events.filter(\.isValid).reduce(0) {
            $0 + $1.kcal * (fraction(end, $1.date) - fraction(start, $1.date))
        }
    }
    static func events(entries: [FoodEntry], samples: [HealthNutritionSample], deletions: [DeletionTask],
                       bundleID: String, includesHealth: Bool, from start: Date, through end: Date,
                       calendar: Calendar = .current) -> [DigestionEvent] {
        var seen = Set<UUID>()
        var result = entries.filter { $0.date >= start && $0.date <= end && seen.insert($0.id).inserted }
            .map { DigestionEvent(date: $0.date, kcal: calories($0.nutrition)) }
        guard includesHealth else { return result }
        var healthIDs = Set<UUID>()
        let external = DiaryMath.externalSamples(samples, entries: entries, deletions: deletions, ownBundleID: bundleID)
            .filter { $0.date >= start && $0.date <= end && $0.value.isFinite && $0.value >= 0 && healthIDs.insert($0.id).inserted }
        // Health represents nutrients as separate samples. Sum each source/day's
        // macros first, then distribute its TEF over calorie timestamps. Treating
        // each nutrient sample as a separate meal would count unknown energy twice.
        let grouped = Dictionary(grouping: external) {
            $0.sourceBundleID + "|" + String(calendar.startOfDay(for: $0.date).timeIntervalSince1970)
        }
        for rows in grouped.values {
            var nutrition = Nutrition.zero
            for row in rows { nutrition[row.nutrient] += row.value }
            guard nutrition.isValid, nutrition.calories > 0 else { continue }
            let tef = calories(nutrition)
            for row in rows where row.nutrient == .calories {
                result.append(DigestionEvent(date: row.date, kcal: tef * row.value / nutrition.calories))
            }
        }
        return result.sorted { $0.date < $1.date }
    }
}

struct EnergyInputs: Equatable, Sendable {
    var resting: RestingEnergyEstimate
    var settings = EnergySettings()
    var meals: [DigestionEvent] = []
    var typicalNutrition: Nutrition = .startingTargets
    var confirmedFoodDays = 0.0
    var foodCoverageComplete = false
    var maintenanceAnchor: Double?
    var typicalTEF: Double { ThermicEffect.calories(typicalNutrition) }
    var isValid: Bool { resting.isValid && settings.isValid && typicalNutrition.isValid && confirmedFoodDays.isFinite && confirmedFoodDays >= 0 }
}

struct EnergyBreakdown: Equatable, Sendable {
    var resting: RestingEnergyEstimate
    var restingSoFar: Double
    var untrackedSoFar: Double
    var untrackedPerDay: Double
    var observedDigestionSoFar: Double
    var digestionAllowanceSoFar: Double
    var coveredActivityDays: Int
    var foodCoverageComplete: Bool
    var calibrationNote: String
    var intakeBasis: String
}

enum ComponentExpenditureCalculator {
    private struct Segment {
        var start: Date
        var end: Date
        var steps: Double // count/second, outside workouts
        var exercise: Double // net kcal/second
        var activeFraction: Double
        var covered: Bool
    }
    private static func segments(from start: Date, through end: Date, workouts: [WorkoutRecord],
                                 steps: [StepInterval], weight: Double, resting: Double) -> [Segment] {
        guard end > start else { return [] }
        let work = workouts.filter { $0.start < end && $0.end > start }
        let walk = steps.filter { $0.start < end && $0.end > start }
        let edges = Set([start, end] + work.flatMap { [max(start, $0.start), min(end, $0.end)] } +
                        walk.flatMap { [max(start, $0.start), min(end, $0.end)] }).sorted()
        return zip(edges, edges.dropFirst()).map { a, b in
            let overlapping = work.filter { $0.start < b && $0.end > a }
            let active = overlapping.map { min(1, $0.duration / $0.end.timeIntervalSince($0.start)) }.max() ?? 0
            let net = overlapping.map {
                max(0, IntradayBurnCalculator.workoutMET($0) * weight / 3600 - resting / CoverageMath.day) *
                    min(1, $0.duration / $0.end.timeIntervalSince($0.start))
            }.max() ?? 0
            let buckets = walk.filter { $0.start < b && $0.end > a }
            let count = overlapping.isEmpty ? buckets.map { $0.count / $0.end.timeIntervalSince($0.start) }.max() ?? 0 : 0
            return Segment(start: a, end: b, steps: count, exercise: net, activeFraction: active, covered: !buckets.isEmpty)
        }
    }
    static func calculate(reference: Double, for day: Date, now: Date, workouts: [WorkoutRecord],
                          steps: [StepDay], intervals: [StepInterval], weightKG: Double,
                          inputs: EnergyInputs, calendar: Calendar) -> IntradayBurnCurve {
        let range = DiaryMath.dayInterval(containing: day, calendar: calendar)
        let cutoff = min(range.end, max(range.start, now))
        let weight = weightKG.isFinite && (25...350).contains(weightKG) ? weightKG : 75
        let maintenance = reference.isFinite && (500...6000).contains(reference) ? reference : 2400
        let resting = inputs.resting.kcalPerDay
        var ids = Set<UUID>()
        let work = workouts.filter { $0.isValid && $0.start <= now && ids.insert($0.id).inserted }
        var buckets = intervals.filter { $0.isValid && $0.start < now && $0.end <= now }
        let recordedBuckets = buckets
        let daily = Dictionary(grouping: steps.filter { $0.isValid && $0.count <= 200000 && $0.date <= now },
            by: { calendar.startOfDay(for: $0.date) }).mapValues { $0.map(\.count).max() ?? 0 }
        for (date, count) in daily where !buckets.contains(where: { calendar.isDate($0.start, inSameDayAs: date) }) {
            let end = min(DiaryMath.dayInterval(containing: date, calendar: calendar).end, now)
            if end > date { buckets.append(StepInterval(start: date, end: end, count: count)) }
        }
        let pieces = segments(from: range.start, through: cutoff, workouts: work, steps: buckets, weight: weight, resting: resting)
        let historyStart = calendar.date(byAdding: .day, value: -14, to: range.start)!
        var history: [(walking: Double, exercise: Double, available: Double)] = []
        for date in Set(recordedBuckets.map { calendar.startOfDay(for: $0.start) }) where date >= historyStart && date < range.start {
            let r = DiaryMath.dayInterval(containing: date, calendar: calendar)
            guard r.end <= now else { continue }
            let past = segments(from: r.start, through: r.end, workouts: work, steps: buckets, weight: weight, resting: resting)
            let recorded = segments(from: r.start, through: r.end, workouts: [], steps: recordedBuckets, weight: weight, resting: resting)
            let covered = recorded.filter(\.covered).reduce(0) { $0 + $1.end.timeIntervalSince($1.start) }
            // Coverage proxy, not proof of device wear. A single partial bucket
            // cannot now qualify as a complete day of calibration evidence.
            guard covered >= 8 * 3600 else { continue }
            let normalizer = CoverageMath.day / r.duration
            let walking = past.reduce(0) { $0 + $1.steps * $1.end.timeIntervalSince($1.start) } * weight * 0.0004 * normalizer
            let exercise = past.reduce(0) { $0 + $1.exercise * $1.end.timeIntervalSince($1.start) } * normalizer
            let available = past.reduce(0) { $0 + (1 - $1.activeFraction) * $1.end.timeIntervalSince($1.start) } / r.duration
            history.append((walking, exercise, available))
        }
        let coveredDays = history.count
        let activityReady = coveredDays >= 7
        let usualWalking = activityReady ? history.reduce(0) { $0 + $1.walking } / Double(coveredDays) : inputs.settings.usualDailySteps * weight * 0.0004
        let usualExercise = activityReady ? history.reduce(0) { $0 + $1.exercise } / Double(coveredDays) : 0
        let usualAvailability = activityReady ? history.reduce(0) { $0 + $1.available } / Double(coveredDays) : 1
        var untracked = inputs.settings.untrackedMovementKcal
        var calibration = "Untracked movement uses your allowance; it is not measured NEAT."
        var calibratedDays = 0
        if activityReady, inputs.confirmedFoodDays >= 7, let anchor = inputs.maintenanceAnchor,
           anchor.isFinite, (1200...6000).contains(anchor) {
            let residual = anchor - resting - inputs.typicalTEF - usualWalking - usualExercise
            let available = usualAvailability
            if residual >= 0, residual <= anchor * 0.5, available > 0.25 {
                untracked = residual / available
                calibratedDays = coveredDays
                calibration = "Untracked movement is a residual fitted to your intake/weight trend. It can also contain logging error, metabolic adaptation and model error; it does not independently measure NEAT."
            } else {
                calibration = "Components disagree with learned maintenance; residual calibration is paused. Review resting energy, food completeness and activity coverage."
            }
        } else if inputs.maintenanceAnchor != nil {
            calibration += " Trend calibration needs 7 recent activity days with at least 8 recorded hours and 7 complete food days."
        }
        func amounts(_ time: Date) -> (walking: Double, exercise: Double, untracked: Double, count: Double) {
            pieces.reduce((0, 0, 0, 0)) { sum, piece in
                let seconds = max(0, min(time, piece.end).timeIntervalSince(piece.start))
                return (sum.0 + piece.steps * seconds * weight * 0.0004,
                        sum.1 + piece.exercise * seconds,
                        sum.2 + (1 - piece.activeFraction) * untracked * seconds / CoverageMath.day,
                        sum.3 + piece.steps * seconds)
            }
        }
        // Entries logged after 'now' can never supply observed digestion.
        let meals = inputs.meals.filter { $0.isValid && $0.date <= min(now, range.end) }
        func knownTEF(_ time: Date) -> Double { ThermicEffect.accumulated(meals, from: range.start, through: time) }
        func digestion(_ time: Date) -> Double {
            let through = min(time, cutoff)
            let elapsed = max(0, through.timeIntervalSince(range.start))
            let recorded = knownTEF(through)
            let soFar = inputs.foodCoverageComplete ? recorded : max(recorded, inputs.typicalTEF * elapsed / CoverageMath.day)
            guard time > cutoff else { return soFar }
            return soFar + max(knownTEF(time) - recorded, inputs.typicalTEF * time.timeIntervalSince(cutoff) / CoverageMath.day)
        }
        func cumulative(_ time: Date) -> Double {
            let elapsed = max(0, time.timeIntervalSince(range.start))
            let a = amounts(min(time, cutoff))
            let future = max(0, time.timeIntervalSince(cutoff))
            return resting * elapsed / CoverageMath.day + a.walking + a.exercise + a.untracked + digestion(time) +
                (untracked * usualAvailability + usualWalking + usualExercise) * future / CoverageMath.day
        }
        var times = Set((0...96).map { range.start.addingTimeInterval(range.duration * Double($0) / 96) })
        times.insert(cutoff)
        for piece in pieces { times.insert(piece.start); times.insert(piece.end) }
        for meal in meals {
            for edge in [meal.date, meal.date.addingTimeInterval(ThermicEffect.duration)] where edge > range.start && edge < range.end { times.insert(edge) }
        }
        let todayWork = work.filter { $0.start < cutoff && $0.end > range.start }
        let points = times.sorted().map { time in
            let workout = todayWork.first { $0.start <= time && $0.end > time }
            return IntradayBurnPoint(time: time, hour: time.timeIntervalSince(range.start) / range.duration * 24,
                linearCumulative: maintenance * time.timeIntervalSince(range.start) / CoverageMath.day,
                actualCumulative: cumulative(time), isProjected: time > now,
                workoutTitle: workout?.title, workoutKind: workout?.kind)
        }
        let a = amounts(cutoff), elapsed = cutoff.timeIntervalSince(range.start)
        let tef = digestion(cutoff), observedTEF = knownTEF(cutoff)
        let restingSoFar = resting * elapsed / CoverageMath.day
        let count = segments(from: range.start, through: cutoff, workouts: [], steps: buckets, weight: weight, resting: resting)
            .reduce(0) { $0 + $1.steps * $1.end.timeIntervalSince($1.start) }
        let recorded = segments(from: range.start, through: cutoff, workouts: [], steps: recordedBuckets, weight: weight, resting: resting)
        let coveredHours = recorded.filter(\.covered).reduce(0) { $0 + $1.end.timeIntervalSince($1.start) } / 3600
        let note = "\(inputs.resting.source). Resting energy is spread evenly over elapsed time. \(calibration) Movement records cover \(Int(coveredHours)) hours so far; missing activity is not evidence of inactivity."
        let details = EnergyBreakdown(resting: inputs.resting, restingSoFar: restingSoFar,
            untrackedSoFar: a.untracked, untrackedPerDay: untracked,
            observedDigestionSoFar: observedTEF, digestionAllowanceSoFar: max(0, tef - observedTEF),
            coveredActivityDays: coveredDays, foodCoverageComplete: inputs.foodCoverageComplete,
            calibrationNote: calibration,
            intakeBasis: inputs.confirmedFoodDays >= 7 ? "Recent confirmed intake" : "Food targets · provisional digestion allowance")
        return IntradayBurnCurve(points: points, dailyBurn: cumulative(range.end), expendedSoFar: cumulative(cutoff),
            linearSoFar: maintenance * elapsed / CoverageMath.day,
            deltaVsLinear: cumulative(cutoff) - maintenance * elapsed / CoverageMath.day,
            workoutBurn: a.exercise, stepBurn: a.walking, tefBurn: tef, stepCount: count,
            workouts: todayWork, fraction: elapsed / range.duration,
            backgroundSoFar: restingSoFar + a.untracked, backgroundPerDay: resting + untracked,
            typicalActivityPerDay: usualWalking + usualExercise, calibrationDays: calibratedDays,
            modelNote: note, hasActivityEstimate: pieces.contains { $0.covered || $0.activeFraction > 0 }, energy: details)
    }
}
