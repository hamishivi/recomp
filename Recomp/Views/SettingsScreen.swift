import SwiftUI
import UniformTypeIdentifiers

struct CSVDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.commaSeparatedText] }
    var text: String
    init(text: String) { self.text = text }
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents, let text = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.text = text
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}

private enum CSVExportKind { case food, body, analysis }

@MainActor
struct SettingsScreen: View {
    @EnvironmentObject private var diary: DiaryStore
    @State private var showGoals = false
    @State private var showEstimatorSettings = false
    @State private var exporting = false
    @State private var exportDocument = CSVDocument(text: "")
    @State private var exportName = "Recomp"
    @AppStorage(AppAppearance.storageKey) private var appearance = AppAppearance.system.rawValue
    var body: some View {
        NavigationStack {
            Form {
                Section("Food") {
                    Button { showGoals = true } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Daily targets")
                                    .foregroundStyle(Theme.ink)
                                Text("\(diary.state.targets.protein.wholeNumber)g P · \(diary.state.targets.carbs.wholeNumber)g C · \(diary.state.targets.fat.wholeNumber)g F")
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundStyle(Theme.muted)
                            }
                            Spacer()
                            Text("\(diary.state.targets.calories.wholeNumber) kcal")
                                .foregroundStyle(.secondary)
                        }
                    }
                    NavigationLink { SavedFoodsSettings() } label: {
                        Label("Your usuals", systemImage: "bookmark")
                    }.accessibilityIdentifier("settings.usuals")
                    Button { showEstimatorSettings = true } label: { Label("Photo & text estimates", systemImage: "camera") }
                }
                Section("Connections") {
                    NavigationLink { HealthSettingsScreen() } label: { Label("Apple Health", systemImage: "heart") }
                    NavigationLink { ActivityContextScreen() } label: {
                        HStack {
                            Label("Workouts & activity", systemImage: "figure.run")
                            Spacer()
                            Text("Strong · Strava")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    NavigationLink { DXAScansScreen() } label: { Label("DEXA reports & exports", systemImage: "doc.text") }
                }
                Section("Preferences") {
                    Picker("Measurement units", selection: Binding(get: { diary.state.measurementUnits }, set: { diary.setMeasurementUnits($0) })) {
                        ForEach(MeasurementUnits.allCases) { Text($0.title).tag($0) }
                    }
                    Picker("Appearance", selection: $appearance) { ForEach(AppAppearance.allCases) { Text($0.title).tag($0.rawValue) } }
                    NavigationLink("Interface preview") { InterfacePreviewScreen() }
                        .accessibilityIdentifier("settings.preview")
                    NavigationLink { WidgetSettingsScreen() } label: { Label("Home Screen widget", systemImage: "rectangle.on.rectangle") }
                }
                Section("Data") {
                    NavigationLink { SyncSettingsScreen() } label: {
                        HStack {
                            Label("Sync & iCloud", systemImage: "arrow.triangle.2.circlepath.icloud")
                            Spacer()
                            Text(diary.isUsingICloud ? "iCloud Drive" : "On device")
                                .font(.caption)
                                .foregroundStyle(Theme.muted)
                        }
                    }
                    NavigationLink { BackupScreen() } label: { Label("Backup & restore", systemImage: "externaldrive") }
                    DisclosureGroup("Export CSV") {
                        Button("Food") { export(.food) }.disabled(diary.state.entries.isEmpty)
                        Button("Measurements") { export(.body) }.disabled(diary.state.measurements.isEmpty)
                        Button("Analysis history") { export(.analysis) }.disabled(!AnalysisCSV.hasRecords(in: diary.state))
                        Text("Readable exports, not backups. Use Backup & restore for a restorable copy.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    NavigationLink("Privacy & data") { PrivacyDetailsScreen() }
                }
                Section {
                } footer: {
                    Text("Recomp 1.10.1").font(.system(.caption, design: .monospaced)).foregroundStyle(Theme.muted)
                }
            }
            .instrumentForm().navigationTitle("Settings").navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showGoals) { GoalsEditor(targets: diary.state.targets) }
            .sheet(isPresented: $showEstimatorSettings) { EstimatorSettingsView() }
            .fileExporter(isPresented: $exporting, document: exportDocument,
                          contentType: .commaSeparatedText, defaultFilename: exportName) { result in
                if case .failure(let error) = result { diary.errorMessage = error.localizedDescription }
                exportDocument = CSVDocument(text: "")
            }
        }
    }
    // Construct only the requested export, when tapped, not all CSVs on every Form render.
    private func export(_ kind: CSVExportKind) {
        switch kind {
        case .food: exportDocument = CSVDocument(text: DiaryCSV.make(entries: diary.state.entries)); exportName = "Recomp-food-log"
        case .body: exportDocument = CSVDocument(text: BodyCSV.make(diary.state.measurements, locations: diary.state.scaleLocations)); exportName = "Recomp-measurements"
        case .analysis: exportDocument = CSVDocument(text: AnalysisCSV.make(state: diary.state)); exportName = "Recomp-analysis-history"
        }
        exporting = true
    }
}

