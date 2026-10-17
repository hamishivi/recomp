import Foundation
import CryptoKit
import CommonCrypto
import Security

/// Native platform cryptography; no network, archive execution, custom cipher or password persistence.
/// Run scripts/check-backup-mac.sh on macOS to exercise this exact implementation.
enum BackupCrypto {
    static func encrypt(_ payload: BackupPayload, password: String) throws -> Data {
        guard password.count >= 12, password.utf8.count <= 256 else { throw BackupError.passwordTooShort }
        var salt = Data(count: 16)
        let randomStatus = salt.withUnsafeMutableBytes { raw in SecRandomCopyBytes(kSecRandomDefault, raw.count, raw.baseAddress!) }
        guard randomStatus == errSecSuccess else { throw BackupError.invalid }
        var envelope = BackupEnvelope(salt: salt, sealed: Data())
        let key = try derive(password: password, salt: salt, iterations: envelope.iterations)
        let box = try AES.GCM.seal(payload.encode(), using: key, authenticating: envelope.authenticatedData)
        guard let combined = box.combined else { throw BackupError.invalid }
        envelope.sealed = combined
        guard envelope.isValid else { throw BackupError.invalid }
        return try JSONEncoder().encode(envelope)
    }
    static func decrypt(_ bytes: Data, password: String) throws -> BackupPayload {
        let envelope = try BackupEnvelope.decode(bytes)
        guard !password.isEmpty, password.utf8.count <= 256 else { throw BackupError.wrongPasswordOrDamaged }
        let key = try derive(password: password, salt: envelope.salt, iterations: envelope.iterations)
        let plaintext: Data
        do {
            let sealed = try AES.GCM.SealedBox(combined: envelope.sealed)
            plaintext = try AES.GCM.open(sealed, using: key, authenticating: envelope.authenticatedData)
        } catch { throw BackupError.wrongPasswordOrDamaged }
        return try BackupPayload.decode(plaintext)
    }
    private static func derive(password: String, salt: Data, iterations: Int) throws -> SymmetricKey {
        let passwordBytes = Array(password.utf8)
        var keyBytes = [UInt8](repeating: 0, count: 32)
        let status = passwordBytes.withUnsafeBytes { p in
            salt.withUnsafeBytes { s in
                CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2), p.bindMemory(to: Int8.self).baseAddress,
                    p.count, s.bindMemory(to: UInt8.self).baseAddress, s.count,
                    CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256), UInt32(iterations), &keyBytes, 32)
            }
        }
        guard status == kCCSuccess else { throw BackupError.invalid }
        let key = SymmetricKey(data: keyBytes)
        // Best effort: Swift may have made copies. This is not a secure-memory guarantee.
        _ = keyBytes.withUnsafeMutableBytes { $0.initializeMemory(as: UInt8.self, repeating: 0) }
        return key
    }
}

/// Ephemeral Wi-Fi pairing: a random 256-bit code is shared out of band.
/// Each connection has a fresh challenge; direction-bound authentication rejects
/// replayed exchanges, reflected packets, wrong codes and tampered data.
enum WiFiSyncCrypto {
    static let maximumPacketBytes = 150_000_000
    static func makeCode() -> String {
        SymmetricKey(size: .bits256).withUnsafeBytes { Data($0).base64EncodedString() }
    }
    static func key(for code: String) throws -> SymmetricKey {
        guard let bytes = Data(base64Encoded: code), bytes.count == 32,
              bytes.base64EncodedString() == code else { throw StateFileError.invalidData }
        return SymmetricKey(data: bytes)
    }
    static func challenge() -> Data {
        SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) }
    }
    private static func context(_ challenge: Data, response: Bool) throws -> Data {
        guard challenge.count == 32 else { throw StateFileError.invalidData }
        return Data((response ? "recomp-sync-v3:response:" : "recomp-sync-v3:request:").utf8) + challenge
    }
    static func seal(_ data: Data, code: String, challenge: Data, response: Bool) throws -> Data {
        guard data.count <= maximumPacketBytes - 28 else { throw StateFileError.invalidData }
        let box = try AES.GCM.seal(data, using: key(for: code), authenticating: context(challenge, response: response))
        guard let result = box.combined else { throw StateFileError.invalidData }
        return result
    }
    static func open(_ packet: Data, code: String, challenge: Data, response: Bool) throws -> Data {
        guard packet.count <= maximumPacketBytes else { throw StateFileError.invalidData }
        return try AES.GCM.open(AES.GCM.SealedBox(combined: packet), using: key(for: code),
            authenticating: context(challenge, response: response))
    }
}
