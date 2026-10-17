import Foundation
import XCTest
#if !RECOMP_NATIVE_TESTS
@testable import RecompCore
#endif

final class AuditRegressionTests: XCTestCase {
    func testFoodRejectsNonfiniteDate() {
        var entry = FoodEntry(name: "Synthetic", date: Date(), meal: .lunch, nutrition: Nutrition(calories: 500))
        entry.date = Date(timeIntervalSince1970: -.infinity)
        XCTAssertFalse(entry.isValid)
    }
    func testFoodRejectsOverflowingVersion() {
        var entry = FoodEntry(name: "Synthetic", date: Date(), meal: .lunch, nutrition: Nutrition(calories: 500))
        entry.version = Int.max
        XCTAssertFalse(entry.isValid)
    }
    func testFoodRejectsImpossibleAndUnknownReceipts() {
        var entry = FoodEntry(name: "Synthetic", date: Date(), meal: .lunch, nutrition: Nutrition(calories: 500))
        entry.exportedVersions = ["calories": 100]
        XCTAssertFalse(entry.isValid)
        entry.exportedVersions = ["unknown": 1]
        XCTAssertFalse(entry.isValid)
    }
    func testBodyRejectsOverflowingVersionAndFutureReceipt() {
        var reading = BodyMeasurement(date: Date(), metric: .weight, value: 85)
        reading.version = Int.max
        XCTAssertFalse(reading.isValid)
        reading.version = 1; reading.exportedVersion = 20
        XCTAssertFalse(reading.isValid)
    }
    func testImpossibleDayCannotEnterBackup() {
        let day = DayReview(dayKey: "2026-02-31", timeZoneID: "UTC", confirmedAt: Date(), total: Nutrition(calories: 2500), estimatedCalorieFraction: 0, includedHealth: false)
        XCTAssertFalse(day.isValid)
        var state = AppState(); state.dayReviews = [day]
        XCTAssertThrowsError(try BackupPayload(createdAt: Date(), bundleID: "test", appearance: "system", state: state).encode())
    }
    func testDuplicateTemplateIDsRejected() {
        var state = AppState(); state.templates.append(state.templates[0])
        XCTAssertFalse(state.isValid)
    }
    func testInvalidStateSaveLeavesExistingBytesUnchanged() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = StateFile(url: root.appendingPathComponent("diary.json"))
        let good = AppState(); try file.save(good)
        let prior = try Data(contentsOf: file.url)
        var bad = good; bad.targets.calories = -1
        XCTAssertThrowsError(try file.save(bad))
        XCTAssertEqual(try Data(contentsOf: file.url), prior)
        XCTAssertEqual(try file.load(), good)
    }
    func testUnicodeAndEmbeddedNULBackupRoundTrip() throws {
        var state = AppState()
        state.entries = [FoodEntry(name: "鸡肉 🥙 café", date: Date(timeIntervalSince1970: 1_780_000_000), meal: .lunch,
            nutrition: Nutrition(calories: 300, protein: 25, carbs: 30, fat: 10), note: "first\nsecond\u{0000}third")]
        let payload = BackupPayload(createdAt: Date(timeIntervalSince1970: 1_780_000_000), bundleID: "test.recomp", appearance: "dark", state: state)
        XCTAssertEqual(try BackupPayload.decode(payload.encode()), payload)
    }
    func testReadOnlyHypotheticalFoodNeverChangesOriginalAcrossRandomMeals() {
        var rng = Random(seed: 17)
        for _ in 0..<1000 {
            var state = AppState()
            let date = Date(timeIntervalSince1970: 1_780_000_000)
            for _ in 0..<5 {
                state.entries.append(FoodEntry(name: "Test", date: date, meal: .lunch, nutrition: rng.nutrition()))
            }
            let original = state
            let total = DiaryMath.localTotal(entries: state.entries, day: date)
            let extra = rng.nutrition()
            let check = FoodCheckProjection(current: total, candidate: extra, targets: state.targets)
            for metric in Nutrient.allCases {
                let independent = state.entries.map { $0.nutrition[metric] }.reduce(0, +) + extra[metric]
                XCTAssertEqual(check.projected[metric], independent, accuracy: 1e-8)
                XCTAssertEqual(check.remaining[metric], state.targets[metric] - independent, accuracy: 1e-8)
            }
            XCTAssertEqual(state, original)
        }
    }
    func testSleepUnionAgainstIndependentSecondGrid() {
        var rng = Random(seed: 908)
        let epoch = Date(timeIntervalSince1970: 1_780_000_000)
        for _ in 0..<1000 {
            var intervals: [(Date, Date)] = []
            var covered = [Bool](repeating: false, count: 600)
            for _ in 0..<20 {
                let start = Int(rng.next() % 800) - 100
                let length = Int(rng.next() % 200)
                let end = start + length
                intervals.append((epoch.addingTimeInterval(Double(start)), epoch.addingTimeInterval(Double(end))))
                for second in 0..<600 where second >= start && second < end { covered[second] = true }
            }
            let expected = Double(covered.filter { $0 }.count)
            XCTAssertEqual(ActivityMath.unionSeconds(intervals, from: epoch, to: epoch.addingTimeInterval(600)), expected)
        }
    }
    func testScaleOffsetsCancelAcrossSeededHistories() throws {
        var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let origin = c.date(from: DateComponents(year: 2026, month: 3, day: 1))! // spans spring DST
        var rng = Random(seed: 5519)
        for _ in 0..<500 {
            let slope = (Double(rng.next() % 1000) - 500) / 10000
            let offset = Double(rng.next() % 8000) / 100 - 40
            var plain: [ScaleDay] = [], shifted: [ScaleDay] = []
            for day in 0..<29 {
                let source = day % 2 == 0 ? "home" : "other"
                let date = c.date(byAdding: .day, value: day, to: origin)!
                let value = 85 + slope * Double(day)
                plain.append(ScaleDay(date: date, value: value, seriesID: source))
                shifted.append(ScaleDay(date: date, value: value + (source == "other" ? offset : 0), seriesID: source))
            }
            let a = try XCTUnwrap(ScaleWeightFit.fit(plain, calendar: c))
            let b = try XCTUnwrap(ScaleWeightFit.fit(shifted, calendar: c))
            XCTAssertEqual(a.fit.slope, slope, accuracy: 1e-10)
            XCTAssertEqual(b.fit.slope, slope, accuracy: 1e-10)
            XCTAssertEqual(a.daily.count, b.daily.count)
        }
    }
    private struct Random {
        var seed: UInt64
        mutating func next() -> UInt64 { seed = seed &* 6364136223846793005 &+ 1442695040888963407; return seed }
        mutating func nutrition() -> Nutrition {
            Nutrition(calories: Double(next() % 15000)/10, protein: Double(next() % 1200)/10,
                carbs: Double(next() % 2000)/10, fat: Double(next() % 800)/10)
        }
    }
}

