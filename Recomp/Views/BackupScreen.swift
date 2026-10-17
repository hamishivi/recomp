import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static let recompBackup = UTType(exportedAs: "app.recomp.encrypted-backup", conformingTo: .data)
}
struct EncryptedBackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.recompBackup] }
    var data: Data
    init(data: Data = Data()) { self.data = data }
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents, data.count <= BackupEnvelope.maximumFileBytes else { throw BackupError.tooLarge }
        self.data = data
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}

@MainActor
struct BackupScreen: View {
    @EnvironmentObject private var diary: DiaryStore
    @AppStorage(AppAppearance.storageKey) private var appearance = AppAppearance.system.rawValue
    @State private var password = ""
    @State private var repeatedPassword = ""
    @State private var importPassword = ""
    @State private var busy = false
    @State private var exporting = false
    @State private var importing = false
    @State private var document = EncryptedBackupDocument()
    @State private var importData: Data?
    @State private var reviewedPayload: BackupPayload?
    @State private var confirmRestore = false
    @State private var status = ""
    @State private var error: String?
    var body: some View {
        Form {
            Section {
                Text("One encrypted file for your local diary, retained meal photos, measurements, scale tags, DEXA reports, context notes and settings.")
                Text("Includes any Apple Health totals you explicitly confirmed in food-day snapshots. Raw imported Health workouts, sleep and steps are not backed up; reconnect to read them. API keys and server tokens are never included.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Create a backup") {
                SecureField("New backup password (12+ characters)", text: $password)
                    .textContentType(.newPassword).textInputAutocapitalization(.never)
                SecureField("Repeat password", text: $repeatedPassword).textInputAutocapitalization(.never)
                Button("Encrypt and choose where to save") { export() }
                    .disabled(busy || diary.loadFailure != nil || password.count < 12 || password != repeatedPassword)
                Text("Keep the password separately in a password manager. There is no password recovery. Store the file somewhere you trust; it contains sensitive personal data, even though it is encrypted. Backups are manual snapshots, not automatic cloud sync.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Restore into an empty diary") {
                Button("Choose encrypted backup") { importing = true }.disabled(busy || diary.loadFailure != nil)
                if let data = importData {
                    Text("Encrypted file selected · \(data.count / 1024) KB").font(.caption)
                    SecureField("Backup password", text: $importPassword).textInputAutocapitalization(.never)
                    Button("Decrypt for review") { decrypt(data) }.disabled(busy || importPassword.isEmpty)
                }
                if let payload = reviewedPayload {
                    LabeledContent("Created", value: payload.createdAt.formatted(date: .abbreviated, time: .shortened))
                    LabeledContent("Meals", value: String(payload.state.entries.count))
                    LabeledContent("Measurements", value: String(payload.state.measurements.count))
                    LabeledContent("DEXA scans", value: String(payload.state.dxaScans.count))
                    LabeledContent("Retained photos", value: String(payload.state.entries.reduce(0) { $0 + ($1.photos?.count ?? 0) }))
                    Text("Original app ID: \(payload.bundleID)").font(.caption).textSelection(.enabled)
                    Button("Review and restore") { confirmRestore = true }
                        .disabled(busy || !diary.state.canRestoreBackup || diary.isSyncing || diary.isRefreshing || payload.bundleID != diary.health.ownBundleID)
                }
                Text("No existing log is overwritten or merged. Restore on an empty installation using the SAME bundle identifier. Health connections and widget numbers remain off afterward. Review and reconnect them explicitly. Original Health sync IDs, versions and deletion queues are preserved—not re-created as new records.")
                    .font(.caption).foregroundStyle(.secondary)
                if !diary.state.canRestoreBackup { Text("This diary is not empty. You can export, but restore is blocked to protect it.").font(.caption).foregroundStyle(.secondary) }
            }
            if busy { Section { ProgressView("Working locally…") } }
            if !status.isEmpty { Section { Text(status).font(.footnote) } }
        }
        .instrumentForm().navigationTitle("Backup & restore").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { dismissKeyboard() }
            }
        }
        .fileExporter(isPresented: $exporting, document: document, contentType: .recompBackup,
                      defaultFilename: "Recomp-\(DayReview.key(Date()))") { result in
            if case .failure(let e) = result { error = e.localizedDescription }
            else { status = "Encrypted backup exported. Verify your saved file and keep its password safe." }
            document = EncryptedBackupDocument()
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.recompBackup, .data], allowsMultipleSelection: false) { result in
            do {
                guard let url = try result.get().first else { return }
                let access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
                guard let size = attributes[.size] as? NSNumber, size.intValue <= BackupEnvelope.maximumFileBytes else { throw BackupError.tooLarge }
                let data = try Data(contentsOf: url)
                _ = try BackupEnvelope.decode(data)
                importData = data; reviewedPayload = nil; importPassword = ""; status = ""
            } catch { self.error = error.localizedDescription }
        }
        .confirmationDialog("Restore this reviewed backup?", isPresented: $confirmRestore, titleVisibility: .visible) {
            Button("Restore into empty diary") {
                if let payload = reviewedPayload, diary.restoreBackup(payload) {
                    appearance = payload.appearance
                    reviewedPayload = nil; importData = nil; importPassword = ""
                    status = "Restored locally. Health connections are paused. Review your diary before reconnecting; restored export receipts do not prove the samples still exist in Health."
                }
            }
        } message: { Text("This writes the reviewed local records and settings. It does not send, remove, or recreate any Health samples. It does not restore server credentials.") }
        .alert("Backup needs attention", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK", role: .cancel) { error = nil }
        } message: { Text(error ?? "") }
    }
    private func export() {
        guard !busy else { return }; busy = true
        let payload = BackupPayload(createdAt: Date(), bundleID: diary.health.ownBundleID, appearance: appearance, state: diary.state)
        let secret = password
        Task {
            defer { busy = false; password = ""; repeatedPassword = "" }
            do {
                let bytes = try await Task.detached(priority: .userInitiated) { try BackupCrypto.encrypt(payload, password: secret) }.value
                document = EncryptedBackupDocument(data: bytes); exporting = true
            } catch { self.error = error.localizedDescription }
        }
    }
    private func decrypt(_ bytes: Data) {
        guard !busy else { return }; busy = true; reviewedPayload = nil
        let secret = importPassword
        Task {
            defer { busy = false; importPassword = "" }
            do { reviewedPayload = try await Task.detached(priority: .userInitiated) { try BackupCrypto.decrypt(bytes, password: secret) }.value }
            catch { self.error = error.localizedDescription }
        }
    }
}
