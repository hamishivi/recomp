import Foundation

@main struct StoreHarness {
    @MainActor static func main() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("recomp-harness-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("diary.json")
        let health = HealthKitService()
        let store = DiaryStore(fileURL: url, health: health)
        var checks = 0
        func check(_ condition: @autoclosure () -> Bool, _ name: String) {
            precondition(condition(), "FAILED: \(name)"); checks += 1; print("PASS: \(name)")
        }
        let now = Date()
        let meal = FoodEntry(name: "Example", date: now, meal: .lunch, nutrition: .startingTargets)
        check(store.saveEntry(meal, makeTemplate: false), "save food")
        check(store.confirmSelectedDay(excluded: false, note: "Reviewed"), "confirm day")
        check(store.selectedDayReview != nil, "confirmation persisted")
        var changed = meal; changed.nutrition.calories = 2600
        check(store.saveEntry(changed, makeTemplate: false), "edit food")
        check(store.selectedDayReview == nil, "food edit invalidates confirmation")
        let weight = BodyMeasurement(date: now, metric: .weight, value: 85)
        let bodyFat = BodyMeasurement(date: now, metric: .bodyFat, value: 19)
        let waist = BodyMeasurement(date: now, metric: .waist, value: 90)
        check(store.saveMeasurements([weight, bodyFat, waist]), "atomic multi-measurement save")
        check(store.bodyPoints.count == 3, "offline body points available")
        var invalid = weight; invalid.metric = .waist
        check(!store.saveMeasurements([invalid]), "reject metric mutation under existing ID")
        store.errorMessage = nil
        health.writableBodyMetrics = [.weight]
        await store.connectBodyHealth()
        check(store.state.bodyHealthEnabled && !store.state.healthEnabled, "body access independent of nutrition")
        check(store.state.measurements.first(where: { $0.id == weight.id })!.exportedVersion == 1, "successful receipt persisted")
        check(store.pendingBodyEntries == 2, "denied body metrics remain pending")
        var updated = weight; updated.value = 84.5
        check(store.saveMeasurements([updated]), "body edit saved")
        await store.synchronize()
        check(store.state.measurements.first(where: { $0.id == weight.id })!.version == 2, "version increments")
        // Drain any task scheduled by the save before making assertions about receipts.
        for _ in 0..<5 { await Task.yield() }
        await store.synchronize()
        check(store.state.measurements.first(where: { $0.id == weight.id })!.exportedVersion == 2, "new receipt after edit")
        store.removeMeasurement(weight.id)
        for _ in 0..<5 { await Task.yield() }
        await store.synchronize()
        check(!store.state.measurements.contains(where: { $0.id == weight.id }), "delete removes local weight")
        check(health.bodyRemovals.contains(where: { $0.id == weight.id }), "delete queues own Health cleanup")
        health.writableBodyMetrics = [.bodyFat, .waist]
        health.failBodyWrites = true
        await store.synchronize()
        check(store.pendingBodyEntries == 2, "failed writes stay pending")
        health.failBodyWrites = false
        await store.synchronize()
        check(store.pendingBodyEntries == 0, "retry succeeds without lost work")
        store.pauseBodyHealth()
        check(!store.state.bodyHealthEnabled && store.state.measurements.count == 2, "pause keeps local data")
        let reloaded = DiaryStore(fileURL: url, health: HealthKitService())
        check(reloaded.state.measurements == store.state.measurements, "restart retains measurements and receipts")
        check(!store.applyRecommendation(Nutrition(calories: 2000)), "cannot apply unsupported/stale proposal")
        // Scale/location update: actual coordinator with local persistence and mock reads.
        let scaleURL = directory.appendingPathComponent("scales.json")
        let scaleHealth = HealthKitService()
        let scales = DiaryStore(fileURL: scaleURL, health: scaleHealth)
        let homeID = scales.state.scaleLocations[0].id
        let otherID = scales.state.scaleLocations[1].id
        check(scales.state.lastScaleLocationID == nil, "no assumed scale on first launch")
        var taggedWeight = BodyMeasurement(date: now, metric: .weight, value: 85)
        taggedWeight.scaleLocationID = homeID
        var taggedFat = BodyMeasurement(date: now, metric: .bodyFat, value: 19)
        taggedFat.scaleLocationID = homeID
        check(scales.saveMeasurements([taggedWeight, taggedFat]), "save tagged multi-metric check-in")
        check(scales.state.lastScaleLocationID == homeID, "new check-in remembers scale")
        check(scales.bodyPoints.allSatisfy { $0.scaleLocationID == homeID }, "local chart points retain tags")
        taggedWeight.scaleLocationID = otherID
        check(scales.saveMeasurements([taggedWeight]), "retag existing weight")
        check(scales.state.measurements.count == 2 && scales.state.measurements.first { $0.id == taggedWeight.id }!.version == 2, "retag edits same measurement identity")
        check(scales.state.lastScaleLocationID == homeID, "editing history does not change next-check-in default")
        var renamed = scales.state.scaleLocations[0]; renamed.name = "My home scale"
        check(scales.saveScaleLocation(renamed), "rename location")
        check(scales.state.measurements.first { $0.id == taggedFat.id }!.scaleLocationID == homeID, "rename keeps historical references")
        check(scales.createScaleLocation(name: "MY HOME SCALE") == nil, "reject duplicate normalized label")
        scales.errorMessage = nil
        let customID = scales.createScaleLocation(name: " Gym ")!
        check(scales.state.scaleLocations.last?.name == "Gym", "trim new custom label")
        var gym = BodyMeasurement(date: now, metric: .weight, value: 85); gym.scaleLocationID = customID
        check(scales.saveMeasurements([gym]) && scales.state.lastScaleLocationID == customID, "custom label usable for new readings")
        var archive = scales.state.scaleLocations.last!; archive.archived = true
        check(scales.saveScaleLocation(archive), "archive scale")
        check(scales.state.lastScaleLocationID == nil && scales.state.measurements.contains { $0.scaleLocationID == customID }, "archive clears default but retains history")
        check(scales.setMaintenanceScale(homeID), "select reference-only maintenance mode")
        check(scales.state.maintenanceScaleLocationID == homeID, "maintenance selection persisted")
        check(!scales.setMaintenanceScale(UUID()), "unknown maintenance scale rejected")
        let scaleReload = DiaryStore(fileURL: scaleURL, health: HealthKitService())
        check(scaleReload.state.scaleLocations == scales.state.scaleLocations && scaleReload.state.measurements == scales.state.measurements, "tagged diary and archive survive restart")
        let imported = HealthBodySample(id: UUID(), date: now, metric: .weight, value: 85, sourceName: "Test scale", sourceBundleID: "test.scale", localMeasurementID: nil)
        scaleHealth.bodyReads = [imported]
        await scales.connectBodyHealth()
        let saveCount = scaleHealth.bodySaves.count
        check(scales.assignHealthScale(imported.id, locationID: otherID), "tag imported reading locally")
        check(scales.bodyPoints.first { $0.id == imported.id }?.scaleLocationID == otherID, "import label reaches chart model")
        check(scales.state.measurements.count == 3 && scaleHealth.bodySaves.count == saveCount, "import tagging neither copies nor exports third-party sample")
        let importReload = DiaryStore(fileURL: scaleURL, health: scaleHealth)
        await importReload.refreshHealth()
        check(importReload.bodyPoints.first { $0.id == imported.id }?.scaleLocationID == otherID, "import tag survives restart and reread")
        check(scales.assignHealthScale(imported.id, locationID: nil), "clear imported tag")
        check(scales.state.healthBodyScaleAssignments[imported.id.uuidString] == nil, "clearing tag removes annotation")
        check(!scales.assignHealthScale(UUID(), locationID: homeID), "cannot tag unknown Health sample")
        check(!scales.assignHealthScale(imported.id, locationID: UUID()), "cannot assign unknown location")
        // DXA records must remain outside scale samples, Health queues and adaptive targets.
        let bodyBefore = scales.bodyPoints
        let targetsBefore = scales.state.targets
        let maintenanceBefore = scales.maintenanceReport
        let historyBefore = scales.state.maintenanceHistory
        let healthSavesBefore = scaleHealth.bodySaves.count
        var scan = DXAScan(scanDay: DXAScan.day(now))
        scan.provider = "Synthetic clinic"; scan.comparisonGroup = "Synthetic scanner"; scan.reviewed = true
        scan.values = [DXAValue(metric: .bodyFat, region: "Total body", value: 19.2, unit: .percent),
                       DXAValue(metric: .totalMass, region: "Total body", value: 87, unit: .kg),
                       DXAValue(metric: .reportedRMR, region: "Whole person", value: 1900, unit: .kcalPerDay)]
        scan.sourceSHA256 = String(repeating: "a", count: 64)
        check(scales.saveDXAScan(scan), "save reviewed DXA scan")
        check(scales.state.dxaScans.count == 1, "scan stored separately")
        check(scales.bodyPoints == bodyBefore && scales.state.targets == targetsBefore, "DXA does not change scale points or targets")
        check(scales.maintenanceReport == maintenanceBefore && scales.state.maintenanceHistory == historyBefore, "DXA does not change learned maintenance or its history")
        check(scaleHealth.bodySaves.count == healthSavesBefore, "DXA does not enqueue or write Health samples")
        var duplicate = scan; duplicate.id = UUID()
        check(!scales.saveDXAScan(duplicate), "exact PDF fingerprint cannot create another scan")
        scan.values[0].value = 19.4
        check(scales.saveDXAScan(scan) && scales.state.dxaScans.count == 1, "edit same scan replaces rather than duplicates")
        let dxReload = DiaryStore(fileURL: scaleURL, health: scaleHealth)
        check(dxReload.state.dxaScans == scales.state.dxaScans, "DXA history survives restart")
        var unreviewed = scan; unreviewed.reviewed = false
        check(!scales.saveDXAScan(unreviewed), "unreviewed scan rejected")
        var futureScan = scan; futureScan.scanDay = DXAScan.day(now.addingTimeInterval(86400 * 2))
        check(!scales.saveDXAScan(futureScan), "future scan date rejected")
        check(scales.state.dxaScans[0].values[0].value == 19.4, "failed edits leave saved scan unchanged")
        let deletionsBefore = scales.state.bodyDeletions
        check(scales.removeDXAScan(scan.id) && scales.state.dxaScans.isEmpty, "delete DXA scan locally")
        check(scales.state.bodyDeletions == deletionsBefore && scaleHealth.bodySaves.count == healthSavesBefore, "DXA deletion leaves Health and scale queues untouched")
        let removedReload = DiaryStore(fileURL: scaleURL, health: scaleHealth)
        check(removedReload.state.dxaScans.isEmpty, "scan deletion persists")
        // 1.6: approved DXA exports use independent links; the native adapter is still mocked.
        func settle(_ target: DiaryStore) async {
            await target.synchronize()
            for _ in 0..<200 {
                await Task.yield()
                if !target.isSyncing { break }
            }
            await target.synchronize()
            for _ in 0..<200 { await Task.yield(); if !target.isSyncing { break } }
        }
        func fixture() -> DXAScan {
            var s = DXAScan(scanDay: DXAScan.day(now.addingTimeInterval(-86400 * 7)))
            s.provider = "Synthetic clinic"; s.reviewed = true
            s.values = [DXAValue(metric: .totalMass, region: "Total body", value: 85, unit: .kg),
                        DXAValue(metric: .bodyFat, region: "Total body", value: 20, unit: .percent),
                        DXAValue(metric: .leanSoftTissue, region: "Total body", value: 65, unit: .kg),
                        DXAValue(metric: .boneMineralContent, region: "Total body", value: 3000, unit: .g)]
            return s
        }
        func approve(_ target: DiaryStore, _ scan: DXAScan, metrics: Set<DXAHealthMetric>) -> Bool {
            target.configureDXAHealth(reviewedScan: scan, metrics: metrics,
                date: DXAHealthTime.date(day: scan.scanDay, timeZoneID: "America/Los_Angeles")!,
                timeZoneID: "America/Los_Angeles", timeIsApproximate: true)
        }
        let dxaURL = directory.appendingPathComponent("dxa-health.json")
        let dh = HealthKitService(); dh.writableDXAMetrics = [.weight]
        let ds = DiaryStore(fileURL: dxaURL, health: dh)
        var full = fixture()
        check(ds.saveDXAScan(full), "new DXA fixture persists without sharing")
        await ds.connectDXAHealth()
        check(ds.state.dxaHealthEnabled && !ds.state.healthEnabled && !ds.state.bodyHealthEnabled, "DXA connection independent of nutrition/body flags")
        check(dh.dxaSaves.isEmpty && ds.state.dxaHealthLinks.isEmpty, "connecting does not auto-export existing scans")
        check(approve(ds, full, metrics: Set(DXAHealthMetric.allCases)), "explicitly approve compatible scan summary")
        await settle(ds)
        check(dh.dxaSaves.count == 1 && ds.pendingDXAMetrics == 2, "partial write permission retains denied fields as pending")
        check(ds.dxaHealthLink(full.id)?.attemptedMetrics == [.weight], "denied unattempted fields are not marked as written")
        check(dh.bodySaves.isEmpty && ds.state.measurements.isEmpty && ds.bodyPoints.isEmpty, "DXA export never creates scale measurement or scale Health write")
        let other = fixture(); check(ds.saveDXAScan(other), "new scan while connection on is still local")
        await settle(ds); check(dh.dxaSaves.count == 1, "new scan requires its own sharing approval")
        dh.writableDXAMetrics = Set(DXAHealthMetric.allCases); await settle(ds)
        check(dh.dxaSaves.count == 3 && ds.pendingDXAMetrics == 0, "grant remaining permissions completes individual receipts")
        check(dh.dxaSaves.first(where: { $0.candidate.metric == .leanBodyMass })?.candidate.value == 68, "coordinator exports fat-free equivalent rather than soft tissue alone")
        await settle(ds); check(dh.dxaSaves.count == 3, "repeated sync does not repeat completed writes")
        let oldReview = full
        full.notes = "An unrelated local note"; check(ds.saveDXAScan(full), "edit local-only DXA notes")
        await settle(ds); check(dh.dxaSaves.count == 3, "notes/PDF metadata are not exported or trigger replacement")
        check(!approve(ds, oldReview, metrics: [.weight]), "stale sharing-review snapshot rejected")
        ds.errorMessage = nil
        full.values[0].value = 84.9; check(ds.saveDXAScan(full), "change shared scan weight")
        await settle(ds)
        check(dh.dxaSaves.last(where: { $0.candidate.metric == .weight })?.candidate.value == 84.9, "changed weight is exported")
        check(dh.dxaSaves.allSatisfy { $0.id == full.id }, "all revisions retain original scan identity")
        let linkAfterEdit = ds.dxaHealthLink(full.id)!
        check(linkAfterEdit.completedVersions.values.allSatisfy { $0 == linkAfterEdit.version }, "edit receipts all advance to current version")
        full.values.removeAll { $0.metric == .bodyFat }; check(ds.saveDXAScan(full), "remove shared field from report")
        await settle(ds)
        check(dh.dxaRemovals.contains { $0.id == full.id && $0.metric == .bodyFat }, "removed field cleans up its old Health sample")
        check(ds.pendingDXAMetrics == 0 && ds.dxaHealthLink(full.id)!.selectedMetrics.contains(.bodyFat), "selection retained but missing value no longer exports")
        full.values.append(DXAValue(metric: .bodyFat, region: "Whole body", value: 19.8, unit: .percent))
        check(ds.saveDXAScan(full), "restore explicitly selected report field")
        await settle(ds)
        check(dh.dxaSaves.last(where: { $0.candidate.metric == .bodyFat })?.candidate.value == 19.8, "restored compatible field is republished with newer version")
        dh.bodyReads = [HealthBodySample(id: UUID(), date: now, metric: .weight, value: 84.9,
            sourceName: "Recomp", sourceBundleID: dh.ownBundleID, localMeasurementID: nil, isRecompDXA: true)]
        await ds.connectBodyHealth()
        check(ds.healthBodySamples.isEmpty && ds.bodyPoints.isEmpty, "own exported scan weights are excluded on Health refresh")
        ds.pauseDXAHealth()
        check(ds.state.bodyHealthEnabled && !ds.state.dxaHealthEnabled, "pausing DXA leaves regular body integration enabled")
        let removalsBefore = dh.dxaRemovals.count
        check(ds.removeDXAScan(full.id), "delete shared scan while DXA sync paused")
        await settle(ds)
        check(ds.pendingDXAMetrics == 3 && dh.dxaRemovals.count == removalsBefore, "paused deletion queue is durable and does not call Health")
        let restartHealth = HealthKitService()
        let restartedDXA = DiaryStore(fileURL: dxaURL, health: restartHealth)
        check(restartedDXA.pendingDXAMetrics == 3, "deleted-scan cleanup survives process restart")
        await restartedDXA.connectDXAHealth()
        check(restartedDXA.pendingDXAMetrics == 3 && restartHealth.dxaRemovals.isEmpty, "denied removals stay pending")
        restartHealth.writableDXAMetrics = Set(DXAHealthMetric.allCases)
        restartHealth.failDXARemovals = true; await settle(restartedDXA)
        check(restartedDXA.pendingDXAMetrics == 3 && !restartedDXA.syncMessage.isEmpty, "removal failure reported and retriable")
        restartHealth.failDXARemovals = false; await settle(restartedDXA)
        check(restartedDXA.pendingDXAMetrics == 0 && restartHealth.dxaRemovals.count == 3, "reconnect cleans up each attempted metric")
        check(restartHealth.dxaRemovals.allSatisfy { $0.id == full.id }, "cleanup scoped to deleted scan identity")
        check(restartedDXA.state.bodyDeletions.isEmpty && restartedDXA.state.dxaScans.contains { $0.id == other.id }, "DEXA cleanup preserves regular queues and other scan")

        let failureURL = directory.appendingPathComponent("dxa-failure.json")
        let fh = HealthKitService(); fh.writableDXAMetrics = Set(DXAHealthMetric.allCases); fh.failDXAWrites = true
        let fs = DiaryStore(fileURL: failureURL, health: fh); let failing = fixture()
        check(fs.saveDXAScan(failing), "failure fixture saved")
        check(approve(fs, failing, metrics: Set(DXAHealthMetric.allCases)), "approval saved while disconnected")
        check(fh.dxaSaves.isEmpty && !fs.state.dxaHealthEnabled, "approval alone while disconnected performs no writes")
        await fs.connectDXAHealth(); await settle(fs)
        check(fs.pendingDXAMetrics == 3 && fs.dxaHealthLink(failing.id)!.attemptedMetrics.count == 3, "failed write attempts persist before API completion")
        let recoveredHealth = HealthKitService(); recoveredHealth.writableDXAMetrics = Set(DXAHealthMetric.allCases)
        let recovered = DiaryStore(fileURL: failureURL, health: recoveredHealth)
        var sawPersistedMarker = false
        recoveredHealth.beforeDXASave = { id, metric in
            let disk = try! StateFile(url: failureURL).load()
            sawPersistedMarker = disk.dxaHealthLinks.first { $0.id == id }!.attemptedMetrics.contains(metric)
        }
        await settle(recovered)
        check(sawPersistedMarker && recovered.pendingDXAMetrics == 0, "retry after restart has durable attempt marker and completes")
        check(recovered.removeDXAHealthExports(failing.id), "request Health-only removal")
        await settle(recovered)
        check(recovered.state.dxaScans.contains { $0.id == failing.id } && recovered.pendingDXAMetrics == 0, "removing exports keeps report in Recomp")
        let previousVersion = recovered.dxaHealthLink(failing.id)!.version
        check(approve(recovered, failing, metrics: [.weight]), "re-enable one type after explicit removal")
        await settle(recovered)
        check(recovered.dxaHealthLink(failing.id)!.version > previousVersion, "re-sharing advances version instead of reusing retired value")
        recovered.pauseHealth(); check(!recovered.state.dxaHealthEnabled, "global pause also pauses DEXA")

        let raceH = HealthKitService(); raceH.writableDXAMetrics = Set(DXAHealthMetric.allCases)
        let race = DiaryStore(fileURL: directory.appendingPathComponent("dxa-race.json"), health: raceH)
        let racing = fixture(); check(race.saveDXAScan(racing), "race fixture saved")
        await race.connectDXAHealth()
        raceH.beforeDXASave = { id, _ in _ = race.removeDXAScan(id) }
        check(approve(race, racing, metrics: Set(DXAHealthMetric.allCases)), "approve scan to test delete-during-write")
        await settle(race)
        check(race.state.dxaScans.isEmpty && race.pendingDXAMetrics == 0, "in-flight deletion is reconciled")
        check(raceH.dxaSaves.count == 1 && raceH.dxaRemovals.count == 1, "no further stale writes after concurrent scan deletion")

        let pauseH = HealthKitService(); pauseH.writableDXAMetrics = Set(DXAHealthMetric.allCases)
        let pause = DiaryStore(fileURL: directory.appendingPathComponent("dxa-pause.json"), health: pauseH)
        let pausedScan = fixture(); check(pause.saveDXAScan(pausedScan), "pause fixture saved")
        await pause.connectDXAHealth()
        pauseH.beforeDXASave = { _, _ in pause.pauseDXAHealth() }
        check(approve(pause, pausedScan, metrics: Set(DXAHealthMetric.allCases)), "approve scan to test pause-during-write")
        await settle(pause)
        check(pauseH.dxaSaves.count == 1 && pause.pendingDXAMetrics == 2, "pause permits in-flight completion but stops new writes")
        await pause.connectDXAHealth(); await settle(pause)
        check(pause.pendingDXAMetrics == 0 && pauseH.dxaSaves.count == 3, "resume completes remaining fields without repeating receipt")

        let editH = HealthKitService(); editH.writableDXAMetrics = Set(DXAHealthMetric.allCases)
        let edit = DiaryStore(fileURL: directory.appendingPathComponent("dxa-edit-race.json"), health: editH)
        var editingScan = fixture(); check(edit.saveDXAScan(editingScan), "edit race fixture saved")
        await edit.connectDXAHealth()
        editH.beforeDXASave = { _, _ in editingScan.values[0].value = 84; _ = edit.saveDXAScan(editingScan) }
        check(approve(edit, editingScan, metrics: Set(DXAHealthMetric.allCases)), "approve scan to test edit-during-write")
        await settle(edit)
        check(edit.pendingDXAMetrics == 0 && editH.dxaSaves.last(where: { $0.candidate.metric == .weight })?.candidate.value == 84, "concurrent edit finishes with latest value")
        check(edit.dxaHealthLink(editingScan.id)!.completedVersions.values.allSatisfy { $0 == edit.dxaHealthLink(editingScan.id)!.version }, "stale completions never mark newer version complete")
        let authH = HealthKitService(); authH.failDXAAccess = true
        let auth = DiaryStore(fileURL: directory.appendingPathComponent("dxa-auth-fail.json"), health: authH)
        let authScan = fixture(); check(auth.saveDXAScan(authScan) && approve(auth, authScan, metrics: [.weight]), "save choices before failed authorization")
        await auth.connectDXAHealth()
        check(!auth.state.dxaHealthEnabled && auth.pendingDXAMetrics == 1 && authH.dxaSaves.isEmpty, "authorization error retains approved choice without false export")
        checks += try await checkFeature17(directory: directory)
        print("\(checks) coordinator checks passed. Mocked adapter only; no native HealthKit or SwiftUI build.")
    }
    @MainActor static func checkFeature17(directory: URL) async throws -> Int {
        var checks = 0
        func check(_ condition: @autoclosure () -> Bool, _ name: String) {
            precondition(condition(), "FAILED: \(name)"); checks += 1; print("PASS: \(name)")
        }
        let now = Date()
        let meal = FoodEntry(name: "Synthetic backup meal", date: now, meal: .lunch, nutrition: .startingTargets)
        func settle(_ target: DiaryStore) async {
            await target.synchronize()
            for _ in 0..<200 {
                await Task.yield()
                if !target.isSyncing { break }
            }
            await target.synchronize()
            for _ in 0..<200 { await Task.yield(); if !target.isSyncing { break } }
        }
        func fixture() -> DXAScan {
            var s = DXAScan(scanDay: DXAScan.day(now.addingTimeInterval(-86400 * 7)))
            s.provider = "Synthetic clinic"; s.reviewed = true
            s.values = [DXAValue(metric: .totalMass, region: "Total body", value: 85, unit: .kg),
                        DXAValue(metric: .bodyFat, region: "Total body", value: 20, unit: .percent),
                        DXAValue(metric: .leanSoftTissue, region: "Total body", value: 65, unit: .kg),
                        DXAValue(metric: .boneMineralContent, region: "Total body", value: 3000, unit: .g)]
            return s
        }
        // Version 1.7: empty-only restoration is local and preserves sync identity.
        var backupState = AppState()
        var backedMeal = meal
        backedMeal.version = 9; backedMeal.exportedVersions = ["calories":9, "protein":9, "carbs":9, "fat":9]
        backedMeal.photos = [MealPhoto(jpeg: Data([0xff,0xd8,0x01,0xff,0xd9]), role: .plate)]
        backupState.entries = [backedMeal]
        var backedWeight = BodyMeasurement(date: now, metric: .weight, value: 85)
        backedWeight.version = 3; backedWeight.exportedVersion = 3
        backupState.measurements = [backedWeight]
        let backedScan = fixture(); backupState.dxaScans = [backedScan]
        var backedLink = DXAHealthLink(id: backedScan.id, selectedMetrics: [.weight], date: DXAHealthTime.date(day: backedScan.scanDay, timeZoneID: TimeZone.current.identifier)!, timeZoneID: TimeZone.current.identifier)
        backedLink.version = 4; backedLink.completedVersions = ["weight":4]; backedLink.attemptedMetrics = [.weight]
        backupState.dxaHealthLinks = [backedLink]
        backupState.healthEnabled = true; backupState.bodyHealthEnabled = true; backupState.dxaHealthEnabled = true
        backupState.activityPreferences.enabled = true; backupState.widgetPreferences.showNumbers = true
        let backup = BackupPayload(createdAt: now, bundleID: "com.example.recomp", appearance: "system", state: backupState)
        let restoreURL = directory.appendingPathComponent("restore.json")
        let rh = HealthKitService(); rh.writableNutrients = Set(Nutrient.allCases); rh.writableBodyMetrics = Set(BodyMetric.allCases); rh.writableDXAMetrics = Set(DXAHealthMetric.allCases)
        let rs = DiaryStore(fileURL: restoreURL, health: rh)
        var commitCount = 0; rs.didCommit = { _ in commitCount += 1 }
        check(rs.restoreBackup(backup), "backup restores into empty diary")
        check(commitCount == 1, "restore emits one committed state for widget refresh")
        check(rs.state.entries == backupState.entries && rs.state.measurements == backupState.measurements, "restored photos and measurement/meal identities preserved")
        check(rs.state.dxaScans == backupState.dxaScans && rs.state.dxaHealthLinks == backupState.dxaHealthLinks, "DEXA sharing selections and receipts preserved")
        check(!rs.state.healthEnabled && !rs.state.bodyHealthEnabled && !rs.state.dxaHealthEnabled && !rs.state.activityPreferences.enabled && !rs.state.widgetPreferences.showNumbers, "all restored connections and widget numbers paused")
        await settle(rs)
        check(rh.foodSaves.isEmpty && rh.bodySaves.isEmpty && rh.dxaSaves.isEmpty && rh.foodRemovals.isEmpty && rh.bodyRemovals.isEmpty && rh.dxaRemovals.isEmpty, "restoring does not write or remove anything in Health")
        let diskBackup = try StateFile(url: restoreURL).load()
        check(diskBackup == rs.state, "restoration persisted atomically")
        check(!rs.restoreBackup(backup), "repeated restore cannot merge or overwrite")
        await rs.connectHealth(); await rs.connectBodyHealth(); await rs.connectDXAHealth(); await settle(rs)
        check(rh.foodSaves.isEmpty && rh.bodySaves.isEmpty && rh.dxaSaves.isEmpty, "reconnect does not replay versions already receipted")
        let otherH = HealthKitService(); otherH.ownBundleID = "different.app"
        let other = DiaryStore(fileURL: directory.appendingPathComponent("different-restore.json"), health: otherH)
        check(!other.restoreBackup(backup) && other.state.entries.isEmpty, "different bundle restore rejected without state mutation")
        let context = ContextEvent(start: now, end: now, kind: .travel, note: "Synthetic")
        let beforeTargets = rs.state.targets
        check(rs.saveContext(context), "context annotation saved")
        var editedContext = context; editedContext.note = "Updated"
        check(rs.saveContext(editedContext) && rs.state.contextEvents.count == 1, "context edit retains identity")
        rs.removeContext(context.id)
        check(rs.state.contextEvents.isEmpty && rs.state.targets == beforeTargets, "context removal never changes targets")
        var pref = ActivityPreferences(); pref.enabled = true; pref.hiddenWorkoutIDs = [UUID()]
        rs.setActivityPreferences(pref); rs.setWidgetNumbers(true)
        check(rs.state.activityPreferences == pref && rs.state.widgetPreferences.showNumbers, "activity and widget preferences persist")
        let rerun = DiaryStore(fileURL: restoreURL, health: HealthKitService())
        check(rerun.state.activityPreferences == pref && rerun.state.widgetPreferences.showNumbers, "new preferences survive restart")
        return checks
    }

}