extension AuditRegressionTests {
    func testEqualVersionFoodConflictRequiresResolution() throws {
        var a = AppState()
        a.entries = [FoodEntry(name: "Original", date: Date(), meal: .lunch, nutrition: Nutrition(calories: 500))]
        var b = a; b.entries[0].nutrition.calories = 600; b.entries[0].lastExportedAt = Date()
        XCTAssertNil(a.mergedIfValid(with: b)); XCTAssertNil(b.mergedIfValid(with: a))
        b.entries[0].version += 1
        XCTAssertEqual(try XCTUnwrap(a.mergedIfValid(with: b)).entries[0].nutrition.calories, 600)
    }
    func testIdenticalFoodCombinesHealthReceipts() throws {
        var a = AppState()
        a.entries = [FoodEntry(name: "Original", date: Date(), meal: .lunch, nutrition: Nutrition(calories: 500, protein: 30))]
        var b = a
        a.entries[0].exportedVersions = ["calories": 1]
        b.entries[0].exportedVersions = ["protein": 1]; b.entries[0].lastExportedAt = Date()
        let merged = try XCTUnwrap(a.mergedIfValid(with: b))
        XCTAssertEqual(merged.entries[0].exportedVersions, ["calories": 1, "protein": 1])
        XCTAssertEqual(merged.entries[0].lastExportedAt, b.entries[0].lastExportedAt)
    }
    func testEqualVersionBodyConflictsButReceiptsCombine() throws {
        var a = AppState(); a.measurements = [BodyMeasurement(date: Date(), metric: .weight, value: 85)]
        var b = a; b.measurements[0].value = 86
        XCTAssertNil(a.mergedIfValid(with: b)); XCTAssertNil(b.mergedIfValid(with: a))
        b = a; b.measurements[0].exportedVersion = 1
        XCTAssertEqual(try XCTUnwrap(a.mergedIfValid(with: b)).measurements[0].exportedVersion, 1)
    }
    func testCompletedDeletionsSurviveRoundTripAndStalePeer() throws {
        var stale = AppState()
        stale.entries = [FoodEntry(name: "Deleted", date: Date(), meal: .lunch, nutrition: Nutrition(calories: 500))]
        stale.measurements = [BodyMeasurement(date: Date(), metric: .weight, value: 85)]
        var deleted = stale
        deleted.recordDeletion(stale.entries[0].id, kind: "food")
        deleted.recordDeletion(stale.measurements[0].id, kind: "body")
        deleted.recordDeletion(stale.templates[0].id, kind: "template")
        deleted.entries = []; deleted.measurements = []; deleted.templates.removeFirst()
        deleted = try JSONDecoder().decode(AppState.self, from: JSONEncoder().encode(deleted))
        XCTAssertTrue(deleted.deletions.isEmpty); XCTAssertTrue(deleted.bodyDeletions.isEmpty)
        for merged in [try XCTUnwrap(deleted.mergedIfValid(with: stale)), try XCTUnwrap(stale.mergedIfValid(with: deleted))] {
            XCTAssertTrue(merged.entries.isEmpty); XCTAssertTrue(merged.measurements.isEmpty)
            XCTAssertFalse(merged.templates.contains { $0.id == stale.templates[0].id })
        }
        let receiving = try XCTUnwrap(stale.mergedIfValid(with: deleted))
        XCTAssertEqual(receiving.deletions.map(\.id), stale.entries.map(\.id))
        XCTAssertEqual(receiving.bodyDeletions.map(\.id), stale.measurements.map(\.id))
    }
    func testRemovedReviewCannotReturnButCanBeReconfirmed() throws {
        let date = Date(timeIntervalSince1970: 1_780_000_000)
        let review = DayReview(dayKey: "2026-05-01", timeZoneID: "UTC", confirmedAt: date,
                               total: Nutrition(calories: 2500), estimatedCalorieFraction: 0, includedHealth: false)
        var stale = AppState(); stale.dayReviews = [review]
        var removed = stale; removed.dayReviews = []; removed.recordReviewRemoval(review.id, at: date.addingTimeInterval(1))
        XCTAssertTrue(try XCTUnwrap(stale.mergedIfValid(with: removed)).dayReviews.isEmpty)
        XCTAssertTrue(try XCTUnwrap(removed.mergedIfValid(with: stale)).dayReviews.isEmpty)
        stale.dayReviews[0].confirmedAt = date.addingTimeInterval(2)
        XCTAssertEqual(try XCTUnwrap(removed.mergedIfValid(with: stale)).dayReviews.count, 1)
        var conflict = stale; conflict.dayReviews[0].total.calories = 2300
        XCTAssertNil(stale.mergedIfValid(with: conflict))
    }
    func testLegacyPendingDeletionsMigrateToDurableRecords() throws {
        var state = AppState(); let id = UUID(); state.deletions = [DeletionTask(id: id)]
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(state)) as? [String: Any])
        json["schemaVersion"] = 7; json.removeValue(forKey: "deletedRecords"); json.removeValue(forKey: "removedReviews")
        let migrated = try JSONDecoder().decode(AppState.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(migrated.schemaVersion, 8); XCTAssertEqual(migrated.deletedIDs("food"), [id]); XCTAssertTrue(migrated.isValid)
    }
    func testInvalidDeletionRecordsRejected() {
        var state = AppState(); state.recordDeletion(UUID(), kind: "unknown"); XCTAssertFalse(state.isValid)
        state = AppState(); state.recordDeletion(state.templates[0].id, kind: "template"); XCTAssertFalse(state.isValid)
    }
    func testStorageSelectionPreservesExistingLocalDiary() {
        let local = URL(fileURLWithPath: "/local/diary.json"), cloud = URL(fileURLWithPath: "/cloud/diary.json")
        XCTAssertEqual(StateFile.chooseDefaultURL(preference: nil, local: local, cloud: cloud, exists: { _ in true }), local)
        XCTAssertEqual(StateFile.chooseDefaultURL(preference: nil, local: local, cloud: cloud, exists: { $0 == cloud }), cloud)
        XCTAssertEqual(StateFile.chooseDefaultURL(preference: "icloud", local: local, cloud: cloud, exists: { _ in true }), cloud)
        XCTAssertEqual(StateFile.chooseDefaultURL(preference: "local", local: local, cloud: cloud, exists: { _ in true }), local)
    }
}

