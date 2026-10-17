import Foundation
import XCTest
#if !RECOMP_NATIVE_TESTS
@testable import RecompCore
#endif

final class TravelTests: XCTestCase {
    let zones = ["America/Los_Angeles", "America/Vancouver", "America/Toronto", "Australia/Sydney", "Australia/Adelaide", "Australia/Perth", "Europe/Paris", "Europe/London", "UTC"]
    func date(_ s: String) -> Date { ISO8601DateFormatter().date(from: s)! }
    func cal(_ z: String) -> Calendar { EntryClock.calendar(in: TimeZone(identifier: z)!) }
    var origin: Date { date("2026-08-01T00:00:00Z") }
    func t(_ days: Double) -> Date { origin.addingTimeInterval(days * CoverageMath.day) }
    func food(_ when: Date, zone: String = "America/Los_Angeles", calories: Double = 500) -> FoodEntry {
        FoodEntry(name: "Synthetic food", date: when, meal: .dinner, nutrition: Nutrition(calories: calories), clock: EntryClock(date: when, timeZoneID: zone))
    }
    func review(_ start: Date, _ end: Date, zone: String = "UTC", calories: Double = 2500, events: [IntakeEvent]? = nil) -> DayReview {
        DayReview(dayKey: DayReview.key(start, calendar: cal(zone)), timeZoneID: zone, confirmedAt: t(40),
            total: Nutrition(calories: calories), estimatedCalorieFraction: (events?.reduce(0) { $0 + $1.estimatedCalories } ?? 0) / max(1, calories), includedHealth: false,
            coverageID: UUID(), coverageStart: start, coverageEnd: end, intakeEvents: events)
    }
    func history(durations: [Double] = Array(repeating: 24, count: 28), rate: Double = 0,
                 alternating: Bool = false) -> (AppState, [BodyPoint], Date) {
        var state = AppState(), cursor = origin
        for (i, hours) in durations.enumerated() {
            let end = cursor.addingTimeInterval(hours * 3600)
            let calories = 2500 * hours / 24
            let event = IntakeEvent(id: "example-\(i)", date: cursor.addingTimeInterval(hours * 1800),
                nutrition: Nutrition(calories: calories), estimatedCalories: 0)
            state.dayReviews.append(review(cursor, end, zone: zones[i % zones.count], calories: calories, events: [event]))
            cursor = end
        }
        let now = cursor.addingTimeInterval(3600)
        for i in state.dayReviews.indices { state.dayReviews[i].confirmedAt = now }
        var points: [BodyPoint] = []
        for day in 0...Int(cursor.timeIntervalSince(origin) / CoverageMath.day) {
            let other = alternating && day % 2 == 1
            points.append(BodyPoint(id: UUID(), date: t(Double(day)), metric: .weight,
                value: 85 + rate * Double(day) + (other ? 1.8 : 0), source: "Synthetic", method: "",
                isLocal: true, excludedFromTrend: false, scaleLocationID: state.scaleLocations[other ? 1 : 0].id))
        }
        return (state, points, now)
    }

