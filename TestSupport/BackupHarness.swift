import Foundation

@main struct BackupHarness {
    static func main() throws {
        var checks = 0
        func check(_ value: @autoclosure () -> Bool, _ label: String) {
            precondition(value(), "FAILED: \(label)"); checks += 1; print("PASS: \(label)")
        }
        func mustReject(_ label: String, _ work: () throws -> Void) {
            do { try work(); preconditionFailure("FAILED: \(label)") } catch { checks += 1; print("PASS: \(label)") }
        }
        let fixture = try Data(contentsOf: URL(fileURLWithPath: "TestSupport/Fixtures/backup-reference.recompbackup"))
        let reference = try BackupCrypto.decrypt(fixture, password: "synthetic fixture password only")
        check(reference.bundleID == "test.recomp.backupfixture", "decrypt independent Python AES-GCM/PBKDF2 fixture")
        check(reference.state.entries.isEmpty && reference.state.isValid, "fixture plaintext is a valid empty diary")
        var state = AppState()
        let food = FoodEntry(name: "Synthetic crypto test", date: Date(), meal: .lunch, nutrition: Nutrition(calories: 500, protein: 30, carbs: 50, fat: 20))
        state.entries = [food]
        let payload = BackupPayload(createdAt: Date(), bundleID: "test.recomp.backupfixture", appearance: "dark", state: state)
        let password = "another synthetic password only"
        let first = try BackupCrypto.encrypt(payload, password: password)
        let second = try BackupCrypto.encrypt(payload, password: password)
        check(first != second, "fresh salt and nonce produce different ciphertext")
        let roundTrip = try BackupCrypto.decrypt(first, password: password)
        check(roundTrip == payload, "native encrypt/decrypt preserves exact payload")
        let envelope = try BackupEnvelope.decode(first)
        check(envelope.salt.count == 16 && envelope.sealed.count > 28, "native envelope uses expected combined nonce/ciphertext/tag format")
        mustReject("wrong password rejected") { _ = try BackupCrypto.decrypt(first, password: "incorrect synthetic password") }
        var tampered = envelope; tampered.sealed[tampered.sealed.count-1] ^= 1
        let tamperedBytes = try JSONEncoder().encode(tampered)
        mustReject("modified tag rejected") { _ = try BackupCrypto.decrypt(tamperedBytes, password: password) }
        tampered = envelope; tampered.salt[0] ^= 1
        let changedSalt = try JSONEncoder().encode(tampered)
        mustReject("modified salt/header rejected") { _ = try BackupCrypto.decrypt(changedSalt, password: password) }
        mustReject("short encryption password refused") { _ = try BackupCrypto.encrypt(payload, password: "short") }
        print("\(checks) native backup cryptography checks passed. This harness does not test the iPhone UI or HealthKit.")
    }
}
