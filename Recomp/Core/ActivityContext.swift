import Foundation

struct ActivityPreferences: Codable, Equatable, Sendable {
    var enabled = false
    var workoutSourceID: String? // nil = all sources; duplicates are labelled, not silently erased.
    var sleepSourceID: String?
    var hiddenWorkoutIDs: Set<UUID> = []
    var isValid: Bool {
        (workoutSourceID?.count ?? 0) <= 250 && (sleepSourceID?.count ?? 0) <= 250 && hiddenWorkoutIDs.count <= 20_000
    }
}

enum ContextKind: String, CaseIterable, Codable, Identifiable, Sendable {
    case travel, illness, creatine, weighingConditions, trainingChange, other
    var id: String { rawValue }
    var title: String {
        switch self {
        case .travel: return "Travel"
        case .illness: return "Illness"
        case .creatine: return "Creatine change"
        case .weighingConditions: return "Different weighing conditions"
        case .trainingChange: return "Training / routine change"
        case .other: return "Other context"
        }
    }
}
struct ContextEvent: Codable, Equatable, Identifiable, Sendable {
    var id = UUID()
    var start: Date
    var end: Date
    var kind: ContextKind
    var note = ""
    var isValid: Bool {
        start.timeIntervalSince1970.isFinite && end.timeIntervalSince1970.isFinite && end >= start && note.count <= 1000
    }
    func overlaps(_ from: Date, _ through: Date) -> Bool { start <= through && end >= from }
}

struct ActivitySource: Identifiable, Equatable, Sendable {
    var id: String
    var name: String
}
struct WorkoutRecord: Identifiable, Equatable, Sendable {
    var id: UUID
    var start: Date
    var end: Date
    var duration: Double // seconds of reported active workout duration, not end-start.
    var kind: String
    var title: String
    var distanceMetres: Double?
    var source: ActivitySource
    var isValid: Bool {
        end > start && duration.isFinite && duration > 0 && duration <= end.timeIntervalSince(start) + 60 &&
        (distanceMetres == nil || (distanceMetres!.isFinite && distanceMetres! >= 0))
    }
}
struct StepDay: Identifiable, Equatable, Sendable {
    var date: Date
    var count: Double
    var id: Date { date }
    // Representation bounds, not a recommended or physiological step range.
    var isValid: Bool {
        date.timeIntervalSince1970.isFinite && count.isFinite && count >= 0 && count.rounded() < Double(Int.max)
    }
}
/// Merged Health step counts in a real elapsed-time interval, never energy estimates.
struct StepInterval: Equatable, Sendable {
    var start: Date
    var end: Date
    var count: Double
    var isValid: Bool {
        start.timeIntervalSince1970.isFinite && end.timeIntervalSince1970.isFinite &&
        end > start && end.timeIntervalSince(start) <= 25 * 3600 &&
        count.isFinite && count >= 0 && count <= 200_000
    }
}
struct SleepInterval: Equatable, Sendable {
    var start: Date
    var end: Date
    var source: ActivitySource
}
struct SleepNight: Identifiable, Equatable, Sendable {
    var date: Date // night attributed to the day of its ending noon boundary.
    var seconds: Double
    var source: ActivitySource
    var id: Date { date }
}
struct ActivityReadout: Equatable, Sendable {
    var workouts: [WorkoutRecord] = []
    var steps: [StepDay] = []
    var stepIntervals: [StepInterval] = []
    var sleep: [SleepInterval] = []
    var warnings: [String] = []
    var refreshedAt: Date?
}

