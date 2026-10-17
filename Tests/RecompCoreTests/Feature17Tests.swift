import XCTest
#if !RECOMP_NATIVE_TESTS
@testable import RecompCore
#endif

final class Feature17Tests: XCTestCase {
    var calendar: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "America/Los_Angeles")!; return c }
    var now: Date { calendar.date(from: DateComponents(year: 2026, month: 9, day: 18, hour: 15))! }
    var jpeg: Data { Data([0xff, 0xd8, 0x01, 0xff, 0xd9]) } // Byte-framing fixture, NOT a decoded real image.
    var source: ActivitySource { ActivitySource(id: "example.writer.a", name: "Writer A") }
    var second: ActivitySource { ActivitySource(id: "example.writer.b", name: "Writer B") }
    func food(_ value: Double = 500) -> FoodEntry {
        FoodEntry(name: "Synthetic meal", date: now, meal: .lunch, nutrition: Nutrition(calories: value, protein: 30, carbs: 40, fat: 20))
    }
    func workout(_ writer: ActivitySource? = nil, offset: Double = 0) -> WorkoutRecord {
        WorkoutRecord(id: UUID(), start: now.addingTimeInterval(offset), end: now.addingTimeInterval(offset + 1800), duration: 1700, kind: "running", title: "Run", distanceMetres: 5000, source: writer ?? source)
    }
    func payload() -> BackupPayload {
        var state = AppState(); var meal = food()
        meal.photos = [MealPhoto(jpeg: jpeg, role: .nutritionLabel, caption: "Synthetic label")]
        meal.version = 5; meal.exportedVersions = ["calories": 5]
        state.entries = [meal]
        state.measurements = [BodyMeasurement(date: now, metric: .weight, value: 85)]
        state.contextEvents = [ContextEvent(start: now, end: now, kind: .travel, note: "Synthetic travel")]
        state.healthEnabled = true; state.bodyHealthEnabled = true; state.dxaHealthEnabled = true
        state.activityPreferences.enabled = true; state.widgetPreferences.showNumbers = true
        return BackupPayload(createdAt: now, bundleID: "test.recomp", appearance: "dark", state: state)
    }
    func testLegacySchemaFiveDecodesNewFieldsSafely() throws {
        var old = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(AppState())) as? [String:Any])
        old["schemaVersion"] = 5
        for key in ["activityPreferences","contextEvents","widgetPreferences"] { old.removeValue(forKey:key) }
        let state = try JSONDecoder().decode(AppState.self, from: JSONSerialization.data(withJSONObject: old))
        XCTAssertEqual(state.schemaVersion, 8); XCTAssertFalse(state.activityPreferences.enabled)
        XCTAssertFalse(state.widgetPreferences.showNumbers); XCTAssertTrue(state.contextEvents.isEmpty)
    }
    func testOldFoodWithoutAttachmentsStillDecodes() throws {
        let data = try JSONEncoder().encode(food())
        let recovered = try JSONDecoder().decode(FoodEntry.self, from: data)
        XCTAssertNil(recovered.photos); XCTAssertTrue(recovered.isValid)
    }
    func testSixPhotosValidSevenRejected() {
        var f = food(); f.photos = (0..<6).map { _ in MealPhoto(jpeg: jpeg) }; XCTAssertTrue(f.isValid)
        f.photos!.append(MealPhoto(jpeg: jpeg)); XCTAssertFalse(f.isValid)
    }
    func testDuplicatePhotoIdentifiersRejected() {
        var f = food(); let p = MealPhoto(jpeg: jpeg); f.photos = [p,p]; XCTAssertFalse(f.isValid)
    }
    func testInvalidImageFramingRejected() {
        XCTAssertFalse(MealPhoto(jpeg: Data("not an image".utf8)).isValid)
        XCTAssertFalse(MealPhoto(jpeg: Data([0xff,0xd8,0])).isValid)
    }
    func testOversizedPhotoRejected() {
        var data = Data(repeating: 1, count: MealPhoto.maximumBytes + 1); data[0] = 0xff; data[1] = 0xd8
        data[data.count-2] = 0xff; data[data.count-1] = 0xd9
        XCTAssertFalse(MealPhoto(jpeg: data).isValid)
    }
    func testCaptionLengthBound() { XCTAssertFalse(MealPhoto(jpeg: jpeg, caption: String(repeating: "x", count: 241)).isValid) }
    func testAttachmentGlobalBudget() {
        var image = Data(repeating: 1, count: 1_500_000); image[0] = 0xff; image[1] = 0xd8
        image[image.count-2] = 0xff; image[image.count-1] = 0xd9
        var s = AppState()
        s.entries = (0..<33).map { _ in var f = food(); f.photos = [MealPhoto(jpeg: image)]; return f }
        XCTAssertTrue(s.photoAttachmentsAreValid)
        var extra = food(); extra.photos = [MealPhoto(jpeg: image)]; s.entries.append(extra)
        XCTAssertFalse(s.photoAttachmentsAreValid); XCTAssertFalse(s.isValid)
    }
    func testEvidenceIndicesAndTextBounded() {
        XCTAssertTrue(FoodEvidence(kind: .label, photoNumber: 6, detail: "per serving").isValid)
        XCTAssertFalse(FoodEvidence(kind: .label, photoNumber: 7, detail: "per serving").isValid)
        XCTAssertFalse(FoodEvidence(kind: .label, photoNumber: 0, detail: "per serving").isValid)
        XCTAssertFalse(FoodEvidence(kind: .visual, photoNumber: nil, detail: "").isValid)
        XCTAssertFalse(FoodEvidence(kind: .visual, photoNumber: nil, detail: String(repeating: "a", count: 401)).isValid)
    }
    func testPhotoRolesRoundTrip() throws {
        for role in MealPhotoRole.allCases {
            let p = MealPhoto(jpeg: jpeg, role: role, caption: "only half eaten")
            XCTAssertEqual(try JSONDecoder().decode(MealPhoto.self, from: JSONEncoder().encode(p)), p)
        }
    }
    func testBackupPayloadRoundTripPreservesIDsPhotosVersionsAndContext() throws {
        let p = payload(), restored = try BackupPayload.decode(p.encode())
        XCTAssertEqual(restored, p); XCTAssertEqual(restored.state.entries[0].photos?.first?.jpeg, jpeg)
        XCTAssertEqual(restored.state.entries[0].version, 5)
    }
    func testRestorePausesAllConnectionsAndWidgetNumbers() throws {
        let p = payload(), restored = try p.restoredState(over: AppState(), bundleID: p.bundleID)
        XCTAssertFalse(restored.healthEnabled); XCTAssertFalse(restored.bodyHealthEnabled); XCTAssertFalse(restored.dxaHealthEnabled)
        XCTAssertFalse(restored.activityPreferences.enabled); XCTAssertFalse(restored.widgetPreferences.showNumbers)
        XCTAssertEqual(restored.entries, p.state.entries); XCTAssertEqual(restored.contextEvents, p.state.contextEvents)
    }
    func testRestoreRejectsNonemptyFoodDiary() {
        var current = AppState(); current.entries = [food()]
        XCTAssertThrowsError(try payload().restoredState(over: current, bundleID: "test.recomp"))
    }
    func testRestoreProtectsCustomizedTargets() {
        var state = AppState(); state.targets.calories = 2400; XCTAssertFalse(state.canRestoreBackup)
    }
    func testRestoreProtectsScaleTagsAndDeletedHistory() {
        var s = AppState(); s.lastScaleLocationID = s.scaleLocations.first?.id; XCTAssertFalse(s.canRestoreBackup)
        s = AppState(); s.ignoredHealthBodyIDs.insert(UUID()); XCTAssertFalse(s.canRestoreBackup)
        s = AppState(); s.contextEvents = [ContextEvent(start: now, end: now, kind: .other)]; XCTAssertFalse(s.canRestoreBackup)
    }
    func testRestoreRejectsDifferentAppIdentity() { XCTAssertThrowsError(try payload().restoredState(over: AppState(), bundleID: "other.app")) }
    func testBackupFutureFormatRefused() throws {
        var p = payload(); p.version = 2; XCTAssertThrowsError(try p.encode())
    }
    func testBackupRejectsInvalidState() throws {
        var p = payload(); p.state.entries[0].nutrition.calories = -1; XCTAssertThrowsError(try p.encode())
    }
    func testMalformedBackupRefused() { XCTAssertThrowsError(try BackupPayload.decode(Data("{}".utf8))) }
    func testEncryptedEnvelopeStrictParameters() throws {
        var e = BackupEnvelope(salt: Data(repeating: 1, count: 16), sealed: Data(repeating: 1, count: 30))
        XCTAssertTrue(e.isValid); e.iterations = 1; XCTAssertFalse(e.isValid)
        XCTAssertThrowsError(try BackupEnvelope.decode(JSONEncoder().encode(e)))
        e.iterations = 600_000; e.cipher = "none"; XCTAssertFalse(e.isValid)
    }
    func testEnvelopeHeaderIsAuthenticatedInput() {
        let e = BackupEnvelope(salt: Data(repeating: 1, count: 16), sealed: Data(repeating: 1, count: 30))
        var altered = e; altered.salt[0] = 2; XCTAssertNotEqual(altered.authenticatedData, e.authenticatedData)
        altered = e; altered.version += 1; XCTAssertNotEqual(altered.authenticatedData, e.authenticatedData)
    }
    func testEnvelopeRejectsShortNonceTagMaterial() {
        XCTAssertFalse(BackupEnvelope(salt: Data(repeating: 0, count: 16), sealed: Data(repeating: 0, count: 27)).isValid)
        XCTAssertFalse(BackupEnvelope(salt: Data(repeating: 0, count: 15), sealed: Data(repeating: 0, count: 50)).isValid)
    }
    func testWorkoutExactIDsDeduplicated() {
        let w = workout(); XCTAssertEqual(ActivityMath.workouts([w,w], preferences: ActivityPreferences()).count, 1)
    }
    func testWorkoutSourceFilterAndLocalHiding() {
        let a = workout(), b = workout(second)
        var p = ActivityPreferences(); p.workoutSourceID = second.id
        XCTAssertEqual(ActivityMath.workouts([a,b], preferences: p), [b])
        p.hiddenWorkoutIDs = [b.id]; XCTAssertTrue(ActivityMath.workouts([a,b], preferences: p).isEmpty)
    }
    func testNearDuplicateWorkoutsFlaggedNotDeleted() {
        let a = workout(), b = workout(second, offset: 20)
        XCTAssertEqual(ActivityMath.possibleDuplicateIDs([a,b]), Set([a.id,b.id]))
        XCTAssertEqual(ActivityMath.workouts([a,b], preferences: ActivityPreferences()).count, 2)
    }
    func testSameWriterAndDifferentActivitiesNotAssumedCopies() {
        let a = workout(); var b = workout(); XCTAssertTrue(ActivityMath.possibleDuplicateIDs([a,b]).isEmpty)
        b.source = second; b.kind = "strength"; XCTAssertTrue(ActivityMath.possibleDuplicateIDs([a,b]).isEmpty)
    }
    func testNonoverlappingWorkoutsNotFlagged() { XCTAssertTrue(ActivityMath.possibleDuplicateIDs([workout(),workout(second, offset: 5000)]).isEmpty) }
    func testInvalidWorkoutExcluded() {
        var w = workout(); w.duration = .infinity; XCTAssertTrue(ActivityMath.workouts([w], preferences: ActivityPreferences()).isEmpty)
        w = workout(); w.distanceMetres = -1; XCTAssertFalse(w.isValid)
    }
    func testSleepIntervalsUnionNotSummed() {
        let intervals = [(now,now.addingTimeInterval(100)), (now.addingTimeInterval(20),now.addingTimeInterval(200)), (now.addingTimeInterval(300),now.addingTimeInterval(400))]
        XCTAssertEqual(ActivityMath.unionSeconds(intervals, from: now, to: now.addingTimeInterval(1000)), 300)
    }
    func testSleepClipsAndIgnoresBackwardsIntervals() {
        XCTAssertEqual(ActivityMath.unionSeconds([(now.addingTimeInterval(-10),now.addingTimeInterval(100)), (now,now.addingTimeInterval(-1))], from: now, to: now.addingTimeInterval(50)), 50)
    }
    func testSleepMultipleWritersRequireChoice() {
        let start = calendar.startOfDay(for: now), end = start.addingTimeInterval(8*3600)
        let a = SleepInterval(start: start, end: end, source: source), b = SleepInterval(start: start, end: end, source: second)
        XCTAssertTrue(ActivityMath.sleepNights([a,b], sourceID: nil, now: now, calendar: calendar).isEmpty)
        XCTAssertEqual(ActivityMath.sleepNights([a,b], sourceID: source.id, now: now, calendar: calendar).first?.seconds, 8*3600)
    }
    func testSleepSingleWriterAutoAndNoMissingZeros() {
        let start = calendar.startOfDay(for: now)
        let samples = [SleepInterval(start: start, end: start.addingTimeInterval(7*3600), source: source)]
        let nights = ActivityMath.sleepNights(samples, sourceID: nil, now: now, calendar: calendar)
        XCTAssertEqual(nights.count, 1); XCTAssertEqual(nights[0].date, start); XCTAssertEqual(nights[0].seconds, 7*3600)
    }
    func testSleepDaylightSavingUsesCalendarBoundaries() {
        let start = calendar.date(from: DateComponents(year: 2026, month: 3, day: 7, hour: 23))!
        let end = calendar.date(from: DateComponents(year: 2026, month: 3, day: 8, hour: 8))!
        let n = calendar.date(from: DateComponents(year: 2026, month: 3, day: 8, hour: 15))!
        let nights = ActivityMath.sleepNights([SleepInterval(start: start,end: end,source: source)], sourceID: nil, now: n, calendar: calendar)
        XCTAssertEqual(nights.first?.seconds, 8*3600)
    }
    func testSleepNoFutureTimeIncluded() {
        let morning = calendar.startOfDay(for: now).addingTimeInterval(6*3600)
        let nights = ActivityMath.sleepNights([SleepInterval(start: morning.addingTimeInterval(-3600),end: morning.addingTimeInterval(3600),source: source)], sourceID: nil, now: morning, calendar: calendar)
        XCTAssertEqual(nights.first?.seconds, 3600)
    }
    func testStepComparisonNeedsEnoughDays() {
        let days = (1...5).map { StepDay(date: calendar.date(byAdding: .day,value: -$0,to: now)!,count: 1000) }
        XCTAssertNil(ActivityMath.stepComparison(days, now: now, calendar: calendar))
    }
    func testStepComparisonExcludesCurrentPartialDay() {
        var days = (1...14).map { StepDay(date: calendar.date(byAdding: .day,value: -$0,to: calendar.startOfDay(for: now))!,count: $0 <= 7 ? 8000 : 4000) }
        days.append(StepDay(date: now, count: 1))
        let text = ActivityMath.stepComparison(days, now: now, calendar: calendar)!
        XCTAssertTrue(text.contains("8000/day")); XCTAssertTrue(text.contains("100% higher")); XCTAssertTrue(text.contains("coverage"))
    }
    func testInvalidContextDatesRejected() { XCTAssertFalse(ContextEvent(start: now,end: now.addingTimeInterval(-1),kind: .travel).isValid) }
    func testContextLengthBoundAndOverlap() {
        var e = ContextEvent(start: now,end: now.addingTimeInterval(100),kind: .creatine)
        XCTAssertTrue(e.overlaps(now.addingTimeInterval(50),now.addingTimeInterval(200)))
        e.note = String(repeating: "a",count:1001); XCTAssertFalse(e.isValid)
    }
    func testWidgetPrivateByDefault() {
        var s = AppState(); s.entries = [food()]
        let snapshot = s.widgetSnapshot(now: now,calendar: calendar)
        XCTAssertNil(snapshot.caloriesRemaining); XCTAssertNil(snapshot.proteinRemaining); XCTAssertFalse(snapshot.showsNumbers)
    }
    func testWidgetLocalRemainingAndOverValues() {
        var s = AppState(); s.widgetPreferences.showNumbers = true; s.entries = [food(2800)]
        let snapshot = s.widgetSnapshot(now: now,calendar: calendar)
        XCTAssertEqual(snapshot.caloriesRemaining, -300); XCTAssertEqual(snapshot.proteinRemaining, 140)
    }
    func testWidgetIgnoresYesterdayAndFutureFood() {
        var s = AppState(); s.widgetPreferences.showNumbers = true
        var yesterday = food(), future = food(); yesterday.date = now.addingTimeInterval(-86400); future.date = now.addingTimeInterval(60)
        s.entries = [yesterday,future,food()]; let w = s.widgetSnapshot(now: now,calendar: calendar)
        XCTAssertEqual(w.entriesCount,1); XCTAssertEqual(w.caloriesRemaining,2000)
    }
    func testWidgetMidnightAndTimezoneInvalidateSnapshot() {
        let w = AppState().widgetSnapshot(now: now,calendar: calendar)
        XCTAssertTrue(w.isCurrent(now: now,calendar: calendar))
        XCTAssertFalse(w.isCurrent(now: calendar.date(byAdding: .day,value: 1,to: now)!,calendar: calendar))
        var other = calendar; other.timeZone = TimeZone(identifier: "Europe/London")!
        XCTAssertFalse(w.isCurrent(now: now,calendar: other))
    }
    func testWidgetNeverIncludesMealNamesBodyOrPhotos() throws {
        let s = payload().state.widgetSnapshot(now: now,calendar: calendar)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(s)) as? [String:Any])
        XCTAssertTrue(Set(object.keys).isSubset(of: ["schema","date","timeZoneID","caloriesRemaining","proteinRemaining","calorieFraction","proteinFraction","carbsFraction","fatFraction","entriesCount","showsNumbers"]))
    }
    func testCheckProjectionDoesNotMutateDiary() {
        let s = payload().state, before = s
        let check = FoodCheckProjection(current: Nutrition(calories: 1800,protein: 125,carbs: 170,fat:65), candidate: Nutrition(calories: 800,protein: 35,carbs: 60,fat:35),targets: .startingTargets)
        XCTAssertEqual(check.projected.calories,2600); XCTAssertEqual(check.remaining.calories,-100); XCTAssertEqual(s,before)
    }
    func testTrendSummaryEmptyState() {
        let summary = TrendSummaryCalculator.calculate(
            entries: [],
            targets: Nutrition(calories: 2500, protein: 180, carbs: 250, fat: 70),
            bodyPoints: [],
            maintenanceReport: MaintenanceReport(title: "Calibrating", message: "", kgPerWeek: nil, estimate: nil),
            startingMaintenance: 2400,
            units: .metric,
            now: now,
            calendar: calendar
        )
        XCTAssertEqual(summary.recentAverageCalories, 0)
        XCTAssertEqual(summary.targetCalories, 2500)
        XCTAssertEqual(summary.loggedDaysCount, 0)
        XCTAssertNil(summary.latestWeight)
        XCTAssertEqual(summary.weightUnit, "kg")
        XCTAssertEqual(summary.estimatedDailyBurn, 2400)
        XCTAssertFalse(summary.isBurnLearned)
        XCTAssertEqual(summary.dailyEnergyBalance, 0)
    }
    func testTrendSummaryCalculates7DayAverageAndBalance() {
        let meal1 = food(2000)
        var meal2 = food(2200)
        meal2.date = calendar.date(byAdding: .day, value: -2, to: now)!
        var mealOld = food(3000)
        mealOld.date = calendar.date(byAdding: .day, value: -10, to: now)!

        let weight1 = BodyPoint(id: UUID(), date: calendar.date(byAdding: .day, value: -7, to: now)!, metric: .weight, value: 80.0, source: "Synthetic", method: "", isLocal: true, excludedFromTrend: false)
        let weight2 = BodyPoint(id: UUID(), date: now, metric: .weight, value: 79.0, source: "Synthetic", method: "", isLocal: true, excludedFromTrend: false)

        let summary = TrendSummaryCalculator.calculate(
            entries: [meal1, meal2, mealOld],
            targets: Nutrition(calories: 2500, protein: 180, carbs: 250, fat: 70),
            bodyPoints: [weight1, weight2],
            maintenanceReport: MaintenanceReport(title: "Active", message: "", kgPerWeek: -1.0, estimate: 2600),
            startingMaintenance: 2400,
            units: .metric,
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(summary.recentAverageCalories, 2100)
        XCTAssertEqual(summary.loggedDaysCount, 2)
        XCTAssertEqual(summary.calorieDeltaVsTarget, -400)
        XCTAssertEqual(summary.latestWeight, 79.0)
        XCTAssertEqual(summary.weightUnit, "kg")
        XCTAssertEqual(summary.weightChangeRatePerWeek, -1.0)
        XCTAssertEqual(summary.estimatedDailyBurn, 2600)
        XCTAssertTrue(summary.isBurnLearned)
        XCTAssertEqual(summary.dailyEnergyBalance, -500)
    }
    func testTrendSummaryImperialUnits() {
        let weightPoint = BodyPoint(id: UUID(), date: now, metric: .weight, value: 80.0, source: "Synthetic", method: "", isLocal: true, excludedFromTrend: false)
        let summary = TrendSummaryCalculator.calculate(
            entries: [food(2200)],
            targets: Nutrition(calories: 2000, protein: 150, carbs: 200, fat: 60),
            bodyPoints: [weightPoint],
            maintenanceReport: MaintenanceReport(title: "", message: "", kgPerWeek: -0.5, estimate: nil),
            startingMaintenance: 2500,
            units: .imperial,
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(summary.weightUnit, "lb")
        let expectedLb = 80.0 / 0.45359237
        XCTAssertEqual(summary.latestWeight!, expectedLb, accuracy: 0.01)
        let expectedRateLb = -0.5 / 0.45359237
        XCTAssertEqual(summary.weightChangeRatePerWeek!, expectedRateLb, accuracy: 0.01)
    }
    func testTrendSummaryIntradayExpenditure() {
        let summary = TrendSummaryCalculator.calculate(
            entries: [],
            targets: Nutrition(calories: 2000, protein: 150, carbs: 200, fat: 60),
            bodyPoints: [],
            maintenanceReport: MaintenanceReport(title: "", message: "", kgPerWeek: nil, estimate: 2400),
            startingMaintenance: 2400,
            units: .metric,
            now: now,
            calendar: calendar
        )
        XCTAssertEqual(summary.dayProgressFraction, 0.625, accuracy: 0.001)
        XCTAssertEqual(summary.expendedSoFarToday, 1500.0, accuracy: 1.0)

        let yesterday = calendar.date(byAdding: .day, value: -1, to: now)!
        let past = TrendSummaryCalculator.dayExpended(dailyBurn: 2400, for: yesterday, now: now, calendar: calendar)
        XCTAssertEqual(past.fraction, 1.0)
        XCTAssertEqual(past.expended, 2400.0)

        let tomorrow = calendar.date(byAdding: .day, value: 1, to: now)!
        let future = TrendSummaryCalculator.dayExpended(dailyBurn: 2400, for: tomorrow, now: now, calendar: calendar)
        XCTAssertEqual(future.fraction, 0.0)
        XCTAssertEqual(future.expended, 0.0)
    }

    func testIntradayBurnSeparatesBackgroundFromActivity() {
        let startOfDay = calendar.startOfDay(for: now)

        // 1. Baseline day with zero logged activity
        let baselineCurve = IntradayBurnCalculator.calculate(
            dailyBurn: 2400,
            for: now,
            now: now, // 15:00
            workouts: [],
            steps: [],
            entries: [],
            weightKG: 75.0,
            calendar: calendar
        )
        XCTAssertEqual(baselineCurve.dailyBurn, 2400)
        XCTAssertEqual(baselineCurve.points.count, 97) // 00:00 to 24:00 at 15-min intervals
        XCTAssertEqual(baselineCurve.points.first!.actualCumulative, 0.0)
        XCTAssertEqual(baselineCurve.points.first!.linearCumulative, 0.0)
        // Midnight point matches daily burn budget
        XCTAssertEqual(baselineCurve.points.last!.linearCumulative, 2400, accuracy: 0.1)
        XCTAssertEqual(baselineCurve.points.last!.actualCumulative, 2400, accuracy: 5.0)

        // Monotonic increase check
        for i in 1..<baselineCurve.points.count {
            XCTAssertGreaterThanOrEqual(baselineCurve.points[i].actualCumulative, baselineCurve.points[i - 1].actualCumulative)
            XCTAssertGreaterThan(baselineCurve.points[i].linearCumulative, baselineCurve.points[i - 1].linearCumulative)
        }

        // 2. Day with 10 km morning run at 07:00 (80 kg runner)
        let runStart = calendar.date(byAdding: .hour, value: 7, to: startOfDay)!
        let runEnd = calendar.date(byAdding: .minute, value: 50, to: runStart)!
        let runWorkout = WorkoutRecord(
            id: UUID(),
            start: runStart,
            end: runEnd,
            duration: 3000,
            kind: "running",
            title: "Morning Run",
            distanceMetres: 10_000,
            source: ActivitySource(id: "strava", name: "Strava")
        )

        let runCurve = IntradayBurnCalculator.calculate(
            dailyBurn: 2400,
            for: now,
            now: now, // 15:00
            workouts: [runWorkout],
            steps: [],
            entries: [],
            weightKG: 80.0,
            calendar: calendar
        )
        // The background excludes a provisional activity allowance; net workout
        // energy replaces that allowance rather than adding to full maintenance.
        XCTAssertEqual(runCurve.workoutBurn, 666.6666667, accuracy: 0.01)
        XCTAssertEqual(runCurve.workouts.count, 1)
        XCTAssertEqual(runCurve.expendedSoFar, 2400 * 0.8 * 15 / 24 + runCurve.workoutBurn, accuracy: 0.01)

        // 3. Step thermogenesis test: 10,000 steps (75 kg)
        let stepDay = StepDay(date: startOfDay, count: 10_000)
        let stepCurve = IntradayBurnCalculator.calculate(
            dailyBurn: 2400,
            for: now,
            now: now,
            workouts: [],
            steps: [stepDay],
            entries: [],
            weightKG: 75.0,
            calendar: calendar
        )
        // A day without a workout counts walking above the background.
        XCTAssertEqual(stepCurve.stepBurn, 300, accuracy: 0.01)
        XCTAssertEqual(stepCurve.points.last!.actualCumulative, 2400)
        XCTAssertEqual(stepCurve.stepCount, 10_000)
    }
}

extension Feature17Tests {
    func testBurnAcrossDSTUsesElapsedHoursAndEndsAtNextMidnight() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        for (text, hours) in [("2026-03-08T00:00:00-08:00", 23.0), ("2026-11-01T00:00:00-07:00", 25.0)] {
            let day = ISO8601DateFormatter().date(from: text)!
            let end = cal.date(byAdding: .day, value: 1, to: day)!
            let midpoint = day.addingTimeInterval(hours * 1800)
            let curve = IntradayBurnCalculator.calculate(dailyBurn: 2400, for: day, now: midpoint, calendar: cal)
            XCTAssertEqual(curve.points.last!.time, end)
            XCTAssertEqual(curve.fraction, 0.5, accuracy: 0.000001)
            XCTAssertEqual(curve.expendedSoFar, hours * 50, accuracy: 0.000001)
            XCTAssertEqual(curve.points.last!.actualCumulative, hours * 100, accuracy: 0.000001)
            let oldAPI = TrendSummaryCalculator.dayExpended(dailyBurn: 2400, for: day, now: midpoint, calendar: cal)
            XCTAssertEqual(oldAPI.expended, curve.expendedSoFar, accuracy: 0.000001)
            let summary = TrendSummaryCalculator.calculate(entries: [], targets: .startingTargets,
                bodyPoints: [], maintenanceReport: MaintenanceReport(), startingMaintenance: 2400,
                units: .metric, now: midpoint, calendar: cal)
            XCTAssertEqual(summary.expendedSoFarToday, curve.expendedSoFar, accuracy: 0.000001)
        }
    }

    func testMealsAndDuplicateStepsDoNotInflateDailyBurn() {
        let start = calendar.startOfDay(for: now)
        let meal = food(2500)
        let step = StepDay(date: start, count: 10000)
        let curve = IntradayBurnCalculator.calculate(dailyBurn: 2400, for: now, now: now,
            steps: [step, step], entries: [meal], calendar: calendar)
        XCTAssertEqual(curve.stepCount, 10000)
        XCTAssertEqual(curve.points.last!.actualCumulative, 2400)
        XCTAssertEqual(curve.tefBurn, 0)
    }

    func testCalorieReviewChecksComponentsWithoutRewritingAlcoholOrLabels() {
        let alcohol = EstimatedFood(name: "Spirit", portion: "50 ml", nutrition: Nutrition(calories: 110))
        let meal = MealEstimate(title: "Drink", items: [alcohol])
        XCTAssertTrue(meal.canLog)
        XCTAssertEqual(meal.nutritionReviewWarnings.count, 1)
        XCTAssertEqual(meal.total.calories, 110)
        let label = EstimatedFood(name: "Label", portion: "1 serving",
            nutrition: Nutrition(calories: 100, protein: 4, carbs: 15, fat: 3))
        XCTAssertTrue(MealEstimate(title: "Snack", items: [label]).nutritionReviewWarnings.isEmpty)
    }
}

