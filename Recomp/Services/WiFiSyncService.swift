import Foundation
import Network
import Combine
#if canImport(UIKit)
import UIKit
#endif

struct WiFiPeer: Identifiable, Equatable {
    let id: String
    let name: String
    let endpoint: NWEndpoint

    static func == (lhs: WiFiPeer, rhs: WiFiPeer) -> Bool {
        lhs.id == rhs.id
    }
}

enum WiFiSyncStatus: Equatable {
    case idle
    case searching
    case connecting(String)
    case syncing(String)
    case success(String)
    case failed(String)
}

@MainActor
final class WiFiSyncService: ObservableObject {
    @Published private(set) var status: WiFiSyncStatus = .idle
    @Published private(set) var discoveredPeers: [WiFiPeer] = []
    @Published private(set) var isAdvertising = false

    private let serviceType = "_recomp-sync3._tcp"
    private let instanceID = UUID()
    private var listener: NWListener?
    private var browser: NWBrowser?
    private var activeConnection: NWConnection?
    private weak var diary: DiaryStore?
    @Published private(set) var isPairing = false
    private var pairingCode: String?
    private var session = UUID()
    private var exchangeTask: Task<Void, Never>?
    private var timeoutTask: Task<Void, Never>?

    var deviceName: String {
        #if canImport(UIKit)
        return UIDevice.current.name
        #else
        return Host.current().localizedName ?? "Mac"
        #endif
    }

    init() {}

    var listeningPort: NWEndpoint.Port? { listener?.port }

    func start(with diary: DiaryStore, code: String, advertise: Bool = true) {
        stop()
        guard (try? WiFiSyncCrypto.key(for: code)) != nil else {
            status = .failed("Paste the pairing code generated on your other device."); return
        }
        pairingCode = code
        isPairing = true
        self.diary = diary
        startListening(advertise: advertise)
        if advertise { startBrowsing() }
    }

    func stop() {
        session = UUID()
        isPairing = false
        pairingCode = nil
        exchangeTask?.cancel(); exchangeTask = nil
        timeoutTask?.cancel(); timeoutTask = nil
        stopListening()
        stopBrowsing()
        activeConnection?.cancel()
        activeConnection = nil
        discoveredPeers = []
        status = .idle
    }

    // MARK: - Bonjour Listener

    private func startListening(advertise: Bool) {
        guard listener == nil else { return }
        let currentSession = session
        do {
            let tcpOptions = NWProtocolTCP.Options()
            tcpOptions.enableKeepalive = true
            let params = NWParameters(tls: nil, tcp: tcpOptions)
            params.includePeerToPeer = true

            let newListener = try NWListener(using: params)
            let txtRecord = NWTXTRecord(["id": instanceID.uuidString])
            if advertise { newListener.service = NWListener.Service(name: deviceName, type: serviceType, domain: nil, txtRecord: txtRecord) }

            newListener.stateUpdateHandler = { [weak self] state in
                Task { @MainActor in
                    guard let self, self.session == currentSession else { return }
                    switch state {
                    case .ready:
                        self.isAdvertising = true
                    case .failed, .cancelled:
                        self.isAdvertising = false
                        self.listener = nil
                    default:
                        break
                    }
                }
            }

            newListener.newConnectionHandler = { [weak self] connection in
                Task { @MainActor in
                    guard let self, self.session == currentSession else { connection.cancel(); return }
                    self.handleIncomingConnection(connection)
                }
            }

            newListener.start(queue: .main)
            self.listener = newListener
        } catch {
            isAdvertising = false
        }
    }

    private func stopListening() {
        listener?.cancel()
        listener = nil
        isAdvertising = false
    }

    // MARK: - Bonjour Browser

