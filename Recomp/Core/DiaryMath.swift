import Foundation

enum DiaryMath {
    static func dayInterval(containing date: Date, calendar: Calendar = .current) -> DateInterval {
        let start = calendar.startOfDay(for: date)
        // Calendar days, not 86,400-second blocks: handles daylight saving changes.
        let end = calendar.date(byAdding: .day, value: 1, to: start)!
        return DateInterval(start: start, end: end)
    }
    static func isOnDay(_ date: Date, day: Date, calendar: Calendar = .current) -> Bool {
        let interval = dayInterval(containing: day, calendar: calendar)
        return date >= interval.start && date < interval.end
    }
    /// Precompute the selected civil date and legacy interval once per query,
    /// rather than rebuilding calendars/formatting the same date for every record.
    static func entries(on day: Date, in entries: [FoodEntry], calendar: Calendar = .current) -> [FoodEntry] {
        let selection = DaySelection(day: day, calendar: calendar)
        return entries.filter { selection.contains(date: $0.date, clock: $0.clock) }
    }
    private struct DaySelection {
        let key: String
        let interval: DateInterval
        init(day: Date, calendar: Calendar) {
            key = DayReview.key(day, calendar: calendar)
            interval = DiaryMath.dayInterval(containing: day, calendar: calendar)
        }
        func contains(date: Date, clock: EntryClock?) -> Bool {
            if let clock { return clock.dayKey == key }
            return date >= interval.start && date < interval.end
        }
    }
    static func localTotal(entries: [FoodEntry], day: Date, calendar: Calendar = .current) -> Nutrition {
        Self.entries(on: day, in: entries, calendar: calendar).reduce(.zero) { $0 + $1.nutrition }
    }
    static func externalSamples(_ samples: [HealthNutritionSample], entries: [FoodEntry],
                                deletions: [DeletionTask], ownBundleID: String) -> [HealthNutritionSample] {
        let localIDs = Set(entries.map(\.id)).union(deletions.map(\.id))
        // Suppress only samples matching our source AND a known entry/tombstone.
        // After a reinstall, old exports without a local diary remain visible.
        return samples.filter { sample in
            guard sample.sourceBundleID == ownBundleID, let id = sample.localEntryID else { return true }
            return !localIDs.contains(id)
        }
    }
    static func healthSampleIsOnDay(_ sample: HealthNutritionSample, day: Date, calendar: Calendar = .current) -> Bool {
        if let clock = sample.clock { return clock.dayKey == DayReview.key(day, calendar: calendar) }
        return isOnDay(sample.date, day: day, calendar: calendar)
    }
    static func healthTotal(_ samples: [HealthNutritionSample], day: Date, calendar: Calendar = .current) -> Nutrition {
        var total = Nutrition.zero
        var seen = Set<UUID>()
        let selection = DaySelection(day: day, calendar: calendar)
        for sample in samples where selection.contains(date: sample.date, clock: sample.clock) {
            guard seen.insert(sample.id).inserted, sample.value.isFinite, sample.value >= 0 else { continue }
            total[sample.nutrient] += sample.value
        }
        return total
    }
    static func mergedTotal(entries: [FoodEntry], deletions: [DeletionTask], samples: [HealthNutritionSample],
                            ownBundleID: String, day: Date, includeHealth: Bool,
                            calendar: Calendar = .current) -> Nutrition {
        let local = localTotal(entries: entries, day: day, calendar: calendar)
        guard includeHealth else { return local }
        let other = externalSamples(samples, entries: entries, deletions: deletions, ownBundleID: ownBundleID)
        return local + healthTotal(other, day: day, calendar: calendar)
    }
    static func weightTrend(_ readings: [WeightReading], calendar: Calendar = .current) -> [DailyWeight] {
        let valid = readings.filter { $0.kilograms.isFinite && $0.kilograms > 0 }
        let grouped = Dictionary(grouping: valid) { calendar.startOfDay(for: $0.date) }
        // Give each measured day equal weight, rather than overweighting days with more weigh-ins.
        let means: [(date: Date, kg: Double)] = grouped.map { date, items in
            (date, items.reduce(0) { $0 + $1.kilograms } / Double(items.count))
        }.sorted { $0.date < $1.date }
        return means.map { point in
            let from = calendar.date(byAdding: .day, value: -6, to: point.date)!
            let window = means.filter { $0.date >= from && $0.date <= point.date }
            return DailyWeight(date: point.date, kilograms: point.kg,
                               rollingAverage: window.reduce(0) { $0 + $1.kg } / Double(window.count))
        }
    }
}