extension Feature17Tests {
    func testSummaryDoesNotCompareDifferentScalesOrExcludedWeight() {
        let a = UUID(), b = UUID()
        func point(_ days: Double, _ value: Double, _ scale: UUID, excluded: Bool = false) -> BodyPoint {
            BodyPoint(id: UUID(), date: now.addingTimeInterval(days * 86400), metric: .weight,
                value: value, source: "Test", method: "Scale", isLocal: true,
                excludedFromTrend: excluded, scaleLocationID: scale)
        }
        let summary = TrendSummaryCalculator.calculate(entries: [], targets: .startingTargets,
            bodyPoints: [point(-6, 80, a), point(-2, 85, b), point(-1, 85, b), point(0, 100, b, excluded: true)],
            maintenanceReport: MaintenanceReport(), startingMaintenance: 2400, units: .metric,
            now: now, calendar: calendar)
        XCTAssertEqual(summary.latestWeight, 85)
        XCTAssertEqual(summary.weightChangeRatePerWeek, 0)
        XCTAssertEqual(summary.weightNetChange, 0)
    }
}

extension Feature17Tests {
    func testSummaryUsesSavedTravelDatesAndRejectsFutureMeals() {
        var utc = Calendar(identifier: .gregorian); utc.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = ISO8601DateFormatter().date(from: "2026-09-25T12:00:00Z")!
        var included = food(1000)
        included.date = ISO8601DateFormatter().date(from: "2026-09-18T23:30:00Z")!
        included.clock = EntryClock(date: included.date, timeZoneID: "Asia/Tokyo", provenance: .recorded)
        var excluded = food(3000)
        excluded.date = ISO8601DateFormatter().date(from: "2026-09-19T01:00:00Z")!
        excluded.clock = EntryClock(date: excluded.date, timeZoneID: "America/Los_Angeles", provenance: .recorded)
        var future = food(5000); future.date = now.addingTimeInterval(3600)
        let r = TrendSummaryCalculator.calculate(entries: [included, excluded, future], targets: .startingTargets,
            bodyPoints: [], maintenanceReport: MaintenanceReport(), startingMaintenance: 2400,
            units: .metric, now: now, calendar: utc)
        XCTAssertEqual(r.loggedDaysCount, 1)
        XCTAssertEqual(r.recentAverageCalories, 1000)
    }

