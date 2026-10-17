import Foundation
import XCTest
#if !RECOMP_NATIVE_TESTS
@testable import RecompCore
#endif

final class SecondAuditTests: XCTestCase {
    func testExtremeStepCountsDoNotCrashRoutineComparison() {
        let now = Date()
        let calendar = Calendar.current
        let rows = (1...14).map { StepDay(date: calendar.date(byAdding: .day, value: -$0,
            to: calendar.startOfDay(for: now))!, count: $0 <= 7 ? 1e100 : 4000) }
        XCTAssertNil(ActivityMath.stepComparison(rows, now: now, calendar: calendar))
    }
    func testNearZeroPriorStepTotalDoesNotOverflowPercent() {
        let now = Date()
        let calendar = Calendar.current
        let rows = (1...14).map { StepDay(date: calendar.date(byAdding: .day, value: -$0,
            to: calendar.startOfDay(for: now))!, count: $0 <= 7 ? 8000 : 1e-308) }
        XCTAssertNil(ActivityMath.stepComparison(rows, now: now, calendar: calendar))
    }
    func testStepRepresentationBoundsAndNormalComparison() {
        let now = Date(), calendar = Calendar.current
        for count in [-1, Double.nan, Double.infinity, Double(Int.max), 1e100] {
            XCTAssertFalse(StepDay(date: now, count: count).isValid)
        }
        XCTAssertFalse(StepDay(date: Date(timeIntervalSince1970: .infinity), count: 1000).isValid)
        XCTAssertTrue(StepDay(date: now, count: 0).isValid)
        XCTAssertTrue(StepDay(date: now, count: 8000).isValid)
        let rows = (1...14).map { StepDay(date: calendar.date(byAdding: .day, value: -$0,
            to: calendar.startOfDay(for: now))!, count: $0 <= 7 ? 8000 : 4000) }
        let text = ActivityMath.stepComparison(rows, now: now, calendar: calendar)
        XCTAssertTrue(text?.contains("8000/day") == true)
        XCTAssertTrue(text?.contains("100% higher") == true)
    }
    private let instant = Date(timeIntervalSince1970: 1_789_732_800)
    func testStorageDayKeyIsGregorianEvenWithOtherSystemCalendar() {
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        for identifier: Calendar.Identifier in [.buddhist, .hebrew, .islamicCivil, .japanese] {
            var calendar = Calendar(identifier: identifier); calendar.timeZone = gregorian.timeZone
            XCTAssertEqual(DayReview.key(instant, calendar: calendar), DayReview.key(instant, calendar: gregorian), "Storage dates must not change with the display calendar: \(identifier)")
        }
    }
    func testCompleteFoodDaysCanBeInvalidatedWithBuddhistCalendar() {
        var calendar = Calendar(identifier: .buddhist); calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let review = DayReview(dayKey: DayReview.key(instant, calendar: calendar), timeZoneID: calendar.timeZone.identifier,
            confirmedAt: instant, total: .startingTargets, estimatedCalorieFraction: 0, includedHealth: false)
        var state = AppState(); state.dayReviews = [review]
        XCTAssertTrue(review.isValid)
        state.invalidateReviews(for: [instant])
        XCTAssertTrue(state.dayReviews.isEmpty, "Editing a meal must clear its completion even with a non-Gregorian calendar")
    }
    func testStoredGregorianDayDecodesInDifferentDisplayCalendar() throws {
        var calendar = Calendar(identifier: .buddhist); calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        var gregorian = Calendar(identifier: .gregorian); gregorian.timeZone = calendar.timeZone
        let review = DayReview(dayKey: DayReview.key(instant, calendar: gregorian), timeZoneID: calendar.timeZone.identifier,
            confirmedAt: instant, total: .startingTargets, estimatedCalorieFraction: 0, includedHealth: false)
        XCTAssertEqual(review.date(calendar: calendar), gregorian.startOfDay(for: instant))
    }
}