@MainActor
// private struct HealthSettingsScreen
struct HealthSettingsScreen: View {
    @EnvironmentObject private var diary: DiaryStore
    @State private var confirmConnect = false
    @State private var requesting = false
    var body: some View {
        Form { healthSection }
            .instrumentForm().navigationTitle("Apple Health").navigationBarTitleDisplayMode(.inline)
            .confirmationDialog("Connect Apple Health?", isPresented: $confirmConnect, titleVisibility: .visible) {
                Button("Connect and export meals & measurements") { connect() }
            } message: {
                Text("Request permission to write calories, macros, and weight to Apple Health. Existing Recomp meals and measurements will be queued for export too. You control each permission.")
            }
    }
    private var healthSection: some View {
        Section {
            if !diary.health.isAvailable {
                Notice(text: "HealthKit is unavailable on this device. Local logging still works.", symbol: "heart.slash")
            } else if diary.state.healthEnabled || diary.state.bodyHealthEnabled {
                Label("Apple Health integration on", systemImage: "heart.fill").foregroundStyle(Theme.accent)
                if diary.state.healthEnabled {
                    LabeledContent("Nutrition write permissions", value: "\(diary.writable.count) of 4")
                    Toggle("Include additional Health nutrition", isOn: Binding(get: { diary.state.includeOtherSources }, set: { diary.setIncludeOtherSources($0) }))
                    LabeledContent("Meals pending export", value: "\(diary.pendingEntries)")
                }
                if diary.state.bodyHealthEnabled {
                    LabeledContent("Weight write permissions", value: "\(diary.bodyWritable.count) of 3")
                    LabeledContent("Readings pending export", value: "\(diary.pendingBodyEntries)")
                }
                LabeledContent("Deletions pending cleanup", value: "\(diary.state.deletions.count + diary.state.bodyDeletions.count)")
                if diary.isSyncing || diary.isRefreshing { ProgressView("Updating…") }
                Button("Sync now") { Task { await diary.synchronize() } }.disabled(diary.isSyncing)
                Button("Review Health permissions") { connect() }.disabled(requesting)
                if !diary.syncMessage.isEmpty { Text(diary.syncMessage).font(.caption).foregroundStyle(.orange) }
            } else {
                Button { confirmConnect = true } label: { Label("Connect Apple Health", systemImage: "heart.fill") }.disabled(requesting)
            }
            if diary.state.healthEnabled || diary.state.bodyHealthEnabled || diary.state.dxaHealthEnabled || diary.state.activityPreferences.enabled {
                Button("Pause all Health connections") { diary.pauseHealth() }
                Text("Pauses food, body, DEXA and activity connections in Recomp. Existing Health records and system permissions are not removed; a request already in progress may finish.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if requesting { ProgressView("Requesting permissions…") }
            DisclosureGroup("Sync details") {
                Text("Writes calories and macros for logged meals, and weight, body fat and waist for measurements.")
                Text("Updates after edits, on opening and on refresh—not continuously in the background.")
                Text("No results can mean no data or no read permission. Check permissions in Apple Health.")
                Text("Recomp excludes its own duplicate exports. Food logged separately in other apps may still count twice.")
            }.font(.caption).foregroundStyle(.secondary)
        } header: { Text("Apple Health") }
    }

    private func connect() {
        requesting = true
        Task {
            await diary.connectAllHealth()
            requesting = false
        }
    }
}

@MainActor
struct UsualEditor: View {
    @EnvironmentObject private var diary: DiaryStore
    @Environment(\.dismiss) private var dismiss
    let template: FoodTemplate
    @State private var name: String
    @State private var inputs: NutritionInputs
    @State private var note: String
    @FocusState private var focusedNutrient: Nutrient?

    init(template: FoodTemplate) {
        self.template = template
        _name = State(initialValue: template.name)
        _inputs = State(initialValue: NutritionInputs(template.nutrition))
        _note = State(initialValue: template.note)
    }

    private var canSave: Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 200, note.count <= 2000 else { return false }
        return inputs.parsed?.containsFood == true
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("Food name", text: $name)
                }
                Section("Nutrition") {
                    NutritionFields(inputs: $inputs, focused: $focusedNutrient)
                }
                Section("Notes") {
                    TextField("Notes or serving details", text: $note, axis: .vertical)
                        .lineLimit(2...5)
                }
                Section {
                    Button("Delete from usuals", role: .destructive) {
                        diary.removeTemplate(template.id)
                        dismiss()
                    }
                }
            }
            .instrumentForm()
            .navigationTitle("Edit usual")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if let nutrition = inputs.parsed {
                            var updated = template
                            updated.name = name
                            updated.nutrition = nutrition
                            updated.note = note
                            if diary.saveTemplate(updated) {
                                dismiss()
                            }
                        }
                    }
                    .disabled(!canSave)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        focusedNutrient = nil
                        dismissKeyboard()
                    }
                }
            }
        }
    }
}

