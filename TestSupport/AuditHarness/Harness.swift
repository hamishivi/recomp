import Foundation

@main struct AuditHarness {
    @MainActor static func main() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("recomp-audit-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        var checks = 0, failures = 0
        func check(_ condition: @autoclosure () -> Bool, _ name: String) {
            checks += 1
            if condition() { print("PASS: \(name)") } else { failures += 1; print("FAIL: \(name)") }
        }
        func makeStore(_ name: String, health: HealthKitService) -> DiaryStore {
            DiaryStore(fileURL: directory.appendingPathComponent(name + ".json"), health: health)
        }
        let now = Date()
        // Work arriving during the final async read MUST be drained before sync completes.
        let h = HealthKitService(); h.writableNutrients = Set(Nutrient.allCases)
        let store = makeStore("sync-tail", health: h)
        await store.connectHealth()
        let meal = FoodEntry(name: "Synthetic late save", date: now, meal: .lunch, nutrition: Nutrition(calories: 500, protein: 30, carbs: 50, fat: 20))
        h.beforeNutritionRead = { _ in
            check(store.saveEntry(meal, makeTemplate: false), "save during final Health read commits")
            await store.synchronize() // equivalent to the save's queued sync arriving now
        }
        await store.synchronize()
        check(store.state.entries.first?.exportCount == 4, "sync drains edits arriving during its final read")

        // The UI changes the selected date synchronously; an old response must not attach to it.
        let rh = HealthKitService(); let reader = makeStore("read-switch", health: rh)
        await reader.connectHealth()
        let beforeDay = reader.selectedDay
        let otherDay = Calendar.current.date(byAdding: .day, value: -1, to: beforeDay)!
        rh.nutritionReads = [HealthNutritionSample(id: UUID(), date: beforeDay, nutrient: .calories, value: 100,
            sourceName: "Synthetic", sourceBundleID: "test.other", localEntryID: nil)]
        rh.beforeBodyRead = {
            reader.selectDay(otherDay)
        }
        await reader.refreshHealth()
        check(reader.healthSamples.isEmpty, "old-day response never installs after selecting another date")
        check(reader.lastRefreshed == nil, "old-day response cannot certify the new day refreshed")
        for _ in 0..<10 { await Task.yield() }

        // A future record is not consumed food and must not become an export.
        let future = FoodEntry(name: "Not eaten", date: now.addingTimeInterval(86400), meal: .dinner, nutrition: Nutrition(calories: 200))
        let fh = HealthKitService(); let food = makeStore("future", health: fh)
        check(!food.saveEntry(future, makeTemplate: false), "reject future food rather than silently logging a plan")
        check(food.state.entries.isEmpty && fh.foodSaves.isEmpty, "rejected future food has no persistence or Health effects")

        // Aggregate correction with retained photos used to reopen as a blank/new AI estimate.
        let jpeg = Data([0xff,0xd8,0x01,0xff,0xd9])
        var original = FoodEntry(name: "Corrected label", date: now, meal: .lunch,
            nutrition: Nutrition(calories: 310, protein: 25, carbs: 30, fat: 10), isEstimate: false)
        original.photos = [MealPhoto(jpeg: jpeg, role: .nutritionLabel)]
        let model = MealEstimatorModel(date: now, original: original)
        check(model.draft?.estimate.total == original.nutrition, "reopening photos preserves corrected aggregate nutrition")
        check(model.draft?.lockedItemIDs.isEmpty == false, "aggregate correction is protected from AI replacement")
        check(!model.hasChanges, "opening an unchanged corrected meal does not claim edits")

        // Stored item evidence must not point at a different photo after replacement/refinement.
        let evidence = FoodEvidence(kind: .label, photoNumber: 1, detail: "old label, 310 kcal")
        let item = EstimatedFood(id: "old", name: "Old label food", portion: "1 serving", nutrition: original.nutrition, evidence: [evidence])
        original.aiDraft = EstimateDraft(estimate: MealEstimate(title: original.name, items: [item]), lockedItemIDs: [item.id])
        let revised = MealEstimatorModel(date: now, original: original)
        revised.photos = [MealPhoto(jpeg: jpeg, role: .plate, caption: "replacement image")]
        EstimationService.response = MealEstimate(title: original.name, items: [item])
        revised.begin(configuration: EstimatorConfiguration())
        for _ in 0..<1000 { if !revised.busy { break }; await Task.yield() }
        check(revised.draft?.estimate.items.first?.evidence?.first?.photoNumber == nil,
            "locked evidence cannot be relabelled as a replacement photo")

        // Photo-only refinements append a generated clarification; preflight must count it.
        var nearLimit = original
        nearLimit.aiDraft?.context = String(repeating: "a", count: 7950)
        let limited = MealEstimatorModel(date: now, original: nearLimit)
        limited.photos = [MealPhoto(jpeg: jpeg, role: .plate)]
        check(!limited.canRequest, "photo-only refinement reserves space for its generated clarification")

        // Real filesystem failure, not an injected save success/failure boolean.
        let diskHealth = HealthKitService()
        let diskURL = directory.appendingPathComponent("disk-failure.json")
        let disk = DiaryStore(fileURL: diskURL, health: diskHealth)
        await disk.connectHealth()
        diskHealth.nutritionReads = [HealthNutritionSample(id: UUID(), date: disk.selectedDay, nutrient: .calories, value: 123,
            sourceName: "Synthetic", sourceBundleID: "test.other", localEntryID: nil)]
        await disk.refreshHealth()
        let diskBefore = disk.state
        let savedBytes = try Data(contentsOf: diskURL)
        try FileManager.default.removeItem(at: diskURL)
        try FileManager.default.createDirectory(at: diskURL, withIntermediateDirectories: false)
        var publications = 0
        disk.didCommit = { _ in publications += 1 }
        check(!disk.saveEntry(meal, makeTemplate: false), "a real filesystem write failure rejects the save")
        check(disk.state == diskBefore && publications == 0, "failed persistence changes neither memory nor widget publication")
        disk.pauseHealth()
        check(disk.state.healthEnabled && disk.healthSamples.count == 1, "failed pause does not clear data while Health remains enabled")
        try FileManager.default.removeItem(at: diskURL)
        try savedBytes.write(to: diskURL)
        let restarted = DiaryStore(fileURL: diskURL, health: HealthKitService())
        check(restarted.state == diskBefore, "restart reads original committed state after a failed save")
        check(disk.saveEntry(meal, makeTemplate: false), "logging recovers when filesystem access returns")
        check(publications == 1, "only the successful commit publishes a new widget snapshot")

        let storage = makeStore("storage-switch", health: HealthKitService())
        check(storage.saveEntry(meal, makeTemplate: false), "storage fixture saves")
        let originalStorageState = storage.state
        let originalPreference = UserDefaults.standard.object(forKey: "recomp_storage_mode")
        defer { UserDefaults.standard.set(originalPreference, forKey: "recomp_storage_mode") }
        let corruptTarget = directory.appendingPathComponent("corrupt-destination.json")
        try Data("invalid JSON".utf8).write(to: corruptTarget)
        check(!storage.switchToStorage(useICloud: true, destination: corruptTarget), "corrupt destination rejects storage switch")
        check(storage.state == originalStorageState && storage.loadFailure == nil, "failed storage switch preserves usable active diary")
        check(UserDefaults.standard.string(forKey: "recomp_storage_mode") == originalPreference as? String, "failed storage switch preserves preference")
        check(storage.saveEntry(FoodEntry(name: "Still writable", date: now, meal: .snack, nutrition: Nutrition(calories: 50)), makeTemplate: false), "original storage remains writable")
        let validTarget = directory.appendingPathComponent("valid-destination.json")
        check(storage.switchToStorage(useICloud: false, destination: validTarget), "valid storage switch succeeds")
        let destinationState = try StateFile(url: validTarget).load()
        check(destinationState == storage.state, "new destination contains validated diary")

        let fast = makeStore("fast-reload", health: HealthKitService())
        check(fast.saveEntry(meal, makeTemplate: false), "rapid reload fixture saves")
        let previousModification = fast.lastLoadedModificationDate!
        var external = fast.state
        external.entries[0].nutrition.calories += 25
        let fastURL = directory.appendingPathComponent("fast-reload.json")
        try StateFile(url: fastURL).save(external)
        try FileManager.default.setAttributes([.modificationDate: previousModification.addingTimeInterval(0.5)], ofItemAtPath: fastURL.path)
        fast.checkForExternalSync()
        check(fast.state == external, "external writes within one second are reloaded")

        // A partial historical log must never be certified as a complete day.
        let partial = makeStore("partial-history", health: HealthKitService())
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: now)!
        let snack = FoodEntry(name: "Only a snack", date: yesterday, meal: .snack, nutrition: Nutrition(calories: 200))
        check(partial.saveEntry(snack, makeTemplate: false), "partial historical food saves")
        partial.rememberMaintenance()
        check(partial.state.dayReviews.isEmpty, "partial past food is not automatically confirmed")