    func testDinnerRemainsOnSeattleCivilDateAcrossAllViewingZones() throws {
        let entry = food(date("2026-09-18T03:00:00Z")) // Sep 17, 20:00 Seattle
        for z in zones {
            let calendar = cal(z), d = try XCTUnwrap(EntryClock.displayDate("2026-09-17", calendar: cal(z)))
            XCTAssertTrue(entry.isOnDiaryDay(d, calendar: calendar), z)
            XCTAssertEqual(DiaryMath.localTotal(entries: [entry], day: d, calendar: calendar).calories, 500, z)
            XCTAssertFalse(entry.isOnDiaryDay(calendar.date(byAdding: .day, value: 1, to: d)!, calendar: calendar), z)
        }
        XCTAssertEqual(entry.date, date("2026-09-18T03:00:00Z"))
    }
    func testWidgetUsesFrozenDiaryDateAfterFlights() {
        var state = AppState(); state.widgetPreferences.showNumbers = true
        let seattleDinner = food(date("2026-09-18T03:00:00Z")) // original Sep 17
        let sydneyLunch = food(date("2026-09-18T04:00:00Z"), zone: "Australia/Sydney", calories: 700)
        state.entries = [seattleDinner, sydneyLunch]
        let now = date("2026-09-18T05:00:00Z"), viewing = cal("Australia/Sydney")
        let widget = state.widgetSnapshot(now: now, calendar: viewing)
        XCTAssertEqual(widget.entriesCount, 1)
        XCTAssertEqual(widget.caloriesRemaining, state.targets.calories - 700)
        XCTAssertEqual(widget.caloriesRemaining, state.targets.calories - DiaryMath.localTotal(entries: state.entries, day: now, calendar: viewing).calories)
        XCTAssertFalse(widget.isCurrent(now: now, calendar: cal("America/Los_Angeles")))
    }
    func testRepeatedDateRetainsDistinctMealIdentitiesAndChronology() {
        let a = food(date("2026-09-17T02:00:00Z"), zone: "Australia/Sydney")
        let b = food(date("2026-09-18T03:00:00Z"), zone: "America/Los_Angeles")
        XCTAssertEqual(a.clock?.dayKey, b.clock?.dayKey)
        XCTAssertNotEqual(a.id, b.id); XCTAssertLessThan(a.date, b.date)
        let day = EntryClock.displayDate("2026-09-17", calendar: cal("Europe/Paris"))!
        XCTAssertEqual(DiaryMath.localTotal(entries: [a,b], day: day, calendar: cal("Europe/Paris")).calories, 1000)
    }
    func testSkippedCivilDateIsNotManufacturedAsZeroFood() {
        let a = food(date("2026-09-18T03:00:00Z")), b = food(date("2026-09-18T22:00:00Z"), zone: "Australia/Sydney")
        XCTAssertEqual(a.clock?.dayKey, "2026-09-17"); XCTAssertEqual(b.clock?.dayKey, "2026-09-19")
        XCTAssertEqual(Set([a,b].compactMap { $0.clock?.dayKey }).count, 2)
        let run = CoverageMath.latestRun([], now: b.date)
        XCTAssertNil(run.interval)
    }
    func testMeasurementChartKeepsOriginalDayButActualInstantIsUnchanged() {
        let entry = food(date("2026-09-18T03:00:00Z"))
        let p = BodyPoint(id: UUID(), date: entry.date, metric: .weight, value: 85, source: "Synthetic", method: "", isLocal: true, excludedFromTrend: false, clock: entry.clock)
        for z in zones {
            let c = cal(z), d = BodyMath.daily([p], metric: .weight, calendar: cal(z))
            XCTAssertEqual(d.count, 1); XCTAssertEqual(DayReview.key(d[0].date, calendar: c), "2026-09-17")
        }
        XCTAssertEqual(p.date, entry.date)
    }
    func testDateEditPreservesOriginalZoneInsteadOfSyncZone() {
        let old = food(date("2026-09-18T03:00:00Z"))
        let newDate = date("2026-09-19T04:00:00Z")
        let clock = EntryClock.updated(old.clock, from: old.date, to: newDate)
        XCTAssertEqual(clock?.timeZoneID, "America/Los_Angeles")
        XCTAssertEqual(clock?.dayKey, "2026-09-18")
        XCTAssertEqual(clock?.healthTimeZoneID, "America/Los_Angeles")
    }
    func testExplicitCorrectionChangesZoneNotInstant() {
        let when = date("2026-09-18T03:00:00Z")
        var entry = food(when)
        entry.clock = EntryClock.updated(entry.clock, from: when, to: when, zoneID: "Australia/Sydney", confirmed: true)
        XCTAssertEqual(entry.date, when); XCTAssertEqual(entry.clock?.dayKey, "2026-09-18")
        XCTAssertEqual(entry.clock?.provenance, .userConfirmed)
    }
    func testInvalidClockCannotBeSavedOrRestored() throws {
        var entry = food(origin); entry.clock?.dayKey = "2026-99-99"
        XCTAssertFalse(entry.isValid)
        var state = AppState(); state.entries = [entry]
        XCTAssertFalse(state.isValid)
        XCTAssertThrowsError(try BackupPayload(createdAt: origin, bundleID: "test", appearance: "system", state: state).encode())
        XCTAssertNil(EntryClock(date: origin, timeZoneID: "not-a-zone"))
        XCTAssertNil(EntryClock(date: Date(timeIntervalSince1970: .infinity), timeZoneID: "UTC"))
    }
    func testHealthMetadataZonePreservesCivilDateWhenKnown() {
        let when = date("2026-09-18T03:00:00Z"), viewing = cal("Australia/Sydney")
        var sample = HealthNutritionSample(id: UUID(), date: when, nutrient: .calories, value: 500, sourceName: "Example", sourceBundleID: "other", localEntryID: nil, clock: EntryClock(date: when, timeZoneID: "America/Los_Angeles", provenance: .healthMetadata))
        let day = EntryClock.displayDate("2026-09-17", calendar: viewing)!
        XCTAssertTrue(DiaryMath.healthSampleIsOnDay(sample, day: day, calendar: viewing))
        sample.clock = nil // Unknown metadata stays view-local, not a guessed location.
        XCTAssertFalse(DiaryMath.healthSampleIsOnDay(sample, day: day, calendar: viewing))
    }
    func testLegacyMigrationUsesUniqueReviewOnlyAsAnInference() {
        var state = AppState(); var entry = food(t(1)); entry.clock = nil; entry.version = 4; entry.exportedVersions = ["calories":4]
        state.entries = [entry]; state.dayReviews = [review(t(0),t(2), zone:"America/Los_Angeles")]
        state.migrateEntryClocks(fallback: TimeZone(identifier: "Australia/Sydney")!)
        XCTAssertEqual(state.entries[0].clock?.timeZoneID, "America/Los_Angeles")
        XCTAssertEqual(state.entries[0].clock?.provenance, .legacyReview)
        XCTAssertTrue(state.entries[0].clock!.needsReview); XCTAssertNil(state.entries[0].clock?.healthTimeZoneID)
        XCTAssertEqual(state.entries[0].date, entry.date); XCTAssertEqual(state.entries[0].version, 4)
        XCTAssertEqual(state.entries[0].exportedVersions, entry.exportedVersions)
    }
    func testAmbiguousLegacyMigrationDoesNotGuessWhichCountry() {
        var state = AppState(); var entry = food(t(1)); entry.clock = nil; state.entries = [entry]
        state.dayReviews = [review(t(0),t(2),zone:"America/Los_Angeles"), review(t(0),t(2),zone:"Australia/Sydney")]
        state.migrateEntryClocks(fallback: TimeZone(identifier: "Europe/Paris")!)
        XCTAssertEqual(state.entries[0].clock?.provenance, .legacyAssumed)
        let first = state.entries[0].clock
        state.migrateEntryClocks(fallback: TimeZone(identifier:"Australia/Sydney")!)
        XCTAssertEqual(state.entries[0].clock, first)
    }
    func testOnDiskUpgradeFreezesFallbackOnceAndKeepsReceipts() throws {
        var state = AppState(); var entry = food(t(1)); entry.clock = nil
        entry.version = 3; entry.exportedVersions = ["protein":2]; state.entries = [entry]
        var raw = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(state)) as? [String:Any]); raw["schemaVersion"] = 6
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true); defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("diary.json"); try JSONSerialization.data(withJSONObject: raw).write(to: url)
        let a = try StateFile(url: url).load(), b = try StateFile(url: url).load()
        XCTAssertEqual(a,b); XCTAssertEqual(a.schemaVersion,8); XCTAssertTrue(a.entries[0].clock!.needsReview)
        XCTAssertEqual(a.entries[0].exportedVersions,entry.exportedVersions)
        let stored = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf:url)) as? [String:Any])
        XCTAssertEqual(stored["schemaVersion"] as? Int,8)
    }
    func testBackupRoundTripRetainsOriginalClocksAndCoverageEvents() throws {
        var (s,_,now) = history(); s.entries = [food(t(1))]
        let original = BackupPayload(createdAt: now, bundleID:"test", appearance:"dark", state:s)
        let decoded = try BackupPayload.decode(original.encode())
        XCTAssertEqual(decoded,original)
        let restored = try decoded.restoredState(over:AppState(),bundleID:"test")
        XCTAssertEqual(restored.entries,s.entries); XCTAssertEqual(restored.dayReviews,s.dayReviews)
        XCTAssertFalse(restored.healthEnabled)
    }
    func testHalfOpenIntervalIncludesStartNotEndAndDeduplicatesExports() {
        let a=food(t(0)),b=food(t(1)); let other=HealthNutritionSample(id:UUID(),date:t(0.5),nutrient:.calories,value:100,sourceName:"Other",sourceBundleID:"other",localEntryID:nil)
        let own=HealthNutritionSample(id:UUID(),date:t(0),nutrient:.calories,value:500,sourceName:"Recomp",sourceBundleID:"own",localEntryID:a.id)
        let p=CoverageMath.preview(entries:[a,b],samples:[own,other,other],deletions:[],bundleID:"own",interval:DateInterval(start:t(0),end:t(1)),includesHealth:true)
        XCTAssertEqual(p.localEntries.map(\.id),[a.id]); XCTAssertEqual(p.total.calories,600); XCTAssertEqual(p.events.count,2)
    }
    func testPartialIntervalUsesMealTimesNotUniformCalorieProrating() throws {
        let a=IntakeEvent(id:"breakfast",date:t(0.25),nutrition:Nutrition(calories:500),estimatedCalories:0)
        let b=IntakeEvent(id:"dinner",date:t(0.8),nutrition:Nutrition(calories:1500),estimatedCalories:500)
        let r=review(t(0),t(1),calories:2000,events:[a,b])
        XCTAssertTrue(r.isValid)
        let sum=try XCTUnwrap(CoverageMath.total([r],from:t(0.5),to:t(1)))
        XCTAssertEqual(sum.nutrition.calories,1500); XCTAssertEqual(sum.estimated,500)
    }
    func testPartialLegacySnapshotIsNeverProrated() {
        let r=review(t(0),t(1))
        XCTAssertNil(CoverageMath.total([r],from:t(0.5),to:t(1)))
        XCTAssertEqual(CoverageMath.total([r],from:t(0),to:t(1))?.nutrition.calories,2500)
    }
    func testInvalidDuplicateOutOfIntervalOrMismatchedEventsAreRejected() {
        let e=IntakeEvent(id:"one",date:t(0.5),nutrition:Nutrition(calories:2500),estimatedCalories:0)
        var r=review(t(0),t(1),events:[e]); XCTAssertTrue(r.isValid)
        r.intakeEvents=[e,e]; XCTAssertFalse(r.isValid)
        r.intakeEvents=[e];r.intakeEvents?[0].date=t(1);XCTAssertFalse(r.isValid)
        r.intakeEvents=[e];r.total.calories=1;XCTAssertFalse(r.isValid)
        r=review(t(0),t(1));r.coverageEnd=nil;XCTAssertFalse(r.isValid)
    }
    func testIntervalBoundsRejectZeroAndExcessiveDurations() {
        XCTAssertFalse(CoverageMath.validInterval(DateInterval(start:origin,duration:0)))
        XCTAssertFalse(CoverageMath.validInterval(DateInterval(start:origin,duration:8*CoverageMath.day)))
        XCTAssertTrue(CoverageMath.validInterval(DateInterval(start:origin,duration:7*CoverageMath.day)))
    }
    func testTimezoneAliasesDoNotResetCoverage() {
        let r=[review(t(0),t(1),zone:"America/Los_Angeles"),review(t(1),t(2),zone:"America/Vancouver")]
        let run=CoverageMath.latestRun(r,now:t(40));XCTAssertFalse(run.conflict);XCTAssertEqual(run.interval?.duration,2*CoverageMath.day)
    }
    func testOverlappingReviewsAreBlockedNotSummed() {
        let r=[review(t(0),t(2)),review(t(1),t(3),zone:"Australia/Sydney")]
        XCTAssertTrue(CoverageMath.latestRun(r,now:t(40)).conflict)
        var s=AppState();s.dayReviews=r
        let m=MaintenanceEngine.evaluate(state:s,points:[],now:t(40))
        XCTAssertNil(m.estimate);XCTAssertNil(m.proposal);XCTAssertTrue(m.title.contains("overlapping"))
    }
    func testExclusionCannotBeCoveredOverByAnOverlappingReview() {
        var excluded=review(t(0.5),t(1));excluded.excludedFromAnalysis=true
        XCTAssertTrue(CoverageMath.latestRun([review(t(0),t(2)),excluded],now:t(40)).conflict)
    }
    func testOneMinuteGapBreaksCoverageInsteadOfAssumingFasting() {
        let a=review(t(0),t(1)),b=review(t(1).addingTimeInterval(60),t(2))
        let run=CoverageMath.latestRun([a,b],now:t(40));XCTAssertEqual(run.reviews.map(\.id),[b.id])
        XCTAssertNil(CoverageMath.total([a,b],from:t(0),to:t(2)))
    }
    func testExcludedAndUnfinishedIntervalsDoNotEnterAnalysis() {
        var middle=review(t(1),t(2));middle.excludedFromAnalysis=true
        var r=[review(t(0),t(1)),middle,review(t(2),t(3)),review(t(3),t(5))]
        for i in r.indices { r[i].confirmedAt=t(4) }
        let run=CoverageMath.latestRun(r,now:t(4))
        XCTAssertEqual(run.reviews.map(\.id),[r[2].id])
    }
    func testFutureDatedConfirmationDoesNotCount() {
        let r=review(t(0),t(1));XCTAssertNil(CoverageMath.latestRun([r],now:t(2)).interval)
    }
    func testEditingFoodInvalidatesExactCoverageNotItsViewingDay() {
        var state=AppState();let a=review(t(0),t(1),zone:"Australia/Sydney"),b=review(t(1),t(2),zone:"Europe/Paris")
        state.dayReviews=[a,b];state.invalidateReviews(for:[t(1)])
        XCTAssertEqual(state.dayReviews.map(\.id),[a.id])
    }
    func testMoveInvalidatesOldAndNewCoverage() {
        var state=AppState();state.dayReviews=[review(t(0),t(1)),review(t(1),t(2)),review(t(2),t(3))]
        let keep=state.dayReviews[2].id;state.invalidateReviews(for:[t(0.5),t(1.5)])
        XCTAssertEqual(state.dayReviews.map(\.id),[keep])
    }
    func testExistingSeattleBaselineIdenticalInAustraliaCanadaEurope() {
        let c=cal("America/Los_Angeles"),now=date("2026-09-18T19:00:00Z")
        let d=AdaptiveDemo.gaining.data(now:now,calendar:c)
        let baseline=MaintenanceEngine.evaluate(state:d.state,points:d.points,now:now,calendar:c)
        XCTAssertNotNil(baseline.estimate);XCTAssertNotNil(baseline.proposal)
        for z in zones { XCTAssertEqual(MaintenanceEngine.evaluate(state:d.state,points:d.points,now:now,calendar:cal(z)),baseline,z) }
    }
    func testShortAndLongFlightIntervalsNormalizePerTwentyFourHours() {
        var hours=Array(repeating:24.0,count:28);hours[6]=14;hours[7]=34;hours[15]=37;hours[16]=11
        let (state,points,now)=history(durations:hours)
        for z in zones {
            let r=MaintenanceEngine.evaluate(state:state,points:points,now:now,calendar:cal(z))
            XCTAssertEqual(r.estimate,2500,z);XCTAssertEqual(r.averageIntake?.calories,2500,z);XCTAssertEqual(r.elapsedDays,28,z)
        }
    }
    func testScaleOffsetsStillCancelDuringTravelWithActualLoss() {
        let (state,points,now)=history(rate:-0.035,alternating:true)
        for z in zones {
            let r=MaintenanceEngine.evaluate(state:state,points:points,now:now,calendar:cal(z))
            XCTAssertEqual(r.kgPerWeek ?? 0,-0.245,accuracy:1e-9,z)
            XCTAssertEqual(r.estimate,2750,z)
        }
    }
    func testDSTUsesActualHoursInSixTransitionWindows() {
        for (zone,instant) in [("America/Los_Angeles","2026-03-20T12:00:00Z"),("America/Los_Angeles","2026-11-12T12:00:00Z"),("Australia/Sydney","2026-04-16T12:00:00Z"),("Australia/Sydney","2026-10-16T12:00:00Z"),("Europe/Paris","2026-04-10T12:00:00Z"),("Europe/Paris","2026-11-05T12:00:00Z")] {
            let c=cal(zone),now=date(instant);var d=AdaptiveDemo.stable.data(now:now,calendar:c)
            let first=d.points[0].date
            for i in d.points.indices { d.points[i].value=85-0.035*d.points[i].date.timeIntervalSince(first)/CoverageMath.day }
            for i in d.state.dayReviews.indices { d.state.dayReviews[i].total.calories=2500*d.state.dayReviews[i].coverageInterval!.duration/CoverageMath.day }
            let r=MaintenanceEngine.evaluate(state:d.state,points:d.points,now:now,calendar:cal("UTC"))
            XCTAssertEqual(r.kgPerWeek ?? 0,-0.245,accuracy:1e-9,zone)
            XCTAssertEqual(r.averageIntake?.calories ?? 0,2500,accuracy:1e-7,zone)
        }
    }
    func testNoBaselineFromShortTripsWithUnrelatedNewScales() {
        var (s,p,now)=history()
        for i in p.indices {
            let group=i/7
            while s.scaleLocations.count <= group { s.scaleLocations.append(ScaleLocation(name:"Synthetic \(s.scaleLocations.count)")) }
            p[i].scaleLocationID=s.scaleLocations[group].id
        }
        let r=MaintenanceEngine.evaluate(state:s,points:p,now:now)
        XCTAssertNil(r.estimate);XCTAssertNil(r.proposal)
    }
    func testDifferentCalendarSystemsDoNotChangeResultOrDiaryDay() {
        let (s,p,now)=history(rate:0.02)
        let base=MaintenanceEngine.evaluate(state:s,points:p,now:now)
        let e=food(origin)
        for id in [Calendar.Identifier.buddhist,.hebrew,.islamic,.japanese] {
            var c=Calendar(identifier:id);c.timeZone=TimeZone(identifier:"Europe/Paris")!
            XCTAssertEqual(MaintenanceEngine.evaluate(state:s,points:p,now:now,calendar:c),base)
            XCTAssertTrue(e.isOnDiaryDay(EntryClock.displayDate(e.clock!.dayKey,calendar:c)!,calendar:c))
        }
    }
    func testCSVRetainsDiaryDateZoneAndCoverageBoundaries() {
        let e=food(origin);let csv=DiaryCSV.make(entries:[e])
        XCTAssertTrue(csv.contains("entry_timezone"));XCTAssertTrue(csv.contains("America/Los_Angeles"));XCTAssertTrue(csv.contains(e.clock!.dayKey))
        var s=AppState();s.dayReviews=[review(t(0),t(1.5))]
        let analysis=AnalysisCSV.make(state:s)
        XCTAssertTrue(analysis.contains("elapsed_hours=36.0"));XCTAssertTrue(analysis.contains("through="))
    }
    func testRepeatedDSTHourRepresentsTwoDifferentInstants() {
        let a=food(date("2026-11-01T08:30:00Z")),b=food(date("2026-11-01T09:30:00Z"))
        XCTAssertEqual(a.clock?.dayKey,b.clock?.dayKey);XCTAssertEqual(b.date.timeIntervalSince(a.date),3600)
        let window=DateInterval(start:a.date,end:b.date)
        let preview=CoverageMath.preview(entries:[a,b],samples:[],deletions:[],bundleID:"test",interval:window,includesHealth:false)
        XCTAssertEqual(preview.localEntries.map(\.id),[a.id])
    }
    func testFutureLabelAfterDateLineCrossingStillResolves() {
        let entry=food(date("2026-09-18T22:00:00Z"),zone:"Australia/Sydney")
        let la=cal("America/Los_Angeles"),label=EntryClock.displayDate(entry.clock!.dayKey,calendar:cal("America/Los_Angeles"))!
        XCTAssertEqual(DayReview.key(label,calendar:la),"2026-09-19")
        XCTAssertEqual(DayReview.key(entry.date,calendar:la),"2026-09-18")
        XCTAssertTrue(entry.isOnDiaryDay(label,calendar:la))
    }
    func testSeededTravelItinerariesRetainCaloriesAndEstimatorInvariance() {
        // 120 synthetic itineraries. Durations are deliberately paired to preserve
        // 28 elapsed days; meal evidence is not assumed to be evenly distributed.
        var seed:UInt64=0x7A_A18
        for _ in 0..<120 {
            seed=seed &* 6364136223846793005 &+ 1
            let short=Double(6+Int((seed >> 32)%31))
            var hours=Array(repeating:24.0,count:28);hours[10]=short;hours[11]=48-short
            let rate=Double(Int((seed >> 16)%9)-4)*0.01
            let (state,points,now)=history(durations:hours,rate:rate,alternating:true)
            let a=MaintenanceEngine.evaluate(state:state,points:points,now:now,calendar:cal("UTC"))
            let z=zones[Int(seed%UInt64(zones.count))]
            let b=MaintenanceEngine.evaluate(state:state,points:points,now:now,calendar:cal(z))
            XCTAssertEqual(a,b,z);XCTAssertEqual(a.averageIntake?.calories,2500)
            XCTAssertEqual(a.kgPerWeek ?? 0,rate*7,accuracy:1e-8)
            XCTAssertEqual(state.dayReviews.reduce(0){$0+$1.total.calories},70_000)
        }
    }
}
