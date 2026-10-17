import Foundation

enum FitnessGoal: String, Codable, CaseIterable, Identifiable, Sendable {
    case recomp, maintain, gentleLoss, slowGain
    var id: String { rawValue }
    var title: String {
        switch self {
        case .recomp: return "Recomposition"
        case .maintain: return "Maintain weight"
        case .gentleLoss: return "Gentle fat loss"
        case .slowGain: return "Slow weight gain"
        }
    }
    // Product heuristics, not clinically validated rates or a prescription.
    var weeklyPercentBand: ClosedRange<Double> {
        switch self {
        case .recomp: return -0.35...0.15
        case .maintain: return -0.15...0.15
        case .gentleLoss: return -0.4 ... -0.1
        case .slowGain: return 0...0.25
        }
    }
    var desiredWeeklyPercent: Double {
        switch self {
        case .recomp: return -0.1
        case .maintain: return 0
        case .gentleLoss: return -0.25
        case .slowGain: return 0.1
        }
    }
}

struct AdaptiveSettings: Codable, Equatable, Sendable {
    var goal: FitnessGoal = .recomp
    var startingMaintenance: Double = 2700
    var proteinPerKG: Double = 2
    var fatGrams: Double = 75
    var guidanceEnabled = false // Explicit opt-in to adult fitness guidance, never automatic target edits.
    var lastChangedAt: Date?
    var isValid: Bool {
        startingMaintenance.isFinite && (1200...6000).contains(startingMaintenance) &&
        proteinPerKG.isFinite && (1.4...2.2).contains(proteinPerKG) && fatGrams.isFinite && (30...150).contains(fatGrams)
    }
}

struct DayReview: Identifiable, Codable, Equatable, Sendable {
    var dayKey: String
    var timeZoneID: String
    var confirmedAt: Date
    var total: Nutrition
    var estimatedCalorieFraction: Double
    var includedHealth: Bool
    var excludedFromAnalysis = false
    var note = ""
    var coverageID: UUID?
    var coverageStart: Date?
    var coverageEnd: Date?
    var intakeEvents: [IntakeEvent]?
    var id: String { coverageID?.uuidString ?? (timeZoneID + ":" + dayKey) }
    var coverageInterval: DateInterval? {
        if let a = coverageStart, let b = coverageEnd, b > a { return DateInterval(start: a, end: b) }
        guard coverageStart == nil, coverageEnd == nil,
              let zone = TimeZone(identifier: timeZoneID),
              let a = EntryClock.displayDate(dayKey, calendar: EntryClock.calendar(in: zone)) else { return nil }
        return DiaryMath.dayInterval(containing: a, calendar: EntryClock.calendar(in: zone))
    }
    var isValid: Bool {
        guard dayKey.count == 10, let zone = TimeZone(identifier: timeZoneID), confirmedAt.timeIntervalSince1970.isFinite,
              total.isValid, total.calories > 0, estimatedCalorieFraction.isFinite,
              (0...1).contains(estimatedCalorieFraction), note.count <= 1000 else { return false }
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = zone
        guard date(calendar: calendar) != nil, let interval = coverageInterval,
              CoverageMath.validInterval(interval), (coverageStart == nil) == (coverageEnd == nil),
              coverageID == nil || coverageStart != nil else { return false }
        if coverageStart != nil && Self.key(interval.start, calendar: calendar) != dayKey { return false }
        if let events = intakeEvents {
            guard events.count <= 20_000, Set(events.map(\.id)).count == events.count,
                  events.allSatisfy({ $0.isValid && CoverageMath.contains(interval, $0.date) }) else { return false }
            let sum = events.reduce(Nutrition.zero) { $0 + $1.nutrition }
            guard Nutrient.allCases.allSatisfy({ abs(sum[$0] - total[$0]) < 0.01 }) else { return false }
            let fraction = events.reduce(0) { $0 + $1.estimatedCalories } / max(1, total.calories)
            guard abs(fraction - estimatedCalorieFraction) < 0.00001 else { return false }
        }
        return true
    }
    static func key(_ date: Date, calendar: Calendar = .current) -> String {
        // Persist civil Gregorian keys regardless of the iPhone display calendar.
        // Keep the timezone: a local diary day is not a UTC day.
        var storageCalendar = Calendar(identifier: .gregorian); storageCalendar.timeZone = calendar.timeZone
        let c = storageCalendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
    func date(calendar: Calendar) -> Date? {
        guard let tz = TimeZone(identifier: timeZoneID) else { return nil }
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = tz
        let parts = dayKey.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3, let date = calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2])),
              Self.key(date, calendar: calendar) == dayKey else { return nil }
        return calendar.startOfDay(for: date)
    }
}

struct TargetRevision: Identifiable, Codable, Equatable, Sendable {
    var id = UUID()
    var date: Date
    var before: Nutrition
    var after: Nutrition
    var reason: String
}

struct MaintenanceSnapshot: Identifiable, Codable, Equatable, Sendable {
    var id: String
    var date: Date
    var from: Date
    var through: Date
    var calories: Double
    var lower: Double
    var upper: Double
    var averageIntake: Double
    var weightKGPerWeek: Double
    var completeDays: Int
    var scaleContext: String?
}

