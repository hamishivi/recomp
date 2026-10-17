import Foundation

/// Report values, not diagnoses or calculated tissue changes. Kept outside BodyMeasurement
/// so scan mass / estimated RMR cannot enter scale-based maintenance.
/// Compatible whole-body values have a separate, explicitly reviewed Health export path.
enum DXAUnit: String, Codable, CaseIterable, Identifiable, Sendable {
    case kg, g, lb, percent, cm2, cm3, in2, in3, gPerCM2, ratio, score, kcalPerDay
    var id: String { rawValue }
    var title: String {
        switch self {
        case .percent: return "%"
        case .cm2: return "cm²"
        case .cm3: return "cm³"
        case .in2: return "in²"
        case .in3: return "in³"
        case .gPerCM2: return "g/cm²"
        case .kcalPerDay: return "kcal/day"
        case .ratio, .score: return rawValue
        default: return rawValue
        }
    }
    func canonical(_ value: Double) -> Double {
        switch self {
        case .g: return value / 1000
        case .lb: return value * 0.45359237
        case .in2: return value * 6.4516
        case .in3: return value * 16.387064
        default: return value
        }
    }
}

enum DXAMetric: String, Codable, CaseIterable, Identifiable, Sendable {
    case bodyFat, totalMass, fatMass, leanSoftTissue, fatFreeMass, unspecifiedLeanMass
    case boneMineralContent, visceralFatMass, visceralFatArea, visceralFatVolume
    case androidGynoidRatio, boneMineralDensity, tScore, zScore, reportedRMR
    var id: String { rawValue }
    var title: String {
        switch self {
        case .bodyFat: return "Body fat"
        case .totalMass: return "Total mass"
        case .fatMass: return "Fat mass"
        case .leanSoftTissue: return "Lean soft tissue"
        case .fatFreeMass: return "Fat-free mass"
        case .unspecifiedLeanMass: return "Lean mass · definition unconfirmed"
        case .boneMineralContent: return "Bone mineral content"
        case .visceralFatMass: return "Visceral fat mass"
        case .visceralFatArea: return "Visceral fat area"
        case .visceralFatVolume: return "Visceral fat volume"
        case .androidGynoidRatio: return "Android/gynoid ratio"
        case .boneMineralDensity: return "Bone mineral density"
        case .tScore: return "T-score"
        case .zScore: return "Z-score"
        case .reportedRMR: return "Report's resting metabolic rate"
        }
    }
    var units: [DXAUnit] {
        switch self {
        case .bodyFat: return [.percent]
        case .visceralFatArea: return [.cm2, .in2]
        case .visceralFatVolume: return [.cm3, .in3]
        case .androidGynoidRatio: return [.ratio]
        case .boneMineralDensity: return [.gPerCM2]
        case .tScore, .zScore: return [.score]
        case .reportedRMR: return [.kcalPerDay]
        default: return [.kg, .lb, .g]
        }
    }
    var canonicalUnit: String { units.first?.title ?? "" }
    func accepts(_ value: Double, unit: DXAUnit) -> Bool {
        guard units.contains(unit), value.isFinite else { return false }
        let v = unit.canonical(value)
        // Broad typing/unit limits only, never clinical cutoffs.
        switch self {
        case .bodyFat: return (0...100).contains(v)
        case .tScore, .zScore: return (-20...20).contains(v)
        case .androidGynoidRatio: return (0...20).contains(v)
        case .boneMineralDensity: return (0.01...10).contains(v)
        case .visceralFatArea: return (0...10000).contains(v)
        case .visceralFatVolume: return (0...100000).contains(v)
        case .reportedRMR: return (100...10000).contains(v)
        case .totalMass: return (0.001...600).contains(v)
        default: return (0...600).contains(v)
        }
    }
    var explanation: String {
        switch self {
        case .leanSoftTissue: return "Non-fat, non-bone tissue, including water and organs—not just muscle. Use only when the report defines lean this way."
        case .fatFreeMass: return "Includes non-fat components, including bone mineral. Keep separate from lean soft tissue."
        case .unspecifiedLeanMass: return "The report says lean mass but its definition is unclear. Do not assume it is muscle or subtract bone automatically."
        case .bodyFat: return "Enter 19 for 19%. Confirm total-body versus regional percentage."
        case .boneMineralContent: return "A mass, not bone mineral density."
        case .boneMineralDensity, .tScore, .zScore: return "Copy the anatomical site exactly. These records are not diagnostic interpretations; review bone findings with the reporting clinician."
        case .reportedRMR: return "Store as printed. A report may estimate this; it is not maintenance calories and is never used to set targets."
        case .visceralFatMass, .visceralFatArea, .visceralFatVolume: return "Check whether the report gives mass, area or volume. These are separate quantities, not interchangeable."
        default: return "Use the report's value and units. Regional and whole-body values are separate; regions are never added to produce a total."
        }
    }
}

struct DXAValue: Codable, Equatable, Identifiable, Sendable {
    var id = UUID()
    var metric: DXAMetric
    var region: String // Explicitly reviewed anatomical site. No guessed 'total' for regional rows.
    var value: Double
    var unit: DXAUnit
    var sourceExcerpt = ""
    var key: String { metric.rawValue + "|" + DXAScan.normalized(region) }
    var canonicalValue: Double { unit.canonical(value) }
    var isValid: Bool {
        metric.accepts(value, unit: unit) && !DXAScan.normalized(region).isEmpty &&
        region.count <= 100 && sourceExcerpt.count <= 1000
    }
}

