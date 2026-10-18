import XCTest
#if !RECOMP_NATIVE_TESTS
@testable import RecompCore
#endif

final class EnergyExpenditureTests: XCTestCase {
    private var calendar: Calendar { EntryClock.utc }
    private var day: Date { Date(timeIntervalSince1970: 1_767_996_000) /* fixed instant; normalized below */ }
    private var start: Date { calendar.startOfDay(for: day) }
    private var end: Date { start.addingTimeInterval(86400) }
    private func inputs(complete: Bool = true) -> EnergyInputs {
        EnergyInputs(resting: RestingEnergyEstimate(kcalPerDay: 1600, date: start.addingTimeInterval(-86400), source: "Synthetic RMR"),
                     typicalNutrition: .zero, foodCoverageComplete: complete)
    }
    private func calculate(_ input: EnergyInputs, now: Date? = nil, workouts: [WorkoutRecord] = [], intervals: [StepInterval] = []) -> IntradayBurnCurve {
        IntradayBurnCalculator.calculate(dailyBurn: 2400, for: start, now: now ?? end,
            workouts: workouts, stepIntervals: intervals, weightKG: 75, energyInputs: input, calendar: calendar)
    }
    private func workout(kind: String = "strength", hours: Double = 1, span: Double? = nil) -> WorkoutRecord {
        let date = start.addingTimeInterval(10 * 3600)
        return WorkoutRecord(id: UUID(), start: date, end: date.addingTimeInterval((span ?? hours) * 3600),
            duration: hours * 3600, kind: kind, title: "Synthetic workout", source: ActivitySource(id: "test", name: "Test"))
    }
    private func point(_ metric: BodyMetric, value: Double, date: Date? = nil, method: String = "Test") -> BodyPoint {
        BodyPoint(id: UUID(), date: date ?? start, metric: metric, value: value, source: "Test scale", method: method,
                  isLocal: true, excludedFromTrend: false)
    }
    private func scan(_ values: [DXAValue]) -> DXAScan {
        DXAScan(scanDay: DXAScan.day(start, calendar: calendar), provider: "Synthetic lab", values: values, reviewed: true)
    }
    private func history(count: Int = 7, hours: Double = 8) -> [StepInterval] {
        (1...count).map { offset in
            let a = start.addingTimeInterval(-Double(offset) * 86400 + 8 * 3600)
            return StepInterval(start: a, end: a.addingTimeInterval(hours * 3600), count: 10000)
        }
    }
    func testCunningham1991EquationAndInputLimits() {
        XCTAssertEqual(RestingEnergyCalculator.predicted(fatFreeMassKG: 60), 1666)
        for value in [Double.nan, .infinity, -1, 0, 500] { XCTAssertNil(RestingEnergyCalculator.predicted(fatFreeMassKG: value)) }
    }
    func testReviewedWholeBodyFFMUsesCorrectEquation() throws {
        let data = scan([DXAValue(metric: .fatFreeMass, region: "Whole body", value: 60000, unit: .g)])
        XCTAssertTrue(data.isValid)
        let result = try XCTUnwrap(RestingEnergyCalculator.resolve(settings: EnergySettings(), points: [], scans: [data], asOf: end, calendar: calendar))
        XCTAssertEqual(result.kcalPerDay, 1666); XCTAssertEqual(result.fatFreeMassKG, 60)
        XCTAssertFalse(result.isMeasured)
    }
    func testLeanSoftTissueMustIncludeBoneAndAmbiguousLeanIsIgnored() throws {
        let good = scan([DXAValue(metric: .leanSoftTissue, region: "Whole body", value: 57.5, unit: .kg),
                         DXAValue(metric: .boneMineralContent, region: "Whole body", value: 2.5, unit: .kg)])
        XCTAssertEqual(try XCTUnwrap(RestingEnergyCalculator.resolve(settings: EnergySettings(), points: [], scans: [good], asOf: end, calendar: calendar)).fatFreeMassKG, 60)
        for values in [[DXAValue(metric: .leanSoftTissue, region: "Whole body", value: 60, unit: .kg)],
                       [DXAValue(metric: .unspecifiedLeanMass, region: "Whole body", value: 60, unit: .kg)],
                       [DXAValue(metric: .fatFreeMass, region: "Left leg", value: 12, unit: .kg)],
                       [DXAValue(metric: .reportedRMR, region: "Whole body", value: 1700, unit: .kcalPerDay)]] {
            XCTAssertNil(RestingEnergyCalculator.resolve(settings: EnergySettings(), points: [], scans: [scan(values)], asOf: end, calendar: calendar))
        }
    }
    func testConflictingDXAValuesDoNotSupplyRestingEnergy() {
        let data = scan([DXAValue(metric: .fatFreeMass, region: "Whole body", value: 60, unit: .kg),
                         DXAValue(metric: .leanSoftTissue, region: "Whole body", value: 57, unit: .kg),
                         DXAValue(metric: .boneMineralContent, region: "Whole body", value: 2, unit: .kg)])
        XCTAssertNil(RestingEnergyCalculator.resolve(settings: EnergySettings(), points: [], scans: [data], asOf: end, calendar: calendar))
    }
    func testPairedBodyCompositionUsesContemporaneousWeight() throws {
        let oldWeight = point(.weight, value: 75, date: start.addingTimeInterval(-10 * 86400))
        let oldFat = point(.bodyFat, value: 20, date: oldWeight.date)
        let newerWeight = point(.weight, value: 85)
        let result = try XCTUnwrap(RestingEnergyCalculator.resolve(settings: EnergySettings(), points: [oldWeight, oldFat, newerWeight], scans: [], asOf: end))
        XCTAssertEqual(result.fatFreeMassKG, 60)
    }
    func testDifferentMethodsExcludedFutureAndStaleBodyValuesAreIgnored() {
        let weight = point(.weight, value: 75)
        var fat = point(.bodyFat, value: 20, method: "Different")
        XCTAssertNil(RestingEnergyCalculator.resolve(settings: EnergySettings(), points: [weight, fat], scans: [], asOf: end))
        fat = point(.bodyFat, value: 20); fat.excludedFromTrend = true
        XCTAssertNil(RestingEnergyCalculator.resolve(settings: EnergySettings(), points: [weight, fat], scans: [], asOf: end))
        for date in [end.addingTimeInterval(86400), start.addingTimeInterval(-100 * 86400)] {
            XCTAssertNil(RestingEnergyCalculator.resolve(settings: EnergySettings(), points: [point(.weight, value: 75, date: date), point(.bodyFat, value: 20, date: date)], scans: [], asOf: end))
        }
    }
    func testManualOverrideWinsAndIsNotAssumedMeasured() throws {
        var settings = EnergySettings(manualRestingKcal: 1850, manualRestingDate: start)
        let data = [point(.weight, value: 75), point(.bodyFat, value: 20)]
        let manual = try XCTUnwrap(RestingEnergyCalculator.resolve(settings: settings, points: data, scans: [], asOf: end))
        XCTAssertEqual(manual.kcalPerDay, 1850); XCTAssertFalse(manual.isMeasured)
        settings.manualRestingDate = end.addingTimeInterval(1)
        XCTAssertEqual(RestingEnergyCalculator.resolve(settings: settings, points: data, scans: [], asOf: end)?.kcalPerDay, 1666)
    }
    func testEnergySettingsValidateAndOldDiariesDecodeDefaults() throws {
        var state = AppState()
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(state)) as? [String: Any])
        json.removeValue(forKey: "energySettings")
        XCTAssertEqual(try JSONDecoder().decode(AppState.self, from: JSONSerialization.data(withJSONObject: json)).energySettings, EnergySettings())
        state.energySettings.manualRestingKcal = 1700
        XCTAssertFalse(state.isValid)
        state.energySettings.manualRestingDate = start
        XCTAssertTrue(state.isValid)
        XCTAssertEqual(try JSONDecoder().decode(AppState.self, from: JSONEncoder().encode(state)), state)
        state.energySettings.untrackedMovementKcal = .nan
        XCTAssertFalse(state.isValid)
    }
    func testNewerEnergySettingsMergeAndProtectNonemptyPreferencesFromRestore() throws {
        let local = AppState()
        var remote = AppState()
        remote.energySettings = EnergySettings(manualRestingKcal: 1700, manualRestingDate: start, updatedAt: start)
        let merged = try XCTUnwrap(local.mergedIfValid(with: remote))
        XCTAssertEqual(merged.energySettings, remote.energySettings)
        XCTAssertFalse(merged.canRestoreBackup)
        XCTAssertEqual(try XCTUnwrap(remote.mergedIfValid(with: local)).energySettings, remote.energySettings)
    }
    func testTEFUsesMacroFractionsAndBoundsCalorieDiscrepancies() {
        XCTAssertEqual(ThermicEffect.calories(Nutrition(calories: 400, protein: 100)), 100)
        XCTAssertEqual(ThermicEffect.calories(Nutrition(calories: 400, carbs: 100)), 30)
        XCTAssertEqual(ThermicEffect.calories(Nutrition(calories: 900, fat: 100)), 13.5)
        XCTAssertEqual(ThermicEffect.calories(Nutrition(calories: 400)), 40)
        XCTAssertEqual(ThermicEffect.calories(Nutrition(calories: 200, protein: 100)), 50)
        XCTAssertEqual(ThermicEffect.calories(Nutrition(calories: 500, protein: 100)), 110)
        XCTAssertEqual(ThermicEffect.calories(Nutrition(calories: 0, protein: 100)), 0)
        XCTAssertEqual(ThermicEffect.calories(Nutrition(calories: .nan)), 0)
    }
    func testDigestionAccumulatesAfterMealAndConservesAcrossMidnight() {
        let events = [DigestionEvent(date: end.addingTimeInterval(-4 * 3600), kcal: 100)]
        XCTAssertEqual(ThermicEffect.accumulated(events, from: start, through: end), 50)
        XCTAssertEqual(ThermicEffect.accumulated(events, from: end, through: end.addingTimeInterval(86400)), 50)
        XCTAssertEqual(ThermicEffect.accumulated(events, from: start, through: end.addingTimeInterval(86400)), 100)
        XCTAssertEqual(ThermicEffect.accumulated(events, from: start, through: events[0].date), 0)
    }
    func testHealthNutrientsAreCombinedBeforeEstimatingDigestion() {
        let source = "test.external"
        let nutrition = Nutrition(calories: 400, protein: 100)
        let a = HealthNutritionSample(id: UUID(), date: start, nutrient: .calories, value: 400, sourceName: "Test", sourceBundleID: source)
        let b = HealthNutritionSample(id: UUID(), date: start.addingTimeInterval(1), nutrient: .protein, value: 100, sourceName: "Test", sourceBundleID: source)
        let result = ThermicEffect.events(entries: [], samples: [a, b, a], deletions: [], bundleID: "our.app", includesHealth: true, from: start, through: end, calendar: calendar)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.reduce(0) { $0 + $1.kcal }, ThermicEffect.calories(nutrition))
    }
    func testOwnHealthExportIsNotDigestedTwice() {
        let entry = FoodEntry(name: "Synthetic", date: start, meal: .breakfast, nutrition: Nutrition(calories: 400, protein: 100))
        let sample = HealthNutritionSample(id: UUID(), date: start, nutrient: .calories, value: 400,
            sourceName: "Recomp", sourceBundleID: "our.app", localEntryID: entry.id)
        let result = ThermicEffect.events(entries: [entry], samples: [sample], deletions: [], bundleID: "our.app", includesHealth: true, from: start, through: end)
        XCTAssertEqual(result.count, 1); XCTAssertEqual(result[0].kcal, 100)
    }
    func testComponentsSumAndRestingIsSubtractedExactlyOnceFromExercise() throws {
        var input = inputs()
        input.meals = [DigestionEvent(date: start, kcal: 100)]
        let curve = calculate(input, workouts: [workout()])
        let detail = try XCTUnwrap(curve.energy)
        XCTAssertEqual(curve.workoutBurn, 3.5 * 75 - 1600 / 24, accuracy: 1e-8)
        XCTAssertEqual(detail.restingSoFar, 1600, accuracy: 1e-8)
        XCTAssertEqual(detail.untrackedSoFar, 150 * 23 / 24, accuracy: 1e-8)
        XCTAssertEqual(curve.tefBurn, 100, accuracy: 1e-8)
        XCTAssertEqual(curve.expendedSoFar, detail.restingSoFar + detail.untrackedSoFar + curve.stepBurn + curve.workoutBurn + curve.tefBurn, accuracy: 1e-8)
    }
    func testWorkoutStepsAndDuplicateWorkoutsAreCountedOnce() {
        let first = workout()
        var copy = first; copy.id = UUID()
        let bucket = StepInterval(start: first.start, end: first.end, count: 1000)
        let curve = calculate(inputs(), workouts: [first, first, copy], intervals: [bucket, bucket])
        XCTAssertEqual(curve.workoutBurn, 3.5 * 75 - 1600 / 24, accuracy: 1e-8)
        XCTAssertEqual(curve.stepBurn, 0); XCTAssertEqual(curve.stepCount, 1000, accuracy: 1e-8)
    }
    func testOverlappingWorkoutsUseLargestNetRate() {
        let curve = calculate(inputs(), workouts: [workout(), workout(kind: "running")])
        XCTAssertEqual(curve.workoutBurn, 7.5 * 75 - 1600 / 24, accuracy: 1e-8)
    }
    func testPauseDurationAndNoNegativeExercise() {
        XCTAssertEqual(calculate(inputs(), workouts: [workout(hours: 1, span: 2)]).workoutBurn, 3.5 * 75 - 1600 / 24, accuracy: 1e-8)
        var input = inputs(); input.resting.kcalPerDay = 4500
        let curve = IntradayBurnCalculator.calculate(dailyBurn: 2400, for: start, now: end, workouts: [workout(kind: "yoga")], weightKG: 25, energyInputs: input, calendar: calendar)
        XCTAssertEqual(curve.workoutBurn, 0); XCTAssertTrue(curve.expendedSoFar.isFinite)
    }
    func testFirstStepBucketCannotReduceTheRestingBackground() {
        let now = start.addingTimeInterval(12 * 3600)
        let baseline = calculate(inputs(), now: now)
        let bucket = StepInterval(start: now.addingTimeInterval(-3600), end: now, count: 1000)
        let observed = calculate(inputs(), now: now, intervals: [bucket])
        XCTAssertEqual(observed.expendedSoFar - baseline.expendedSoFar, 30, accuracy: 1e-8)
        XCTAssertEqual(observed.energy?.restingSoFar, baseline.energy?.restingSoFar)
    }
    func testIncompleteFoodGetsLabelledAllowanceAndCompleteFoodDoesNot() throws {
        var input = inputs(complete: false); input.typicalNutrition = Nutrition(calories: 2400)
        let incomplete = calculate(input)
        XCTAssertEqual(incomplete.tefBurn, 240, accuracy: 1e-8)
        XCTAssertEqual(try XCTUnwrap(incomplete.energy).digestionAllowanceSoFar, 240, accuracy: 1e-8)
        input.foodCoverageComplete = true
        XCTAssertEqual(calculate(input).tefBurn, 0)
    }
    func testCompleteCalibrationReproducesAnchorOnTypicalDay() throws {
        var input = inputs(complete: false)
        input.typicalNutrition = .startingTargets; input.confirmedFoodDays = 7; input.maintenanceAnchor = 2400
        let today = StepInterval(start: start.addingTimeInterval(8 * 3600), end: start.addingTimeInterval(16 * 3600), count: 10000)
        let curve = calculate(input, intervals: history() + [today])
        XCTAssertEqual(curve.calibrationDays, 7)
        XCTAssertEqual(curve.dailyBurn, 2400, accuracy: 1e-8)
        XCTAssertEqual(try XCTUnwrap(curve.energy).untrackedPerDay, 2400 - 1600 - 300 - input.typicalTEF, accuracy: 1e-8)
    }
    func testSparseActivityCannotCalibrateAndContradictoryAnchorIsRejected() throws {
        var input = inputs(complete: false)
        input.typicalNutrition = .startingTargets; input.confirmedFoodDays = 7; input.maintenanceAnchor = 2400
        let partial = calculate(input, intervals: history(hours: 1))
        XCTAssertEqual(partial.calibrationDays, 0)
        XCTAssertEqual(try XCTUnwrap(partial.energy).untrackedPerDay, 150)
        input.maintenanceAnchor = 1200
        let contradiction = calculate(input, intervals: history())
        XCTAssertEqual(contradiction.calibrationDays, 0)
        XCTAssertTrue(try XCTUnwrap(contradiction.energy).calibrationNote.contains("disagree"))
    }
    func testForecastStartsAtExactCutoffAndFutureMealsCannotChangeSoFar() throws {
        let now = start.addingTimeInterval(12.125 * 3600)
        var input = inputs(complete: false); input.typicalNutrition = .startingTargets
        let before = calculate(input, now: now)
        input.meals = [DigestionEvent(date: now.addingTimeInterval(3600), kcal: 200)]
        let after = calculate(input, now: now)
        XCTAssertEqual(before.expendedSoFar, after.expendedSoFar)
        XCTAssertEqual(after.projectedPoints.first, after.currentPoint)
        XCTAssertEqual(try XCTUnwrap(after.currentPoint).time, now)
        XCTAssertGreaterThan(after.dailyBurn, after.expendedSoFar)
    }
    func testComponentModelRespectsDSTAndUpcomingDays() {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        for (month, date, hours) in [(3, 8, 23), (11, 1, 25)] {
            let a = cal.date(from: DateComponents(year: 2026, month: month, day: date))!
            let b = cal.date(byAdding: .day, value: 1, to: a)!
            var input = inputs(); input.resting.date = a.addingTimeInterval(-86400)
            let curve = IntradayBurnCalculator.calculate(dailyBurn: 2400, for: a, now: b, energyInputs: input, calendar: cal)
            XCTAssertEqual(curve.energy?.restingSoFar ?? 0, 1600 * Double(hours) / 24, accuracy: 1e-8)
        }
        let future = IntradayBurnCalculator.calculate(dailyBurn: 2400, for: end, now: start.addingTimeInterval(3600), energyInputs: inputs(), calendar: calendar)
        XCTAssertEqual(future.expendedSoFar, 0); XCTAssertTrue(future.estimatedPoints.isEmpty)
    }
    func testMissingRestingInputKeepsLegacyFallbackExplicit() {
        let curve = IntradayBurnCalculator.calculate(dailyBurn: 2400, for: start, now: end, calendar: calendar)
        XCTAssertNil(curve.energy); XCTAssertEqual(curve.dailyBurn, 2400)
    }
    func testFutureRestingEstimateCannotAffectEarlierDay() {
        var input = inputs(); input.resting.date = end.addingTimeInterval(1)
        XCTAssertNil(calculate(input).energy)
    }
    func testDailyStepSummariesDoNotInventHourlyCoverageForCalibration() {
        var input = inputs(complete: false)
        input.typicalNutrition = .startingTargets; input.confirmedFoodDays = 7; input.maintenanceAnchor = 2400
        let summaries = (1...7).map { StepDay(date: start.addingTimeInterval(-Double($0) * 86400), count: 10000) }
        let curve = IntradayBurnCalculator.calculate(dailyBurn: 2400, for: start, now: end,
            steps: summaries, energyInputs: input, calendar: calendar)
        XCTAssertEqual(curve.calibrationDays, 0); XCTAssertEqual(curve.energy?.coveredActivityDays, 0)
    }
    func testCalibratedForecastDoesNotAddMovementAllowanceDuringExpectedExercise() {
        var input = inputs(complete: false)
        input.typicalNutrition = .startingTargets; input.confirmedFoodDays = 7; input.maintenanceAnchor = 2400
        let past = (1...7).map { offset -> WorkoutRecord in
            var item = workout(); item.start = item.start.addingTimeInterval(-Double(offset) * 86400)
            item.end = item.end.addingTimeInterval(-Double(offset) * 86400); return item
        }
        let curve = calculate(input, now: start, workouts: past, intervals: history())
        XCTAssertEqual(curve.calibrationDays, 7)
        XCTAssertEqual(curve.dailyBurn, 2400, accuracy: 1e-8)
    }
}
