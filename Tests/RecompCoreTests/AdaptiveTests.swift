import XCTest
#if !RECOMP_NATIVE_TESTS
@testable import RecompCore
#endif

final class AdaptiveTests: XCTestCase {
    var calendar: Calendar {
        var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "America/Los_Angeles")!; return c
    }
    var now: Date { ISO8601DateFormatter().date(from: "2026-09-18T12:00:00-07:00")! }
    func data(_ scenario: AdaptiveDemo = .stable) -> (state: AppState, points: [BodyPoint]) { scenario.data(now: now, calendar: calendar) }
    func report(_ state: AppState, _ points: [BodyPoint]) -> MaintenanceReport { MaintenanceEngine.evaluate(state: state, points: points, now: now, calendar: calendar) }
    func add(_ days: Int, _ date: Date) -> Date { calendar.date(byAdding: .day, value: days, to: date)! }

    func testEmptyDoesNotPresentGuessAsMeasured() {
        let r = report(AppState(), [])
        XCTAssertNil(r.estimate); XCTAssertNil(r.proposal); XCTAssertEqual(r.completedDays, 0)
    }
    func testStableWeightMaintenanceEqualsIntake() {
        let d = data(); let r = report(d.state, d.points)
        XCTAssertEqual(r.estimate!, 2500, accuracy: 0.01)
        XCTAssertEqual(r.kgPerWeek!, 0, accuracy: 0.001)
        XCTAssertEqual(r.completedDays, 28); XCTAssertEqual(r.weightDays, 29)
        XCTAssertNil(r.proposal)
    }
    func testLosingWeightIncreasesEstimatedMaintenance() {
        let d = data(.losing); let r = report(d.state, d.points)
        XCTAssertEqual(r.estimate!, 3000, accuracy: 25)
        XCTAssertLessThan(r.kgPerWeek!, 0)
        XCTAssertEqual(r.proposal!.calories, 2650)
    }
    func testGainingWeightLowersEstimatedMaintenance() {
        let d = data(.gaining); let r = report(d.state, d.points)
        XCTAssertEqual(r.estimate!, 2150, accuracy: 25)
        XCTAssertGreaterThan(r.kgPerWeek!, 0)
        XCTAssertEqual(r.proposal!.calories, 2350)
    }
    func testManualOptInRequiredForProposal() {
        var d = data(.gaining); d.state.adaptive.guidanceEnabled = false
        let r = report(d.state, d.points)
        XCTAssertNotNil(r.estimate); XCTAssertNil(r.proposal)
    }
    func testMissingFoodDayBreaksWindowNotZeroFilled() {
        let d = data(.incomplete); let r = report(d.state, d.points)
        XCTAssertNil(r.estimate); XCTAssertEqual(r.completedDays, 9); XCTAssertNil(r.proposal)
    }
    func testExcludedDayBreaksWindow() {
        var d = data(); d.state.dayReviews[18].excludedFromAnalysis = true
        XCTAssertNil(report(d.state, d.points).estimate)
    }
    func testMealsWithoutConfirmationDoNotCount() {
        var d = data(); d.state.dayReviews = []
        for i in 1...28 { d.state.entries.append(FoodEntry(name: "Meals", date: add(-i, now), meal: .dinner, nutrition: .startingTargets)) }
        XCTAssertNil(report(d.state, d.points).estimate)
    }
    func testTodayIsExcludedEvenWhenConfirmed() {
        var d = data()
        d.state.dayReviews.append(DayReview(dayKey: DayReview.key(now, calendar: calendar), timeZoneID: calendar.timeZone.identifier,
            confirmedAt: now, total: Nutrition(calories: 9000), estimatedCalorieFraction: 0, includedHealth: false))
        XCTAssertEqual(report(d.state, d.points).averageIntake!.calories, 2500)
    }
    func testFinalWeighInDayFoodNotIncluded() {
        var d = data()
        // Last usable weight is yesterday morning, so yesterday's food is AFTER the final boundary.
        d.points.removeLast(); d.state.dayReviews[d.state.dayReviews.count - 1].total.calories = 9000
        let r = report(d.state, d.points)
        XCTAssertEqual(r.completedDays, 27); XCTAssertEqual(r.averageIntake!.calories, 2500)
    }
    func testTwentyCompleteDaysNotEnough() {
        var d = data(); d.state.dayReviews = Array(d.state.dayReviews.suffix(20))
        XCTAssertNil(report(d.state, d.points).estimate)
    }
    func testTwentyOneCompleteDaysCanEstimate() {
        var d = data(); d.state.dayReviews = Array(d.state.dayReviews.suffix(21))
        let r = report(d.state, d.points)
        XCTAssertNotNil(r.estimate); XCTAssertEqual(r.completedDays, 21)
        XCTAssertEqual(r.title, "Early maintenance estimate")
    }
    func testNoWeighInsMeansNoEstimate() { let d = data(); XCTAssertNil(report(d.state, []).estimate) }
    func testSparseWeighInsCannotEstimate() {
        let d = data(); XCTAssertNil(report(d.state, [d.points.first!, d.points.last!]).estimate)
    }
    func testRepeatedSameDayWeighInsDoNotMeetCoverage() {
        let d = data(); var points = Array(d.points.prefix(4))
        for _ in 0..<30 { var p = d.points.first!; p.id = UUID(); points.append(p) }
        points.append(d.points.last!); XCTAssertNil(report(d.state, points).estimate)
    }
    func testLongWeighInGapBlocksEstimate() {
        let d = data(); let points = d.points.enumerated().filter { !(10...16).contains($0.offset) }.map(\.element)
        XCTAssertNil(report(d.state, points).estimate)
    }
    func testStaleDataDoesNotOfferNewTarget() {
        var d = data(.gaining)
        d.points = d.points.map { var p = $0; p.date = add(-6, p.date); return p }
        d.state.dayReviews = d.state.dayReviews.map { var r = $0; r.dayKey = DayReview.key(add(-6, r.date(calendar: calendar)!), calendar: calendar); return r }
        let r = report(d.state, d.points)
        XCTAssertNotNil(r.estimate); XCTAssertNil(r.proposal); XCTAssertTrue(r.recommendation.contains("stale"))
    }
    func testFutureWeightDoesNotChangeEstimate() {
        var d = data(); var p = d.points.last!; p.id = UUID(); p.date = add(1, now); p.value = 100
        d.points.append(p); XCTAssertEqual(report(d.state, d.points).estimate, 2500)
    }
    func testRecentWaterSpikeBlocksProposal() {
        let d = data(.water); let r = report(d.state, d.points)
        XCTAssertEqual(r.estimate!, 2500, accuracy: 25); XCTAssertNil(r.proposal)
        XCTAssertTrue(r.recommendationTitle.contains("uncertain"))
    }
    func testIsolatedOldOutlierDoesNotDominateSlope() {
        var d = data(); d.points[8].value += 3
        let r = report(d.state, d.points)
        XCTAssertEqual(r.estimate!, 2500, accuracy: 25)
    }
    func testRecentTrendDisagreementBlocksAdjustment() {
        var d = data(.gaining)
        for i in 15..<d.points.count { d.points[i].value = d.points[14].value - Double(i - 14) * 0.03 }
        XCTAssertNil(report(d.state, d.points).proposal)
    }
    func testBodyFatReadingsDoNotAffectEnergyEstimate() {
        var d = data(); let old = report(d.state, d.points)
        d.points += d.points.enumerated().map { i, point in var p = point; p.id = UUID(); p.metric = .bodyFat; p.value = 30 - Double(i) * 0.5; return p }
        let new = report(d.state, d.points)
        XCTAssertEqual(new.estimate, old.estimate); XCTAssertEqual(new.proposal, old.proposal)
    }
    func testWaistImprovementSupportsHold() {
        let d = data(.waist); let r = report(d.state, d.points)
        XCTAssertEqual(r.waistChangeCM!, -1, accuracy: 0.001)
        XCTAssertNil(r.proposal); XCTAssertTrue(r.recommendation.contains("Waist"))
    }
    func testSingleWaistReadingDoesNotClaimProgress() {
        var d = data(.waist)
        let last = d.points.last!.date
        d.points.removeAll { $0.metric == .waist && $0.date != last }
        XCTAssertNil(report(d.state, d.points).waistChangeCM)
    }
    func testDifferentWaistMethodsAreNotCompared() {
        var d = data(.waist)
        for i in d.points.indices where d.points[i].metric == .waist && d.points[i].value == 89 { d.points[i].method = "different tape method" }
        XCTAssertNil(report(d.state, d.points).waistChangeCM)
    }
    func testDifferentTimeZoneConfirmationsRemainEligibleByActualCoverage() {
        var d = data(); d.state.dayReviews = d.state.dayReviews.map { var r = $0; r.timeZoneID = "Australia/Sydney"; return r }
        XCTAssertEqual(report(d.state, d.points).estimate, 2500)
    }
    func testDSTCalendarDaysPreserveEstimate() {
        let now = ISO8601DateFormatter().date(from: "2026-03-20T12:00:00-07:00")!
        let d = AdaptiveDemo.losing.data(now: now, calendar: calendar)
        let r = MaintenanceEngine.evaluate(state: d.state, points: d.points, now: now, calendar: calendar)
        XCTAssertEqual(r.completedDays, 28); XCTAssertEqual(r.kgPerWeek!, -0.456, accuracy: 0.00001) // Actual elapsed time across the 23-hour DST day.
    }
    func testChangedTargetCooldownBlocksRepeatedCut() {
        var d = data(.gaining)
        d.state.recordTargets(Nutrition(calories: 2450, protein: 170, carbs: 274, fat: 75), at: add(-5, now), reason: "Test")
        let r = report(d.state, d.points)
        XCTAssertNil(r.proposal); XCTAssertTrue(r.recommendation.contains("14 days"))
    }
    func testCooldownEndsAfterFourteenDays() {
        var d = data(.gaining); d.state.adaptive.lastChangedAt = add(-14, now)
        XCTAssertNotNil(report(d.state, d.points).proposal)
    }
    func testNewGoalCooldownBlocksAdjustment() {
        var d = data(.gaining); d.state.adaptive.lastChangedAt = add(-1, now)
        XCTAssertNil(report(d.state, d.points).proposal)
    }
    func testMismatchBetweenActualIntakeAndTargetBlocksCut() {
        var d = data(.gaining); d.state.targets.calories = 1800
        let r = report(d.state, d.points)
        XCTAssertNil(r.proposal); XCTAssertTrue(r.recommendationTitle.contains("intake"))
    }
    func testVeryLowIntakeDoesNotSuggestMoreRestriction() {
        var d = data(); for i in d.state.dayReviews.indices { d.state.dayReviews[i].total.calories = 900 }
        let r = report(d.state, d.points); XCTAssertNil(r.estimate); XCTAssertNil(r.proposal)
    }
    func testRapidWeightLossDoesNotPrescribeTargets() {
        var d = data(); for i in d.points.indices { d.points[i].value -= Double(i) * 0.18 }
        let r = report(d.state, d.points); XCTAssertNil(r.proposal)
    }
    func testRangeIsNotSpuriouslyPrecise() {
        let d = data(); let r = report(d.state, d.points)
        XCTAssertLessThanOrEqual(r.lower!, r.estimate! - 150)
        XCTAssertGreaterThanOrEqual(r.upper!, r.estimate! + 150)
    }
    func testEstimatedFoodsWidenSensitivityRange() {
        var d = data(); for i in d.state.dayReviews.indices { d.state.dayReviews[i].estimatedCalorieFraction = 0 }
        let measured = report(d.state, d.points)
        for i in d.state.dayReviews.indices { d.state.dayReviews[i].estimatedCalorieFraction = 1 }
        let estimated = report(d.state, d.points)
        XCTAssertGreaterThan(estimated.upper! - estimated.lower!, measured.upper! - measured.lower!)
        XCTAssertEqual(estimated.estimate, measured.estimate)
    }
    func testProposedMacrosReconcileToCalories() {
        for example in [AdaptiveDemo.losing, .gaining] {
            let d = data(example); let proposal = report(d.state, d.points).proposal!
            XCTAssertLessThanOrEqual(abs(proposal.macroCalories - proposal.calories), 3)
            XCTAssertLessThanOrEqual(abs(proposal.calories - d.state.targets.calories), 150)
            XCTAssertGreaterThan(proposal.carbs, 0)
        }
    }
    func testProteinOnlyProposalDoesNotCutCalories() {
        var d = data(); d.state.targets.protein = 100
        let r = report(d.state, d.points)
        XCTAssertEqual(r.proposal!.calories, 2500); XCTAssertEqual(r.proposal!.protein, 170)
    }
    func testMaintenanceInitialGuessDoesNotBiasLearnedEstimate() {
        var d = data(); d.state.adaptive.startingMaintenance = 4500
        XCTAssertEqual(report(d.state, d.points).estimate, 2500)
    }
    func testNoAutomaticTargetMutation() {
        let d = data(.gaining); let original = d.state
        _ = report(d.state, d.points); XCTAssertEqual(d.state, original)
    }
    func testAnalysisWorksWithoutHealthOrAPIServer() {
        let d = data(); XCTAssertFalse(d.state.healthEnabled); XCTAssertFalse(d.state.bodyHealthEnabled)
        XCTAssertNotNil(report(d.state, d.points).estimate)
    }
    func testExplicitTargetRevisionStoresBeforeAndAfter() {
        var state = AppState(); let old = state.targets
        let new = Nutrition(calories: 2600, protein: 170, carbs: 311, fat: 75)
        state.recordTargets(new, at: now, reason: "Reviewed increase")
        XCTAssertEqual(state.targetRevisions.count, 1); XCTAssertEqual(state.targetRevisions[0].before, old)
        XCTAssertEqual(state.targetRevisions[0].after, new); XCTAssertEqual(state.targets, new)
        state.recordTargets(new, at: now, reason: "No-op"); XCTAssertEqual(state.targetRevisions.count, 1)
    }
    func testLocalFoodEditInvalidatesReview() {
        var d = data(); let date = d.state.dayReviews[10].date(calendar: calendar)!
        d.state.invalidateReviews(for: [date]); XCTAssertEqual(d.state.dayReviews.count, 27)
        XCTAssertFalse(d.state.dayReviews.contains { $0.dayKey == DayReview.key(date, calendar: calendar) })
    }
    func testInvalidationWorksAcrossOriginalTimeZones() {
        var d = data(); var c = calendar; c.timeZone = TimeZone(identifier: "Australia/Sydney")!
        let date = add(-10, now)
        d.state.dayReviews.append(DayReview(dayKey: DayReview.key(date, calendar: c), timeZoneID: c.timeZone.identifier, confirmedAt: now,
            total: .startingTargets, estimatedCalorieFraction: 0, includedHealth: false))
        d.state.invalidateReviews(for: [date])
        XCTAssertFalse(d.state.dayReviews.contains { $0.timeZoneID == c.timeZone.identifier })
    }
    func testDemoDoesNotPopulateActualDiaryOrMeasurementLogs() {
        for demo in AdaptiveDemo.allCases {
            let d = data(demo); XCTAssertTrue(d.state.entries.isEmpty); XCTAssertTrue(d.state.measurements.isEmpty)
            XCTAssertTrue(d.state.maintenanceHistory.isEmpty)
        }
    }
    func testMalformedReviewDoesNotCount() {
        var d = data(); d.state.dayReviews[20].dayKey = "2026-99-99"
        XCTAssertNil(report(d.state, d.points).estimate)
    }
    func testAnalysisCSVIncludesDifferentRecordKindsAndEscapes() {
        var d = data(); d.state.dayReviews[0].note = "=danger"
        d.state.recordTargets(Nutrition(calories: 2600), at: now, reason: "=formula")
        let csv = AnalysisCSV.make(state: d.state)
        XCTAssertTrue(csv.contains("confirmed_day")); XCTAssertTrue(csv.contains("targets_before")); XCTAssertTrue(csv.contains("targets_after"))
        XCTAssertTrue(csv.contains("'=formula"))
    }
    func testTargetValidationAndMacroBudget() {
        XCTAssertNil(MaintenanceEngine.checkedTargets(calories: 2000, protein: 100, carbs: -1, fat: 70))
        XCTAssertNil(MaintenanceEngine.checkedTargets(calories: 2000, protein: 100, carbs: 100, fat: 70))
        XCTAssertNotNil(MaintenanceEngine.checkedTargets(calories: 2000, protein: 150, carbs: 215, fat: 60))
    }
}

