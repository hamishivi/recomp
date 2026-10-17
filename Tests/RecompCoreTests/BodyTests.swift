import XCTest
#if !RECOMP_NATIVE_TESTS
@testable import RecompCore
#endif

final class BodyTests: XCTestCase {
    let day = ISO8601DateFormatter().date(from: "2026-09-18T08:00:00-07:00")!
    var calendar: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "America/Los_Angeles")!; return c }
    func record(_ metric: BodyMetric = .weight, _ value: Double = 85) -> BodyMeasurement { BodyMeasurement(date: day, metric: metric, value: value) }
    func sample(_ metric: BodyMetric = .weight, _ value: Double = 85, local: UUID? = nil, source: String = "com.example.recomp") -> HealthBodySample {
        HealthBodySample(id: UUID(), date: day, metric: metric, value: value, sourceName: "Scale", sourceBundleID: source, localMeasurementID: local)
    }
    func merge(_ local: [BodyMeasurement], _ health: [HealthBodySample], _ deletes: [BodyDeletion] = []) -> [BodyPoint] {
        BodyMath.merged(local: local, health: health, deletions: deletes, ownBundleID: "com.example.recomp")
    }
    func testWeightUnitRoundTrip() {
        let pounds = MeasurementUnits.imperial.display(85, metric: .weight)
        XCTAssertEqual(pounds, 187.3929229, accuracy: 0.0001)
        XCTAssertEqual(MeasurementUnits.imperial.canonical(pounds, metric: .weight), 85, accuracy: 1e-9)
    }
    func testLengthUnitRoundTrip() {
        XCTAssertEqual(MeasurementUnits.imperial.canonical(36, metric: .waist), 91.44, accuracy: 1e-9)
        XCTAssertEqual(MeasurementUnits.imperial.display(91.44, metric: .waist), 36, accuracy: 1e-9)
    }
    func testPercentUnaffectedByDisplayUnits() {
        XCTAssertEqual(MeasurementUnits.imperial.display(19, metric: .bodyFat), 19)
        XCTAssertEqual(MeasurementUnits.imperial.canonical(19, metric: .bodyFat), 19)
    }
    func testBodyFatHealthPercentageFractionConversion() {
        XCTAssertEqual(BodyMath.healthValue(19, metric: .bodyFat), 0.19, accuracy: 1e-10)
        XCTAssertEqual(BodyMath.fromHealth(0.19, metric: .bodyFat), 19, accuracy: 1e-10)
    }
    func testWeightAndWaistHealthUnitsNotRescaledTwice() {
        XCTAssertEqual(BodyMath.healthValue(85, metric: .weight), 85)
        XCTAssertEqual(BodyMath.healthValue(90, metric: .waist), 90)
    }
    func testValidationRejectsWrongPercentScaleAndNonfiniteValues() {
        XCTAssertFalse(record(.bodyFat, 0.19).isValid)
        XCTAssertFalse(record(.bodyFat, 190).isValid)
        XCTAssertFalse(record(.weight, .nan).isValid)
        XCTAssertFalse(record(.weight, -.infinity).isValid)
        XCTAssertFalse(record(.waist, 0).isValid)
        XCTAssertTrue(record(.bodyFat, 19).isValid)
    }
    func testHealthSupportedMetricsOnly() {
        XCTAssertEqual(Set(BodyMetric.allCases.filter(\.healthSupported)), Set([.weight, .bodyFat, .waist]))
        XCTAssertFalse(record(.chest, 105).needsExport)
    }
    func testReceiptVersionsAndEdits() {
        var r = record(); XCTAssertTrue(r.needsExport)
        r.exportedVersion = 1; XCTAssertFalse(r.needsExport)
        r.version = 2; XCTAssertTrue(r.needsExport)
    }
    func testSyncIDStableAndSeparateFromFoodAndOtherMetrics() {
        let id = UUID()
        XCTAssertEqual(BodyMath.syncID(id: id, metric: .weight), BodyMath.syncID(id: id, metric: .weight))
        XCTAssertNotEqual(BodyMath.syncID(id: id, metric: .weight), BodyMath.syncID(id: id, metric: .bodyFat))
        XCTAssertNotEqual(BodyMath.syncID(id: id, metric: .weight), SyncIdentity.sampleID(entryID: id, nutrient: .calories))
    }
    func testOwnHealthExportDoesNotDuplicateLocalMeasurement() {
        let r = record(); XCTAssertEqual(merge([r], [sample(local: r.id)]).count, 1)
    }
    func testForeignSourceWithMatchingIDIsNotSilentlyDeleted() {
        let r = record(); XCTAssertEqual(merge([r], [sample(local: r.id, source: "other.scale")]).count, 2)
    }
    func testPendingDeletionSuppressesOwnExport() {
        let r = record(); XCTAssertTrue(merge([], [sample(local: r.id)], [BodyDeletion(id: r.id, metric: .weight)]).isEmpty)
    }
    func testOldUnlinkedExportsRemainReadableAfterReinstall() {
        XCTAssertEqual(merge([], [sample(local: UUID())]).count, 1)
    }
    func testDuplicateHealthUUIDIsNotCountedTwice() {
        let s = sample(); XCTAssertEqual(merge([], [s, s]).count, 1)
    }
    func testLocalReadingPriorityAvoidsDuplicatedWeighingBias() {
        let points = merge([record(.weight, 85)], [sample(.weight, 88, source: "scale")])
        XCTAssertEqual(BodyMath.daily(points, metric: .weight, calendar: calendar).first!.value, 85)
    }
    func testExcludedLocalNotReintroducedFromForeignDuplicate() {
        var r = record(); r.excludedFromTrend = true
        let points = merge([r], [sample(source: "scale")])
        XCTAssertTrue(BodyMath.daily(points, metric: .weight, calendar: calendar).isEmpty)
        XCTAssertEqual(points.count, 2)
    }
    func testDailyMedianLimitsSameDayOutliers() {
        let points = merge([record(.weight, 85), record(.weight, 85.2), record(.weight, 95)], [])
        XCTAssertEqual(BodyMath.daily(points, metric: .weight, calendar: calendar).first!.value, 85.2)
    }
    func testMalformedHealthValueIgnored() { XCTAssertTrue(merge([], [sample(.weight, .nan)]).isEmpty) }
    func testBodyCSVContainsCanonicalUnitsAndEscapes() {
        var r = record(.bodyFat, 19); r.note = "=malicious"; r.method = "scale, bathroom"
        let csv = BodyCSV.make([r])
        XCTAssertTrue(csv.contains("19.0")); XCTAssertTrue(csv.contains("\"%\"")); XCTAssertTrue(csv.contains("'=malicious"))
    }
    func testNewStateRoundTripRetainsAllNewFields() throws {
        var state = AppState(); state.measurements = [record(), record(.bodyFat, 19), record(.waist, 90)]
        state.bodyHealthEnabled = true; state.measurementUnits = .imperial; state.ignoredHealthBodyIDs.insert(UUID())
        let result = try JSONDecoder().decode(AppState.self, from: JSONEncoder().encode(state))
        XCTAssertEqual(result, state); XCTAssertTrue(result.isValid)
    }
    func testLegacyV11MigrationWithoutNewKeys() throws {
        var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(AppState())) as? [String: Any])
        for key in ["measurements", "bodyDeletions", "bodyHealthEnabled", "measurementUnits", "dayReviews", "adaptive", "targetRevisions", "maintenanceHistory", "ignoredHealthBodyIDs", "scaleLocations", "lastScaleLocationID", "maintenanceScaleLocationID", "healthBodyScaleAssignments"] { legacy.removeValue(forKey: key) }
        legacy["schemaVersion"] = 1
        let migrated = try JSONDecoder().decode(AppState.self, from: JSONSerialization.data(withJSONObject: legacy))
        XCTAssertEqual(migrated.schemaVersion, 8); XCTAssertEqual(migrated.targets, .startingTargets)
        XCTAssertTrue(migrated.measurements.isEmpty); XCTAssertTrue(migrated.dayReviews.isEmpty)
        XCTAssertFalse(migrated.bodyHealthEnabled); XCTAssertTrue(migrated.isValid)
    }
    func testUnknownFutureSchemaFailsWithoutOverwriting() throws {
        var encoded = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(AppState())) as? [String: Any]); encoded["schemaVersion"] = 99
        XCTAssertThrowsError(try JSONDecoder().decode(AppState.self, from: JSONSerialization.data(withJSONObject: encoded)))
    }
    func testDuplicateMeasurementIDsFailStateValidation() {
        var state = AppState(); let r = record(); state.measurements = [r, r]; XCTAssertFalse(state.isValid)
    }
    func testDeletedAndLiveSameIDFailStateValidation() {
        var state = AppState(); let r = record(); state.measurements = [r]; state.bodyDeletions = [BodyDeletion(id: r.id, metric: r.metric)]
        XCTAssertFalse(state.isValid)
    }
    func testUnsupportedMeasurementDeletionRejected() {
        var state = AppState(); state.bodyDeletions = [BodyDeletion(id: UUID(), metric: .chest)]; XCTAssertFalse(state.isValid)
    }
    func testBadAdaptivePreferencesRejected() {
        var state = AppState(); state.adaptive.proteinPerKG = 10; XCTAssertFalse(state.isValid)
        state.adaptive = AdaptiveSettings(); state.adaptive.startingMaintenance = .infinity; XCTAssertFalse(state.isValid)
    }
    func testDayReviewRejectsInvalidFraction() {
        let review = DayReview(dayKey: "2026-09-17", timeZoneID: calendar.timeZone.identifier, confirmedAt: day,
                              total: .startingTargets, estimatedCalorieFraction: 1.5, includedHealth: false)
        XCTAssertFalse(review.isValid)
    }
}
