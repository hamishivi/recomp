import Foundation

@main struct StartupCoordinatorChecks {
    @MainActor static func main() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("recomp-startup-coordinator-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        var checks = 0, failures = 0
        func check(_ value: @autoclosure () -> Bool, _ name: String) {
            checks += 1
            if value() { print("PASS: \(name)") } else { failures += 1; print("FAIL: \(name)") }
        }
        var state = AppState(); state.bodyHealthEnabled = true
        let file = StateFile(url: root.appendingPathComponent("diary.json")); try file.save(state)
        let health = HealthKitService()
        let store = DiaryStore(fileURL: file.url, health: health)
        var reads = 0
        health.beforeBodyRead = {
            reads += 1
            health.beforeBodyRead = { reads += 1 }
            // Simulates active-scene notification during start()'s first read.
            await store.foreground()
        }
        await store.start()
        check(reads == 1, "overlapping startup/foreground callbacks cause one Health read")
        check(!store.isSyncing && !store.isRefreshing, "coalesced foreground completes normally")
        await store.start()
        check(reads == 1, "second start is idempotent")
        await store.foreground()
        check(reads == 2, "a later foreground still refreshes")

        // A DATA CHANGE during that same read must still schedule a drain.
        let activeFile = StateFile(url: root.appendingPathComponent("active.json"))
        state.healthEnabled = true; try activeFile.save(state)
        let activeHealth = HealthKitService(); activeHealth.writableNutrients = Set(Nutrient.allCases)
        let activeStore = DiaryStore(fileURL: activeFile.url, health: activeHealth)
        let meal = FoodEntry(name: "Synthetic late meal", date: Date(), meal: .lunch, nutrition: .startingTargets)
        activeHealth.beforeBodyRead = {
            _ = activeStore.saveEntry(meal, makeTemplate: false)
            await activeStore.synchronize() // deterministic queue-drain trigger
        }
        await activeStore.foreground()
        check(activeHealth.foodSaves.count == 4, "meal saved during foreground still exports every nutrient")
        check(activeStore.state.entries.first?.exportCount == 4, "late meal receipts are persisted")

        let badURL = root.appendingPathComponent("bad.json")
        try Data("bad JSON".utf8).write(to: badURL)
        let badHealth = HealthKitService(); var badReads = 0
        badHealth.beforeBodyRead = { badReads += 1 }
        let badStore = DiaryStore(fileURL: badURL, health: badHealth)
        await badStore.foreground()
        check(badStore.loadFailure != nil && badReads == 0, "invalid diary remains protected without Health work")
        let untouched = try Data(contentsOf: badURL)
        check(untouched == Data("bad JSON".utf8), "failed launch leaves invalid source bytes untouched")
        print("STARTUP: \(checks) checks, \(failures) failures")
        if failures > 0 { exit(1) }
    }
}