    private func startBrowsing() {
        guard browser == nil else { return }
        let currentSession = session
        let params = NWParameters()
        params.includePeerToPeer = true
        let newBrowser = NWBrowser(for: .bonjour(type: serviceType, domain: nil), using: params)

        newBrowser.browseResultsChangedHandler = { [weak self] results, _ in
            Task { @MainActor in
                guard let self, self.session == currentSession else { return }
                var peers: [WiFiPeer] = []
                for result in results {
                    if case .service(let name, _, _, _) = result.endpoint {
                        if case .bonjour(let txt) = result.metadata, let peerID = txt.dictionary["id"], peerID == self.instanceID.uuidString {
                            continue
                        }
                        let peer = WiFiPeer(id: name, name: name, endpoint: result.endpoint)
                        if !peers.contains(peer) {
                            peers.append(peer)
                        }
                    }
                }
                self.discoveredPeers = peers
                if case .searching = self.status {
                    if peers.isEmpty {
                        self.status = .searching
                    }
                }
            }
        }

        newBrowser.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                guard let self, self.session == currentSession else { return }
                switch state {
                case .ready:
                    if self.discoveredPeers.isEmpty {
                        self.status = .searching
                    }
                case .failed(let error):
                    let desc = error.localizedDescription
                    if desc.localizedCaseInsensitiveContains("NoAuth") || desc.contains("-65547") {
                        self.status = .failed("Local Network permission required. Allow Local Network for Recomp in iOS Settings.")
                    } else {
                        self.status = .failed("Discovery failed: \(error.localizedDescription)")
                    }
                    self.browser = nil
                case .cancelled:
                    self.browser = nil
                default:
                    break
                }
            }
        }

        newBrowser.start(queue: .main)
        self.browser = newBrowser
    }

    private func stopBrowsing() {
        browser?.cancel()
        browser = nil
        discoveredPeers = []
    }

    // Only one bounded exchange is allowed at a time. All continuations verify
    // ownership before merging or sending state, including after stop/restart.
    func sync(with peer: WiFiPeer) {
        guard isPairing, activeConnection == nil else { return }
        let connection = NWConnection(to: peer.endpoint, using: .tcp)
        begin(connection, peerName: peer.name, incoming: false)
    }

    private func handleIncomingConnection(_ connection: NWConnection) {
        guard isPairing, activeConnection == nil else { connection.cancel(); return }
        begin(connection, peerName: "paired device", incoming: true)
    }

    private func begin(_ connection: NWConnection, peerName: String, incoming: Bool) {
        activeConnection = connection
        status = .connecting(peerName)
        timeoutTask = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: 30_000_000_000) } catch { return }
            guard let self, self.activeConnection === connection else { return }
            self.finish(connection, status: .failed("Sync timed out. Try again with both devices open."))
        }
        connection.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                guard let self, self.activeConnection === connection else { return }
                switch state {
                case .ready:
                    guard self.exchangeTask == nil else { return }
                    self.status = .syncing(peerName)
                    self.exchangeTask = Task { await self.exchange(connection, peerName: peerName, incoming: incoming) }
                case .waiting(let error):
                    self.finish(connection, status: .failed("Network unavailable: \(error.localizedDescription)"))
                case .failed, .cancelled:
                    self.finish(connection, status: .failed("Connection closed. Check both devices and try again."))
                default: break
                }
            }
        }
        connection.start(queue: .main)
    }

    private func finish(_ connection: NWConnection, status: WiFiSyncStatus) {
        guard activeConnection === connection else { return }
        activeConnection = nil
        connection.cancel()
        exchangeTask?.cancel(); exchangeTask = nil
        timeoutTask?.cancel(); timeoutTask = nil
        self.status = status
    }

    private func checkActive(_ connection: NWConnection) throws {
        try Task.checkCancellation()
        guard isPairing, activeConnection === connection else { throw StateFileError.invalidData }
    }

    private func exchange(_ connection: NWConnection, peerName: String, incoming: Bool) async {
        guard let diary, let code = pairingCode else { return }
        do {
            let challenge: Data
            if incoming {
                challenge = WiFiSyncCrypto.challenge()
                try await send(challenge, on: connection)
                let packet = try await receive(on: connection)
                try checkActive(connection)
                let plaintext = try WiFiSyncCrypto.open(packet, code: code, challenge: challenge, response: false)
                let peer = try JSONDecoder().decode(AppState.self, from: plaintext)
                guard diary.mergeExternalState(peer) else { throw StateFileError.invalidData }
                let reply = try WiFiSyncCrypto.seal(JSONEncoder().encode(diary.state), code: code, challenge: challenge, response: true)
                try checkActive(connection)
                try await send(reply, on: connection)
            } else {
                challenge = try await receive(on: connection, maximum: 32)
                try checkActive(connection)
                let packet = try WiFiSyncCrypto.seal(JSONEncoder().encode(diary.state), code: code, challenge: challenge, response: false)
                try await send(packet, on: connection)
                let reply = try await receive(on: connection)
                try checkActive(connection)
                let plaintext = try WiFiSyncCrypto.open(reply, code: code, challenge: challenge, response: true)
                let peer = try JSONDecoder().decode(AppState.self, from: plaintext)
                guard diary.mergeExternalState(peer) else { throw StateFileError.invalidData }
            }
            finish(connection, status: .success("Synced with \(peerName)."))
        } catch {
            finish(connection, status: .failed("Sync failed. Check that both devices use the same pairing code and current app version. No unauthenticated data was accepted."))
        }
    }

    private func send(_ data: Data, on connection: NWConnection) async throws {
        try checkActive(connection)
        guard !data.isEmpty, data.count <= WiFiSyncCrypto.maximumPacketBytes else { throw StateFileError.invalidData }
        var length = UInt32(data.count).bigEndian
        var packet = Data(bytes: &length, count: 4)
        packet.append(data)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(content: packet, completion: .contentProcessed { error in
                if let error { continuation.resume(throwing: error) } else { continuation.resume() }
            })
        }
    }

    private func receive(on connection: NWConnection, maximum: Int = WiFiSyncCrypto.maximumPacketBytes) async throws -> Data {
        let header = try await receiveExact(4, on: connection)
        // Data slices are not guaranteed to be UInt32-aligned.
        let length = header.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        guard length > 0, length <= maximum else { throw StateFileError.invalidData }
        return try await receiveExact(Int(length), on: connection)
    }

    private func receiveExact(_ count: Int, on connection: NWConnection) async throws -> Data {
        var data = Data()
        while data.count < count {
            try checkActive(connection)
            let chunk: Data = try await withCheckedThrowingContinuation { continuation in
                connection.receive(minimumIncompleteLength: 1, maximumLength: min(65536, count - data.count)) { chunk, _, _, error in
                    if let error { continuation.resume(throwing: error) }
                    else if let chunk, !chunk.isEmpty { continuation.resume(returning: chunk) }
                    else { continuation.resume(throwing: StateFileError.invalidData) }
                }
            }
            data.append(chunk)
        }
        return data
    }
}