        // Editing confirmed intake must invalidate today's cached maintenance estimate
        // even when Health is disabled (and consequently no sync will refresh it).
        let fixture = AdaptiveDemo.stable.data()
        var synthetic = fixture.state
        synthetic.measurements = fixture.points.map { BodyMeasurement(id: $0.id, date: $0.date, metric: $0.metric,
            value: $0.value, method: $0.method) }
        let middle = Calendar.current.date(byAdding: .day, value: -14, to: Calendar.current.startOfDay(for: now))!
        var correction = FoodEntry(name: "Synthetic confirmed food", date: middle, meal: .lunch, nutrition: .startingTargets)
        synthetic.entries = [correction]
        let historyURL = directory.appendingPathComponent("history-invalidation.json")
        try StateFile(url: historyURL).save(synthetic)
        let historyStore = DiaryStore(fileURL: historyURL, health: HealthKitService())
        historyStore.rememberMaintenance()
        check(historyStore.state.dayReviews == synthetic.dayReviews, "reviewed snapshots survive missing local food without being rewritten")
        check(historyStore.state.maintenanceHistory.count == 1, "synthetic complete intake produces today's audit snapshot")
        correction.nutrition.calories += 100
        check(historyStore.saveEntry(correction, makeTemplate: false), "correction to confirmed past food is saved")
        check(historyStore.maintenanceReport.estimate == nil && historyStore.state.maintenanceHistory.isEmpty,
            "food correction removes now-invalid cached maintenance without requiring Health sync")

