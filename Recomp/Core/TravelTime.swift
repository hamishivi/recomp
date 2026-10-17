import Foundation

/// A diary label belongs to the place where a record was entered, not the place
/// from which it is later viewed. The absolute Date remains the source of chronology.
struct EntryClock: Codable, Equatable, Sendable {
    enum Provenance: String, Codable, Sendable {
        case recorded, userConfirmed, healthMetadata, legacyReview, legacyAssumed
    }
    var timeZoneID: String
    var dayKey: String
    var provenance: Provenance
    var needsReview: Bool { provenance == .legacyReview || provenance == .legacyAssumed }
    var healthTimeZoneID: String? { needsReview ? nil : timeZoneID }
    var zone: TimeZone { TimeZone(identifier: timeZoneID) ?? TimeZone(secondsFromGMT: 0)! }
    var calendar: Calendar { Self.calendar(in: zone) }
    init?(date: Date, timeZoneID: String, provenance: Provenance = .recorded) {
        guard date.timeIntervalSince1970.isFinite, let zone = TimeZone(identifier: timeZoneID),
              abs(date.timeIntervalSince1970) < 100_000_000_000,
              Self.calendar(in: zone).component(.era, from: date) == 1 else { return nil }
        self.timeZoneID = timeZoneID
        self.dayKey = DayReview.key(date, calendar: Self.calendar(in: zone))
        self.provenance = provenance
    }
    func isValid(for date: Date) -> Bool {
        guard TimeZone(identifier: timeZoneID) != nil, dayKey.count == 10,
              date.timeIntervalSince1970.isFinite, abs(date.timeIntervalSince1970) < 100_000_000_000 else { return false }
        return calendar.component(.era, from: date) == 1 && DayReview.key(date, calendar: calendar) == dayKey
    }
    static func calendar(in zone: TimeZone) -> Calendar {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = zone; return calendar
    }
    static let utc = calendar(in: TimeZone(secondsFromGMT: 0)!)
    /// A plotting/selection date, not the event's timestamp. Reconstruct civil components.
    static func displayDate(_ key: String, calendar: Calendar = .current) -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        let cal = Self.calendar(in: calendar.timeZone)
        guard let date = cal.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2])),
              DayReview.key(date, calendar: cal) == key else { return nil }
        return date
    }
    static func label(date: Date, clock: EntryClock?) -> String {
        let f = DateFormatter(); f.locale = .current
        f.calendar = EntryClock.calendar(in: clock?.zone ?? .current)
        f.timeZone = clock?.zone ?? .current; f.dateStyle = .medium; f.timeStyle = .short
        return f.string(from: date) + " · " + (clock?.timeZoneID ?? "zone unavailable") +
            (clock?.needsReview == true ? " (assumed; review)" : "")
    }
    static func updated(_ old: EntryClock?, from oldDate: Date?, to date: Date, zoneID: String? = nil,
                        confirmed: Bool = false) -> EntryClock? {
        let zone = zoneID ?? old?.timeZoneID ?? TimeZone.current.identifier
        let provenance: Provenance = confirmed ? .userConfirmed :
            (old == nil ? .recorded : old!.provenance)
        return EntryClock(date: date, timeZoneID: zone, provenance: provenance)
    }
}

extension FoodEntry {
    func isOnDiaryDay(_ day: Date, calendar: Calendar = .current) -> Bool {
        if let clock { return clock.dayKey == DayReview.key(day, calendar: calendar) }
        return DiaryMath.isOnDay(date, day: day, calendar: calendar)
    }
}

/// Timestamped totals preserve exact food timing when a weight boundary splits a
/// reviewed interval. No uniform hourly eating assumption is made.
struct IntakeEvent: Codable, Equatable, Sendable, Identifiable {
    var id: String
    var date: Date
    var nutrition: Nutrition
    var estimatedCalories: Double
    var isValid: Bool {
        !id.isEmpty && id.count <= 150 && date.timeIntervalSince1970.isFinite &&
        nutrition.isValid && estimatedCalories.isFinite && estimatedCalories >= 0 &&
        estimatedCalories <= nutrition.calories + 0.001
    }
}

struct CoveragePreview: Equatable, Sendable {
    var interval: DateInterval
    var localEntries: [FoodEntry]
    var events: [IntakeEvent]
    var includesHealth: Bool
    var warnings: [String]
    var total: Nutrition { events.reduce(.zero) { $0 + $1.nutrition } }
    var estimatedFraction: Double {
        min(1, events.reduce(0) { $0 + $1.estimatedCalories } / max(1, total.calories))
    }
}