// v1.9.1 startup/selection regressions.
final class StartupRegressionTests: XCTestCase {
    private func calendar(_ zone: String) -> Calendar {
        EntryClock.calendar(in: TimeZone(identifier: zone)!)
    }
    private func withFile(_ work: (StateFile) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("recomp-startup-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try work(StateFile(url: root.appendingPathComponent("diary.json")))
    }
    func testCurrentDiaryLoadDoesNotRewriteBytes() throws {
        try withFile { file in
            var state = AppState()
            let date = Date(timeIntervalSince1970: 1_700_000_000)
            state.entries = [FoodEntry(name: "Synthetic", date: date, meal: .lunch,
                nutrition: .startingTargets, clock: EntryClock(date: date, timeZoneID: "Australia/Adelaide"))]
            try file.save(state)
            let original = try Data(contentsOf: file.url)
            let loaded = try file.load()
            XCTAssertEqual(loaded, state)
            XCTAssertEqual(try Data(contentsOf: file.url), original)
        }
    }
    func testLegacySchemaStillMigratesAndPersistsOnlyOnce() throws {
        try withFile { file in
            var state = AppState()
            state.entries = [FoodEntry(name: "Legacy", date: Date(timeIntervalSince1970: 1_700_000_000), meal: .lunch, nutrition: .startingTargets)]
            var raw = try XCTUnwrap(try JSONSerialization.jsonObject(with: JSONEncoder().encode(state)) as? [String: Any])
            raw["schemaVersion"] = 6
            try JSONSerialization.data(withJSONObject: raw).write(to: file.url)
            let loaded = try file.load()
            XCTAssertEqual(loaded.schemaVersion, 8)
            XCTAssertNotNil(loaded.entries[0].clock)
            XCTAssertTrue(loaded.entries[0].clock!.needsReview)
            let first = try Data(contentsOf: file.url)
            XCTAssertEqual(try file.load(), loaded)
            XCTAssertEqual(try Data(contentsOf: file.url), first)
            XCTAssertEqual((try JSONSerialization.jsonObject(with: first) as? [String: Any])?["schemaVersion"] as? Int, 8)
        }
    }
    func testInvalidOrMissingSchemaDoesNotOverwriteFile() throws {
        try withFile { file in
            for schema: Any? in [nil, "7", 999] {
                var raw = try XCTUnwrap(try JSONSerialization.jsonObject(with: JSONEncoder().encode(AppState())) as? [String: Any])
                raw["schemaVersion"] = schema
                let data = try JSONSerialization.data(withJSONObject: raw)
                try data.write(to: file.url)
                XCTAssertThrowsError(try file.load())
                XCTAssertEqual(try Data(contentsOf: file.url), data)
            }
        }
    }
    func testAttachmentsSurviveLoadWithoutSecondJSONTree() throws {
        try withFile { file in
            var state = AppState()
            var entry = FoodEntry(name: "Fixture", date: Date(timeIntervalSince1970: 1_700_000_000), meal: .lunch, nutrition: .startingTargets)
            // Framing bytes exercise persistence, not native image decoding.
            entry.photos = [MealPhoto(jpeg: Data([0xff, 0xd8]) + Data(repeating: 0x42, count: 100_000) + Data([0xff, 0xd9]))]
            state.entries = [entry]
            try file.save(state)
            XCTAssertEqual(try file.load(), state)
        }
    }
    func testBulkDaySelectionMatchesOriginalAcrossTravelCalendarsAndBoundaries() {
        let zones = ["America/Los_Angeles", "Australia/Sydney", "Australia/Adelaide", "America/Toronto", "America/Vancouver", "Europe/Paris", "Europe/London", "Pacific/Auckland", "UTC"]
        let now = Date(timeIntervalSince1970: 1_789_732_800)
        var entries: [FoodEntry] = []
        for i in 0..<300 {
            let date = now.addingTimeInterval(Double(i - 150) * 3600)
            entries.append(FoodEntry(name: "Synthetic", date: date, meal: .lunch, nutrition: .startingTargets,
                clock: i % 3 == 0 ? nil : EntryClock(date: date, timeZoneID: zones[i % zones.count])))
        }
        for zone in zones {
            for id: Calendar.Identifier in [.gregorian, .buddhist, .hebrew] {
                var cal = Calendar(identifier: id); cal.timeZone = TimeZone(identifier: zone)!
                for offset in -4...4 {
                    let date = now.addingTimeInterval(Double(offset) * 86_400)
                    let reference = entries.filter { $0.isOnDiaryDay(date, calendar: cal) }
                    XCTAssertEqual(DiaryMath.entries(on: date, in: entries, calendar: cal), reference)
                    XCTAssertEqual(DiaryMath.localTotal(entries: entries, day: date, calendar: cal), reference.reduce(.zero) { $0 + $1.nutrition })
                }
            }
        }
    }
    func testHealthBulkDayTotalsPreserveDeduplicationAndSourceDates() {
        let now = Date(timeIntervalSince1970: 1_789_732_800)
        let cal = calendar("Australia/Sydney")
        let interval = DiaryMath.dayInterval(containing: now, calendar: cal)
        var samples: [HealthNutritionSample] = []
        for date in [interval.start.addingTimeInterval(-1), interval.start, now, interval.end] {
            for zone in ["America/Los_Angeles", "Australia/Sydney"] {
                samples.append(HealthNutritionSample(id: UUID(), date: date, nutrient: .calories, value: 100,
                    sourceName: "Test", sourceBundleID: "test.source", localEntryID: nil,
                    clock: EntryClock(date: date, timeZoneID: zone)))
            }
            samples.append(HealthNutritionSample(id: UUID(), date: date, nutrient: .protein, value: 10,
                sourceName: "Test", sourceBundleID: "test.source", localEntryID: nil))
        }
        var reference = Nutrition.zero
        for sample in samples where DiaryMath.healthSampleIsOnDay(sample, day: now, calendar: cal) { reference[sample.nutrient] += sample.value }
        samples += samples
        XCTAssertEqual(DiaryMath.healthTotal(samples, day: now, calendar: cal), reference)
    }
    func testUnchangedWidgetReadoutCanSkipRepublishing() {
        let now = Date(timeIntervalSince1970: 1_789_732_800)
        let cal = calendar("America/Los_Angeles")
        let state = AppState()
        let first = state.widgetSnapshot(now: now, calendar: cal)
        let second = state.widgetSnapshot(now: now.addingTimeInterval(60), calendar: cal)
        XCTAssertNotEqual(first, second) // Only timestamps change.
        XCTAssertTrue(first.hasSameReadout(as: second, now: second.date, calendar: cal))
    }
    func testWidgetChangesPrivacyAndCountForceRepublishing() {
        let now = Date(timeIntervalSince1970: 1_789_732_800)
        let cal = calendar("America/Los_Angeles")
        let first = AppState().widgetSnapshot(now: now, calendar: cal)
        var changed = first; changed.showsNumbers = true
        XCTAssertFalse(first.hasSameReadout(as: changed, now: now, calendar: cal))
        changed = first; changed.entriesCount += 1
        XCTAssertFalse(first.hasSameReadout(as: changed, now: now, calendar: cal))
        changed = first; changed.caloriesRemaining = 200
        XCTAssertFalse(first.hasSameReadout(as: changed, now: now, calendar: cal))
        changed = first; changed.proteinRemaining = 80
        XCTAssertFalse(first.hasSameReadout(as: changed, now: now, calendar: cal))
    }
    func testWidgetMidnightTimezoneAndClockRollbackForceRepublishing() {
        let now = Date(timeIntervalSince1970: 1_789_732_800)
        let cal = calendar("America/Los_Angeles")
        let state = AppState(), first = state.widgetSnapshot(now: now, calendar: cal)
        let tomorrow = now.addingTimeInterval(86_400)
        XCTAssertFalse(first.hasSameReadout(as: state.widgetSnapshot(now: tomorrow, calendar: cal), now: tomorrow, calendar: cal))
        let abroad = calendar("Australia/Sydney")
        XCTAssertFalse(first.hasSameReadout(as: state.widgetSnapshot(now: now, calendar: abroad), now: now, calendar: abroad))
        let earlier = now.addingTimeInterval(-120)
        XCTAssertFalse(first.hasSameReadout(as: state.widgetSnapshot(now: earlier, calendar: cal), now: earlier, calendar: cal))
    }
}

final class IntakeRingTests: XCTestCase {
    func testEmptyIntakeHasEmptyRing() {
        let p = IntakeRingProgress(value: 0, target: 2500)
        XCTAssertEqual(p.fraction, 0); XCTAssertEqual(p.remaining, 2500)
    }
    func testHalfIntake() {
        let p = IntakeRingProgress(value: 1250, target: 2500)
        XCTAssertEqual(p.fraction, 0.5); XCTAssertEqual(p.remaining, 1250)
    }
    func testCompleteIntake() {
        let p = IntakeRingProgress(value: 170, target: 170)
        XCTAssertEqual(p.fraction, 1); XCTAssertEqual(p.remaining, 0)
    }
    func testOverTargetDoesNotWrapOrHideExcess() {
        let p = IntakeRingProgress(value: 3000, target: 2500)
        XCTAssertEqual(p.fraction, 1); XCTAssertEqual(p.remaining, -500)
        XCTAssertEqual(p.value, 3000)
    }
    func testZeroTargetIsNotAFullRing() {
        let p = IntakeRingProgress(value: 50, target: 0)
        XCTAssertFalse(p.hasTarget); XCTAssertEqual(p.fraction, 0); XCTAssertNil(p.remaining)
    }
    func testInvalidTargetCannotCreateInvalidGeometry() {
        for target in [-1, Double.nan, .infinity, -.infinity] {
            let p = IntakeRingProgress(value: 170, target: target)
            XCTAssertFalse(p.hasTarget); XCTAssertEqual(p.fraction, 0); XCTAssertNil(p.remaining)
        }
    }
    func testInvalidIntakeCannotCreateInvalidGeometry() {
        for value in [Double.nan, .infinity, -.infinity] {
            let p = IntakeRingProgress(value: value, target: 2500)
            XCTAssertEqual(p.fraction, 0); XCTAssertNil(p.remaining)
        }
        XCTAssertEqual(IntakeRingProgress(value: -1, target: 2500).fraction, 0)
    }
    func testTinyPositiveTargetAndLargeIntakeStayFinite() {
        let p = IntakeRingProgress(value: .greatestFiniteMagnitude, target: .leastNonzeroMagnitude)
        XCTAssertEqual(p.fraction, 1); XCTAssertTrue(p.fraction.isFinite)
    }
    func testRingsDoNotChangeCalorieAndMacroTotals() {
        let food = Nutrition(calories: 2750, protein: 160, carbs: 240, fat: 100)
        let targets = Nutrition.startingTargets
        let progress = Nutrient.allCases.map { IntakeRingProgress(value: food[$0], target: targets[$0]) }
        XCTAssertEqual(progress[0].fraction, 1)
        XCTAssertEqual(progress[3].remaining, -25)
        XCTAssertEqual(food.calories, 2750); XCTAssertEqual(targets.calories, 2500)
    }
    func testGeneratedRingFractionsStayWithinBounds() {
        // Deterministic numerical scenarios, not additional XCTest methods.
        for i in 1...2000 {
            let value = Double(i * 31 % 20000)
            let target = Double(i * 23 % 3500)
            let p = IntakeRingProgress(value: value, target: target)
            XCTAssertTrue(p.fraction.isFinite && (0...1).contains(p.fraction))
            if let remaining = p.remaining { XCTAssertEqual(remaining + value, target) }
        }
    }
}

final class PolishCoreTests: XCTestCase {
    func testPhotoBatchOnlyLatestCanFinish() {
        var session = PhotoImportSession()
        XCTAssertFalse(session.isActive)
        let first = session.begin(), second = session.begin()
        XCTAssertNotEqual(first, second)
        XCTAssertFalse(session.accepts(first))
        XCTAssertFalse(session.finish(first))
        XCTAssertTrue(session.isActive)
        XCTAssertTrue(session.accepts(second))
        XCTAssertTrue(session.finish(second))
        XCTAssertFalse(session.isActive)
    }
    func testCancelledPhotoBatchCannotCommit() {
        var session = PhotoImportSession()
        let first = session.begin()
        session.cancel()
        XCTAssertFalse(session.accepts(first)); XCTAssertFalse(session.finish(first))
        let second = session.begin()
        XCTAssertFalse(session.finish(first)); XCTAssertTrue(session.accepts(second))
    }
    func testCompletedPhotoBatchCannotFinishTwice() {
        var session = PhotoImportSession()
        let ticket = session.begin()
        XCTAssertTrue(session.finish(ticket)); XCTAssertFalse(session.finish(ticket))
    }
    func testRapidPhotoReplacementStateMachine() {
        var session = PhotoImportSession()
        var previous: UUID?
        // Every outstanding earlier completion is stale, including after an explicit cancel.
        for i in 0..<1000 {
            let ticket = session.begin()
            if let previous { XCTAssertFalse(session.finish(previous)) }
            if i.isMultiple(of: 3) {
                session.cancel(); XCTAssertFalse(session.accepts(ticket))
            } else { XCTAssertTrue(session.accepts(ticket)); XCTAssertTrue(session.finish(ticket)) }
            previous = ticket
        }
    }
    func testEmptyAnalysisHasNoCSVRecords() {
        XCTAssertFalse(AnalysisCSV.hasRecords(in: AppState()))
    }
    func testTargetHistoryExportWithoutCompleteFoodDay() {
        var state = AppState()
        state.recordTargets(Nutrition(calories: 2400, protein: 170, carbs: 260, fat: 75), at: Date(), reason: "Synthetic change")
        XCTAssertTrue(state.dayReviews.isEmpty)
        XCTAssertTrue(AnalysisCSV.hasRecords(in: state))
        XCTAssertTrue(AnalysisCSV.make(state: state).contains("targets_after"))
    }
    func testRemovedTargetHistoryDisablesEmptyExport() {
        var state = AppState()
        state.recordTargets(Nutrition(calories: 2400), at: Date(), reason: "Synthetic change")
        XCTAssertTrue(AnalysisCSV.hasRecords(in: state))
        state.targetRevisions = []
        XCTAssertFalse(AnalysisCSV.hasRecords(in: state))
    }
}
