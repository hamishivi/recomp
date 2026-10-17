import Foundation

enum BodyMetric: String, Codable, CaseIterable, Identifiable, Sendable {
    case weight, bodyFat, waist, hips, chest, neck, upperArm, thigh, calf
    var id: String { rawValue }
    var title: String {
        switch self {
        case .weight: return "Weight"
        case .bodyFat: return "Body fat"
        case .waist: return "Waist"
        case .hips: return "Hips"
        case .chest: return "Chest"
        case .neck: return "Neck"
        case .upperArm: return "Upper arm"
        case .thigh: return "Thigh"
        case .calf: return "Calf"
        }
    }
    var canonicalUnit: String { self == .weight ? "kg" : self == .bodyFat ? "%" : "cm" }
    var healthSupported: Bool { [.weight, .bodyFat, .waist].contains(self) }
    // Input sanity limits, NOT healthy ranges or clinical thresholds.
    func accepts(_ value: Double) -> Bool {
        guard value.isFinite else { return false }
        switch self {
        case .weight: return (20...500).contains(value)
        case .bodyFat: return (1...75).contains(value)
        default: return (5...300).contains(value)
        }
    }
}

enum MeasurementUnits: String, Codable, CaseIterable, Identifiable, Sendable {
    case metric, imperial
    var id: String { rawValue }
    var title: String { self == .metric ? "kg / cm" : "lb / in" }
    func unit(for metric: BodyMetric) -> String {
        if self == .metric || metric == .bodyFat { return metric.canonicalUnit }
        return metric == .weight ? "lb" : "in"
    }
    func display(_ value: Double, metric: BodyMetric) -> Double {
        guard self == .imperial, metric != .bodyFat else { return value }
        return metric == .weight ? value / 0.45359237 : value / 2.54
    }
    func canonical(_ value: Double, metric: BodyMetric) -> Double {
        guard self == .imperial, metric != .bodyFat else { return value }
        return metric == .weight ? value * 0.45359237 : value * 2.54
    }
}

struct BodyMeasurement: Identifiable, Codable, Equatable, Sendable {
    var id = UUID()
    var date: Date
    var metric: BodyMetric
    var value: Double // kg, percentage points (19 means 19%), or cm.
    var method = ""
    var note = ""
    var excludedFromTrend = false
    var version = 1
    var exportedVersion = 0
    var clock: EntryClock?
    var scaleLocationID: UUID? // Optional; old records and imports are never auto-tagged.
    var isValid: Bool {
        metric.accepts(value) && date.timeIntervalSince1970.isFinite && (clock?.isValid(for: date) ?? true) && method.count <= 100 &&
        note.count <= 1000 && version > 0 && version < Int.max && exportedVersion >= 0 && exportedVersion <= version
    }
    var needsExport: Bool { metric.healthSupported && exportedVersion < version }
}

struct BodyDeletion: Identifiable, Codable, Equatable, Sendable {
    var id: UUID
    var metric: BodyMetric
}

struct HealthBodySample: Identifiable, Equatable, Sendable {
    var id: UUID
    var date: Date
    var metric: BodyMetric
    var value: Double
    var sourceName: String
    var sourceBundleID: String
    var localMeasurementID: UUID?
    var clock: EntryClock?
    var isRecompDXA = false // Exclude own DXA exports, even after reinstall or deletion.
}

struct BodyPoint: Identifiable, Equatable, Sendable {
    var id: UUID
    var date: Date
    var metric: BodyMetric
    var value: Double
    var source: String
    var method: String
    var isLocal: Bool
    var excludedFromTrend: Bool
    var scaleLocationID: UUID? = nil
    var clock: EntryClock? = nil
}

struct DailyBodyPoint: Identifiable, Equatable, Sendable {
    var date: Date
    var value: Double
    var id: Date { date }
}

enum BodyMath {
    static let metadataKey = "com.recomp.measurementID"
    static func syncID(id: UUID, metric: BodyMetric) -> String { "recomp.body.\(id.uuidString).\(metric.rawValue)" }
    static func healthValue(_ value: Double, metric: BodyMetric) -> Double { metric == .bodyFat ? value / 100 : value }
    static func fromHealth(_ value: Double, metric: BodyMetric) -> Double { metric == .bodyFat ? value * 100 : value }
    static func merged(local: [BodyMeasurement], health: [HealthBodySample], deletions: [BodyDeletion], ownBundleID: String, scaleAssignments: [String: UUID] = [:]) -> [BodyPoint] {
        let known = Set(local.map(\.id)).union(deletions.map(\.id))
        var seen = Set<UUID>()
        let external = health.filter {
            !$0.isRecompDXA && $0.metric.accepts($0.value) && seen.insert($0.id).inserted &&
            !($0.sourceBundleID == ownBundleID && $0.localMeasurementID.map { known.contains($0) } == true)
        }
        let a = local.filter(\.isValid).map {
            BodyPoint(id: $0.id, date: $0.date, metric: $0.metric, value: $0.value, source: "Recomp",
                      method: $0.method, isLocal: true, excludedFromTrend: $0.excludedFromTrend, scaleLocationID: $0.scaleLocationID, clock: $0.clock)
        }
        let b = external.map {
            BodyPoint(id: $0.id, date: $0.date, metric: $0.metric, value: $0.value, source: $0.sourceName,
                      method: $0.sourceBundleID, isLocal: false, excludedFromTrend: false, scaleLocationID: scaleAssignments[$0.id.uuidString], clock: $0.clock)
        }
        return (a + b).sorted { $0.date < $1.date }
    }
    static func daily(_ points: [BodyPoint], metric: BodyMetric, calendar: Calendar = .current) -> [DailyBodyPoint] {
        let grouped = Dictionary(grouping: points.filter { $0.metric == metric && metric.accepts($0.value) }) {
            ($0.clock.flatMap { EntryClock.displayDate($0.dayKey, calendar: calendar) }) ?? calendar.startOfDay(for: $0.date)
        }
        return grouped.compactMap { day, records in
            // Explicit local entries take priority for this day/metric. If all are excluded,
            // don't silently substitute an imported reading of the very same measurement.
            let local = records.filter(\.isLocal)
            let selected = (local.isEmpty ? records : local).filter { !$0.excludedFromTrend }
            guard let value = median(selected.map(\.value)) else { return nil }
            return DailyBodyPoint(date: day, value: value)
        }.sorted { $0.date < $1.date }
    }
    static func median(_ values: [Double]) -> Double? {
        let sorted = values.filter(\.isFinite).sorted()
        guard !sorted.isEmpty else { return nil }
        let middle = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
    }
}

enum BodyCSV {
    static func make(_ records: [BodyMeasurement], locations: [ScaleLocation] = []) -> String {
        let formatter = ISO8601DateFormatter()
        let header = "id,date,measurement,value,unit,method,excluded_from_trend,note,scale_location_id,scale_location,entry_timezone,diary_date,timezone_provenance"
        let rows = records.sorted { $0.date < $1.date }.map {
            [$0.id.uuidString, formatter.string(from: $0.date), $0.metric.title, String($0.value),
             $0.metric.canonicalUnit, $0.method, String($0.excludedFromTrend), $0.note,
             $0.scaleLocationID?.uuidString ?? "", ScaleMath.locationName($0.scaleLocationID, locations: locations), $0.clock?.timeZoneID ?? "", $0.clock?.dayKey ?? "", $0.clock?.provenance.rawValue ?? "unknown"].map(DiaryCSV.escape).joined(separator: ",")
        }
        return ([header] + rows).joined(separator: "\r\n") + "\r\n"
    }
}