    func testSummaryDoesNotTurnWithinDayFluctuationsIntoWeeklyChange() {
        let points = [80.0, 82.0].enumerated().map { i, value in
            BodyPoint(id: UUID(), date: now.addingTimeInterval(Double(i - 1) * 3600), metric: .weight,
                value: value, source: "Test", method: "Scale", isLocal: true, excludedFromTrend: false)
        }
        let r = TrendSummaryCalculator.calculate(entries: [], targets: .startingTargets,
            bodyPoints: points, maintenanceReport: MaintenanceReport(), startingMaintenance: 2400,
            units: .metric, now: now, calendar: calendar)
        XCTAssertEqual(r.latestWeight, 81)
        XCTAssertNil(r.weightChangeRatePerWeek)
        XCTAssertNil(r.weightNetChange)
    }

    func testWeightSummaryIgnoresWaistAndKeepsLocalExclusionsAheadOfImports() {
        let id = UUID()
        let prior = BodyPoint(id: UUID(), date: now.addingTimeInterval(-86400), metric: .weight,
            value: 80, source: "Local", method: "", isLocal: true, excludedFromTrend: false, scaleLocationID: id)
        var excluded = prior; excluded.id = UUID(); excluded.date = now; excluded.value = 100; excluded.excludedFromTrend = true
        var imported = excluded; imported.id = UUID(); imported.isLocal = false; imported.excludedFromTrend = false
        var waist = prior; waist.id = UUID(); waist.date = now; waist.metric = .waist; waist.value = 90
        let result = ScaleMath.latestWeightSeries([prior, excluded, imported, waist], now: now, calendar: calendar)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.last?.value, 80)
    }
}