extension AuditRegressionTests {
    func testDeletedContextDXAAndNonHealthMeasurementStayDeleted() throws {
        var stale = AppState(); let now = Date()
        stale.contextEvents = [ContextEvent(start: now, end: now, kind: .travel)]
        stale.measurements = [BodyMeasurement(date: now, metric: .neck, value: 40)]
        var scan = DXAScan(scanDay: "2026-09-01"); scan.provider = "Clinic"; scan.reviewed = true
        scan.values = [DXAValue(metric: .bodyFat, region: "Total body", value: 20, unit: .percent)]
        stale.dxaScans = [scan]
        stale.dxaHealthLinks = [DXAHealthLink(id: scan.id, selectedMetrics: [.bodyFat], date: DXAScan.date(for: scan.scanDay)!, timeZoneID: "UTC", attemptedMetrics: [.bodyFat])]
        var deleted = stale
        deleted.recordDeletion(scan.id, kind: "dxa"); deleted.dxaScans = []; deleted.dxaHealthLinks = []
        deleted.recordDeletion(stale.contextEvents[0].id, kind: "context"); deleted.contextEvents = []
        deleted.recordDeletion(stale.measurements[0].id, kind: "body"); deleted.measurements = []
        let merged = try XCTUnwrap(stale.mergedIfValid(with: deleted))
        XCTAssertTrue(merged.contextEvents.isEmpty); XCTAssertTrue(merged.measurements.isEmpty); XCTAssertTrue(merged.bodyDeletions.isEmpty)
        XCTAssertTrue(merged.dxaScans.isEmpty); XCTAssertEqual(merged.dxaHealthLinks[0].version, 2)
        XCTAssertTrue(merged.dxaHealthLinks[0].selectedMetrics.isEmpty)
        XCTAssertEqual(merged.dxaHealthLinks[0].pendingMetrics(scan: nil), [.bodyFat])
    }
}