@MainActor
struct SavedFoodsSettings: View {
    @EnvironmentObject private var diary: DiaryStore
    @State private var search = ""
    @State private var editingFood: FoodTemplate?
    private var foods: [FoodTemplate] {
        diary.state.templates.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) }
    }
    var body: some View {
        List {
            Section {
                if foods.isEmpty { Text(search.isEmpty ? "No saved foods." : "No matches.").foregroundStyle(.secondary) }
                ForEach(foods) { food in
                    Button {
                        editingFood = food
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(food.name).foregroundStyle(Theme.ink)
                                Text("\(food.nutrition.calories.wholeNumber) kcal · P \(food.nutrition.protein.wholeNumber)g · C \(food.nutrition.carbs.wholeNumber)g · F \(food.nutrition.fat.wholeNumber)g")
                                    .font(.system(.caption, design: .monospaced)).foregroundStyle(Theme.muted)
                            }
                            Spacer()
                            Image(systemName: "pencil")
                                .font(.caption)
                                .foregroundStyle(Theme.muted)
                        }.padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                    .swipeActions(edge: .trailing) {
                        Button("Remove", role: .destructive) { diary.removeTemplate(food.id) }
                    }
                    .swipeActions(edge: .leading) {
                        Button {
                            editingFood = food
                        } label: {
                            Label("Edit", systemImage: "pencil")
                        }
                        .tint(Theme.accent)
                    }
                }
            } footer: { Text("Tap any usual to edit its name, macros, or notes. Swipe left to delete.") }
        }.searchable(text: $search, prompt: "Find a food")
            .instrumentForm().navigationTitle("Your usuals").navigationBarTitleDisplayMode(.inline)
            .sheet(item: $editingFood) { food in
                UsualEditor(template: food)
            }
    }
}

struct PrivacyDetailsScreen: View {
    var body: some View {
        Form {
            Section("On this device") {
                Text("Meals, photos, scale tags and reports stay in the protected local diary. No ads or analytics.")
                Text("The diary is excluded from device backups. Save an encrypted backup before uninstalling; there is no automatic cloud restore.")
            }
            Section("Apple Health") {
                Text("Health uses your system sync settings. Pausing Recomp does not revoke permissions or remove existing exports.")
                Text("Edit or delete Recomp meals here. Deleting a Health sample does not delete its diary entry.")
            }
            Section("AI estimates") {
                Text("Only approved meal photos and details go to your selected AI connection. Health records, measurements and DEXA reports are not sent. Provider retention policies and API charges apply.")
                Text("Estimates can be wrong. Review portions and labels before saving.")
            }
            Section("Activity & maintenance") {
                Text("Workout summaries, steps and sleep are read-only. Strong sets and reps are not imported.")
                Text("Maintenance runs locally. Activity is context, not an extra calorie allowance. Targets change only after your review.")
            }
        }.instrumentForm().navigationTitle("Privacy & data").navigationBarTitleDisplayMode(.inline)
    }
}