extension Feature17Tests {
    func testMergeRejectsConflictingScaleNamesInsteadOfReportingSuccess() {
        var a = AppState(), b = AppState()
        a.scaleLocations.append(ScaleLocation(name: "Travel"))
        b.scaleLocations.append(ScaleLocation(name: "Travel"))
        XCTAssertTrue(a.isValid); XCTAssertTrue(b.isValid)
        XCTAssertNil(a.mergedIfValid(with: b))
    }

    func testMergeFoodCorrectionInvalidatesReviewedIntake() {
        var a = AppState()
        var original = food(2000)
        original.date = calendar.date(byAdding: .day, value: -1, to: now)!
        a.entries = [original]
        a.dayReviews = [DayReview(dayKey: DayReview.key(original.date, calendar: calendar),
            timeZoneID: calendar.timeZone.identifier, confirmedAt: now, total: original.nutrition,
            estimatedCalorieFraction: 0, includedHealth: false)]
        var b = a
        b.entries[0].version += 1; b.entries[0].nutrition.calories = 2500
        let merged = a.mergedIfValid(with: b)
        XCTAssertEqual(merged?.entries.first?.nutrition.calories, 2500)
        XCTAssertTrue(merged?.dayReviews.isEmpty == true)
        XCTAssertTrue(b.mergedIfValid(with: a)?.dayReviews.isEmpty == true)
    }
}

