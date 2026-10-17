import Foundation
import Combine

@MainActor
final class ActivityModel: ObservableObject {
    @Published private(set) var readout = ActivityReadout()
    @Published private(set) var busy = false
    @Published var error: String?
    @Published private(set) var authorizing = false
    private let health: ActivityHealthService
    init(health: ActivityHealthService? = nil) { self.health = health ?? ActivityHealthService() }
    private var generation = 0
    func requestAccess() async -> Bool {
        do { try await health.requestAccess(); return true }
        catch { self.error = error.localizedDescription; return false }
    }
    /// Persist opt-in before starting any read. A successful system permission prompt
    /// cannot override a failed diary save or a protected/unreadable local file.
    func connect(using diary: DiaryStore) async {
        guard !authorizing else { return }
        guard diary.loadFailure == nil else { error = "Unlock or recover your diary before connecting activity."; return }
        error = nil
        authorizing = true
        defer { authorizing = false }
        guard await requestAccess() else { return }
        var preferences = diary.state.activityPreferences
        preferences.enabled = true
        guard diary.setActivityPreferences(preferences) else {
            error = diary.errorMessage ?? "Activity settings could not be saved. No activity was read."
            return
        }
        await refresh(enabled: diary.state.activityPreferences.enabled)
    }
    func refresh(enabled: Bool) async {
        // Foreground and the preference observer can request the same read together.
        // Coalesce enabled reads, but a pause must ALWAYS invalidate an in-flight read.
        if enabled && busy { return }
        generation += 1
        let token = generation
        guard enabled else { readout = ActivityReadout(); busy = false; return }
        busy = true
        let fetched = await health.read()
        guard token == generation else { return }
        readout = fetched; busy = false
    }
    var workoutSources: [ActivitySource] { unique(readout.workouts.map(\.source)) }
    var sleepSources: [ActivitySource] { unique(readout.sleep.map(\.source)) }
    private func unique(_ sources: [ActivitySource]) -> [ActivitySource] {
        var seen = Set<String>()
        return sources.filter { seen.insert($0.id).inserted }.sorted { $0.name < $1.name }
    }
}