enum CoverageMath {
    static let day: TimeInterval = 86_400
    static func contains(_ interval: DateInterval, _ date: Date) -> Bool {
        date >= interval.start && date < interval.end
    }
    static func overlaps(_ a: DateInterval, _ b: DateInterval) -> Bool {
        a.start < b.end && b.start < a.end
    }
    static func validInterval(_ interval: DateInterval) -> Bool {
        interval.start.timeIntervalSince1970.isFinite && interval.end.timeIntervalSince1970.isFinite &&
            interval.duration > 0 && interval.duration <= 7 * day
    }
    static func preview(entries: [FoodEntry], samples: [HealthNutritionSample], deletions: [DeletionTask],
                        bundleID: String, interval: DateInterval, includesHealth: Bool,
                        warnings: [String] = []) -> CoveragePreview {
        let local = entries.filter { contains(interval, $0.date) }.sorted { $0.date < $1.date }
        var events = local.map {
            IntakeEvent(id: "food:" + $0.id.uuidString, date: $0.date, nutrition: $0.nutrition,
                        estimatedCalories: $0.isEstimate ? $0.nutrition.calories : 0)
        }
        if includesHealth {
            var seen = Set<UUID>()
            for sample in DiaryMath.externalSamples(samples, entries: entries, deletions: deletions, ownBundleID: bundleID)
                where contains(interval, sample.date) && seen.insert(sample.id).inserted && sample.value.isFinite && sample.value >= 0 {
                var n = Nutrition.zero; n[sample.nutrient] = sample.value
                events.append(IntakeEvent(id: "health:" + sample.id.uuidString, date: sample.date,
                                          nutrition: n, estimatedCalories: n.calories))
            }
        }
        return CoveragePreview(interval: interval, localEntries: local,
            events: events.sorted { $0.date == $1.date ? $0.id < $1.id : $0.date < $1.date },
            includesHealth: includesHealth, warnings: warnings)
    }
    struct Run {
        var reviews: [DayReview] = []
        var conflict = false
        var interval: DateInterval? {
            guard let first = reviews.first?.coverageInterval, let last = reviews.last?.coverageInterval else { return nil }
            return DateInterval(start: first.start, end: last.end)
        }
    }
    /// Latest contiguous, fully ended coverage. Different names for a timezone are
    /// irrelevant. Overlapping snapshots are rejected, NEVER added twice.
    static func latestRun(_ reviews: [DayReview], now: Date, lookbackDays: Double = 43) -> Run {
        let earliest = now.addingTimeInterval(-lookbackDays * day)
        let ended = reviews.filter { $0.isValid && $0.confirmedAt <= now &&
            $0.coverageInterval.map { $0.start >= earliest && $0.end <= now } == true
        }.sorted {
            let a = $0.coverageInterval!, b = $1.coverageInterval!
            return a.start == b.start ? a.end < b.end : a.start < b.start
        }
        // An exclusion cannot be covered over by a second overlapping snapshot.
        for (a, b) in zip(ended, ended.dropFirst()) {
            if overlaps(a.coverageInterval!, b.coverageInterval!) { return Run(conflict: true) }
        }
        let ordered = ended.filter { !$0.excludedFromAnalysis }
        var run = Run()
        for review in ordered {
            let interval = review.coverageInterval!
            if let last = run.reviews.last?.coverageInterval {
                if interval.start < last.end { run.conflict = true; return run }
                if abs(interval.start.timeIntervalSince(last.end)) > 0.001 { run.reviews = [] }
            }
            run.reviews.append(review)
        }
        return run
    }
    /// Sum actual events in partial boundary snapshots. Legacy snapshots with no
    /// event detail must be included whole; never pro-rate an assumed meal pattern.
    static func total(_ reviews: [DayReview], from start: Date, to end: Date) -> (nutrition: Nutrition, estimated: Double)? {
        guard start < end else { return nil }
        var cursor = start, total = Nutrition.zero, estimated = 0.0
        for review in reviews {
            guard let interval = review.coverageInterval, interval.end > start, interval.start < end else { continue }
            let a = max(start, interval.start), b = min(end, interval.end)
            guard abs(a.timeIntervalSince(cursor)) < 0.001 else { return nil }
            if a == interval.start && b == interval.end {
                total = total + review.total; estimated += review.total.calories * review.estimatedCalorieFraction
            } else if let events = review.intakeEvents {
                for event in events where event.date >= a && event.date < b {
                    total = total + event.nutrition; estimated += event.estimatedCalories
                }
            } else { return nil }
            cursor = b
        }
        guard abs(cursor.timeIntervalSince(end)) < 0.001 else { return nil }
        return (total, estimated)
    }
}

extension AppState {
    /// Old versions did not record capture zones. Freeze their display once on
    /// migration, visibly marking inference. Never invent a verified location.
    mutating func migrateEntryClocks(fallback: TimeZone) {
        func legacy(_ date: Date) -> EntryClock? {
            let zones = Set(dayReviews.filter { $0.coverageInterval.map { CoverageMath.contains($0, date) } == true }.map(\.timeZoneID))
            return EntryClock(date: date, timeZoneID: (zones.count == 1 ? zones.first : nil) ?? fallback.identifier,
                              provenance: zones.count == 1 ? .legacyReview : .legacyAssumed)
        }
        for i in entries.indices where entries[i].clock == nil { entries[i].clock = legacy(entries[i].date) }
        for i in measurements.indices where measurements[i].clock == nil { measurements[i].clock = legacy(measurements[i].date) }
    }
}
