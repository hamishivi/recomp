import Foundation

/// Only types with an explicit whole-body HealthKit equivalent are eligible.
/// Regional rows, RMR, bone results and ambiguous lean definitions remain report-only.
enum DXAHealthMetric: String, Codable, CaseIterable, Identifiable, Sendable {
    case weight, bodyFat, leanBodyMass
    var id: String { rawValue }
    var title: String {
        switch self {
        case .weight: return "Weight"
        case .bodyFat: return "Body fat percentage"
        case .leanBodyMass: return "Lean body mass"
        }
    }
    var unit: String { self == .bodyFat ? "%" : "kg" }
    func healthValue(_ canonical: Double) -> Double { self == .bodyFat ? canonical / 100 : canonical }
}

enum DXAHealthBasis: String, Codable, Sendable {
    case reportedTotalMass, reportedBodyFat, reportedFatFreeMass, leanSoftTissuePlusBone
    var explanation: String {
        switch self {
        case .reportedTotalMass: return "Reported whole-body total mass."
        case .reportedBodyFat: return "Reported whole-body percentage; not recalculated from other fields."
        case .reportedFatFreeMass: return "Reported whole-body fat-free mass, including bone mineral. Not muscle mass."
        case .leanSoftTissuePlusBone: return "Calculated for Health: whole-body lean soft tissue + bone mineral content. The original report values stay unchanged. Not muscle mass."
        }
    }
}

struct DXAHealthCandidate: Equatable, Identifiable, Sendable {
    var metric: DXAHealthMetric
    var value: Double // kg or percentage points, not Health's percent fraction
    var basis: DXAHealthBasis
    var id: DXAHealthMetric { metric }
}

struct DXAHealthPlan: Equatable, Sendable {
    var candidates: [DXAHealthCandidate] = []
    var warnings: [String] = []
    func candidate(_ metric: DXAHealthMetric) -> DXAHealthCandidate? { candidates.first { $0.metric == metric } }
}

enum DXAHealthMapping {
    static func isWholeBody(_ region: String) -> Bool {
        // Deliberately do not accept "total" alone, subtotal, total-body-less-head, or regional totals.
        ["total body", "whole body", "total-body", "whole-body"].contains(DXAScan.normalized(region))
    }
    static func plan(_ scan: DXAScan) -> DXAHealthPlan {
        guard scan.isValid else { return DXAHealthPlan(warnings: ["Review and save a valid scan first."]) }
        var plan = DXAHealthPlan()
        func rows(_ metric: DXAMetric) -> [DXAValue] {
            scan.values.filter { $0.metric == metric && isWholeBody($0.region) }
        }
        func unique(_ metric: DXAMetric) -> DXAValue? {
            let matches = rows(metric)
            if matches.count > 1 {
                plan.warnings.append("More than one whole-body \(metric.title.lowercased()) row. Resolve the duplicate before sharing that value.")
            }
            return matches.count == 1 ? matches[0] : nil
        }
        let mass = unique(.totalMass), fat = unique(.bodyFat)
        if let mass { plan.candidates.append(.init(metric: .weight, value: mass.canonicalValue, basis: .reportedTotalMass)) }
        if let fat { plan.candidates.append(.init(metric: .bodyFat, value: fat.canonicalValue, basis: .reportedBodyFat)) }
        let free = unique(.fatFreeMass), soft = unique(.leanSoftTissue), bone = unique(.boneMineralContent)
        // Never use reported "lean" with an unknown definition; never infer lean mass from a percentage
        // whose denominator may be soft-tissue mass rather than total mass.
        var lean: DXAHealthCandidate?
        if let free, free.canonicalValue > 0 {
            lean = .init(metric: .leanBodyMass, value: free.canonicalValue, basis: .reportedFatFreeMass)
        } else if rows(.fatFreeMass).isEmpty, let soft, let bone, soft.canonicalValue > 0 {
            lean = .init(metric: .leanBodyMass, value: soft.canonicalValue + bone.canonicalValue, basis: .leanSoftTissuePlusBone)
        }
        if let free, let soft, let bone,
           abs(free.canonicalValue - soft.canonicalValue - bone.canonicalValue) > 0.2 {
            lean = nil
            plan.warnings.append("Fat-free mass disagrees with lean soft tissue + bone mineral by more than 0.2 kg. Check the report before sharing lean body mass.")
        }
        if let value = lean, !value.value.isFinite || value.value > 600 ||
            (mass.map { value.value > $0.canonicalValue + 0.1 } ?? false) {
            lean = nil
            plan.warnings.append("The lean-body-mass result exceeds total mass or the input limit. Check units and definitions.")
        }
        if let lean { plan.candidates.append(lean) }
        else {
            plan.warnings.append("Lean body mass needs unambiguous whole-body fat-free mass, or whole-body lean soft tissue plus bone mineral content. Regional or undefined lean values are not exported.")
        }
        return plan
    }
}