extension AdaptiveTests {
    func testLegacyFoodBoundariesRefitMatchingWeightDays() throws {
        var d = data()
        for i in d.points.indices {
            d.points[i].date = d.points[i].date.addingTimeInterval(12 * 3600)
            d.points[i].value = 85 + Double(i * i) * 0.001
        }
        let r = report(d.state, d.points)
        let from = try XCTUnwrap(r.start), through = try XCTUnwrap(r.end)
        let matched = d.points.filter { $0.date >= from && $0.date <= through }
        let series = ScaleWeightFit.elapsedSeries(matched, locations: d.state.scaleLocations)
        let fit = try XCTUnwrap(ScaleWeightFit.fitElapsed(ScaleMath.days(series)))
        XCTAssertNotNil(r.estimate)
        XCTAssertEqual(r.kgPerWeek!, fit.fit.slope * 7, accuracy: 0.000001)
        XCTAssertEqual(r.weightDays, fit.daily.count)
    }

    func testMaintenanceWindowNeverExceeds42ElapsedDays() {
        let end = calendar.startOfDay(for: now)
        let start = add(-43, end)
        var state = AppState()
        var points: [BodyPoint] = []
        for i in 0...43 {
            let date = add(i, start)
            if i < 43 {
                state.dayReviews.append(DayReview(dayKey: DayReview.key(date, calendar: calendar),
                    timeZoneID: calendar.timeZone.identifier, confirmedAt: end,
                    total: .startingTargets, estimatedCalorieFraction: 0, includedHealth: false))
            }
            points.append(BodyPoint(id: UUID(), date: date, metric: .weight, value: 85,
                source: "Test", method: "Scale", isLocal: true, excludedFromTrend: false))
        }
        let r = MaintenanceEngine.evaluate(state: state, points: points, now: end, calendar: calendar)
        XCTAssertEqual(r.elapsedDays, 42)
        XCTAssertEqual(r.estimate, 2500)
    }

    func testChangingTrendWidensSensitivityRange() {
        let stable = data()
        var changed = stable
        for i in changed.points.indices {
            changed.points[i].value -= max(0, Double(i - 14)) * 0.07
        }
        let a = report(stable.state, stable.points), b = report(changed.state, changed.points)
        XCTAssertNotNil(b.estimate)
        XCTAssertGreaterThan(b.upper! - b.lower!, a.upper! - a.lower!)
    }
}
