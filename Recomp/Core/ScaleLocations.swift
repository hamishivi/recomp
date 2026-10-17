import Foundation

/// User-defined labels for a physical scale / measuring location. Not GPS locations.
struct ScaleLocation: Identifiable, Codable, Equatable, Sendable {
    var id = UUID()
    var name: String
    var archived = false
    var isValid: Bool {
        !name.isEmpty && name.count <= 60 && name == name.trimmingCharacters(in: .whitespacesAndNewlines) &&
        !name.unicodeScalars.contains { CharacterSet.controlCharacters.contains($0) }
    }
    static func nameKey(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    }
    static let starters: [ScaleLocation] = [
        ScaleLocation(id: UUID(uuidString: "5984E2DA-6604-492E-9704-A937B633F411")!, name: "Home"),
        ScaleLocation(id: UUID(uuidString: "5984E2DA-6604-492E-9704-A937B633F412")!, name: "Girlfriend’s")
    ]
}

enum ScaleFilter: Hashable, Sendable {
    case all, untagged, location(UUID)
    func includes(_ point: BodyPoint) -> Bool {
        switch self {
        case .all: return true
        case .untagged: return point.scaleLocationID == nil
        case .location(let id): return point.scaleLocationID == id
        }
    }
}

struct BodyScaleSeries: Identifiable, Sendable {
    var id: String
    var label: String
    var points: [DailyBodyPoint]
}

struct ScaleDay: Identifiable, Equatable, Sendable {
    var date: Date
    var value: Double
    var seriesID: String
    var id: String { seriesID + ":" + String(date.timeIntervalSince1970) }
}

enum ScaleMath {
    static func locationName(_ id: UUID?, locations: [ScaleLocation]) -> String {
        guard let id else { return "Untagged" }
        return locations.first { $0.id == id }?.name ?? "Unknown scale"
    }
    static func seriesID(_ point: BodyPoint) -> String {
        if let id = point.scaleLocationID {
            // Weight tags identify the physical scale even if a method note changes.
            // Keep methods apart for body-fat and tape measurements.
            let method = point.metric == .weight ? "" : ":" + point.method
            return "location:" + id.uuidString + method
        }
        return (point.isLocal ? "untagged:local:" : "untagged:health:") + point.method
    }
    static func seriesLabel(_ point: BodyPoint, locations: [ScaleLocation]) -> String {
        if let id = point.scaleLocationID {
            let name = locationName(id, locations: locations)
            return point.metric == .weight || point.method.isEmpty ? name : name + " · " + point.method
        }
        let detail = point.isLocal ? point.method : point.source
        return detail.isEmpty ? "Untagged" : "Untagged · " + detail
    }
    static func series(_ points: [BodyPoint], metric: BodyMetric, locations: [ScaleLocation], calendar: Calendar = .current) -> [BodyScaleSeries] {
        let groups = Dictionary(grouping: points.filter { $0.metric == metric }, by: seriesID)
        return groups.compactMap { key, records in
            let daily = BodyMath.daily(records, metric: metric, calendar: calendar)
            guard !daily.isEmpty, let first = records.first else { return nil }
            return BodyScaleSeries(id: key, label: seriesLabel(first, locations: locations), points: daily)
        }.sorted { $0.label == $1.label ? $0.id < $1.id : $0.label < $1.label }
    }
    /// One daily median per physical scale/source. Preserve excluded local rows
    /// until daily aggregation so imports cannot silently replace them.
    static func latestWeightSeries(_ points: [BodyPoint], now: Date = Date(), calendar: Calendar = .current) -> [DailyBodyPoint] {
        let valid = points.filter { $0.date.timeIntervalSince1970.isFinite && $0.date <= now }
        return series(valid, metric: .weight, locations: [], calendar: calendar).sorted { a, b in
            let ad = a.points.last!.date, bd = b.points.last!.date
            if ad != bd { return ad > bd }
            if a.points.count != b.points.count { return a.points.count > b.points.count }
            return a.id < b.id
        }.first?.points ?? []
    }

    static func days(_ series: [BodyScaleSeries]) -> [ScaleDay] {
        var result: [ScaleDay] = []
        for group in series {
            for point in group.points { result.append(ScaleDay(date: point.date, value: point.value, seriesID: group.id)) }
        }
        return result.sorted { a, b in a.date == b.date ? a.seriesID < b.seriesID : a.date < b.date }
    }
}

extension AppState {
    var scaleLocationsAreValid: Bool {
        let ids = Set(scaleLocations.map(\.id))
        return scaleLocations.count <= 100 && ids.count == scaleLocations.count && scaleLocations.allSatisfy(\.isValid) &&
            Set(scaleLocations.map { ScaleLocation.nameKey($0.name) }).count == scaleLocations.count &&
            measurements.allSatisfy { $0.scaleLocationID.map { ids.contains($0) } ?? true } &&
            healthBodyScaleAssignments.allSatisfy { UUID(uuidString: $0.key) != nil && ids.contains($0.value) } &&
            (lastScaleLocationID.map { ids.contains($0) } ?? true) &&
            (maintenanceScaleLocationID.map { ids.contains($0) } ?? true)
    }
}