extension Feature17Tests {
    func testMergeKeepsNewerBodyMeasurementVersion() {
        var a = AppState()
        a.measurements = [BodyMeasurement(date: now, metric: .weight, value: 80)]
        var b = a; b.measurements[0].version += 1; b.measurements[0].value = 81
        XCTAssertEqual(a.mergedIfValid(with: b)?.measurements.first?.value, 81)
        XCTAssertEqual(b.mergedIfValid(with: a)?.measurements.first?.value, 81)
    }
}


extension Feature17Tests {
    func testMergeUsesNewestTargetChangeInsteadOfLongestHistory() {
        var a = AppState(), b = AppState()
        a.recordTargets(Nutrition(calories: 2600), at: now, reason: "Latest")
        b.recordTargets(Nutrition(calories: 2700), at: now.addingTimeInterval(-7200), reason: "Old")
        b.recordTargets(Nutrition(calories: 2800), at: now.addingTimeInterval(-3600), reason: "Also old")
        XCTAssertEqual(a.mergedIfValid(with: b)?.targets.calories, 2600)
        XCTAssertEqual(b.mergedIfValid(with: a)?.targets.calories, 2600)
    }
}

extension Feature17Tests {
    func testOwnBurnCountsOverlappingWorkoutsAndStepsOnce() {
        let start = calendar.startOfDay(for: now).addingTimeInterval(8 * 3600)
        let end = start.addingTimeInterval(3600)
        let a = WorkoutRecord(id: UUID(), start: start, end: end, duration: 3600, kind: "strength", title: "Lift", source: source)
        var copy = a; copy.id = UUID(); copy.source = second
        let bucket = StepInterval(start: start, end: end, count: 5000)
        let curve = IntradayBurnCalculator.calculate(dailyBurn: 2400, for: now, now: now,
            workouts: [a, a, copy], stepIntervals: [bucket, bucket], weightKG: 80, calendar: calendar)
        XCTAssertEqual(curve.stepCount, 5000, accuracy: 1e-6)
        XCTAssertEqual(curve.workoutBurn, 200, accuracy: 1e-6) // (3.5 - 1) * 80 * 1 hour
        XCTAssertEqual(curve.stepBurn, 0)
        XCTAssertEqual(curve.expendedSoFar, curve.backgroundSoFar + 200, accuracy: 1e-6)
    }
    func testHourlyStepsOutsideWorkoutAndPartialOverlap() {
        let start = calendar.startOfDay(for: now).addingTimeInterval(8 * 3600)
        let bucket = StepInterval(start: start, end: start.addingTimeInterval(3600), count: 6000)
        let w = WorkoutRecord(id: UUID(), start: start, end: start.addingTimeInterval(1800), duration: 1800,
                              kind: "walking", title: "Walk", source: source)
        let curve = IntradayBurnCalculator.calculate(dailyBurn: 2400, for: now, now: now,
            workouts: [w], stepIntervals: [bucket, bucket], weightKG: 75, calendar: calendar)
        XCTAssertEqual(curve.stepBurn, 90, accuracy: 1e-6) // Only the half outside the workout.
        XCTAssertEqual(curve.workoutBurn, 105, accuracy: 1e-6)
        let before = curve.points.first { $0.time == start }!
        let after = curve.points.first { $0.time == bucket.end }!
        XCTAssertEqual(after.actualCumulative - before.actualCumulative, 80 + 195, accuracy: 1e-6)
    }
    func testOwnBurnCalibrationReturnsMaintenanceForUsualActivity() {
        let start = calendar.startOfDay(for: now)
        let days = (1...7).map { StepDay(date: calendar.date(byAdding: .day, value: -$0, to: start)!, count: 10000) }
        let end = calendar.date(byAdding: .day, value: 1, to: start)!
        let curve = IntradayBurnCalculator.calculate(dailyBurn: 2400, for: start, now: end,
            steps: days + [StepDay(date: start, count: 10000)], weightKG: 75, calendar: calendar)
        XCTAssertEqual(curve.calibrationDays, 7)
        XCTAssertEqual(curve.typicalActivityPerDay, 300, accuracy: 1e-6)
        XCTAssertEqual(curve.backgroundPerDay, 2100, accuracy: 1e-6)
        XCTAssertEqual(curve.dailyBurn, 2400, accuracy: 1e-6)
        let busy = IntradayBurnCalculator.calculate(dailyBurn: 2400, for: start, now: end,
            steps: days + [StepDay(date: start, count: 20000)], weightKG: 75, calendar: calendar)
        XCTAssertEqual(busy.dailyBurn, 2700, accuracy: 1e-6)
        let quiet = IntradayBurnCalculator.calculate(dailyBurn: 2400, for: start, now: end,
            steps: days + [StepDay(date: start, count: 0)], weightKG: 75, calendar: calendar)
        XCTAssertEqual(quiet.dailyBurn, 2100, accuracy: 1e-6)
    }
    func testMissingHistoryIsNotZeroAndFutureRecordsDoNotCount() {
        let start = calendar.startOfDay(for: now)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: start)!
        let future = WorkoutRecord(id: UUID(), start: tomorrow, end: tomorrow.addingTimeInterval(3600), duration: 3600,
                                   kind: "running", title: "Future", source: source)
        let curve = IntradayBurnCalculator.calculate(dailyBurn: 2400, for: now, now: now,
            workouts: [future], steps: [StepDay(date: tomorrow, count: 10000)], calendar: calendar)
        XCTAssertFalse(curve.hasActivityEstimate); XCTAssertEqual(curve.calibrationDays, 0)
        XCTAssertEqual(curve.expendedSoFar, 1500); XCTAssertEqual(curve.dailyBurn, 2400)
    }
    func testForecastAndExactNowMarkerNeverCreditFutureActivity() {
        let start = calendar.startOfDay(for: now)
        let exactNow = now.addingTimeInterval(123)
        let bucket = StepInterval(start: start.addingTimeInterval(8 * 3600), end: start.addingTimeInterval(9 * 3600), count: 10000)
        let curve = IntradayBurnCalculator.calculate(dailyBurn: 2400, for: now, now: exactNow,
            stepIntervals: [bucket], calendar: calendar)
        XCTAssertEqual(curve.points.first { $0.time == exactNow }?.actualCumulative, curve.expendedSoFar)
        XCTAssertEqual(curve.expendedSoFar, curve.backgroundSoFar + curve.stepBurn + curve.workoutBurn, accuracy: 1e-6)
        XCTAssertEqual(curve.dailyBurn - curve.expendedSoFar, 2400 * (1 - curve.fraction), accuracy: 1e-6)
        for pair in zip(curve.points, curve.points.dropFirst()) {
            XCTAssertGreaterThanOrEqual(pair.1.actualCumulative, pair.0.actualCumulative)
        }
    }
    func testPausedWorkoutUsesActiveDurationAndInvalidInputsRemainFinite() {
        let start = calendar.startOfDay(for: now).addingTimeInterval(8 * 3600)
        let w = WorkoutRecord(id: UUID(), start: start, end: start.addingTimeInterval(3600), duration: 1800,
                              kind: "strength", title: "Lift", source: source)
        let curve = IntradayBurnCalculator.calculate(dailyBurn: .nan, for: now, now: now, workouts: [w],
            stepIntervals: [StepInterval(start: start, end: start, count: .infinity)], weightKG: .nan, calendar: calendar)
        XCTAssertEqual(curve.workoutBurn, 93.75, accuracy: 1e-6)
        XCTAssertTrue(curve.points.allSatisfy { $0.actualCumulative.isFinite && $0.actualCumulative >= 0 })
    }
}