enum SyncIdentity {
    static let entryMetadataKey = "com.recomp.entryID"
    static let estimateMetadataKey = "com.recomp.isEstimate"
    static func sampleID(entryID: UUID, nutrient: Nutrient) -> String {
        "recomp.\(entryID.uuidString).\(nutrient.rawValue)"
    }
    static func pendingNutrients(for entry: FoodEntry) -> [Nutrient] {
        Nutrient.allCases.filter { (entry.exportedVersions[$0.rawValue] ?? 0) < entry.version }
    }
}

enum DiaryCSV {
    static func make(entries: [FoodEntry]) -> String {
        let formatter = ISO8601DateFormatter()
        let header = "id,date,meal,name,calories_kcal,protein_g,carbs_g,fat_g,is_estimate,note,entry_timezone,diary_date,timezone_provenance"
        let lines = entries.sorted { $0.date < $1.date }.map { entry -> String in
            [entry.id.uuidString, formatter.string(from: entry.date), entry.meal.rawValue,
             entry.name, String(entry.nutrition.calories), String(entry.nutrition.protein),
             String(entry.nutrition.carbs), String(entry.nutrition.fat), String(entry.isEstimate), entry.note, entry.clock?.timeZoneID ?? "", entry.clock?.dayKey ?? "", entry.clock?.provenance.rawValue ?? "unknown"]
                .map(escape).joined(separator: ",")
        }
        return ([header] + lines).joined(separator: "\r\n") + "\r\n"
    }
    static func escape(_ input: String) -> String {
        var safe = input
        // Avoid spreadsheet formula execution if a food name begins with a formula character.
        let stripped = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if let first = stripped.first, "=+-@".contains(first) { safe = "'" + input }
        return "\"" + safe.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}

/// Safe ring geometry only. Actual intake is never capped or rewritten.
struct IntakeRingProgress: Equatable, Sendable {
    let value: Double
    let target: Double
    var hasTarget: Bool { target.isFinite && target > 0 }
    var fraction: Double {
        guard hasTarget, value.isFinite, value > 0 else { return 0 }
        return min(value / target, 1)
    }
    var remaining: Double? {
        guard hasTarget, value.isFinite else { return nil }
        let delta = target - value
        return delta.isFinite ? delta : nil
    }
}

struct TrendSummary: Equatable, Sendable {
    var recentAverageCalories: Double
    var targetCalories: Double
    var calorieDeltaVsTarget: Double { recentAverageCalories - targetCalories }
    var loggedDaysCount: Int

    var latestWeight: Double? // display units
    var weightUnit: String // "kg" or "lb"
    var weightChangeRatePerWeek: Double? // in display units per week
    var weightNetChange: Double? // in display units over recent period