/// Persistent per-scan, per-type export receipts. Missing scan/selected value means remove
/// a previously attempted export. Keeping the attempt before an await makes crash cleanup possible.
struct DXAHealthLink: Codable, Equatable, Identifiable, Sendable {
    var id: UUID // DXAScan.id; its namespace is distinct from ordinary body measurements
    var version = 1
    var selectedMetrics: Set<DXAHealthMetric> = []
    var date: Date
    var timeZoneID: String
    var timeIsApproximate = true
    var attemptedMetrics: Set<DXAHealthMetric> = []
    var completedVersions: [String: Int] = [:]
    var lastExportedAt: Date?
    var isValid: Bool {
        version > 0 && version < Int.max && date.timeIntervalSince1970.isFinite &&
        TimeZone(identifier: timeZoneID) != nil &&
        completedVersions.allSatisfy { DXAHealthMetric(rawValue: $0.key) != nil && $0.value > 0 && $0.value <= version }
    }
    func desiredValues(scan: DXAScan?) -> [DXAHealthCandidate] {
        guard let scan, scan.id == id else { return [] }
        return DXAHealthMapping.plan(scan).candidates.filter { selectedMetrics.contains($0.metric) }
    }
    func pendingMetrics(scan: DXAScan?) -> [DXAHealthMetric] {
        let desired = Set(desiredValues(scan: scan).map(\.metric))
        return DXAHealthMetric.allCases.filter {
            (desired.contains($0) || attemptedMetrics.contains($0)) && completedVersions[$0.rawValue] != version
        }.sorted { a, b in
            // Remove vanished/deselected fields before writing replacement values.
            let ad = desired.contains(a), bd = desired.contains(b)
            return ad == bd ? a.rawValue < b.rawValue : !ad
        }
    }
}

enum DXAHealthIdentity {
    static let scanMetadataKey = "com.recomp.dxa.scanID"
    static let methodMetadataKey = "com.recomp.dxa.method"
    static let basisMetadataKey = "com.recomp.dxa.basis"
    static let dayMetadataKey = "com.recomp.dxa.scanDay"
    static let approximateTimeMetadataKey = "com.recomp.dxa.approximateTime"
    static func sampleID(scanID: UUID, metric: DXAHealthMetric) -> String {
        "recomp.dxa.\(scanID.uuidString).\(metric.rawValue)"
    }
    static func isOwnScanExport(source: String, ownBundleID: String, scanID: String?, syncID: String?) -> Bool {
        guard source == ownBundleID else { return false }
        if let scanID, UUID(uuidString: scanID) != nil { return true }
        guard let syncID else { return false }
        let parts = syncID.split(separator: ".")
        return parts.count == 4 && parts[0] == "recomp" && parts[1] == "dxa" &&
            UUID(uuidString: String(parts[2])) != nil && DXAHealthMetric(rawValue: String(parts[3])) != nil
    }
}

enum DXAHealthTime {
    /// Construct a real instant on the report's calendar date, in the explicitly chosen timezone.
    /// Noon is only a labelled date-only placeholder, not an inferred scan time.
    static func date(day: String, timeZoneID: String, preserving time: Date? = nil) -> Date? {
        guard DXAScan.date(for: day) != nil, let zone = TimeZone(identifier: timeZoneID) else { return nil }
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = zone
        let dayParts = day.split(separator: "-").compactMap { Int($0) }
        let hm = time.map { calendar.dateComponents([.hour, .minute], from: $0) }
        let components = DateComponents(year: dayParts[0], month: dayParts[1], day: dayParts[2],
                                        hour: hm?.hour ?? 12, minute: hm?.minute ?? 0)
        guard let result = calendar.date(from: components), self.day(result, timeZoneID: timeZoneID) == day else { return nil }
        // Nonexistent local times during a DST change must be explicitly reviewed, not normalized silently.
        let actual = calendar.dateComponents([.hour, .minute], from: result)
        guard actual.hour == components.hour && actual.minute == components.minute else { return nil }
        return result
    }
    static func day(_ date: Date, timeZoneID: String) -> String? {
        guard let zone = TimeZone(identifier: timeZoneID) else { return nil }
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = zone
        return DXAScan.day(date, calendar: calendar)
    }
}

extension AppState {
    var dxaHealthIsValid: Bool {
        Set(dxaHealthLinks.map(\.id)).count == dxaHealthLinks.count && dxaHealthLinks.allSatisfy { link in
            guard link.isValid else { return false }
            if let scan = dxaScans.first(where: { $0.id == link.id }) {
                return DXAHealthTime.day(link.date, timeZoneID: link.timeZoneID) == scan.scanDay
            }
            return link.selectedMetrics.isEmpty // deleted-scan cleanup tombstone
        }
    }
}