extension Feature17Tests {
    func testOwnBurnWorkoutCrossesMidnightWithoutCountingWholeSessionTwice() {
        let start = calendar.startOfDay(for: now)
        let w = WorkoutRecord(id: UUID(), start: start.addingTimeInterval(-1800), end: start.addingTimeInterval(1800), duration: 3600,
                              kind: "strength", title: "Lift", source: source)
        let curve = IntradayBurnCalculator.calculate(dailyBurn: 2400, for: now, now: now,
            workouts: [w], weightKG: 80, calendar: calendar)
        XCTAssertEqual(curve.workoutBurn, 100, accuracy: 1e-6)
    }
    func testOwnBurnActivityOnDSTDaysUsesElapsedTime() {
        for (text, hours) in [("2026-03-08T00:00:00-08:00", 23.0), ("2026-11-01T00:00:00-07:00", 25.0)] {
            let start = ISO8601DateFormatter().date(from: text)!
            let end = calendar.date(byAdding: .day, value: 1, to: start)!
            let w = WorkoutRecord(id: UUID(), start: start.addingTimeInterval(4 * 3600), end: start.addingTimeInterval(5 * 3600),
                                  duration: 3600, kind: "strength", title: "Lift", source: source)
            let curve = IntradayBurnCalculator.calculate(dailyBurn: 2400, for: start, now: end,
                workouts: [w], weightKG: 80, calendar: calendar)
            XCTAssertEqual(curve.dailyBurn, 80 * hours + 200, accuracy: 1e-6)
            XCTAssertEqual(curve.points.last!.time, end)
        }
    }
    func testExtremeActivityHistoryDoesNotMakeBackgroundNegative() {
        let start = calendar.startOfDay(for: now)
        let days = (0...7).map { StepDay(date: calendar.date(byAdding: .day, value: -$0, to: start)!, count: 100000) }
        let curve = IntradayBurnCalculator.calculate(dailyBurn: 2400, for: now, now: now, steps: days, weightKG: 75, calendar: calendar)
        XCTAssertEqual(curve.calibrationDays, 0)
        XCTAssertGreaterThan(curve.backgroundPerDay, 0)
        XCTAssertTrue(curve.modelNote.contains("Provisional"))
    }

