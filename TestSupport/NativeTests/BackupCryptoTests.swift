import XCTest
import Foundation

// This target compiles the production Core and BackupCrypto sources against Apple's
// SDK, not portable substitutes. Run only with the supplied disposable-simulator runner.
final class BackupCryptoTests: XCTestCase {
    private func payload() -> BackupPayload {
        var state = AppState()
        state.entries = [FoodEntry(name: "Synthetic native backup", date: Date(timeIntervalSince1970: 1_700_000_000),
            meal: .lunch, nutrition: Nutrition(calories: 500, protein: 30, carbs: 50, fat: 20))]
        return BackupPayload(createdAt: Date(timeIntervalSince1970: 1_700_000_001), bundleID: "test.recomp.backupfixture", appearance: "dark", state: state)
    }
    func testIndependentFixture() throws {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "backup-reference", withExtension: "recompbackup"))
        let result = try BackupCrypto.decrypt(Data(contentsOf: url), password: "synthetic fixture password only")
        XCTAssertEqual(result.bundleID, "test.recomp.backupfixture")
        XCTAssertTrue(result.state.entries.isEmpty)
        XCTAssertTrue(result.state.isValid)
    }
    func testExactRoundTripAndIndependentRandomness() throws {
        let expected = payload(), password = "synthetic password for native test"
        let first = try BackupCrypto.encrypt(expected, password: password)
        let second = try BackupCrypto.encrypt(expected, password: password)
        XCTAssertNotEqual(first, second)
        XCTAssertEqual(try BackupCrypto.decrypt(first, password: password), expected)
        XCTAssertEqual(try BackupCrypto.decrypt(second, password: password), expected)
    }
    func testWrongPasswordAndTamperingFail() throws {
        let password = "synthetic password for native test"
        let bytes = try BackupCrypto.encrypt(payload(), password: password)
        XCTAssertThrowsError(try BackupCrypto.decrypt(bytes, password: "incorrect synthetic password"))
        var envelope = try BackupEnvelope.decode(bytes)
        envelope.sealed[envelope.sealed.count - 1] ^= 1
        XCTAssertThrowsError(try BackupCrypto.decrypt(JSONEncoder().encode(envelope), password: password))
        envelope = try BackupEnvelope.decode(bytes); envelope.salt[0] ^= 1
        XCTAssertThrowsError(try BackupCrypto.decrypt(JSONEncoder().encode(envelope), password: password))
    }
    func testUnicodeAndNullPasswordBytes() throws {
        let password = "synthetic\0password中文🏋️ for test"
        let expected = payload()
        XCTAssertEqual(try BackupCrypto.decrypt(BackupCrypto.encrypt(expected, password: password), password: password), expected)
    }
}

extension BackupCryptoTests {
    func testWiFiPairingAuthenticationAndReplayProtection() throws {
        let code = WiFiSyncCrypto.makeCode(), challenge = WiFiSyncCrypto.challenge()
        let data = Data("synthetic private diary".utf8)
        let packet = try WiFiSyncCrypto.seal(data, code: code, challenge: challenge, response: false)
        XCTAssertEqual(try WiFiSyncCrypto.open(packet, code: code, challenge: challenge, response: false), data)
        XCTAssertNotEqual(packet, try WiFiSyncCrypto.seal(data, code: code, challenge: challenge, response: false))
        XCTAssertThrowsError(try WiFiSyncCrypto.open(packet, code: WiFiSyncCrypto.makeCode(), challenge: challenge, response: false))
        XCTAssertThrowsError(try WiFiSyncCrypto.open(packet, code: code, challenge: WiFiSyncCrypto.challenge(), response: false))
        XCTAssertThrowsError(try WiFiSyncCrypto.open(packet, code: code, challenge: challenge, response: true))
        var tampered = packet; tampered[tampered.count - 1] ^= 1
        XCTAssertThrowsError(try WiFiSyncCrypto.open(tampered, code: code, challenge: challenge, response: false))
        XCTAssertThrowsError(try WiFiSyncCrypto.open(data, code: code, challenge: challenge, response: false))
        XCTAssertThrowsError(try WiFiSyncCrypto.key(for: "short guessable password"))
    }
}
