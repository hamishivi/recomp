import Foundation
import WidgetKit

/// The extension receives only an explicitly enabled, local-food-only summary.
@MainActor
enum WidgetPublisher {
    private static var lastPublished: (url: URL, snapshot: WidgetSnapshot)?
    static var groupID: String? { Bundle.main.object(forInfoDictionaryKey: "RecompAppGroup") as? String }
    static var container: URL? {
        guard let id = groupID, !id.isEmpty else { return nil }
        return FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: id)
    }
    @discardableResult
    static func publish(_ state: AppState, now: Date = Date()) -> Bool {
        #if DEBUG && targetEnvironment(simulator)
        // UI smoke tests use an isolated diary and must not publish synthetic totals.
        if ProcessInfo.processInfo.arguments.contains("--recomp-ui-test") { return false }
        #endif
        guard let directory = container else { return false }
        var url = directory.appendingPathComponent(WidgetSnapshot.filename)
        let snapshot = state.widgetSnapshot(now: now)
        if let last = lastPublished, last.url == url,
           last.snapshot.hasSameReadout(as: snapshot, now: now),
           FileManager.default.fileExists(atPath: url.path) { return true }
        do {
            let data = try JSONEncoder().encode(snapshot)
            try data.write(to: url, options: [.atomic, .completeFileProtection])
            var values = URLResourceValues(); values.isExcludedFromBackup = true
            try url.setResourceValues(values)
            WidgetCenter.shared.reloadTimelines(ofKind: WidgetSnapshot.kind)
            lastPublished = (url, snapshot) // Only after a successful protected write.
            return true
        } catch { return false }
    }
}
