import Foundation

@main struct Audit2Harness {
    @MainActor static func main() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("recomp-audit2-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        var checks = 0, failures = 0
        func check(_ value: @autoclosure () -> Bool, _ name: String) {
            checks += 1
            if value() { print("PASS: \(name)") } else { failures += 1; print("FAIL: \(name)") }
        }
        // Weight-derived maintenance must not remain in today's audit history after its
        // only weight source is removed by pausing Health. Older snapshots stay historical.
        let fixture = AdaptiveDemo.stable.data()
        var state = fixture.state
        state.healthEnabled = true
        state.activityPreferences.enabled = true
        let file = StateFile(url: root.appendingPathComponent("pause.json")); try file.save(state)
        let health = HealthKitService()
        health.bodyReads = fixture.points.map { HealthBodySample(id: $0.id, date: $0.date, metric: $0.metric,
            value: $0.value, sourceName: "Synthetic scale", sourceBundleID: "test.scale", localMeasurementID: nil) }
        let diary = DiaryStore(fileURL: file.url, health: health)
        await diary.refreshHealth()
        check(diary.maintenanceReport.estimate != nil && !diary.state.maintenanceHistory.isEmpty, "imported weights establish a synthetic maintenance snapshot")
        diary.pauseHealth()
        check(!diary.state.activityPreferences.enabled, "general Pause Health integration also pauses activity reads")
        check(diary.bodyPoints.isEmpty && diary.maintenanceReport.estimate == nil, "pause removes imported weights from current analysis")
        check(diary.state.maintenanceHistory.isEmpty, "pause also removes now-invalid current maintenance snapshot")

        // Save/reopen without recalculation must not silently relabel verified label totals.
        let original = FoodEntry(name: "Verified label", date: Date(), meal: .lunch,
            nutrition: Nutrition(calories: 250, protein: 25, carbs: 20, fat: 7), isEstimate: false)
        let model = MealEstimatorModel(date: original.date, original: original)
        check(model.entry()?.isEstimate == false, "unchanged verified meal stays verified when reopening its breakdown")

        // Connect/permission completion must fail closed on a real disk-write failure.
        let activityFile = StateFile(url: root.appendingPathComponent("activity.json"))
        try activityFile.save(AppState())
        let activityStore = DiaryStore(fileURL: activityFile.url, health: HealthKitService())
        try FileManager.default.removeItem(at: activityFile.url)
        try FileManager.default.createDirectory(at: activityFile.url, withIntermediateDirectories: false)
        let reader = ActivityHealthService(), activity = ActivityModel(health: reader)
        await activity.connect(using: activityStore)
        check(reader.requests == 1, "activity requests system access through its adapter")
        check(!activityStore.state.activityPreferences.enabled && reader.reads == 0, "failed settings write never starts activity reads")
        check(activity.error != nil && !activity.authorizing, "failed connect exposes an error and leaves no stuck authorization state")
        try FileManager.default.removeItem(at: activityFile.url)
        await activity.connect(using: activityStore)
        check(activityStore.state.activityPreferences.enabled && reader.reads == 1, "successful persisted opt-in starts activity reads")
        check(activity.error == nil, "successful retry clears the previous activity connection error")
        let persistedActivity = try activityFile.load()
        check(persistedActivity.activityPreferences.enabled, "activity opt-in is durable before reading")
        reader.beforeRead = { await activity.refresh(enabled: false) }
        await activity.refresh(enabled: true)
        check(activity.readout.steps.isEmpty && !activity.busy, "late activity response cannot repopulate a paused readout")
        let reads = reader.reads
        reader.beforeRead = { await activity.refresh(enabled: true) }
        await activity.refresh(enabled: true)
        check(reader.reads == reads + 1, "simultaneous foreground/preference reads coalesce")
        check(!activity.busy && !activity.readout.steps.isEmpty, "coalesced read completes normally")
        let deniedReader = ActivityHealthService(); deniedReader.failAuthorization = true
        let denied = ActivityModel(health: deniedReader)
        let deniedStore = DiaryStore(fileURL: root.appendingPathComponent("denied.json"), health: HealthKitService())
        await denied.connect(using: deniedStore)
        check(!deniedStore.state.activityPreferences.enabled && deniedReader.reads == 0, "failed permission request starts no read and persists no opt-in")

        // Editing nutrition or actually asking AI must still mark the result estimated.
        if var item = model.draft?.estimate.items.first {
            item.nutrition.calories += 50; model.edit(item, locked: true)
            check(model.entry()?.isEstimate == true, "changed nutrition is still estimated until explicitly verified")
        }
        let reused = MealEstimatorModel(date: original.date, original: original)
        reused.clarification = "Recheck the amount"
        EstimationService.response = reused.draft!.estimate
        reused.begin(configuration: EstimatorConfiguration())
        for _ in 0..<1000 { if !reused.busy { break }; await Task.yield() }
        check(reused.entry()?.isEstimate == true, "new AI result is estimated even if its totals happen to match")
        print("AUDIT2: \(checks) checks, \(failures) failures")
        if failures > 0 { exit(1) }
    }
}
