import XCTest
#if !RECOMP_NATIVE_TESTS
@testable import RecompCore
#endif

final class ScaleTests: XCTestCase {
    var calendar: Calendar {
        var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "America/Los_Angeles")!; return c
    }
    var now: Date { ISO8601DateFormatter().date(from: "2026-09-18T12:00:00-07:00")! }
    var home: UUID { ScaleLocation.starters[0].id }
    var other: UUID { ScaleLocation.starters[1].id }
    func scenario(rate: Double = 0, offset: Double = 1.5, weekly: Bool = false) -> (state: AppState, points: [BodyPoint]) {
        var d = AdaptiveDemo.stable.data(now: now, calendar: calendar)
        for i in d.points.indices {
            let isOther = weekly ? (i / 7) % 2 == 1 : i % 2 == 1
            d.points[i].scaleLocationID = isOther ? other : home
            d.points[i].value = 85 + rate * Double(i) + (isOther ? offset : 0)
        }
        return d
    }
    func report(_ d: (state: AppState, points: [BodyPoint])) -> MaintenanceReport {
        MaintenanceEngine.evaluate(state: d.state, points: d.points, now: now, calendar: calendar)
    }
    func testStarterLocationsHaveNoInventedReadingsOrDefault() {
        let state = AppState()
        XCTAssertEqual(state.scaleLocations.map(\.name), ["Home", "Girlfriend’s"])
        XCTAssertTrue(state.measurements.isEmpty); XCTAssertNil(state.lastScaleLocationID)
        XCTAssertTrue(state.healthBodyScaleAssignments.isEmpty); XCTAssertTrue(state.isValid)
    }
    func testInvalidAndDuplicateLocationNamesRejected() {
        for name in ["", " ", " Home", "Home\nScale", String(repeating: "x", count: 61)] {
            XCTAssertFalse(ScaleLocation(name: name).isValid)
        }
        var state = AppState(); state.scaleLocations.append(ScaleLocation(name: "HOME"))
        XCTAssertFalse(state.isValid)
    }
    func testUnknownLocationReferencesRejected() {
        var state = AppState(); var m = BodyMeasurement(date: now, metric: .weight, value: 85)
        m.scaleLocationID = UUID(); state.measurements = [m]; XCTAssertFalse(state.isValid)
        state.measurements = []; state.lastScaleLocationID = UUID(); XCTAssertFalse(state.isValid)
        state.lastScaleLocationID = nil; state.maintenanceScaleLocationID = UUID(); XCTAssertFalse(state.isValid)
    }
    func testMalformedHealthAssignmentRejected() {
        var state = AppState(); state.healthBodyScaleAssignments["not-a-uuid"] = home; XCTAssertFalse(state.isValid)
        state.healthBodyScaleAssignments = [UUID().uuidString: UUID()]; XCTAssertFalse(state.isValid)
    }
    func testArchivedLocationKeepsHistoricalReferenceValid() {
        var state = AppState(); state.scaleLocations[0].archived = true
        var m = BodyMeasurement(date: now, metric: .weight, value: 85); m.scaleLocationID = home
        state.measurements = [m]; XCTAssertTrue(state.isValid)
        let p = BodyMath.merged(local: [m], health: [], deletions: [], ownBundleID: "app")
        XCTAssertEqual(ScaleMath.series(p, metric: .weight, locations: state.scaleLocations).first?.label, "Home")
    }
    func testRenameChangesLabelNotMeasurementOrIdentity() {
        var d = scenario(); let records = d.points
        d.state.scaleLocations[0].name = "Bedroom scale"
        XCTAssertEqual(d.points, records)
        XCTAssertTrue(report(d).scaleContext.contains("Bedroom scale"))
        XCTAssertEqual(report(d).estimate, 2500)
    }
    func testV12MigrationKeepsOldReadingsUntagged() throws {
        var state = AppState(); state.measurements = [BodyMeasurement(date: now, metric: .weight, value: 85)]
        state.measurements[0].version = 4; state.measurements[0].exportedVersion = 3
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(state)) as? [String: Any])
        json["schemaVersion"] = 2
        for key in ["scaleLocations", "lastScaleLocationID", "maintenanceScaleLocationID", "healthBodyScaleAssignments"] { json.removeValue(forKey: key) }
        let migrated = try JSONDecoder().decode(AppState.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(migrated.schemaVersion, 8); XCTAssertNil(migrated.measurements[0].scaleLocationID)
        XCTAssertEqual(migrated.measurements.map { var e = $0; e.clock = nil; return e }, state.measurements); XCTAssertEqual(migrated.targets, state.targets)
        XCTAssertEqual(migrated.scaleLocations, ScaleLocation.starters); XCTAssertTrue(migrated.isValid)
    }
    func testTaggedStateAndHealthOverridesRoundTrip() throws {
        var state = AppState(); var m = BodyMeasurement(date: now, metric: .bodyFat, value: 19); m.scaleLocationID = other
        state.measurements = [m]; state.lastScaleLocationID = other; state.maintenanceScaleLocationID = home
        state.healthBodyScaleAssignments[UUID().uuidString] = home
        let copy = try JSONDecoder().decode(AppState.self, from: JSONEncoder().encode(state))
        XCTAssertEqual(copy, state); XCTAssertTrue(copy.isValid)
    }
    func testImportedTagIsLocalAnnotationWithoutDuplicate() {
        let sample = HealthBodySample(id: UUID(), date: now, metric: .weight, value: 85, sourceName: "Scale app", sourceBundleID: "scale", localMeasurementID: nil)
        let points = BodyMath.merged(local: [], health: [sample], deletions: [], ownBundleID: "recomp", scaleAssignments: [sample.id.uuidString: other])
        XCTAssertEqual(points.count, 1); XCTAssertEqual(points[0].id, sample.id)
        XCTAssertFalse(points[0].isLocal); XCTAssertEqual(points[0].scaleLocationID, other)
        XCTAssertEqual(points[0].value, 85)
    }
    func testOwnHealthExportsStillDeduplicatedAfterTagging() {
        var m = BodyMeasurement(date: now, metric: .weight, value: 85); m.scaleLocationID = home
        let sample = HealthBodySample(id: UUID(), date: now, metric: .weight, value: 85, sourceName: "Recomp", sourceBundleID: "recomp", localMeasurementID: m.id)
        let points = BodyMath.merged(local: [m], health: [sample], deletions: [], ownBundleID: "recomp", scaleAssignments: [sample.id.uuidString: other])
        XCTAssertEqual(points.count, 1); XCTAssertEqual(points[0].scaleLocationID, home)
    }
    func testFiltersSeparateLocationsAndUntagged() {
        var p = scenario().points[0]
        XCTAssertTrue(ScaleFilter.all.includes(p)); XCTAssertTrue(ScaleFilter.location(home).includes(p))
        XCTAssertFalse(ScaleFilter.location(other).includes(p)); XCTAssertFalse(ScaleFilter.untagged.includes(p))
        p.scaleLocationID = nil; XCTAssertTrue(ScaleFilter.untagged.includes(p))
    }
    func testSameDayDifferentScalesNeverAveragedForChart() {
        let d = scenario(); var second = d.points[0]; second.id = UUID(); second.scaleLocationID = other; second.value = 95
        let series = ScaleMath.series([d.points[0], second], metric: .weight, locations: d.state.scaleLocations, calendar: calendar)
        XCTAssertEqual(series.count, 2); XCTAssertEqual(Set(series.map { $0.points[0].value }), Set([85.0, 95.0]))
    }
    func testSameScaleSameDayReadingsUseMedianOnce() {
        let d = scenario(); var second = d.points[0]; second.id = UUID(); second.value = 87
        let series = ScaleMath.series([d.points[0], second], metric: .weight, locations: d.state.scaleLocations, calendar: calendar)
        XCTAssertEqual(series.count, 1); XCTAssertEqual(series[0].points.count, 1); XCTAssertEqual(series[0].points[0].value, 86)
    }
    func testLocalPriorityIsPerScaleNotAcrossDifferentScales() {
        let d = scenario(); var p = d.points[0]; p.isLocal = false; p.scaleLocationID = other; p.value = 90
        let series = ScaleMath.series([d.points[0], p], metric: .weight, locations: d.state.scaleLocations, calendar: calendar)
        XCTAssertEqual(series.count, 2)
    }
    func testBodyFatDifferentMethodsRemainSeparate() {
        let d = scenario(); var a = d.points[0]; a.metric = .bodyFat; a.value = 19; a.method = "BIA"
        var b = a; b.id = UUID(); b.method = "DEXA"; b.value = 22
        XCTAssertEqual(ScaleMath.series([a, b], metric: .bodyFat, locations: d.state.scaleLocations).count, 2)
    }
    func testDailyAlternationWithFixedOffsetDoesNotInventWeightGain() throws {
        let r = report(scenario(offset: 2.4))
        XCTAssertEqual(try XCTUnwrap(r.estimate), 2500, accuracy: 0.01)
        XCTAssertEqual(try XCTUnwrap(r.kgPerWeek), 0, accuracy: 1e-8)
        XCTAssertEqual(r.weightDays, 29); XCTAssertNil(r.proposal)
        XCTAssertTrue(r.scaleContext.contains("2 scale/source"))
    }
    func testWeekLongVisitsWithFixedOffsetDoNotInventWeightGain() throws {
        let r = report(scenario(offset: 3, weekly: true))
        XCTAssertEqual(try XCTUnwrap(r.estimate), 2500, accuracy: 0.01)
        XCTAssertEqual(try XCTUnwrap(r.kgPerWeek), 0, accuracy: 1e-8); XCTAssertNil(r.proposal)
    }
    func testTrueLossTrendPreservedDespiteDifferentScaleBaselines() throws {
        let d = scenario(rate: -0.065, offset: 3, weekly: true)
        let r = report(d)
        XCTAssertEqual(try XCTUnwrap(r.kgPerWeek), -0.455, accuracy: 1e-8)
        XCTAssertEqual(try XCTUnwrap(r.estimate), 3000, accuracy: 25)
        XCTAssertEqual(r.proposal?.calories, 2650)
    }
    func testEstimateInvariantToConstantScaleOffsets() throws {
        for offset in [-5.0, -0.3, 0, 0.8, 8] {
            for weekly in [false, true] {
                let r = report(scenario(rate: 0.02, offset: offset, weekly: weekly))
                XCTAssertEqual(try XCTUnwrap(r.kgPerWeek), 0.14, accuracy: 1e-8)
                XCTAssertEqual(try XCTUnwrap(r.estimate), 2350, accuracy: 25)
            }
        }
    }
    func testSingleScaleSelectionNeverFallsBackToOtherLocation() {
        var d = scenario(); d.state.maintenanceScaleLocationID = home
        let r = report(d); XCTAssertEqual(r.estimate, 2500); XCTAssertEqual(r.weightDays, 15)
        d.points.removeAll { $0.scaleLocationID == home }
        XCTAssertNil(report(d).estimate)
    }
    func testSoleOneOffNewScaleCannotDistortMaintenance() {
        var d = scenario()
        for i in d.points.indices { d.points[i].scaleLocationID = home; d.points[i].value = 85 }
        d.points[28].scaleLocationID = other; d.points[28].value = 105
        let r = report(d)
        XCTAssertEqual(r.estimate, 2500); XCTAssertEqual(r.completedDays, 27); XCTAssertNil(r.proposal)
        XCTAssertTrue(r.scaleNotice.contains("need more same-scale history"))
    }
    func testUntaggedReadingsNotSilentlyPooledWithTaggedData() {
        var d = scenario()
        var untagged = d.points[28]; untagged.id = UUID(); untagged.scaleLocationID = nil; untagged.value = 105
        d.points.append(untagged)
        let r = report(d); XCTAssertEqual(r.estimate, 2500); XCTAssertTrue(r.scaleNotice.contains("1 untagged"))
    }
    func testLegacyUntaggedAnalysisHasExplicitAssumptionWarning() {
        let d = AdaptiveDemo.stable.data(now: now, calendar: calendar)
        let r = report(d); XCTAssertEqual(r.estimate, 2500); XCTAssertTrue(r.scaleNotice.contains("assumes one scale"))
    }
    func testDisconnectedShortScaleHistoriesCannotEstablishLongTrend() {
        var d = scenario()
        for i in d.points.indices { d.points[i].scaleLocationID = i < 14 ? home : other }
        let r = report(d); XCTAssertNil(r.estimate); XCTAssertTrue(r.message.contains("spanning 21 days"))
    }
    func testDifferentScaleTrendsSuppressTargetSuggestion() {
        var d = scenario()
        for i in d.points.indices where d.points[i].scaleLocationID == other { d.points[i].value += Double(i) * 0.10 }
        let r = report(d); XCTAssertNotNil(r.estimate); XCTAssertNil(r.proposal)
        XCTAssertEqual(r.recommendationTitle, "Check comparable scale history")
    }
    func testExcludedReadingsDoNotReappearInSameScaleChart() {
        var d = scenario(); d.points[0].excludedFromTrend = true
        let s = ScaleMath.series([d.points[0]], metric: .weight, locations: d.state.scaleLocations)
        XCTAssertTrue(s.isEmpty)
    }
    func testSameScaleBodyFatChangesDoNotDriveMaintenance() {
        var d = scenario(); let expected = report(d)
        var fat = d.points[28]; fat.id = UUID(); fat.metric = .bodyFat; fat.value = 35; d.points.append(fat)
        XCTAssertEqual(report(d), expected)
    }
    func testWaistDifferentLocationsNotComparedAsOneSeries() {
        var d = AdaptiveDemo.waist.data(now: now, calendar: calendar)
        for i in d.points.indices where d.points[i].metric == .waist { d.points[i].scaleLocationID = d.points[i].value == 90 ? home : other }
        XCTAssertNil(report(d).waistChangeCM)
    }
    func testReversedInputOrderDoesNotChangeReport() {
        let d = scenario(rate: -0.02, weekly: true)
        XCTAssertEqual(report(d), report((d.state, d.points.reversed())))
    }
    func testMeasurementCSVContainsEscapedLocationAndStableID() {
        var m = BodyMeasurement(date: now, metric: .weight, value: 85); m.scaleLocationID = home
        let csv = BodyCSV.make([m], locations: [ScaleLocation(id: home, name: "=Private, scale")])
        XCTAssertTrue(csv.contains("scale_location_id,scale_location")); XCTAssertTrue(csv.contains(home.uuidString))
        XCTAssertTrue(csv.contains("'=Private, scale"))
    }
    func testMultipleScalesSameDayOnlyCountAsOneWeighInDay() {
        var d = scenario()
        let additional = d.points.map { p -> BodyPoint in
            var p = p; p.id = UUID(); p.scaleLocationID = p.scaleLocationID == home ? other : home; p.value = 85
            return p
        }
        for i in d.points.indices { d.points[i].value = 85 }
        d.points += additional; XCTAssertEqual(report(d).weightDays, 29)
    }
    func testFitterWithOnlyOneReadingPerScaleReturnsNoFit() {
        let d = scenario(); let days = d.points.map { ScaleDay(date: $0.date, value: $0.value, seriesID: $0.id.uuidString) }
        XCTAssertNil(ScaleWeightFit.fit(days, calendar: calendar))
    }
}
