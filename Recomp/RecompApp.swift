import SwiftUI

@main
@MainActor
struct RecompApp: App {
    @StateObject private var diary: DiaryStore
    @StateObject private var activity = ActivityModel()
    @AppStorage(AppAppearance.storageKey) private var appearance = AppAppearance.system.rawValue
    init() {
        #if DEBUG && targetEnvironment(simulator)
        if ProcessInfo.processInfo.arguments.contains("--recomp-ui-test") {
            let root = (FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true))
                .appendingPathComponent("Recomp-UI-Test-Only", isDirectory: true)
            if ProcessInfo.processInfo.arguments.contains("--reset-test-diary") {
                try? FileManager.default.removeItem(at: root)
            }
            _diary = StateObject(wrappedValue: DiaryStore(fileURL: root.appendingPathComponent("diary.json")))
            return
        }
        #endif
        _diary = StateObject(wrappedValue: DiaryStore())
    }
    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(diary)
                .environmentObject(activity)
                .tint(Theme.accent)
                .preferredColorScheme((AppAppearance(rawValue: appearance) ?? .system).colorScheme)
        }
    }
}
