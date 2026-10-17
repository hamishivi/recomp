import Foundation
import Network
import Darwin

@MainActor final class DiaryStore {
    var state: AppState
    var merges = 0
    init(_ name: String) {
        state = AppState()
        state.entries = [FoodEntry(name: name, date: Date(), meal: .snack, nutrition: Nutrition(calories: 100))]
    }
    func mergeExternalState(_ peer: AppState) -> Bool {
        guard peer.isValid else { return false }
        state = state.merging(with: peer); merges += 1
        return true
    }
}

@main struct WiFiHarness {
    @MainActor static func wait(_ condition: () -> Bool) async throws {
        for _ in 0..<150 {
            if condition() { return }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        throw NSError(domain: "WiFi test timed out", code: 1)
    }
    @MainActor static func main() async throws {
        setbuf(stdout, nil)
        let a = WiFiSyncService(), b = WiFiSyncService()
        let da = DiaryStore("Synthetic A"), db = DiaryStore("Synthetic B")
        let code = WiFiSyncCrypto.makeCode()
        defer { print("Final transport state: \(a.status), \(b.status); ports: \(String(describing: a.listeningPort)), \(String(describing: b.listeningPort))"); a.stop(); b.stop() }
        a.start(with: da, code: code, advertise: false)
        b.start(with: db, code: WiFiSyncCrypto.makeCode(), advertise: false)
        try await wait { a.isAdvertising && b.isAdvertising }
        print("Listeners ready")
        a.sync(with: WiFiPeer(id: "b", name: "Synthetic B", endpoint: .hostPort(host: "127.0.0.1", port: b.listeningPort!)))
        try await wait { if case .failed = a.status { return true }; return false }
        try await wait { if case .failed = b.status { return true }; return false }
        precondition(da.merges == 0 && db.merges == 0, "Wrong code must not merge either diary")
        print("PASS: wrong-code exchange cannot read or modify diary")
        b.stop()
        b.start(with: db, code: code, advertise: false)
        try await wait { b.isAdvertising }
        print("Starting matched-code exchange")
        b.sync(with: WiFiPeer(id: "a", name: "Synthetic A", endpoint: .hostPort(host: "127.0.0.1", port: a.listeningPort!)))
        try await wait { if case .success = b.status { return true }; return false }
        precondition(da.state.entries.count == 2 && db.state.entries.count == 2)
        print("PASS: encrypted paired exchange merges both synthetic diaries")
        let mergeCount = db.merges
        let stalled = NWConnection(host: "127.0.0.1", port: b.listeningPort!, using: .tcp)
        stalled.start(queue: .main)
        try await wait { if case .syncing = b.status { return true }; return false }
        b.stop()
        try await Task.sleep(nanoseconds: 200_000_000)
        stalled.cancel()
        precondition(db.merges == mergeCount && b.status == .idle && b.listeningPort == nil)
        print("PASS: stopping an incoming stalled exchange prevents late writes")
        a.stop(); b.stop()
        precondition(!a.isPairing && !b.isPairing && a.discoveredPeers.isEmpty && b.discoveredPeers.isEmpty)
        print("PASS: stopping pairing clears discovery and closes the session")
    }
}
