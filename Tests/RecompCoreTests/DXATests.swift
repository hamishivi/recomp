import Foundation
import XCTest
#if !RECOMP_NATIVE_TESTS
@testable import RecompCore
#endif

final class DXATests: XCTestCase {
    private func scan(day: String = "2026-09-01", fat: Double = 20, group: String = "Clinic / scanner A") -> DXAScan {
        var s = DXAScan(scanDay: day)
        s.provider = "Example clinic"; s.scanner = "Device A"; s.comparisonGroup = group; s.reviewed = true
        s.values = [DXAValue(metric: .bodyFat, region: "Total body", value: fat, unit: .percent)]
        return s
    }
    private func candidates(_ text: String) -> [DXACandidate] { DXATextParser.candidates(in: text) }
    func testCanonicalMassUnits() {
        XCTAssertEqual(DXAUnit.lb.canonical(100), 45.359237, accuracy: 1e-8)
        XCTAssertEqual(DXAUnit.g.canonical(3500), 3.5)
    }
    func testAreaAndVolumeAreDistinct() {
        XCTAssertEqual(DXAUnit.in2.canonical(1), 6.4516)
        XCTAssertEqual(DXAUnit.in3.canonical(1), 16.387064)
        XCTAssertFalse(DXAMetric.visceralFatMass.accepts(100, unit: .cm3))
        XCTAssertFalse(DXAMetric.visceralFatArea.accepts(100, unit: .cm3))
    }
    func testPercentAndBoneUnits() {
        XCTAssertEqual(DXAUnit.percent.canonical(19), 19)
        XCTAssertFalse(DXAMetric.boneMineralContent.accepts(1.2, unit: .gPerCM2))
        XCTAssertFalse(DXAMetric.boneMineralDensity.accepts(3200, unit: .g))
    }
    func testSignedScoresAllowedButNoNegativeMass() {
        XCTAssertTrue(DXAMetric.tScore.accepts(-2.1, unit: .score))
        XCTAssertTrue(DXAMetric.zScore.accepts(1.2, unit: .score))
        XCTAssertFalse(DXAMetric.fatMass.accepts(-2.1, unit: .kg))
    }
    func testNonFiniteValuesRejected() {
        for m in DXAMetric.allCases {
            XCTAssertFalse(m.accepts(.nan, unit: m.units[0]))
            XCTAssertFalse(m.accepts(.infinity, unit: m.units[0]))
        }
    }
    func testInvalidDateRejectedWithoutNormalization() {
        for date in ["2026-02-30", "2025-02-29", "09/18/2026", "2026-1-01", "1800-01-01", "", "2026-99-01"] {
            XCTAssertNil(DXAScan.date(for: date), date)
        }
        XCTAssertNotNil(DXAScan.date(for: "2024-02-29"))
    }
    func testScanNeedsProviderReviewAndAtLeastOneResult() {
        var s = scan(); XCTAssertTrue(s.isValid)
        s.reviewed = false; XCTAssertFalse(s.isValid)
        s.reviewed = true; s.provider = " \n "; XCTAssertFalse(s.isValid)
        s.provider = "Test"; s.values = []; XCTAssertFalse(s.isValid)
    }
    func testUnreviewedRegionRejected() {
        var s = scan(); s.values[0].region = ""; XCTAssertFalse(s.isValid)
    }
    func testDuplicatesMetricSiteRejected() {
        var s = scan(); var duplicate = s.values[0]; duplicate.id = UUID(); duplicate.region = " total   BODY "
        s.values.append(duplicate); XCTAssertFalse(s.isValid)
    }
    func testRegionalValuesNotSummedIntoTotals() {
        var s = scan(); s.values[0].region = "Trunk"
        XCTAssertTrue(s.isValid); XCTAssertNil(s.value(.bodyFat))
        XCTAssertEqual(s.value(.bodyFat, region: "Trunk")?.value, 20)
    }
    func testDuplicateValueIdentityRejected() {
        var s = scan(); var duplicate = s.values[0]; duplicate.region = "Trunk"; s.values.append(duplicate)
        XCTAssertFalse(s.isValid)
    }
    func testTextLimitsProtectState() {
        var s = scan(); s.notes = String(repeating: "x", count: 4001); XCTAssertFalse(s.isValid)
        s.notes = ""; s.values[0].sourceExcerpt = String(repeating: "x", count: 1001); XCTAssertFalse(s.isValid)
    }
    func testPDFRetentionNeedsValidFingerprintAndHeader() {
        var s = scan(); s.retainedPDF = Data("%PDF-1.4\nsynthetic".utf8)
        XCTAssertFalse(s.isValid)
        s.sourceSHA256 = String(repeating: "a", count: 64); XCTAssertTrue(s.isValid)
        s.retainedPDF = Data("Not a PDF".utf8); XCTAssertFalse(s.isValid)
    }
    func testOversizedPDFRejected() {
        var s = scan(); s.sourceSHA256 = String(repeating: "a", count: 64)
        s.retainedPDF = Data("%PDF-".utf8) + Data(repeating: 0, count: DXAScan.maxPDFBytes)
        XCTAssertFalse(s.isValid)
    }
    func testStateRejectsDuplicatePDFAndIDs() {
        var s = scan(); s.sourceSHA256 = String(repeating: "b", count: 64)
        var state = AppState(); state.dxaScans = [s]; XCTAssertTrue(state.isValid)
        var other = s; other.id = UUID(); state.dxaScans.append(other); XCTAssertFalse(state.isValid)
        other.sourceSHA256 = nil; other.id = s.id; state.dxaScans = [s, other]; XCTAssertFalse(state.isValid)
    }
    func testSchema3MigrationKeepsDiaryAndStartsEmptyScanLog() throws {
        var state = AppState()
        state.entries = [FoodEntry(name: "Existing", date: Date(), meal: .lunch, nutrition: .startingTargets)]
        state.measurements = [BodyMeasurement(date: Date(), metric: .weight, value: 85)]
        state.lastScaleLocationID = state.scaleLocations[0].id
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(state)) as? [String: Any])
        object["schemaVersion"] = 3; object.removeValue(forKey: "dxaScans")
        let migrated = try JSONDecoder().decode(AppState.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertEqual(migrated.schemaVersion, 8); XCTAssertTrue(migrated.dxaScans.isEmpty)
        XCTAssertEqual(migrated.entries.map { var e = $0; e.clock = nil; return e }, state.entries); XCTAssertEqual(migrated.measurements.map { var e = $0; e.clock = nil; return e }, state.measurements)
        XCTAssertEqual(migrated.lastScaleLocationID, state.lastScaleLocationID); XCTAssertTrue(migrated.isValid)
    }
    func testSchema4RoundTripWithReportBytesAndReviewedValues() throws {
        var state = AppState(); var s = scan(); s.sourceSHA256 = String(repeating: "a", count: 64)
        s.retainedPDF = Data("%PDF-1.4\nsynthetic".utf8); state.dxaScans = [s]
        XCTAssertEqual(try JSONDecoder().decode(AppState.self, from: JSONEncoder().encode(state)), state)
    }
    func testFutureSchemaRejected() throws {
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(AppState())) as? [String: Any])
        object["schemaVersion"] = 999
        XCTAssertThrowsError(try JSONDecoder().decode(AppState.self, from: JSONSerialization.data(withJSONObject: object)))
    }
    func testSavingRoundTripPreservesStateFile() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let f = StateFile(url: dir.appendingPathComponent("state.json")); var state = AppState(); state.dxaScans = [scan()]
        try f.save(state); XCTAssertEqual(try f.load(), state)
        var bad = state; bad.dxaScans[0].reviewed = false
        XCTAssertThrowsError(try f.save(bad)); XCTAssertEqual(try f.load(), state)
    }
    func testScanResultsNeverAffectMaintenanceOrTargets() {
        let now = DXAScan.date(for: "2026-09-18")!
        var data = AdaptiveDemo.stable.data(now: now)
        let before = MaintenanceEngine.evaluate(state: data.state, points: data.points, now: now)
        var s = scan(); s.values += [DXAValue(metric: .totalMass, region: "Total body", value: 200, unit: .kg),
                                   DXAValue(metric: .reportedRMR, region: "Whole person", value: 4500, unit: .kcalPerDay)]
        data.state.dxaScans = [s]
        XCTAssertEqual(MaintenanceEngine.evaluate(state: data.state, points: data.points, now: now), before)
        XCTAssertEqual(data.state.targets, .startingTargets)
    }
    func testComparisonNeedsExplicitMatchingGroup() {
        let old = scan(); let current = scan(day: "2026-09-18", fat: 19)
        XCTAssertEqual(DXATrends.previousDifference(for: current.values[0], scan: current, scans: [old, current])?.difference, -1)
        var different = current; different.comparisonGroup = "Different scanner"
        XCTAssertNil(DXATrends.previousDifference(for: different.values[0], scan: different, scans: [old]))
        var empty = current; empty.comparisonGroup = ""
        var oldEmpty = old; oldEmpty.comparisonGroup = ""
        XCTAssertNil(DXATrends.previousDifference(for: empty.values[0], scan: empty, scans: [oldEmpty]))
    }
    func testComparisonDoesNotMixRegionsOrSameDate() {
        let current = scan(); var old = scan(day: "2026-08-01"); old.values[0].region = "Trunk"
        XCTAssertNil(DXATrends.previousDifference(for: current.values[0], scan: current, scans: [old]))
        old.values[0].region = "Total body"; old.scanDay = current.scanDay
        XCTAssertNil(DXATrends.previousDifference(for: current.values[0], scan: current, scans: [old]))
    }
    func testLatestComparableScanChosenNotLatestOtherScanner() {
        let a = scan(day: "2026-07-01", fat: 23)
        let b = scan(day: "2026-08-01", fat: 22)
        let c = scan(day: "2026-08-30", fat: 18, group: "Different")
        let current = scan(fat: 21)
        let r = DXATrends.previousDifference(for: current.values[0], scan: current, scans: [c, a, b])
        XCTAssertEqual(r, DXAComparison(previousDay: "2026-08-01", difference: -1))
    }
    func testComparisonConvertsUnitsWithoutChangingOriginals() {
        var old = scan(day: "2026-08-01"); old.values = [DXAValue(metric: .fatMass, region: "Total body", value: 40, unit: .lb)]
        var current = scan(); current.values = [DXAValue(metric: .fatMass, region: "Total body", value: 18, unit: .kg)]
        XCTAssertEqual(DXATrends.previousDifference(for: current.values[0], scan: current, scans: [old])!.difference, 18 - 40 * 0.45359237, accuracy: 1e-8)
        XCTAssertEqual(old.values[0].value, 40)
    }
    func testUnspecifiedLeanMassNeverComparedWithTissueOrItself() {
        var a = scan(day: "2026-08-01"); a.values = [DXAValue(metric: .unspecifiedLeanMass, region: "Total body", value: 65, unit: .kg)]
        var b = scan(); b.values = a.values
        XCTAssertNil(DXATrends.previousDifference(for: b.values[0], scan: b, scans: [a]))
        b.values[0].metric = .leanSoftTissue
        XCTAssertNil(DXATrends.previousDifference(for: b.values[0], scan: b, scans: [a]))
    }
    func testInconsistentMassWarningIsNonDestructive() {
        var s = scan(); s.values += [DXAValue(metric: .totalMass, region: "Total body", value: 80, unit: .kg),
            DXAValue(metric: .fatMass, region: "Total body", value: 90, unit: .kg)]
        XCTAssertFalse(s.reviewNotes.isEmpty); XCTAssertEqual(s.value(.fatMass)?.value, 90)
    }
    func testMassBalanceCheckDoesNotInferLean() {
        var s = scan(); s.values += [DXAValue(metric: .totalMass, region: "Total body", value: 85, unit: .kg),
            DXAValue(metric: .fatMass, region: "Total body", value: 17, unit: .kg),
            DXAValue(metric: .leanSoftTissue, region: "Total body", value: 50, unit: .kg),
            DXAValue(metric: .boneMineralContent, region: "Total body", value: 3000, unit: .g)]
        XCTAssertTrue(s.reviewNotes.contains { $0.contains("does not closely match") })
        XCTAssertNil(s.value(.fatFreeMass)); XCTAssertEqual(s.value(.leanSoftTissue)?.value, 50)
    }
    func testCSVFormulaSafetyAndOriginalUnits() {
        var s = scan(); s.provider = "=SUM(A1), clinic"; s.values[0].region = "@region"
        let csv = DXACSV.make([s])
        XCTAssertTrue(csv.contains("'=SUM(A1), clinic")); XCTAssertTrue(csv.contains("'@region"))
        XCTAssertTrue(csv.contains("reported_value,reported_unit")); XCTAssertTrue(csv.contains("canonical_unit"))
    }
    func testLabelledTotalPercentage() {
        let c = candidates("Total Body Fat %: 19.2%")
        XCTAssertEqual(c.count, 1); XCTAssertEqual(c[0].value.region, "Total body")
        XCTAssertEqual(c[0].value.value, 19.2); XCTAssertEqual(c[0].value.unit, .percent)
    }
    func testHeaderAndSuffixMassUnits() {
        let c = candidates("Total Mass (lbs) 187.4\nTotal Fat Mass: 17 kg\nBone Mineral Content (BMC): 3,150 g")
        XCTAssertEqual(c.count, 3)
        XCTAssertEqual(c[0].value.unit, .lb); XCTAssertEqual(c[2].value.value, 3150)
        XCTAssertEqual(c[2].value.canonicalValue, 3.15)
    }
    func testGenericMetricRequiresRegionReview() {
        let c = candidates("Fat Mass: 17 kg")
        XCTAssertEqual(c.count, 1); XCTAssertEqual(c[0].value.region, ""); XCTAssertFalse(c[0].value.isValid)
    }
    func testUnspecifiedLeanDefinitionNotGuessed() {
        let c = candidates("Total Lean Mass: 65 kg\nTotal Lean Soft Tissue: 62 kg")
        XCTAssertEqual(c.count, 2); XCTAssertEqual(c[0].value.metric, .unspecifiedLeanMass)
        XCTAssertEqual(c[1].value.metric, .leanSoftTissue)
    }
    func testTAndZScoreSitesNotGuessed() {
        let c = candidates("T-score: -1.2\nZ-score: +0.5")
        XCTAssertEqual(c.count, 2); XCTAssertEqual(c[0].value.value, -1.2); XCTAssertEqual(c[0].value.region, "")
    }
    func testBMDAndVATAndRMR() {
        let c = candidates("BMD: 1.201 g/cm²\nVAT Area: 80 cm²\nVAT Volume: 30 in³\nEstimated RMR: 1750 kcal/day")
        XCTAssertEqual(c.count, 4); XCTAssertEqual(c[0].value.metric, .boneMineralDensity)
        XCTAssertEqual(c[1].value.metric, .visceralFatArea); XCTAssertEqual(c[2].value.metric, .visceralFatVolume)
        XCTAssertEqual(c[3].value.metric, .reportedRMR)
    }
    func testParserRejectsMissingAndConflictingUnits() {
        for text in ["Total Mass: 185", "Total Mass (kg): 185 lbs", "VAT mass: 30 cm3", "Body Fat %: 19 kg", "Total Mass: 85 stones"] {
            XCTAssertTrue(candidates(text).isEmpty, text)
        }
    }
    func testParserRejectsTableRowsMultipleValuesAndDates() {
        for text in ["Total 19.2 85 16.3 65.5 3.2", "Total Mass: 85 kg 84 kg", "Measured date: 09/10/2026", "Birth Date: 11/08/1997", "Trunk Fat Mass: 8 kg", "Subtotal 19% 50 kg"] {
            XCTAssertTrue(candidates(text).isEmpty, text)
        }
    }
    func testRepeatedCandidatesRemainUnselectedNotSilentlyResolved() {
        let c = candidates("Total Mass: 85 kg\nTotal Mass: 82 kg")
        XCTAssertEqual(c.count, 2); XCTAssertNotEqual(c[0].id, c[1].id)
    }
    func testCommaDecimalLeftForManualReview() {
        XCTAssertTrue(candidates("Total Mass: 85,4 kg").isEmpty)
        XCTAssertNil(DXATextParser.number("12,34")); XCTAssertNil(DXATextParser.number("1,2,3"))
        XCTAssertEqual(DXATextParser.number("1,234.5"), 1234.5)
    }
    func testUnexpectedTextAndOversizeDoNotInventValues() {
        XCTAssertTrue(candidates("No selectable report text").isEmpty)
        XCTAssertTrue(candidates("Fat mass is what we measure; typically 20 kg in our example.").isEmpty)
        XCTAssertTrue(candidates(String(repeating: "x", count: 100001)).isEmpty)
    }
    func testCandidatesRetainVerbatimSourceLine() {
        let c = candidates("Total Fat Mass: 17.2 kg")
        XCTAssertEqual(c.first?.value.sourceExcerpt, "Total Fat Mass: 17.2 kg")
    }
    func testTwoPriorScansOnSameDateDoNotProduceArbitraryDifference() {
        let current = scan()
        let a = scan(day: "2026-08-01", fat: 19), b = scan(day: "2026-08-01", fat: 23)
        XCTAssertNil(DXATrends.previousDifference(for: current.values[0], scan: current, scans: [a,b]))
        XCTAssertNil(DXATrends.previousDifference(for: current.values[0], scan: current, scans: [b,a]))
    }

    func testTotalWithoutBodyQualifierStillNeedsSiteReview() {
        let c = candidates("Total Mass: 85 kg\nTotal Body Mass: 85 kg")
        XCTAssertEqual(c.count, 2)
        XCTAssertEqual(c[0].value.region, "")
        XCTAssertEqual(c[1].value.region, "Total body")
    }

}