    var estimatedDailyBurn: Double // kcal/day
    var isBurnLearned: Bool // true if learned from data, false if baseline guess
    var dailyEnergyBalance: Double { recentAverageCalories > 0 ? recentAverageCalories - estimatedDailyBurn : 0 }
    var dayDurationSeconds: Double = 86400
    var dayProgressFraction: Double = 0.0 // 0.0 to 1.0 elapsed
    var expendedSoFarToday: Double {
        if let curve = intradayCurve { return curve.expendedSoFar }
        return estimatedDailyBurn * dayDurationSeconds / CoverageMath.day * dayProgressFraction
    }
    var intradayCurve: IntradayBurnCurve? = nil
}

enum TrendSummaryCalculator {
    static func calculate(
        entries: [FoodEntry],
        targets: Nutrition,
        bodyPoints: [BodyPoint],
        maintenanceReport: MaintenanceReport,
        startingMaintenance: Double,
        units: MeasurementUnits,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> TrendSummary {
        let today = calendar.startOfDay(for: now)
        let sevenDaysAgo = calendar.date(byAdding: .day, value: -6, to: today) ?? today

        // Filter by the same saved civil-date keys as the diary, not the phone's
        // current timezone applied to timestamps. Exclude future actual meals.
        let firstKey = DayReview.key(sevenDaysAgo, calendar: calendar)
        let lastKey = DayReview.key(today, calendar: calendar)
        var dayTotals: [String: Double] = [:]
        for entry in entries where entry.date <= now {
            let key = entry.clock?.dayKey ?? DayReview.key(entry.date, calendar: calendar)
            guard key >= firstKey && key <= lastKey else { continue }
            dayTotals[key, default: 0] += entry.nutrition.calories
        }

        let loggedDays = dayTotals.values.filter { $0 > 0 }
        let avgCalories = loggedDays.isEmpty ? 0 : (loggedDays.reduce(0, +) / Double(loggedDays.count))

        let comparablePoints = ScaleMath.latestWeightSeries(bodyPoints, now: now, calendar: calendar)
        let latestDisplayWeight = comparablePoints.last.map { units.display($0.value, metric: .weight) }
        let weightUnit = units.unit(for: .weight)
        let ratePerWeek: Double?
        if let kgPerWeek = maintenanceReport.kgPerWeek, kgPerWeek.isFinite {
            ratePerWeek = units == .imperial ? kgPerWeek / 0.45359237 : kgPerWeek
        } else {
            let twoWeeksAgo = calendar.date(byAdding: .day, value: -14, to: today) ?? today
            let recent = comparablePoints.filter { $0.date >= twoWeeksAgo }
            if let first = recent.first, let last = recent.last, last.date > first.date {
                let days = Double(calendar.dateComponents([.day], from: first.date, to: last.date).day ?? 0)
                ratePerWeek = days > 0 ? units.display(last.value - first.value, metric: .weight) * 7 / days : nil
            } else { ratePerWeek = nil }
        }
        // Never label an old pair of readings as a recent change.
        let recent = comparablePoints.filter { $0.date >= sevenDaysAgo }
        let netChange: Double?
        if let first = recent.first, let last = recent.last, last.date > first.date {
            netChange = units.display(last.value - first.value, metric: .weight)
        } else { netChange = nil }

        // Estimated daily burn
        let burn: Double
        let isLearned: Bool
        if let est = maintenanceReport.estimate, est.isFinite, est > 500 {
            burn = est
            isLearned = true
        } else {
            burn = startingMaintenance.isFinite && startingMaintenance > 0 ? startingMaintenance : 2500
            isLearned = false
        }

        // Intraday elapsed fraction
        let todayInterval = DiaryMath.dayInterval(containing: now, calendar: calendar)
        let dayFraction = min(1, max(0, now.timeIntervalSince(today)) / todayInterval.duration)

        return TrendSummary(
            recentAverageCalories: avgCalories,
            targetCalories: targets.calories,
            loggedDaysCount: loggedDays.count,
            latestWeight: latestDisplayWeight,
            weightUnit: weightUnit,
            weightChangeRatePerWeek: ratePerWeek,
            weightNetChange: netChange,
            estimatedDailyBurn: burn,
            isBurnLearned: isLearned,
            dayDurationSeconds: todayInterval.duration,
            dayProgressFraction: dayFraction
        )
    }

    static func dayExpended(
        dailyBurn: Double,
        for day: Date,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> (expended: Double, fraction: Double) {
        let startOfDay = calendar.startOfDay(for: day)
        let startOfToday = calendar.startOfDay(for: now)
        if startOfDay < startOfToday {
            return (dailyBurn * DiaryMath.dayInterval(containing: day, calendar: calendar).duration / CoverageMath.day, 1.0)
        } else if startOfDay > startOfToday {
            return (0.0, 0.0)
        } else {
            let interval = DiaryMath.dayInterval(containing: now, calendar: calendar)
            let elapsed = max(0, min(interval.duration, now.timeIntervalSince(startOfToday)))
            let fraction = elapsed / interval.duration
            return (dailyBurn * elapsed / CoverageMath.day, fraction)
        }
    }
}

struct IntradayBurnPoint: Identifiable, Equatable, Sendable {
    var id: Double { hour }
    var time: Date
    var hour: Double // 0.0 to 24.0
    var linearCumulative: Double // M * (hour / 24.0)
    var actualCumulative: Double // Dynamic cumulative burn
    var isProjected: Bool // hour > current hour
    var workoutTitle: String?
    var workoutKind: String?
}

struct IntradayBurnCurve: Equatable, Sendable {
    var points: [IntradayBurnPoint]
    var dailyBurn: Double
    var expendedSoFar: Double
    var linearSoFar: Double
    var deltaVsLinear: Double
    var workoutBurn: Double
    var stepBurn: Double
    var tefBurn: Double
    var stepCount: Double
    var workouts: [WorkoutRecord]
    var fraction: Double
    var backgroundSoFar: Double = 0
    var backgroundPerDay: Double = 0
    var typicalActivityPerDay: Double = 0
    var calibrationDays: Int = 0
    var modelNote: String = ""
    var hasActivityEstimate: Bool = false

    var currentPoint: IntradayBurnPoint? { points.last { !$0.isProjected } }
    var estimatedPoints: [IntradayBurnPoint] { points.filter { !$0.isProjected } }
    var projectedPoints: [IntradayBurnPoint] {
        let future = points.filter(\.isProjected)
        // Share the exact cutoff so the forecast has no gap at the join.
        guard !future.isEmpty, let currentPoint else { return future }
        return [currentPoint] + future
    }
    var workoutMarkers: [IntradayBurnPoint] {
        guard let start = points.first?.time else { return [] }
        // One event per start time, including short and overnight sessions.
        let starts = Set(workouts.map { max(start, $0.start) })
        return points.filter { starts.contains($0.time) && !$0.isProjected }
    }
    func point(nearestTo time: Date) -> IntradayBurnPoint? {
        points.min { abs($0.time.timeIntervalSince(time)) < abs($1.time.timeIntervalSince(time)) }
    }
}

enum IntradayBurnCalculator {
    // Net MET estimates: resting expenditure is already in the background.
    // Population averages, not individual metabolic measurements. See the model audit.
    static func workoutMET(_ workout: WorkoutRecord) -> Double {
        switch workout.kind {
        case "running":
            if let distance = workout.distanceMetres, distance > 0 {
                let mph = distance / 1609.344 / (workout.duration / 3600)
                switch mph {
                case ..<4.3: return 6.5
                case ..<5: return 7.8
                case ..<5.5: return 8.5
                case ..<6: return 9
                case ..<6.7: return 9.3
                case ..<7: return 10.5
                case ..<7.5: return 11
                case ..<8: return 11.8
                default: return 12
                }
            }
            return 7.5
        case "walking": return 3.8
        case "hiking": return 5.3
        case "cycling", "swimming": return 6
        case "strength": return 3.5
        case "yoga": return 2.3
        default: return 3 // Deliberately modest when intensity/type is unknown.
        }
    }
    private struct Segment {
        var start: Date
        var end: Date
        var stepsPerSecond: Double
        var workoutPerSecond: Double
        func amounts(through time: Date) -> (steps: Double, workout: Double) {
            let seconds = max(0, min(end, time).timeIntervalSince(start))
            return (seconds * stepsPerSecond, seconds * workoutPerSecond)
        }
    }
    private static func segments(from: Date, through: Date, workouts: [WorkoutRecord], steps: [StepInterval], weight: Double) -> [Segment] {
        guard through > from else { return [] }
        let w = workouts.filter { $0.start < through && $0.end > from }
        let s = steps.filter { $0.start < through && $0.end > from }
        let edges = Set([from, through] + w.flatMap { [max(from, $0.start), min(through, $0.end)] } +
                        s.flatMap { [max(from, $0.start), min(through, $0.end)] }).sorted()
        return zip(edges, edges.dropFirst()).map { a, b in
            // Overlapping recordings cannot represent two simultaneous bodies.
            // Use the largest net rate, not the sum of Strava/Watch copies.
            let workoutRate = w.filter { $0.start < b && $0.end > a }.map {
                (workoutMET($0) - 1) * weight / 3600 * min(1, $0.duration / $0.end.timeIntervalSince($0.start))
            }.max() ?? 0
            // Uniform timing within each hourly bucket is an approximation. Exclude
            // the workout portion so its steps never add a second energy estimate.
            let stepRate = workoutRate > 0 ? 0 : (s.filter { $0.start < b && $0.end > a }.map {
                $0.count / $0.end.timeIntervalSince($0.start)
            }.max() ?? 0) * weight * 0.0004
            return Segment(start: a, end: b, stepsPerSecond: stepRate, workoutPerSecond: workoutRate)
        }
    }
    static func calculate(
        dailyBurn: Double, for day: Date, now: Date = Date(),
        workouts: [WorkoutRecord] = [], steps: [StepDay] = [], stepIntervals: [StepInterval] = [],
        entries: [FoodEntry] = [], weightKG: Double = 75.0,
        calendar: Calendar = .current
    ) -> IntradayBurnCurve {
        let interval = DiaryMath.dayInterval(containing: day, calendar: calendar)
        let rate = dailyBurn.isFinite && (500...6000).contains(dailyBurn) ? dailyBurn : 2400
        let weight = weightKG.isFinite && (25...350).contains(weightKG) ? weightKG : 75
        let budget = rate * interval.duration / CoverageMath.day
        let cutoff = min(interval.end, max(interval.start, now))
        let elapsed = cutoff.timeIntervalSince(interval.start)
        let fraction = elapsed / interval.duration
        var seen = Set<UUID>()
        let validWorkouts = workouts.filter { $0.isValid && $0.start <= now && seen.insert($0.id).inserted }
        let dayWorkouts = validWorkouts.filter { $0.start < cutoff && $0.end > interval.start }
        // Repeated read snapshots are aggregates, never increments.
        let dailySteps = Dictionary(grouping: steps.filter { $0.isValid && $0.count <= 200_000 && $0.date <= now },
                                    by: { calendar.startOfDay(for: $0.date) }).mapValues { $0.map(\.count).max() ?? 0 }
        var timedSteps = stepIntervals.filter { $0.isValid && $0.start < now && $0.end <= now }
        // Legacy/test clients with only daily totals retain an explicitly coarse curve.
        for (date, count) in dailySteps where !timedSteps.contains(where: { calendar.isDate($0.start, inSameDayAs: date) }) {
            let end = min(DiaryMath.dayInterval(containing: date, calendar: calendar).end, now)
            if end > date { timedSteps.append(StepInterval(start: date, end: end, count: count)) }
        }
        let historicalStart = calendar.date(byAdding: .day, value: -14, to: interval.start)!
        var historicalRates: [Double] = []
        // Only completed days with observed steps qualify; missing days aren't zero.
        let observedDays = Set(timedSteps.map { calendar.startOfDay(for: $0.start) })
        for date in observedDays where date >= historicalStart && date < interval.start {
            let d = DiaryMath.dayInterval(containing: date, calendar: calendar)
            guard d.end <= now else { continue }
            let pieces = segments(from: d.start, through: d.end, workouts: validWorkouts, steps: timedSteps, weight: weight)
            let total = pieces.reduce(0.0) { sum, piece in
                let a = piece.amounts(through: d.end); return sum + a.steps + a.workout
            }
            historicalRates.append(total * CoverageMath.day / d.duration)
        }
        let average = historicalRates.isEmpty ? 0 : historicalRates.reduce(0, +) / Double(historicalRates.count)
        let calibrated = historicalRates.count >= 7 && average <= rate * 0.5
        // Until history is adequate, reserve 20% of maintenance for typical activity.
        // This is a labelled provisional allocation, not a claim to measure BMR.
        let usualActivity = calibrated ? average : rate * 0.2
        let background = rate - usualActivity
        let daySteps = timedSteps.filter { $0.start < cutoff && $0.end > interval.start }
        let hasActivity = !daySteps.isEmpty || !dayWorkouts.isEmpty
        let pieces = segments(from: interval.start, through: cutoff, workouts: validWorkouts, steps: timedSteps, weight: weight)
        func activityAt(_ time: Date) -> (steps: Double, workout: Double) {
            pieces.reduce((steps: 0.0, workout: 0.0)) { sum, piece in
                let a = piece.amounts(through: time); return (sum.steps + a.steps, sum.workout + a.workout)
            }
        }
        let observed = activityAt(cutoff)
        let deduplicatedSteps = segments(from: interval.start, through: cutoff, workouts: [], steps: timedSteps, weight: 1)
            .reduce(0.0) { $0 + $1.amounts(through: cutoff).steps } / 0.0004
        func cumulative(_ time: Date) -> Double {
            let seconds = max(0, time.timeIntervalSince(interval.start))
            guard hasActivity else { return rate * seconds / CoverageMath.day }
            let a = activityAt(min(time, cutoff))
            let forecast = max(0, time.timeIntervalSince(cutoff)) * usualActivity / CoverageMath.day
            return background * seconds / CoverageMath.day + a.steps + a.workout + forecast
        }
        var times = Set((0...96).map { interval.start.addingTimeInterval(interval.duration * Double($0) / 96) })
        times.insert(cutoff) // Header and marker agree even between quarter hours.
        // Preserve every change in activity rate. Quarter-hour sampling alone
        // smooths away short workouts and shifts their apparent start/end times.
        for piece in pieces {
            times.insert(piece.start)
            times.insert(piece.end)
        }
        let points = times.sorted().map { time -> IntradayBurnPoint in
            let f = time.timeIntervalSince(interval.start) / interval.duration
            let workout = dayWorkouts.first { $0.start <= time && $0.end > time }
            return IntradayBurnPoint(time: time, hour: f * 24,
                linearCumulative: budget * f, actualCumulative: cumulative(time),
                isProjected: time > now, workoutTitle: workout?.title, workoutKind: workout?.kind)
        }
        let expended = cumulative(cutoff)
        let note: String
        if !hasActivity {
            note = "No activity data for this day. Showing maintenance pace, not assuming zero movement."
        } else if calibrated {
            note = "Background calibrated against \(historicalRates.count) recent activity days; includes resting burn, digestion and untracked movement."
        } else {
            note = "Provisional background: 80% of maintenance. Calibration needs 7 recent activity days with a plausible activity allowance."
        }
        return IntradayBurnCurve(points: points, dailyBurn: cumulative(interval.end),
            expendedSoFar: expended, linearSoFar: budget * fraction,
            deltaVsLinear: expended - budget * fraction, workoutBurn: observed.workout, stepBurn: observed.steps, tefBurn: 0,
            stepCount: deduplicatedSteps, workouts: dayWorkouts, fraction: fraction,
            backgroundSoFar: (hasActivity ? background : rate) * elapsed / CoverageMath.day,
            backgroundPerDay: background, typicalActivityPerDay: usualActivity,
            calibrationDays: calibrated ? historicalRates.count : 0, modelNote: note, hasActivityEstimate: hasActivity)
    }
}