struct DXAScan: Codable, Equatable, Identifiable, Sendable {
    static let maxPDFBytes = 12 * 1024 * 1024
    static let maxAllPDFBytes = 48 * 1024 * 1024
    var id = UUID()
    var scanDay: String // YYYY-MM-DD as printed; never interpreted as a birthday or inferred from file date.
    var provider = ""
    var scanner = ""
    var comparisonGroup = "" // User-assigned comparable scanner/protocol, independent of bathroom-scale tags.
    var notes = ""
    var values: [DXAValue] = []
    var sourceFilename = ""
    var sourceSHA256: String?
    var retainedPDF: Data?
    var reviewed = false
    var isValid: Bool {
        guard Self.date(for: scanDay) != nil, !Self.normalized(provider).isEmpty,
              provider.count <= 120, scanner.count <= 160, comparisonGroup.count <= 160,
              notes.count <= 4000, sourceFilename.count <= 250, reviewed,
              !values.isEmpty, values.count <= 100, values.allSatisfy(\.isValid),
              Set(values.map(\.id)).count == values.count,
              Set(values.map(\.key)).count == values.count else { return false }
        if let hash = sourceSHA256 {
            guard hash.count == 64, hash.allSatisfy({ "0123456789abcdef".contains($0) }) else { return false }
        }
        if let data = retainedPDF {
            guard data.count <= Self.maxPDFBytes, data.starts(with: Data("%PDF-".utf8)), sourceSHA256 != nil else { return false }
        }
        return true
    }
    var date: Date { Self.date(for: scanDay) ?? .distantPast }
    static func normalized(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ").lowercased()
    }
    static func day(_ date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
    static func date(for day: String) -> Date? {
        let pieces = day.split(separator: "-", omittingEmptySubsequences: false)
        guard pieces.count == 3, day.count == 10,
              let y = Int(pieces[0]), (1900...2200).contains(y), let m = Int(pieces[1]), let d = Int(pieces[2]) else { return nil }
        var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(secondsFromGMT: 0)!
        guard let date = c.date(from: DateComponents(year: y, month: m, day: d, hour: 12)), Self.day(date, calendar: c) == day else { return nil }
        return date
    }
    func value(_ metric: DXAMetric, region: String = "Total body") -> DXAValue? {
        values.first { $0.metric == metric && Self.normalized($0.region) == Self.normalized(region) }
    }
    /// Advisory consistency checks, not corrections: percentages may use tissue mass denominators.
    var reviewNotes: [String] {
        var result: [String] = []
        if let t = value(.totalMass), let f = value(.fatMass), f.canonicalValue > t.canonicalValue {
            result.append("Total-body fat mass exceeds total mass. Check the units and selected row.")
        }
        if let t = value(.totalMass), let f = value(.fatMass), let l = value(.leanSoftTissue), let b = value(.boneMineralContent),
           abs(t.canonicalValue - f.canonicalValue - l.canonicalValue - b.canonicalValue) > max(0.5, t.canonicalValue * 0.02) {
            result.append("Fat + lean soft tissue + bone mineral does not closely match total mass. Check the report; nothing is automatically corrected.")
        }
        return result
    }
}

extension AppState {
    var dxaScansAreValid: Bool {
        let hashes = dxaScans.compactMap(\.sourceSHA256)
        return dxaScans.allSatisfy(\.isValid) && Set(dxaScans.map(\.id)).count == dxaScans.count &&
            Set(hashes).count == hashes.count &&
            dxaScans.reduce(0, { $0 + ($1.retainedPDF?.count ?? 0) }) <= DXAScan.maxAllPDFBytes
    }
}

struct DXAComparison: Equatable, Sendable {
    var previousDay: String
    var difference: Double // canonical units, percentage points for body fat
}

enum DXATrends {
    static func previousDifference(for value: DXAValue, scan: DXAScan, scans: [DXAScan]) -> DXAComparison? {
        let group = DXAScan.normalized(scan.comparisonGroup)
        // Matching user tags are necessary, not proof of clinical comparability.
        guard !group.isEmpty, value.metric != .unspecifiedLeanMass else { return nil }
        let matching = scans.filter { $0.id != scan.id && $0.scanDay < scan.scanDay &&
            DXAScan.normalized($0.comparisonGroup) == group && $0.value(value.metric, region: value.region) != nil }
        guard let latestDay = matching.map(\.scanDay).max() else { return nil }
        let latest = matching.filter { $0.scanDay == latestDay }
        // Repeated same-day scans are not silently resolved or averaged.
        guard latest.count == 1, let prior = latest.first,
              let old = prior.value(value.metric, region: value.region) else { return nil }

        return DXAComparison(previousDay: prior.scanDay, difference: value.canonicalValue - old.canonicalValue)
    }
}

enum DXACSV {
    static func make(_ scans: [DXAScan]) -> String {
        let header = "scan_id,scan_date,provider,scanner,comparison_group,metric,region,reported_value,reported_unit,canonical_value,canonical_unit,source_filename,notes"
        let rows = scans.sorted { $0.scanDay < $1.scanDay }.flatMap { scan in
            scan.values.map { v in
                [scan.id.uuidString, scan.scanDay, scan.provider, scan.scanner, scan.comparisonGroup,
                 v.metric.title, v.region, String(v.value), v.unit.title, String(v.canonicalValue),
                 v.metric.canonicalUnit, scan.sourceFilename, scan.notes].map(DiaryCSV.escape).joined(separator: ",")
            }
        }
        return ([header] + rows).joined(separator: "\r\n") + "\r\n"
    }
}