    func testBurnChartPreservesShortWorkoutBoundariesAndUsesOneMarker() {
        let start = calendar.startOfDay(for: now).addingTimeInterval(8 * 3600 + 7 * 60)
        let end = start.addingTimeInterval(6 * 60)
        let workout = WorkoutRecord(id: UUID(), start: start, end: end, duration: 360,
                                    kind: "strength", title: "Short session", source: source)
        let curve = IntradayBurnCalculator.calculate(dailyBurn: 2400, for: now, now: now,
            workouts: [workout], weightKG: 80, calendar: calendar)
        let before = curve.points.first { $0.time == start }
        let after = curve.points.first { $0.time == end }
        XCTAssertNotNil(before)
        XCTAssertNotNil(after)
        // Six minutes of background (8 kcal) plus net strength activity (20 kcal).
        XCTAssertEqual((after?.actualCumulative ?? 0) - (before?.actualCumulative ?? 0), 28, accuracy: 1e-6)
        XCTAssertEqual(curve.workoutMarkers.count, 1)
        XCTAssertEqual(curve.workoutMarkers.first?.time, start)
        XCTAssertEqual(curve.workoutMarkers.first?.workoutTitle, "Short session")
    }

    func testBurnChartSeriesShareExactCutoffAndHandlePastAndFutureDays() {
        let cutoff = now.addingTimeInterval(137)
        let today = IntradayBurnCalculator.calculate(dailyBurn: 2400, for: now, now: cutoff, calendar: calendar)
        XCTAssertEqual(today.estimatedPoints.last?.time, cutoff)
        XCTAssertEqual(today.projectedPoints.first, today.estimatedPoints.last)
        XCTAssertEqual(today.currentPoint?.actualCumulative, today.expendedSoFar)
        XCTAssertTrue(today.projectedPoints.dropFirst().allSatisfy { $0.time > cutoff && $0.isProjected })

        let yesterday = calendar.date(byAdding: .day, value: -1, to: now)!
        let past = IntradayBurnCalculator.calculate(dailyBurn: 2400, for: yesterday, now: cutoff, calendar: calendar)
        XCTAssertTrue(past.projectedPoints.isEmpty)
        XCTAssertEqual(past.estimatedPoints, past.points)
        XCTAssertEqual(past.currentPoint?.actualCumulative, past.dailyBurn)

        let tomorrow = calendar.date(byAdding: .day, value: 1, to: now)!
        let future = IntradayBurnCalculator.calculate(dailyBurn: 2400, for: tomorrow, now: cutoff, calendar: calendar)
        XCTAssertTrue(future.estimatedPoints.isEmpty)
        XCTAssertNil(future.currentPoint)
        XCTAssertEqual(future.projectedPoints, future.points)
        XCTAssertEqual(future.expendedSoFar, 0)
    }