struct MaintenanceReport: Equatable, Sendable {
    var title = "Collecting a baseline"
    var message = "Confirm at least 21 elapsed days of complete food coverage with comparable weigh-ins. Unfinished intervals and missing hours are not assumed complete."
    var completedDays = 0
    var elapsedDays: Double?
    var weightDays = 0
    var start: Date?
    var end: Date? // End-exclusive food boundary; may also be the final morning weigh-in.
    var averageIntake: Nutrition?
    var weightKG: Double?
    var kgPerWeek: Double?
    var waistChangeCM: Double?
    var estimate: Double?
    var lower: Double?
    var upper: Double?
    var caveats: [String] = []
    var scaleContext = ""
    var scaleNotice = ""
    var recommendationTitle = "Keep collecting data"
    var recommendation = "Keep your existing targets for now. A starting guess is not a learned maintenance estimate."
    var proposal: Nutrition?
    var canApply: Bool { proposal != nil }
}

extension AppState {
    mutating func invalidateReviews(for dates: [Date]) {
        // Remove confirmations in their ORIGINAL calendars too (for edits made while travelling).
        let invalid = dayReviews.filter { review in
            guard let interval = review.coverageInterval else { return true }
            return dates.contains { CoverageMath.contains(interval, $0) }
        }
        for review in invalid { recordReviewRemoval(review.id) }
        let ids = Set(invalid.map(\.id))
        dayReviews.removeAll { ids.contains($0.id) }
    }
    mutating func recordTargets(_ targets: Nutrition, at date: Date, reason: String) {
        guard targets != self.targets else { return }
        targetRevisions.append(TargetRevision(date: date, before: self.targets, after: targets, reason: reason))
        self.targets = targets
    }
}


enum AnalysisCSV {
    static func hasRecords(in state: AppState) -> Bool {
        !state.dayReviews.isEmpty || !state.maintenanceHistory.isEmpty || !state.targetRevisions.isEmpty
    }
    static func make(state: AppState) -> String {
        let formatter = ISO8601DateFormatter()
        let header = "record_type,date,calories_kcal,protein_g,carbs_g,fat_g,maintenance_low,maintenance_high,weight_kg_per_week,details"
        var rows: [[String]] = []
        for day in state.dayReviews.sorted(by: { $0.dayKey < $1.dayKey }) {
            rows.append(["confirmed_day", day.dayKey, String(day.total.calories), String(day.total.protein), String(day.total.carbs), String(day.total.fat), "", "", "",
                "from=\(day.coverageInterval.map { formatter.string(from: $0.start) } ?? ""); through=\(day.coverageInterval.map { formatter.string(from: $0.end) } ?? ""); elapsed_hours=\((day.coverageInterval?.duration ?? 0) / 3600); zone=\(day.timeZoneID); includes_health=\(day.includedHealth); excluded=\(day.excludedFromAnalysis); \(day.note)"])
        }
        for snapshot in state.maintenanceHistory.sorted(by: { $0.date < $1.date }) {
            rows.append(["maintenance", formatter.string(from: snapshot.date), String(snapshot.calories), "", "", "", String(snapshot.lower), String(snapshot.upper), String(snapshot.weightKGPerWeek),
                "confirmed_intervals=\(snapshot.completeDays); elapsed_days=\(snapshot.through.timeIntervalSince(snapshot.from) / CoverageMath.day); intake=\(snapshot.averageIntake); from=\(formatter.string(from: snapshot.from)); through=\(formatter.string(from: snapshot.through)); scales=\(snapshot.scaleContext ?? "Legacy mixed-source analysis")"])
        }
        for revision in state.targetRevisions.sorted(by: { $0.date < $1.date }) {
            for (kind, n) in [("targets_before", revision.before), ("targets_after", revision.after)] {
                rows.append([kind, formatter.string(from: revision.date), String(n.calories), String(n.protein), String(n.carbs), String(n.fat), "", "", "", revision.reason])
            }
        }
        return ([header] + rows.map { $0.map(DiaryCSV.escape).joined(separator: ",") }).joined(separator: "\r\n") + "\r\n"
    }
}


extension AppState {
    func deletedIDs(_ kind: String) -> Set<UUID> { deletedRecords[kind] ?? [] }
    mutating func recordDeletion(_ id: UUID, kind: String) { deletedRecords[kind, default: []].insert(id) }
    mutating func recordReviewRemoval(_ id: String, at date: Date = Date()) {
        removedReviews[id] = max(removedReviews[id] ?? .distantPast, date)
    }
    var syncDeletionsAreValid: Bool {
        let records: [String: Set<UUID>] = ["food": Set(entries.map(\.id)), "body": Set(measurements.map(\.id)),
            "template": Set(templates.map(\.id)), "context": Set(contextEvents.map(\.id)), "dxa": Set(dxaScans.map(\.id))]
        return deletedRecords.allSatisfy { kind, ids in
            guard let active = records[kind] else { return false }
            return ids.count <= 100_000 && ids.isDisjoint(with: active)
        } && removedReviews.count <= 100_000 && removedReviews.allSatisfy { id, date in
            !id.isEmpty && id.count <= 300 && date.timeIntervalSince1970.isFinite
        } && dayReviews.allSatisfy { review in
            removedReviews[review.id].map { review.confirmedAt > $0 } ?? true
        }
    }
}