        let deletionHealth = HealthKitService(); deletionHealth.writableNutrients = Set(Nutrient.allCases)
        let deletionStore = makeStore("durable-delete", health: deletionHealth)
        await deletionStore.connectHealth()
        check(deletionStore.saveEntry(meal, makeTemplate: false), "durable deletion fixture saves")
        await deletionStore.synchronize()
        let staleReplica = deletionStore.state
        deletionStore.removeEntry(meal.id)
        await deletionStore.synchronize()
        check(deletionStore.state.deletions.isEmpty, "successful Health cleanup drains transient queue")
        check(deletionStore.state.deletedIDs("food").contains(meal.id), "Health cleanup preserves deletion identity")
        check(deletionStore.mergeExternalState(staleReplica), "stale replica merges after cleanup")
        check(deletionStore.state.entries.isEmpty, "completed deletion cannot resurrect from stale replica")
        deletionHealth.nutritionReads = [HealthNutritionSample(id: UUID(), date: meal.date, nutrient: .calories, value: 500,
            sourceName: "Recomp", sourceBundleID: deletionHealth.ownBundleID, localEntryID: meal.id)]
        await deletionStore.refreshHealth()
        check(deletionStore.total.calories == 0, "stale own Health sample stays hidden after queue cleanup")

        print("AUDIT: \(checks) checks, \(failures) failures")
        if failures > 0 { exit(1) }
    }
}