    func testBurnChartOvernightOngoingWorkoutNeverPlotsFutureActivityAsEstimated() {
        let start = calendar.startOfDay(for: now)
        let cutoff = start.addingTimeInterval(7 * 60)
        let workout = WorkoutRecord(id: UUID(), start: start.addingTimeInterval(-600),
                                    end: start.addingTimeInterval(600), duration: 1200,
                                    kind: "strength", title: "Overnight", source: source)
        let curve = IntradayBurnCalculator.calculate(dailyBurn: 2400, for: now, now: cutoff,
            workouts: [workout], weightKG: 80, calendar: calendar)
        XCTAssertEqual(curve.workoutMarkers.count, 1)
        XCTAssertEqual(curve.workoutMarkers.first?.time, start)
        XCTAssertEqual(curve.workoutBurn, 200 * 7 / 60, accuracy: 1e-6)
        XCTAssertTrue(curve.estimatedPoints.allSatisfy { $0.time <= cutoff })
        XCTAssertFalse(curve.points.contains { $0.time == workout.end })
    }

    func testBurnChartSelectionUsesAbsoluteTimeAcrossRepeatedDSTHour() {
        let first = ISO8601DateFormatter().date(from: "2026-11-01T01:30:00-07:00")!
        let repeated = ISO8601DateFormatter().date(from: "2026-11-01T01:30:00-08:00")!
        let curve = IntradayBurnCalculator.calculate(dailyBurn: 2400, for: first, now: repeated, calendar: calendar)
        XCTAssertEqual(curve.point(nearestTo: repeated)?.time, repeated)
        XCTAssertNotEqual(curve.point(nearestTo: first)?.time, repeated)
        XCTAssertEqual(curve.point(nearestTo: first.addingTimeInterval(-100_000))?.time, curve.points.first?.time)
    }
}
