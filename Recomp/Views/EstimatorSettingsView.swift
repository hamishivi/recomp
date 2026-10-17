import SwiftUI

@MainActor
struct EstimatorSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var configuration = EstimatorConfiguration()
    @State private var message: String?
    @State private var confirmRemove = false
    @State private var confirmTest = false
    @State private var loaded = false
    @State private var testing = false
    @State private var testTask: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            Form {
                Section("Connection") {
                    Picker("AI connection", selection: $configuration.mode) {
                        ForEach(EstimatorMode.allCases) { Text($0.title).tag($0) }
                    }
                    Text(configuration.mode == .directOpenAI ?
                        "Your iPhone calls OpenAI directly. No server, tunnel or running Mac is needed." :
                        "Advanced option: keep the OpenAI key on a server you control.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                if configuration.mode == .directOpenAI { directSection } else { serverSection }
                Section("Check the connection") {
                    Button("Test connection…") { confirmTest = true }
                        .accessibilityIdentifier("test-ai-connection")
                    Text("Sends a small synthetic food description, not your diary or photos. It is a billed API request. A successful response confirms connectivity, not nutritional accuracy. Nothing is logged.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("What leaves your phone") {
                    Text("Only the meal photos you select, the food details you type, and that meal’s current breakdown are sent after you confirm. Your Apple Health records, weight, targets, DEXA reports, activity and other diary entries are not included.")
                    Text("Photos are resized and re-encoded without original metadata. You can keep the resized photos attached to a confirmed meal; they remain in the protected local diary and encrypted backups. Photograph the food, not faces or unrelated documents.")
                    Text("Requests use store=false. That disables response storage but does not guarantee zero provider retention. Internet access and separate API billing are required. Manual entry and Health sync do not require AI.")
                    Text("Credentials stay in this app’s device-only Keychain, not diary backups, widgets or the project. Keychain data can survive reinstalling. Forgetting a key here does not revoke it at OpenAI; revoke it in your API account if lost or exposed.")
                }.font(.footnote)
                Section {
                    Button("Forget AI settings", role: .destructive) { confirmRemove = true }
                }
                if !loaded {
                    Section { Button("Retry loading secure settings") { load() } }
                }
            }
            .disabled(testing)
            .instrumentForm()
            .navigationTitle("Photo & text estimates").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { testTask?.cancel(); dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        do { try EstimatorKeychain.save(configuration); dismiss() }
                        catch { message = error.localizedDescription }
                    }.disabled(!loaded || testing)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { dismissKeyboard() }
                }
            }
            .overlay { if testing { ProgressView("Testing AI connection…").padding().background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12)) } }
            .task { if !loaded { load() } }
            .onDisappear {
                testTask?.cancel(); testTask = nil
                configuration.apiKey = ""; configuration.accessToken = ""
                loaded = false // Reload Keychain if navigation later shows this view again.
            }
            .alert("Estimator settings", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
                Button("OK", role: .cancel) { message = nil }
            } message: { Text(message ?? "") }
            .confirmationDialog("Forget the saved AI connection and credential?", isPresented: $confirmRemove, titleVisibility: .visible) {
                Button("Forget settings", role: .destructive) {
                    do { try EstimatorKeychain.remove(); configuration = EstimatorConfiguration(); loaded = true }
                    catch { message = error.localizedDescription }
                }
            } message: { Text("This removes settings from this phone. It does not revoke API keys, stop requests already accepted, or delete meals.") }
            .confirmationDialog("Send a small billed test request?", isPresented: $confirmTest, titleVisibility: .visible) {
                Button("Send test request") { testConnection() }
                Button("Cancel", role: .cancel) { }
            } message: { Text("The test sends ‘One large egg, no added oil’ to \(configuration.destinationDescription). No personal records are read or sent.") }
        }
    }

    private var directSection: some View {
        Section("Personal API key") {
            SecureField("OpenAI API key", text: $configuration.apiKey)
                .textInputAutocapitalization(.never).autocorrectionDisabled().privacySensitive()
                .accessibilityIdentifier("openai-api-key")
            Picker("Model", selection: $configuration.model) {
                ForEach(DirectAIModel.allCases) { Text($0.title).tag($0) }
            }
            if configuration.model.supportsReasoning {
                Picker("Reasoning", selection: $configuration.reasoningEffort) {
                    ForEach(ReasoningEffort.allCases) { Text($0.title).tag($0) }
                }
                Text("Allows the model to reason through portion volume, hidden oils, food density, and ingredient breakdown before formulating the estimate.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Text("Create a dedicated key in your own OpenAI API project. API billing is separate from ChatGPT. Configure usage alerts and an enforced spend limit where your account supports it; an alert alone does not stop spending. Requests are never automatically retried.")
                .font(.footnote)
            Toggle("I understand the personal-key risk and separate API charges", isOn: $configuration.personalKeyAcknowledged)
            Text("OpenAI recommends keeping API keys on a backend, not in mobile apps. This direct mode is an explicit trade-off for your privately installed app. Keychain reduces exposure at rest but cannot make a key in a compromised app/device secret. Never bundle a shared key in an app you distribute.")
                .font(.caption).foregroundStyle(.secondary)
            Link("OpenAI API-key safety guidance", destination: URL(string: "https://help.openai.com/en/articles/5112595-best-practices-for-api-key-safety")!)
                .font(.footnote)
        }
    }
    private var serverSection: some View {
        Section("Optional server") {
            TextField("https://your-estimator.example", text: $configuration.baseURL)
                .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                .accessibilityLabel("Estimation server URL")
            SecureField("Server access token", text: $configuration.accessToken)
                .textInputAutocapitalization(.never).autocorrectionDisabled().privacySensitive()
            Text("Use RECOMP_ACCESS_TOKEN here, not an OpenAI API key. Enter the base HTTPS address without /v1/estimate. The optional Server folder and PHOTO-SETUP.md document deployment. Saving a different connection removes the inactive credential from this Keychain item.")
                .font(.caption).foregroundStyle(.secondary)
            if EstimatorConfiguration.allowLocalHTTP {
                Text("Debug simulator only: http://localhost:8787 is allowed. A real iPhone requires HTTPS.").font(.caption)
            }
        }
    }
    private func load() {
        do { configuration = try EstimatorKeychain.load(); loaded = true }
        catch { loaded = false; message = error.localizedDescription }
    }
    private func testConnection() {
        guard loaded, !testing else { return }
        do {
            let config = try configuration.normalizedForSaving()
            testing = true
            testTask = Task {
                defer { testing = false; testTask = nil }
                do {
                    let input = EstimateRequest(description: "One large egg, no added oil", clarification: "", images: [], currentEstimate: nil, lockedItemIDs: [], excludedFoods: [])
                    _ = try await EstimationService.estimate(input, configuration: config)
                    try Task.checkCancellation()
                    message = "Connection worked. A valid estimate response was received; no food was logged. Tap Save to keep these settings."
                } catch {
                    if !Task.isCancelled { message = error.localizedDescription }
                }
            }
        } catch { message = error.localizedDescription }
    }
}