@MainActor
struct SyncSettingsScreen: View {
    @EnvironmentObject private var diary: DiaryStore
    @StateObject private var wifiSync = WiFiSyncService()
    @State private var syncNotice: String?
    @State private var pairingCode = ""

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Label("Direct Wi-Fi Sync", systemImage: "wifi")
                            .font(.headline)
                            .foregroundStyle(Theme.ink)
                        Spacer()
                        if wifiSync.isAdvertising {
                            Text("Broadcasting")
                                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                .foregroundStyle(Color.green)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.green.opacity(0.12))
                                .clipShape(Capsule())
                        }
                    }

                    Text("Syncs meals, measurements and settings directly between your iPhone and Mac over your local Wi-Fi. No cloud account or developer subscription needed.")
                        .font(.caption)
                        .foregroundStyle(Theme.muted)

                    TextField("Pairing code", text: $pairingCode)
                        .textContentType(.none)
                        .autocorrectionDisabled()
                        .disabled(wifiSync.isPairing)
                    if wifiSync.isPairing {
                        Button("Stop pairing") { wifiSync.stop(); pairingCode = "" }
                    } else {
                        Button("Create pairing code") { pairingCode = WiFiSyncCrypto.makeCode() }
                        if !pairingCode.isEmpty {
                            ShareLink("Share pairing code", item: pairingCode)
                        }
                        Button("Start pairing") { wifiSync.start(with: diary, code: pairingCode) }
                            .disabled((try? WiFiSyncCrypto.key(for: pairingCode)) == nil)
                    }
                    Text("Create a code on one device and paste it on the other. Start pairing on both, then tap Sync Now on one. Share the code privately; anyone with it can sync while this screen is open.")
                        .font(.caption).foregroundStyle(Theme.muted)

                    if wifiSync.isPairing && wifiSync.discoveredPeers.isEmpty {
                        HStack(spacing: 8) {
                            ProgressView()
                                .controlSize(.small)
                            Text("Searching for nearby devices on Wi-Fi…")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(Theme.muted)
                        }
                        .padding(.vertical, 4)
                    } else {
                        VStack(spacing: 8) {
                            ForEach(wifiSync.discoveredPeers) { peer in
                                HStack {
                                    Image(systemName: peer.name.lowercased().contains("iphone") ? "iphone" : "laptopcomputer")
                                        .foregroundStyle(Theme.accent)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(peer.name)
                                            .font(.subheadline.weight(.semibold))
                                            .foregroundStyle(Theme.ink)
                                        Text("Available to sync")
                                            .font(.caption2)
                                            .foregroundStyle(Theme.muted)
                                    }
                                    Spacer()
                                    Button("Sync Now") {
                                        wifiSync.sync(with: peer)
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .controlSize(.small)
                                }
                                .padding(8)
                                .background(Theme.background)
                                .cornerRadius(8)
                            }
                        }
                    }

                    switch wifiSync.status {
                    case .connecting(let name):
                        Label("Connecting to \(name)…", systemImage: "arrow.triangle.2.circlepath")
                            .font(.caption).foregroundStyle(Theme.accent)
                    case .syncing(let name):
                        Label("Syncing with \(name)…", systemImage: "arrow.triangle.2.circlepath")
                            .font(.caption).foregroundStyle(Theme.accent)
                    case .success(let message):
                        Label(message, systemImage: "checkmark.circle.fill")
                            .font(.caption).foregroundStyle(Color.green)
                    case .failed(let message):
                        Label(message, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption).foregroundStyle(Color.red)
                    case .idle, .searching:
                        EmptyView()
                    }
                }
                .padding(.vertical, 4)
            } header: {
                Text("Local Wi-Fi Sync")
            } footer: {
                Text("Make sure both your Mac and iPhone have Recomp open on the same Wi-Fi network.")
            }

            Section {
                Toggle("iCloud Drive sync", isOn: Binding(
                    get: { diary.isUsingICloud },
                    set: { newValue in
                        if diary.switchToStorage(useICloud: newValue) {
                            syncNotice = newValue ? "Switched to iCloud Drive. Changes now sync between iPhone and Mac." : "Switched to local storage."
                        }
                    }
                ))
            } header: {
                Text("iCloud Storage")
            } footer: {
                Text("Stores your diary in iCloud Drive (Recomp/diary.json) on supported platforms.")
            }

            Section {
                LabeledContent("Storage location", value: diary.isUsingICloud ? "iCloud Drive" : "Local on-device")
                if let date = diary.lastLoadedModificationDate {
                    LabeledContent("Last modified", value: date.formatted(date: .abbreviated, time: .shortened))
                }
                LabeledContent("Meals logged", value: "\(diary.state.entries.count)")
                LabeledContent("Body readings", value: "\(diary.state.measurements.count)")
            } header: {
                Text("Status")
            }

            Section {
                Button {
                    diary.checkForExternalSync()
                    diary.reloadLocalFile()
                    syncNotice = "Reloaded latest data from disk."
                } label: {
                    Label("Reload from disk", systemImage: "arrow.clockwise")
                }
            } footer: {
                if let notice = syncNotice {
                    Text(notice).font(.caption).foregroundStyle(Theme.accent)
                }
            }
        }
        .instrumentForm()
        .navigationTitle("Sync & Storage")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear {
            wifiSync.stop(); pairingCode = ""
        }
    }
}
