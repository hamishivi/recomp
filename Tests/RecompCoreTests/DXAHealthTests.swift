import XCTest
#if !RECOMP_NATIVE_TESTS
@testable import RecompCore
#endif

final class DXAHealthTests: XCTestCase {
    func scan() -> DXAScan {
        var s = DXAScan(scanDay: "2026-09-01")
        s.provider = "Synthetic"; s.reviewed = true
        s.values = [
            DXAValue(metric: .totalMass, region: "Total body", value: 85, unit: .kg),
            DXAValue(metric: .bodyFat, region: "Total body", value: 20, unit: .percent),
            DXAValue(metric: .leanSoftTissue, region: "Total body", value: 65, unit: .kg),
            DXAValue(metric: .boneMineralContent, region: "Total body", value: 3000, unit: .g)]
        return s
    }
    func link(_ s: DXAScan, metrics: Set<DXAHealthMetric> = Set(DXAHealthMetric.allCases)) -> DXAHealthLink {
        DXAHealthLink(id: s.id, selectedMetrics: metrics,
            date: DXAHealthTime.date(day: s.scanDay, timeZoneID: "America/Los_Angeles")!, timeZoneID: "America/Los_Angeles")
    }
    func testCompatibleWholeBodyFieldsAndDerivedLean() {
        let p = DXAHealthMapping.plan(scan())
        XCTAssertEqual(p.candidates.count, 3)
        XCTAssertEqual(p.candidate(.weight)?.value, 85)
        XCTAssertEqual(p.candidate(.bodyFat)?.value, 20)
        XCTAssertEqual(p.candidate(.leanBodyMass)?.value, 68)
        XCTAssertEqual(p.candidate(.leanBodyMass)?.basis, .leanSoftTissuePlusBone)
    }
    func testPercentUnitUsesFractionNotPercentagePoints() {
        XCTAssertEqual(DXAHealthMetric.bodyFat.healthValue(19.5), 0.195, accuracy: 1e-12)
        XCTAssertEqual(DXAHealthMetric.weight.healthValue(85), 85)
    }
    func testAllReportMassUnitsConvertToKG() {
        var s = scan(); s.values[0].value = 200; s.values[0].unit = .lb
        s.values[2].value = 65000; s.values[2].unit = .g
        let p = DXAHealthMapping.plan(s)
        XCTAssertEqual(p.candidate(.weight)!.value, 90.718474, accuracy: 1e-8)
        XCTAssertEqual(p.candidate(.leanBodyMass)!.value, 68, accuracy: 1e-8)
    }
    func testMappingDoesNotMutateReport() {
        let s = scan(); let copy = s; _ = DXAHealthMapping.plan(s); XCTAssertEqual(s, copy)
    }
    func testExplicitFatFreeMassHasPriority() {
        var s = scan(); s.values.append(DXAValue(metric: .fatFreeMass, region: "Total body", value: 68.1, unit: .kg))
        XCTAssertEqual(DXAHealthMapping.plan(s).candidate(.leanBodyMass)?.basis, .reportedFatFreeMass)
    }
    func testConflictingLeanDefinitionsDoNotExport() {
        var s = scan(); s.values.append(DXAValue(metric: .fatFreeMass, region: "Total body", value: 65, unit: .kg))
        XCTAssertNil(DXAHealthMapping.plan(s).candidate(.leanBodyMass))
    }
    func testSoftTissueAloneIsNotHealthLeanMass() {
        var s = scan(); s.values.removeAll { $0.metric == .boneMineralContent }
        XCTAssertNil(DXAHealthMapping.plan(s).candidate(.leanBodyMass))
    }
    func testUndefinedLeanMassNotGuessed() {
        var s = scan(); s.values.removeAll { $0.metric == .leanSoftTissue || $0.metric == .boneMineralContent }
        s.values.append(DXAValue(metric: .unspecifiedLeanMass, region: "Total body", value: 68, unit: .kg))
        XCTAssertNil(DXAHealthMapping.plan(s).candidate(.leanBodyMass))
    }
    func testPercentageAndTotalMassDoNotInventFatFreeMass() {
        var s = scan(); s.values = Array(s.values.prefix(2))
        XCTAssertNil(DXAHealthMapping.plan(s).candidate(.leanBodyMass))
    }
    func testDerivedLeanCannotExceedTotalMass() {
        var s = scan(); s.values[2].value = 90
        XCTAssertNil(DXAHealthMapping.plan(s).candidate(.leanBodyMass))
    }
    func testZeroFatFreeMassNotExportedOrOverridden() {
        var s = scan(); s.values.append(DXAValue(metric: .fatFreeMass, region: "Whole body", value: 0, unit: .kg))
        XCTAssertNil(DXAHealthMapping.plan(s).candidate(.leanBodyMass))
    }
    func testRegionalRowsNeverBecomeWholeBody() {
        for region in ["Arms", "Total", "Total body less head", "Subtotal", "Android", "Trunk"] {
            var s = scan(); s.values = s.values.map { var v = $0; v.region = region; return v }
            XCTAssertTrue(DXAHealthMapping.plan(s).candidates.isEmpty, region)
        }
    }
    func testWholeBodyAliasNormalization() {
        for region in ["  TOTAL  BODY ", "Whole body", "whole-body", "total-body"] {
            var s = scan(); s.values = s.values.map { var v = $0; v.region = region; return v }
            XCTAssertEqual(DXAHealthMapping.plan(s).candidates.count, 3, region)
        }
    }
    func testAmbiguousAliasDuplicatesBlockThatMetric() {
        var s = scan(); s.values.append(DXAValue(metric: .totalMass, region: "Whole body", value: 86, unit: .kg))
        XCTAssertTrue(s.isValid); XCTAssertNil(DXAHealthMapping.plan(s).candidate(.weight))
        XCTAssertEqual(DXAHealthMapping.plan(s).candidate(.bodyFat)?.value, 20)
    }
    func testAmbiguousFatFreeMassCannotFallBackToDerived() {
        var s = scan()
        s.values += [DXAValue(metric: .fatFreeMass, region: "Whole body", value: 68, unit: .kg),
                     DXAValue(metric: .fatFreeMass, region: "Total body", value: 69, unit: .kg)]
        XCTAssertNil(DXAHealthMapping.plan(s).candidate(.leanBodyMass))
    }
    func testUnreviewedOrInvalidScanExportsNothing() {
        var s = scan(); s.reviewed = false
        XCTAssertTrue(DXAHealthMapping.plan(s).candidates.isEmpty)
        s.reviewed = true; s.values[0].value = .nan
        XCTAssertTrue(DXAHealthMapping.plan(s).candidates.isEmpty)
    }
    func testBoneScoresAndRMRNeverMapToUnrelatedTypes() {
        var s = scan()
        s.values = [DXAValue(metric: .tScore, region: "Total body", value: -1, unit: .score),
                    DXAValue(metric: .reportedRMR, region: "Total body", value: 1750, unit: .kcalPerDay),
                    DXAValue(metric: .boneMineralDensity, region: "Total body", value: 1.2, unit: .gPerCM2)]
        XCTAssertTrue(DXAHealthMapping.plan(s).candidates.isEmpty)
    }
    func testNewLinkPendingOnlyChosenCompatibleMetrics() {
        let s = scan(), l = link(scan(), metrics: [.weight]) // intentionally other ID
        XCTAssertTrue(l.desiredValues(scan: s).isEmpty)
        let own = link(s, metrics: [.weight]); XCTAssertEqual(own.pendingMetrics(scan: s), [.weight])
    }
    func testDeniedUnattemptedMetricDoesNotNeedCleanup() {
        let s = scan(); var l = link(s, metrics: [.weight]); l.selectedMetrics = []; l.version += 1
        XCTAssertTrue(l.pendingMetrics(scan: s).isEmpty)
    }
    func testAttemptMarkerSurvivesMissingReceipt() {
        let s = scan(); var l = link(s); l.attemptedMetrics = [.weight]; l.selectedMetrics = []; l.version += 1
        XCTAssertEqual(l.pendingMetrics(scan: nil), [.weight])
    }
    func testEditedVersionMakesPreviouslyCompletedFieldsPending() {
        let s = scan(); var l = link(s, metrics: [.weight]); l.completedVersions = ["weight": 1]
        XCTAssertTrue(l.pendingMetrics(scan: s).isEmpty); l.version += 1
        XCTAssertEqual(l.pendingMetrics(scan: s), [.weight])
    }
    func testMissingSelectedResultTriggersRemovalBeforeUpsert() {
        var s = scan(); var l = link(s); l.attemptedMetrics = Set(DXAHealthMetric.allCases)
        s.values.removeAll { $0.metric == .bodyFat }; l.version += 1
        XCTAssertEqual(l.pendingMetrics(scan: s).first, .bodyFat)
        XCTAssertFalse(l.desiredValues(scan: s).contains { $0.metric == .bodyFat })
    }
    func testStableIdentitySeparateFromFoodAndScaleSamples() {
        let id = UUID()
        XCTAssertEqual(DXAHealthIdentity.sampleID(scanID: id, metric: .weight), DXAHealthIdentity.sampleID(scanID: id, metric: .weight))
        XCTAssertNotEqual(DXAHealthIdentity.sampleID(scanID: id, metric: .weight), BodyMath.syncID(id: id, metric: .weight))
        XCTAssertNotEqual(DXAHealthIdentity.sampleID(scanID: id, metric: .weight), DXAHealthIdentity.sampleID(scanID: id, metric: .bodyFat))
    }
    func testOwnDXARecognitionDoesNotDependOnLocalScanExistence() {
        let id = UUID()
        XCTAssertTrue(DXAHealthIdentity.isOwnScanExport(source: "ours", ownBundleID: "ours", scanID: id.uuidString, syncID: nil))
        XCTAssertTrue(DXAHealthIdentity.isOwnScanExport(source: "ours", ownBundleID: "ours", scanID: nil,
            syncID: DXAHealthIdentity.sampleID(scanID: id, metric: .weight)))
        XCTAssertFalse(DXAHealthIdentity.isOwnScanExport(source: "other", ownBundleID: "ours", scanID: id.uuidString, syncID: nil))
        XCTAssertFalse(DXAHealthIdentity.isOwnScanExport(source: "ours", ownBundleID: "ours", scanID: nil, syncID: "recomp.dxa.not-a-uuid.weight"))
        XCTAssertFalse(DXAHealthIdentity.isOwnScanExport(source: "ours", ownBundleID: "ours", scanID: nil,
            syncID: BodyMath.syncID(id: id, metric: .weight)))
    }
    func testScanWeightCannotReenterScalePoints() {
        let s = HealthBodySample(id: UUID(), date: Date(), metric: .weight, value: 85,
            sourceName: "Recomp", sourceBundleID: "ours", localMeasurementID: nil, isRecompDXA: true)
        XCTAssertTrue(BodyMath.merged(local: [], health: [s], deletions: [], ownBundleID: "ours").isEmpty)
        var scale = s; scale.isRecompDXA = false
        XCTAssertEqual(BodyMath.merged(local: [], health: [scale], deletions: [], ownBundleID: "ours").count, 1)
    }
    func testDayOnlyTimestampUsesChosenTimezone() {
        let a = DXAHealthTime.date(day: "2026-09-01", timeZoneID: "America/Los_Angeles")!
        let b = DXAHealthTime.date(day: "2026-09-01", timeZoneID: "Australia/Sydney")!
        XCTAssertEqual(DXAHealthTime.day(a, timeZoneID: "America/Los_Angeles"), "2026-09-01")
        XCTAssertEqual(DXAHealthTime.day(b, timeZoneID: "Australia/Sydney"), "2026-09-01")
        XCTAssertNotEqual(a, b)
    }
    func testTimestampRejectsInvalidDateZoneAndDSTGap() {
        XCTAssertNil(DXAHealthTime.date(day: "2026-02-30", timeZoneID: "UTC"))
        XCTAssertNil(DXAHealthTime.date(day: "2026-09-01", timeZoneID: "Invalid/Zone"))
        let formatter = ISO8601DateFormatter()
        let early = formatter.date(from: "2026-03-07T10:30:00Z")! // 02:30 PST
        XCTAssertNil(DXAHealthTime.date(day: "2026-03-08", timeZoneID: "America/Los_Angeles", preserving: early))
    }
    func testLinkValidationReceiptsAndReferences() {
        let s = scan(); var l = link(s); var state = AppState(); state.dxaScans = [s]; state.dxaHealthLinks = [l]
        XCTAssertTrue(state.isValid)
        state.dxaScans = []; XCTAssertFalse(state.isValid)
        l.selectedMetrics = []; state.dxaHealthLinks = [l]; XCTAssertTrue(state.isValid)
        l.completedVersions = ["weight": 2]; XCTAssertFalse(l.isValid)
        l.completedVersions = ["fake": 1]; XCTAssertFalse(l.isValid)
        l.completedVersions = [:]; l.timeZoneID = "???"; XCTAssertFalse(l.isValid)
    }
    func testStateRejectsScanAndTimestampDateMismatch() {
        let s = scan(); var state = AppState(); state.dxaScans = [s]
        var l = link(s); l.date = l.date.addingTimeInterval(86400); state.dxaHealthLinks = [l]
        XCTAssertFalse(state.isValid)
    }
    func testVersionFourUpgradeRetainsScanWithoutAutomaticSharing() throws {
        var state = AppState(); state.dxaScans = [scan()]
        var data = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(state)) as? [String: Any])
        data["schemaVersion"] = 4; data.removeValue(forKey: "dxaHealthEnabled"); data.removeValue(forKey: "dxaHealthLinks")
        let loaded = try JSONDecoder().decode(AppState.self, from: JSONSerialization.data(withJSONObject: data))
        XCTAssertEqual(loaded.schemaVersion, 8); XCTAssertEqual(loaded.dxaScans, state.dxaScans)
        XCTAssertFalse(loaded.dxaHealthEnabled); XCTAssertTrue(loaded.dxaHealthLinks.isEmpty); XCTAssertTrue(loaded.isValid)
    }
    func testReceiptsSelectionsAndPauseRoundTrip() throws {
        let s = scan(); var state = AppState(); state.dxaScans = [s]
        var l = link(s); l.attemptedMetrics = [.weight]; l.completedVersions = ["weight": 1]
        state.dxaHealthLinks = [l]; state.dxaHealthEnabled = true
        let copy = try JSONDecoder().decode(AppState.self, from: JSONEncoder().encode(state))
        XCTAssertEqual(copy, state); XCTAssertEqual(copy.dxaHealthLinks[0].pendingMetrics(scan: s).count, 2)
    }
    func testNewStateNoSharingAndNoFakeMeasurements() {
        let state = AppState(); XCTAssertFalse(state.dxaHealthEnabled)
        XCTAssertTrue(state.dxaHealthLinks.isEmpty); XCTAssertTrue(state.dxaScans.isEmpty)
    }
}