enum ActivityMath {
    static func workouts(_ all: [WorkoutRecord], preferences: ActivityPreferences) -> [WorkoutRecord] {
        var seen = Set<UUID>()
        return all.filter { $0.isValid && !preferences.hiddenWorkoutIDs.contains($0.id) &&
            (preferences.workoutSourceID == nil || $0.source.id == preferences.workoutSourceID) && seen.insert($0.id).inserted
        }.sorted { $0.start > $1.start }
    }
    /// Merely flags likely copies across writers. Overlapping workouts need user review; no fuzzy deletion.
    static func possibleDuplicateIDs(_ workouts: [WorkoutRecord]) -> Set<UUID> {
        var ids = Set<UUID>()
        let sorted = workouts.filter(\.isValid).sorted { $0.start < $1.start }
        for i in sorted.indices {
            var j = i + 1
            while j < sorted.count && sorted[j].start.timeIntervalSince(sorted[i].start) <= 300 {
                let a = sorted[i], b = sorted[j]
                if a.source.id != b.source.id && a.kind == b.kind {
                    let overlap = min(a.end, b.end).timeIntervalSince(max(a.start, b.start))
                    let shorter = min(a.end.timeIntervalSince(a.start), b.end.timeIntervalSince(b.start))
                    if overlap > 0 && overlap / shorter >= 0.85 && abs(a.duration - b.duration) <= max(180, 0.15 * max(a.duration, b.duration)) {
                        ids.insert(a.id); ids.insert(b.id)
                    }
                }
                j += 1
            }
        }
        return ids
    }
    /// Merge stage and unspecified-asleep intervals WITHIN ONE chosen source. In-bed/awake aren't provided here.
    static func unionSeconds(_ intervals: [(Date, Date)], from: Date, to: Date) -> Double {
        guard to > from else { return 0 }
        let clipped = intervals.map { (max($0.0, from), min($0.1, to)) }.filter { $0.1 > $0.0 }.sorted { $0.0 < $1.0 }
        var start: Date?, end: Date?, total = 0.0
        for pair in clipped {
            if let currentEnd = end, pair.0 <= currentEnd { end = max(currentEnd, pair.1) }
            else {
                if let s = start, let e = end { total += e.timeIntervalSince(s) }
                start = pair.0; end = pair.1
            }
        }
        if let s = start, let e = end { total += e.timeIntervalSince(s) }
        return total
    }
    static func sleepNights(_ all: [SleepInterval], sourceID: String?, now: Date = Date(), calendar: Calendar = .current) -> [SleepNight] {
        let sources = Set(all.map { $0.source.id })
        // Auto-select only if unambiguous. Never sum different trackers' sleep totals.
        guard let chosen = sourceID ?? (sources.count == 1 ? sources.first : nil),
              let source = all.first(where: { $0.source.id == chosen })?.source else { return [] }
        let selected = all.filter { $0.source.id == chosen && $0.end > $0.start }.map { ($0.start, $0.end) }
        var results: [SleepNight] = []
        for offset in (0..<30).reversed() {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: calendar.startOfDay(for: now)),
                  let noon = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: day),
                  let previousNoon = calendar.date(byAdding: .day, value: -1, to: noon) else { continue }
            let seconds = unionSeconds(selected, from: previousNoon, to: min(noon, now))
            if seconds > 0 { results.append(SleepNight(date: day, seconds: seconds, source: source)) }
        }
        return results
    }
    /// Descriptive routine-change signal; not an expenditure estimate, causal claim or calorie adjustment.
    static func stepComparison(_ values: [StepDay], now: Date = Date(), calendar: Calendar = .current) -> String? {
        let today = calendar.startOfDay(for: now)
        guard let recentStart = calendar.date(byAdding: .day, value: -7, to: today),
              let previousStart = calendar.date(byAdding: .day, value: -14, to: today) else { return nil }
        let recent = values.filter { $0.date >= recentStart && $0.date < today && $0.isValid }
        let previous = values.filter { $0.date >= previousStart && $0.date < recentStart && $0.isValid }
        guard Set(recent.map { calendar.startOfDay(for: $0.date) }).count >= 6,
              Set(previous.map { calendar.startOfDay(for: $0.date) }).count >= 6 else { return nil }
        let a = recent.map(\.count).reduce(0,+) / Double(recent.count)
        let b = previous.map(\.count).reduce(0,+) / Double(previous.count)
        guard b > 0 else { return nil }
        let change = (a-b)/b * 100
        // A finite numerator can still overflow when divided by a tiny denominator.
        // Never convert nonfinite or out-of-range readings to Int for UI text.
        guard a.isFinite, a.rounded() < Double(Int.max), change.isFinite,
              abs(change).rounded() < Double(Int.max) else { return nil }
        return "Available step data: \(Int(a.rounded()))/day over the last week, \(Int(abs(change).rounded()))% \(change >= 0 ? "higher" : "lower") than the prior week. Device coverage may have changed."
    }
}
