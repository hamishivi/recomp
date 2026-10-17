import XCTest
#if !RECOMP_NATIVE_TESTS
@testable import RecompCore
#endif

final class RecompCoreTests: XCTestCase {
    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return c
    }
    private func date(_ string: String) -> Date { ISO8601DateFormatter().date(from: string)! }
    private var day: Date { date("2026-09-17T12:00:00-07:00") }
    private func entry(id: UUID = UUID(), nutrition: Nutrition = Nutrition(calories: 100, protein: 20)) -> FoodEntry {
        FoodEntry(id: id, name: "Test meal", date: day, meal: .lunch, nutrition: nutrition)
    }
    private func sample(nutrient: Nutrient = .calories, value: Double = 100, id: UUID = UUID(),
                        source: String = "com.example.recomp", entryID: UUID? = nil) -> HealthNutritionSample {
        HealthNutritionSample(id: id, date: day, nutrient: nutrient, value: value,
                              sourceName: "Test source", sourceBundleID: source, localEntryID: entryID)
    }
    func testStartingTargets() {
        XCTAssertEqual(Nutrition.startingTargets.calories, 2500)
        XCTAssertEqual(Nutrition.startingTargets.protein, 170)
        XCTAssertEqual(Nutrition.startingTargets.carbs, 285)
        XCTAssertEqual(Nutrition.startingTargets.fat, 75)
        XCTAssertEqual(Nutrition.startingTargets.macroCalories, 2495)
    }
    func testConversationRemainder() {
        let eaten = Nutrition(calories: 1800, protein: 125, carbs: 170, fat: 65)
        XCTAssertEqual(Nutrition.startingTargets - eaten, Nutrition(calories: 700, protein: 45, carbs: 115, fat: 10))
    }
    func testOverTargetIsNotClampedToZero() {
        XCTAssertEqual((Nutrition.startingTargets - Nutrition(calories: 2700, protein: 180, carbs: 300, fat: 80)).calories, -200)
    }
    func testScalingPreservesDecimalMacros() {
        let food = Nutrition(calories: 230, protein: 42, carbs: 9, fat: 3.5)
        XCTAssertEqual(food.scaled(by: 0.5), Nutrition(calories: 115, protein: 21, carbs: 4.5, fat: 1.75))
    }
    func testNutritionValidation() {
        XCTAssertFalse(Nutrition(calories: -1).isValid)
        XCTAssertFalse(Nutrition(protein: .nan).isValid)
        XCTAssertFalse(Nutrition(fat: .infinity).isValid)
        XCTAssertFalse(Nutrition.zero.containsFood)
        XCTAssertTrue(Nutrition(calories: 1).containsFood)
    }
    func testDecimalParsing() {
        XCTAssertEqual(InputNumber.parse("3.5"), 3.5)
        XCTAssertEqual(InputNumber.parse(" 3,5 "), 3.5)
        XCTAssertEqual(InputNumber.parse("0"), 0)
    }
    func testBadNumericInput() {
        for value in ["", " ", "NaN", "inf", "-1", "123foo", "1,2.3", "1 000", "1e999", "1000001"] {
            XCTAssertNil(InputNumber.parse(value), value)
        }
    }
    func testNumberEditingDoesNotInsertGrouping() {
        XCTAssertEqual(InputNumber.editString(2500), "2500")
        XCTAssertEqual(InputNumber.editString(3.5), "3.5")
    }
    func testOverwriteOrAppend() {
        // Typing at end of number overwrites instead of adding on
        XCTAssertEqual(InputNumber.overwriteOrAppend(old: "250", new: "2504", shouldOverwrite: true), "4")
        // Typing at start of number overwrites
        XCTAssertEqual(InputNumber.overwriteOrAppend(old: "250", new: "4250", shouldOverwrite: true), "4")
        // Typing in middle of number overwrites
        XCTAssertEqual(InputNumber.overwriteOrAppend(old: "250", new: "2450", shouldOverwrite: true), "4")
        // Typing a digit that matches existing start or end
        XCTAssertEqual(InputNumber.overwriteOrAppend(old: "350", new: "3350", shouldOverwrite: true), "3")
        XCTAssertEqual(InputNumber.overwriteOrAppend(old: "350", new: "3503", shouldOverwrite: true), "3")
        XCTAssertEqual(InputNumber.overwriteOrAppend(old: "350", new: "3500", shouldOverwrite: true), "0")
        // Pasting a multi-digit number overwrites
        XCTAssertEqual(InputNumber.overwriteOrAppend(old: "250", new: "250120", shouldOverwrite: true), "120")
        // Typing decimal point normalizes to 0.
        XCTAssertEqual(InputNumber.overwriteOrAppend(old: "250", new: "250.", shouldOverwrite: true), "0.")
        XCTAssertEqual(InputNumber.overwriteOrAppend(old: "250", new: "250,", shouldOverwrite: true), "0,")
        // Deleting text (backspace) is preserved
        XCTAssertEqual(InputNumber.overwriteOrAppend(old: "250", new: "25", shouldOverwrite: true), "25")
        // When overwrite is disabled, typing appends normally
        XCTAssertEqual(InputNumber.overwriteOrAppend(old: "4", new: "45", shouldOverwrite: false), "45")
        // Blank old field appends normally
        XCTAssertEqual(InputNumber.overwriteOrAppend(old: "", new: "5", shouldOverwrite: true), "5")
    }
    func testFoodNameValidation() {
        var item = entry()
        item.name = "  "
        XCTAssertFalse(item.isValid)
        item.name = "Meal"
        XCTAssertTrue(item.isValid)
    }
    func testSpringDSTHas23Hours() {
        let interval = DiaryMath.dayInterval(containing: date("2026-03-08T12:00:00-07:00"), calendar: calendar)
        XCTAssertEqual(interval.duration, 23 * 3600)
    }
    func testAutumnDSTHas25Hours() {
        let interval = DiaryMath.dayInterval(containing: date("2026-11-01T12:00:00-08:00"), calendar: calendar)
        XCTAssertEqual(interval.duration, 25 * 3600)
    }
    func testMidnightBelongsOnlyToNextDay() {
        let midnight = date("2026-09-18T00:00:00-07:00")
        XCTAssertFalse(DiaryMath.isOnDay(midnight, day: day, calendar: calendar))
        XCTAssertTrue(DiaryMath.isOnDay(midnight, day: midnight, calendar: calendar))
    }
    func testTimeZoneChangesDayAssignment() {
        let nearMidnight = date("2026-09-18T01:00:00Z")
        XCTAssertTrue(DiaryMath.isOnDay(nearMidnight, day: day, calendar: calendar))
        var utc = calendar; utc.timeZone = TimeZone(secondsFromGMT: 0)!
        XCTAssertFalse(DiaryMath.isOnDay(nearMidnight, day: day, calendar: utc))
    }
    func testOwnExportIsNotCountedTwice() {
        let item = entry()
        let total = DiaryMath.mergedTotal(entries: [item], deletions: [], samples: [sample(entryID: item.id)],
                                         ownBundleID: "com.example.recomp", day: day, includeHealth: true, calendar: calendar)
        XCTAssertEqual(total, item.nutrition)
    }
    func testThirdPartyNutritionAddsToLocalDiary() {
        let total = DiaryMath.mergedTotal(entries: [entry()], deletions: [], samples: [sample(value: 80, source: "third.party")],
                                         ownBundleID: "com.example.recomp", day: day, includeHealth: true, calendar: calendar)
        XCTAssertEqual(total.calories, 180)
        XCTAssertEqual(total.protein, 20)
    }
    func testHealthIntegrationCanBeExcluded() {
        let total = DiaryMath.mergedTotal(entries: [entry()], deletions: [], samples: [sample(value: 80, source: "third.party")],
                                         ownBundleID: "com.example.recomp", day: day, includeHealth: false, calendar: calendar)
        XCTAssertEqual(total.calories, 100)
    }
    func testPendingDeletionDoesNotReappearViaHealth() {
        let id = UUID()
        let total = DiaryMath.mergedTotal(entries: [], deletions: [DeletionTask(id: id)], samples: [sample(entryID: id)],
                                         ownBundleID: "com.example.recomp", day: day, includeHealth: true, calendar: calendar)
        XCTAssertEqual(total, .zero)
    }
    func testOldExportsRemainVisibleAfterReinstall() {
        let total = DiaryMath.mergedTotal(entries: [], deletions: [], samples: [sample(entryID: UUID())],
                                         ownBundleID: "com.example.recomp", day: day, includeHealth: true, calendar: calendar)
        XCTAssertEqual(total.calories, 100)
    }
    func testForeignSourceWithMatchingMetadataIsNotSilentlyRemoved() {
        let item = entry()
        let other = sample(source: "other.app", entryID: item.id)
        XCTAssertEqual(DiaryMath.externalSamples([other], entries: [item], deletions: [], ownBundleID: "com.example.recomp").count, 1)
    }
    func testDuplicateHealthUUIDOnlyCountsOnce() {
        let s = sample()
        XCTAssertEqual(DiaryMath.healthTotal([s, s], day: day, calendar: calendar).calories, 100)
    }
    func testMalformedHealthValuesAreIgnored() {
        let samples = [sample(value: -.infinity), sample(value: -1), sample(value: .nan), sample(value: 10)]
        XCTAssertEqual(DiaryMath.healthTotal(samples, day: day, calendar: calendar).calories, 10)
    }
    func testStableIDsAreDistinctPerNutrient() {
        let id = UUID()
        let ids = Nutrient.allCases.map { SyncIdentity.sampleID(entryID: id, nutrient: $0) }
        XCTAssertEqual(Set(ids).count, 4)
        XCTAssertEqual(SyncIdentity.sampleID(entryID: id, nutrient: .protein), SyncIdentity.sampleID(entryID: id, nutrient: .protein))
    }
    func testPartialPermissionLeavesOnlyUnsavedValuesPending() {
        var item = entry()
        item.exportedVersions["calories"] = 1
        item.exportedVersions["protein"] = 1
        XCTAssertEqual(Set(SyncIdentity.pendingNutrients(for: item)), Set([.carbs, .fat]))
        XCTAssertEqual(item.exportCount, 2)
    }
    func testEditNeedsNewVersionForEveryNutrient() {
        var item = entry()
        for nutrient in Nutrient.allCases { item.exportedVersions[nutrient.rawValue] = 1 }
        XCTAssertTrue(SyncIdentity.pendingNutrients(for: item).isEmpty)
        item.version += 1
        XCTAssertEqual(SyncIdentity.pendingNutrients(for: item).count, 4)
    }
    func testOlderInFlightReceiptDoesNotClearNewEdit() {
        var item = entry()
        item.version = 2
        item.exportedVersions["calories"] = 1
        XCTAssertTrue(SyncIdentity.pendingNutrients(for: item).contains(.calories))
    }
    func testDeletionRequiresAllFourAcknowledgements() {
        var deletion = DeletionTask(id: UUID())
        deletion.completedNutrients = [.calories, .protein, .carbs]
        XCTAssertFalse(deletion.isComplete)
        deletion.completedNutrients.insert(.fat)
        XCTAssertTrue(deletion.isComplete)
    }
    func testDayWeightMeansHaveEqualWeight() {
        let readings = [WeightReading(id: UUID(), date: day, kilograms: 80),
                        WeightReading(id: UUID(), date: day.addingTimeInterval(100), kilograms: 82),
                        WeightReading(id: UUID(), date: calendar.date(byAdding: .day, value: 1, to: day)!, kilograms: 83)]
        let result = DiaryMath.weightTrend(readings, calendar: calendar)
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result[0].kilograms, 81)
        XCTAssertEqual(result[1].rollingAverage, 82)
    }
    func testRollingWeightDoesNotInventMissingDays() {
        let aWeekAgo = calendar.date(byAdding: .day, value: -7, to: day)!
        let readings = [WeightReading(id: UUID(), date: aWeekAgo, kilograms: 90), WeightReading(id: UUID(), date: day, kilograms: 85)]
        let result = DiaryMath.weightTrend(readings, calendar: calendar)
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result.last?.rollingAverage, 85)
    }
    func testEmptyWeightDataIsEmptyNotZero() { XCTAssertTrue(DiaryMath.weightTrend([]).isEmpty) }
    func testStarterFoodsAreNotAutomaticallyLogged() {
        let state = AppState()
        XCTAssertTrue(state.entries.isEmpty)
        XCTAssertFalse(state.healthEnabled)
        XCTAssertEqual(state.templates.count, 5)
        XCTAssertTrue(state.templates.allSatisfy(\.isEstimate))
    }
    func testStarterFoodValuesMatchApproximateConversationBreakdown() {
        let total = FoodTemplate.starters.reduce(Nutrition.zero) { $0 + $1.nutrition }
        XCTAssertEqual(total.calories, 1780)
        XCTAssertEqual(total.protein, 127)
        XCTAssertEqual(total.carbs, 167)
        XCTAssertEqual(total.fat, 64)
    }
    func testCSVQuotesCommasQuotesAndNewlines() {
        var item = entry()
        item.name = "Eggs, \"fried\""
        item.note = "Line one\nLine two"
        let csv = DiaryCSV.make(entries: [item])
        XCTAssertTrue(csv.contains("\"Eggs, \"\"fried\"\"\""))
        XCTAssertTrue(csv.contains("\"Line one\nLine two\""))
    }
    func testCSVProtectsFormulaLikeNames() {
        XCTAssertEqual(DiaryCSV.escape("=1+1"), "\"'=1+1\"")
        XCTAssertEqual(DiaryCSV.escape(" @sum(A1)"), "\"' @sum(A1)\"")
    }
    func testStateRoundTripPreservesQueuesAndReceipts() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = StateFile(url: directory.appendingPathComponent("diary.json"))
        var state = AppState()
        state.entries = [entry()]
        state.entries[0].exportedVersions["protein"] = 1
        state.deletions = [DeletionTask(id: UUID(), completedNutrients: [.fat])]
        try file.save(state)
        XCTAssertEqual(try file.load(), state)
    }
    func testMissingFileStartsOfflineAndEmpty() throws {
        let file = StateFile(url: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("diary.json"))
        let result = try file.load()
        XCTAssertTrue(result.entries.isEmpty)
        XCTAssertFalse(result.healthEnabled)
    }
    func testCorruptFileIsNotOverwrittenByLoad() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        let bytes = Data("not valid JSON".utf8)
        try bytes.write(to: url)
        XCTAssertThrowsError(try StateFile(url: url).load())
        XCTAssertEqual(try Data(contentsOf: url), bytes)
    }
    func testUnknownSchemaIsRejected() {
        var state = AppState(); state.schemaVersion = 999
        XCTAssertFalse(state.isValid)
    }
    func testDuplicateOrDeletedEntryIDsAreRejected() {
        var state = AppState(); let item = entry()
        state.entries = [item, item]
        XCTAssertFalse(state.isValid)
        state.entries = [item]
        state.deletions = [DeletionTask(id: item.id)]
        XCTAssertFalse(state.isValid)
    }

    func testAppStateMerging() {
        var local = AppState()
        var remote = AppState()

        let entryA = entry(id: UUID(), nutrition: Nutrition(calories: 100, protein: 10))
        var entryB = entry(id: UUID(), nutrition: Nutrition(calories: 200, protein: 20))
        entryB.version = 1
        var entryBUpdated = entryB
        entryBUpdated.version = 2
        entryBUpdated.name = "Updated Entry B"
        let entryC = entry(id: UUID(), nutrition: Nutrition(calories: 300, protein: 30))

        local.entries = [entryA, entryB]
        remote.entries = [entryBUpdated, entryC]

        // 1. Basic merge: disjoint entries combine, higher version wins
        let merged1 = local.merging(with: remote)
        XCTAssertEqual(merged1.entries.count, 3)
        XCTAssertTrue(merged1.entries.contains { $0.id == entryA.id })
        XCTAssertTrue(merged1.entries.contains { $0.id == entryC.id })
        let mergedB = merged1.entries.first { $0.id == entryB.id }
        XCTAssertEqual(mergedB?.version, 2)
        XCTAssertEqual(mergedB?.name, "Updated Entry B")

        // 2. Deletion handling: deleted entry is purged from both sides
        remote.deletions = [DeletionTask(id: entryA.id)]
        let merged2 = local.merging(with: remote)
        XCTAssertEqual(merged2.entries.count, 2)
        XCTAssertFalse(merged2.entries.contains { $0.id == entryA.id })
        XCTAssertTrue(merged2.deletions.contains { $0.id == entryA.id })

        // 3. Body measurements merge without duplicating
        let m1 = BodyMeasurement(id: UUID(), date: day, metric: .weight, value: 75.0)
        let m2 = BodyMeasurement(id: UUID(), date: day.addingTimeInterval(3600), metric: .waist, value: 32.0)
        local.measurements = [m1]
        remote.measurements = [m1, m2]
        let merged3 = local.merging(with: remote)
        XCTAssertEqual(merged3.measurements.count, 2)

        // 4. Body deletion purges measurement
        local.bodyDeletions = [BodyDeletion(id: m1.id, metric: .weight)]
        local.measurements.removeAll { $0.id == m1.id }
        let merged4 = local.merging(with: remote)
        XCTAssertEqual(merged4.measurements.count, 1)
        XCTAssertEqual(merged4.measurements.first?.id, m2.id)

        // 5. Symmetric commutativity on food entries
        let symmetricMerged = remote.merging(with: local)
        XCTAssertEqual(merged4.entries.map(\.id), symmetricMerged.entries.map(\.id))
    }
}

