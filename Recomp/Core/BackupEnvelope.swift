import Foundation

/// A bounded, versioned authenticated-encryption envelope. Salt and cipher metadata are public;
/// date, counts and diary content are encrypted. No attacker-selected KDF work factor is accepted.
struct BackupEnvelope: Codable, Sendable {
    var format = "recomp-encrypted"
    var version = 1
    var cipher = "AES-256-GCM"
    var kdf = "PBKDF2-HMAC-SHA256"
    var iterations = 600_000
    var salt: Data
    var sealed: Data // CryptoKit combined: 12-byte nonce + ciphertext + 16-byte tag.
    static let maximumFileBytes = 230 * 1024 * 1024
    var isValid: Bool {
        format == "recomp-encrypted" && version == 1 && cipher == "AES-256-GCM" && kdf == "PBKDF2-HMAC-SHA256" &&
        iterations == 600_000 && salt.count == 16 && sealed.count >= 28 && sealed.count <= BackupPayload.maximumPlainBytes + 28
    }
    var authenticatedData: Data {
        Data("\(format)|\(version)|\(cipher)|\(kdf)|\(iterations)|\(salt.base64EncodedString())".utf8)
    }
    static func decode(_ bytes: Data) throws -> Self {
        guard bytes.count <= maximumFileBytes else { throw BackupError.tooLarge }
        guard let envelope = try? JSONDecoder().decode(Self.self, from: bytes), envelope.isValid else { throw BackupError.invalid }
        return envelope
    }
}
