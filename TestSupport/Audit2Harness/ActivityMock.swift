import Foundation
// Read-only adapter double. It does not contact Apple Health or the recording apps.
@MainActor final class ActivityHealthService {
    var reads = 0, requests = 0
    var failAuthorization = false
    var beforeRead: (() async -> Void)?
    var result = ActivityReadout(steps: [StepDay(date: Date(), count: 100)], refreshedAt: Date())
    func requestAccess() async throws {
        requests += 1
        if failAuthorization { throw CocoaError(.userCancelled) }
    }
    func read() async -> ActivityReadout {
        reads += 1
        if let beforeRead { self.beforeRead = nil; await beforeRead() }
        return result
    }
}
