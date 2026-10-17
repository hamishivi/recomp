import Foundation

struct DXACandidate: Identifiable, Equatable, Sendable {
    var id: Int // line index; repeating values on different lines remain visible for review
    var value: DXAValue
}

/// Deliberately narrow, offline label/value parser. Never guesses table column order,
/// scan dates, regional totals, unlabeled units, or which historical result is current.
/// Candidates are offered individually; none is saved/accepted automatically.
enum DXATextParser {
    static let maxCharacters = 100_000
    static let labels: [(String, DXAMetric, String)] = [
        ("total body fat %", .bodyFat, "Total body"), ("total body fat", .bodyFat, "Total body"),
        ("body fat percentage", .bodyFat, ""), ("body fat %", .bodyFat, ""),
        ("total mass", .totalMass, ""), ("total body mass", .totalMass, "Total body"),
        ("total body fat mass", .fatMass, "Total body"), ("total fat mass", .fatMass, ""), ("fat mass", .fatMass, ""), ("fat tissue", .fatMass, ""),
        ("total body lean soft tissue", .leanSoftTissue, "Total body"), ("total lean soft tissue", .leanSoftTissue, ""), ("lean soft tissue", .leanSoftTissue, ""),
        ("total lean tissue", .leanSoftTissue, ""), ("lean tissue", .leanSoftTissue, ""),
        ("total lean mass", .unspecifiedLeanMass, ""), ("lean mass", .unspecifiedLeanMass, ""),
        ("fat-free mass", .fatFreeMass, ""), ("fat free mass", .fatFreeMass, ""),
        ("total body bone mineral content", .boneMineralContent, "Total body"), ("total bone mineral content", .boneMineralContent, ""),
        ("bone mineral content (bmc)", .boneMineralContent, ""), ("bone mineral content", .boneMineralContent, ""),
        ("bmc", .boneMineralContent, ""),
        ("visceral fat mass", .visceralFatMass, "VAT"), ("vat mass", .visceralFatMass, "VAT"),
        ("visceral fat area", .visceralFatArea, "VAT"), ("vat area", .visceralFatArea, "VAT"),
        ("visceral fat volume", .visceralFatVolume, "VAT"), ("vat volume", .visceralFatVolume, "VAT"),
        ("android/gynoid ratio", .androidGynoidRatio, "Android/gynoid"), ("a/g ratio", .androidGynoidRatio, "Android/gynoid"),
        ("bone mineral density", .boneMineralDensity, ""), ("bmd", .boneMineralDensity, ""),
        ("t-score", .tScore, ""), ("z-score", .zScore, ""),
        ("resting metabolic rate", .reportedRMR, "Whole person"), ("estimated rmr", .reportedRMR, "Whole person"),
        ("rmr", .reportedRMR, "Whole person")
    ]
    private struct Rule {
        let label: String
        let metric: DXAMetric
        let region: String
        let expression: NSRegularExpression
    }
    private static let rules: [Rule] = labels.compactMap { label, metric, region in
        let pattern = "^" + NSRegularExpression.escapedPattern(for: label) +
            #"(?:\s*\(([^)]+)\))?\s*[:=]?\s+([-+]?\d[\d,]*(?:\.\d+)?)\s*([A-Za-z%²³/0-9^]*)\.?$"#
        guard let expression = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return nil }
        return Rule(label: label, metric: metric, region: region, expression: expression)
    }
    static func candidates(in text: String) -> [DXACandidate] {
        guard text.count <= maxCharacters else { return [] }
        var results: [DXACandidate] = []
        for (lineID, original) in text.components(separatedBy: .newlines).enumerated() {
            let line = original.replacingOccurrences(of: "\u{00a0}", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty, line.count <= 600 else { continue }
            for rule in rules {
                let label = rule.label, metric = rule.metric, region = rule.region
                guard let match = rule.expression.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) else { continue }
                func group(_ index: Int) -> String {
                    guard let r = Range(match.range(at: index), in: line) else { return "" }
                    return String(line[r])
                }
                guard let number = number(group(2)) else { continue }
                let headerUnit = parseUnit(group(1)), suffixUnit = parseUnit(group(3))
                // Both written units must be recognized and agree; don't fall back on an unknown suffix.
                if !group(1).isEmpty && headerUnit == nil { continue }
                if !group(3).isEmpty && suffixUnit == nil { continue }
                if let a = headerUnit, let b = suffixUnit, a != b { continue }
                let implicit: DXAUnit? = label.contains("%") ? .percent :
                    metric == .androidGynoidRatio ? .ratio : (metric == .tScore || metric == .zScore) ? .score : nil
                guard let unit = suffixUnit ?? headerUnit ?? implicit, metric.accepts(number, unit: unit) else { continue }
                results.append(DXACandidate(id: lineID, value: DXAValue(metric: metric, region: region,
                    value: number, unit: unit, sourceExcerpt: line)))
                break
            }
        }
        return results
    }
    /// English decimal / grouping only; ambiguous comma-decimal text is left for manual review.
    static func number(_ text: String) -> Double? {
        let pattern = #"^[-+]?(?:\d+|\d{1,3}(?:,\d{3})+)(?:\.\d+)?$"#
        guard text.range(of: pattern, options: .regularExpression) != nil,
              let value = Double(text.replacingOccurrences(of: ",", with: "")), value.isFinite else { return nil }
        return value
    }
    static func parseUnit(_ text: String) -> DXAUnit? {
        switch text.lowercased().trimmingCharacters(in: .whitespaces) {
        case "kg", "kgs": return .kg
        case "g", "grams": return .g
        case "lb", "lbs": return .lb
        case "%": return .percent
        case "cm2", "cm²", "cm^2": return .cm2
        case "cm3", "cm³", "cm^3", "cc": return .cm3
        case "in2", "in²", "in^2": return .in2
        case "in3", "in³", "in^3": return .in3
        case "g/cm2", "g/cm²", "g/cm^2": return .gPerCM2
        case "ratio": return .ratio
        case "score": return .score
        case "kcal/day", "cal/day": return .kcalPerDay
        default: return nil
        }
    }
}
