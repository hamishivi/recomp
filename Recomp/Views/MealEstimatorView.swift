import SwiftUI
import PhotosUI
import AVFoundation

private enum FoodSheet: Identifiable {
    case settings, usuals, mealHistory, ingredient(EstimatedFood), photo(MealPhoto)
    var id: String {
        switch self {
        case .settings: return "settings"
        case .usuals: return "usuals"
        case .mealHistory: return "mealHistory"
        case .ingredient(let food): return "food:" + food.id
        case .photo(let photo): return "photo:" + photo.id.uuidString
        }
    }
}

/// One draft, one Save. Photos, manual values and AI are inputs, not different logging modes.
@MainActor
struct MealEstimatorView: View {
    @EnvironmentObject private var diary: DiaryStore
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model: MealEstimatorModel
    @State private var inputs: NutritionInputs
    @State private var selectedPhotos: [PhotosPickerItem] = []
    @State private var importTask: Task<Void, Never>?
    @State private var photoImport = PhotoImportSession()
    @State private var mode: MealEntryMode
    @State private var camera = false
    @State private var sheet: FoodSheet?
    @State private var confirmUpload = false
    @State private var confirmDiscard = false
    @State private var confirmDelete = false
    @State private var uploadConfiguration: EstimatorConfiguration?
    @State private var cameraDenied = false
    @State private var saved = false
    @State private var initializedZone = false
    @FocusState private var focusedNutrient: Nutrient?
    var onSaved: (() -> Void)?

    init(date: Date, entry: FoodEntry? = nil, seed: FoodEntry? = nil,
         mode: MealEntryMode = .log, onSaved: (() -> Void)? = nil) {
        _mode = State(initialValue: entry == nil ? mode : .log)
        _model = StateObject(wrappedValue: MealEstimatorModel(date: date, original: entry, seed: seed))
        _inputs = State(initialValue: NutritionInputs((entry ?? seed)?.nutrition ?? .zero))
        self.onSaved = onSaved
    }
    private var importing: Bool { photoImport.isActive }
    private var nutritionBinding: Binding<NutritionInputs> {
        Binding(get: { inputs }, set: { value in inputs = value; model.setManualTotal(value.parsed) })
    }
    private var readyToSave: Bool {
        model.canSave && inputs.parsed == model.total && !importing && !saved && diary.loadFailure == nil
    }
    var body: some View {
        NavigationStack {
            Form {
                foodSection
                photoSection
                estimateSection
                nutritionSection
                breakdownSection
                if mode == .check { checkSection } else { loggingSection }
            }
            .onAppear {
                if !initializedZone {
                    initializedZone = true
                    if !model.isExistingMeal { model.zoneID = diary.defaultEntryZone }
                }
            }
            .onChange(of: model.inputRevision) { _, _ in inputs = NutritionInputs(model.total) }
            .instrumentForm()
            .navigationTitle(mode == .check ? "Check food" : model.original == nil ? "Log food" : "Edit food")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(mode == .check ? "Close" : "Cancel") {
                        if model.hasChanges || importing { confirmDiscard = true } else { dismiss() }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if !model.history.isEmpty {
                        Button { model.undo() } label: { Image(systemName: "arrow.uturn.backward") }
                            .accessibilityLabel(model.undoTitle).accessibilityIdentifier("food.undo")
                            .help(model.undoTitle).disabled(model.busy || importing)
                            .keyboardShortcut("z", modifiers: .command)
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if mode == .log {
                        Button("Save") { save() }.disabled(!readyToSave).accessibilityIdentifier("food.save")
                    }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        focusedNutrient = nil
                        dismissKeyboard()
                    }
                }
            }
            .interactiveDismissDisabled(model.hasChanges || model.busy || importing)
            .onDisappear { model.cancelRequest(); cancelPhotoImport(); uploadConfiguration = nil }
            .sheet(item: $sheet) { destination in
                switch destination {
                case .settings: EstimatorSettingsView()
                case .usuals:
                    SavedFoodPicker(replacing: model.total.containsFood) { model.useTemplate($0) }
                case .mealHistory:
                    FoodHistoryPicker(replacing: model.total.containsFood, excludingID: model.original?.id) {
                        model.useHistoricalFood($0)
                    }
                case .ingredient(let food):
                    EstimatedFoodEditor(food: food, locked: model.editorLock(for: food),
                        onDelete: ingredientRemoval(for: food)
                    ) { value, locked in model.edit(value, locked: locked) }
                case .photo(let photo):
                    MealPhotoDetails(photo: photo, onDelete: { model.photos.removeAll { $0.id == photo.id } }) { value in
                        if let index = model.photos.firstIndex(where: { $0.id == value.id }) { model.photos[index] = value }
                    }
                }
            }
            .fullScreenCover(isPresented: $camera) {
                MealCameraPicker(onPhoto: { image in
                    camera = false
                    do { if model.photos.count < MealPhoto.maximumCount { model.photos.append(try MealPhotoPreparation.from(image: image)) } }
                    catch { model.error = error.localizedDescription }
                }, onCancel: { camera = false }).ignoresSafeArea()
            }
            .onChange(of: selectedPhotos) { _, items in if !items.isEmpty { importPhotos(items) } }
            .confirmationDialog("Send to AI?", isPresented: $confirmUpload, titleVisibility: .visible) {
                Button("Estimate") {
                    if let configuration = uploadConfiguration { model.begin(configuration: configuration) }
                    uploadConfiguration = nil
                }
                Button("Cancel", role: .cancel) { uploadConfiguration = nil }
            } message: {
                Text("Send \(model.photos.count) photos and this meal’s details to \(uploadConfiguration?.destinationDescription ?? "your AI connection"). No Health records or other meals are sent. API charges and provider retention policies apply.")
            }
            .confirmationDialog("Discard changes?", isPresented: $confirmDiscard, titleVisibility: .visible) {
                Button("Discard", role: .destructive) { model.cancelRequest(); cancelPhotoImport(); dismiss() }
            } message: { Text("Unsaved food and photos will be discarded.") }
            .alert("Couldn’t complete", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
                Button("OK", role: .cancel) { model.error = nil }
            } message: { Text(model.error ?? "") }
            .confirmationDialog("Delete this food?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    guard mode == .log, let original = model.original else { return }
                    diary.removeEntry(original.id)
                    if let error = diary.errorMessage { model.error = error; diary.errorMessage = nil }
                    else { dismiss(); onSaved?() }
                }
            } message: { Text("This entry and its Recomp Health exports will be removed.") }
            .alert("Camera access is off", isPresented: $cameraDenied) {
                Button("Open Settings") { if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) } }
                Button("Cancel", role: .cancel) { }
            } message: { Text("Allow camera access in Settings, or choose a photo.") }
        }
    }
    private var foodSection: some View {
        Section {
            TextField("Food or meal", text: Binding(get: { model.foodName }, set: { model.rename($0) }))
                .accessibilityIdentifier("food.name").disabled(model.busy)
            Button { sheet = .usuals } label: { Label("Your usuals", systemImage: "bookmark") }
                .accessibilityIdentifier("food.usuals").disabled(model.busy || importing)
            Button { sheet = .mealHistory } label: { Label("Meal history", systemImage: "clock.arrow.circlepath") }
                .accessibilityIdentifier("food.history").disabled(model.busy || importing)
        }
    }
    private var photoSection: some View {
        Section {
            if !model.photos.isEmpty {
                ScrollView(.horizontal) {
                    HStack(alignment: .top, spacing: 12) {
                        ForEach(Array(model.photos.enumerated()), id: \.element.id) { index, photo in
                            MealPhotoTile(photo: photo, number: index + 1, onOpen: { sheet = .photo(photo) },
                                          onRemove: { model.photos.removeAll { $0.id == photo.id } })
                        }
                    }.padding(.vertical, 4)
                }.disabled(model.busy || importing)
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) { photoButtons }
                VStack(alignment: .leading, spacing: 8) { photoButtons }
            }.disabled(model.busy || importing || model.photos.count >= MealPhoto.maximumCount)
            if importing { ProgressView("Preparing photos…") }
        } header: { Text(model.photos.isEmpty ? "Photos" : "Photos · \(model.photos.count) of 6") }
    }
    @ViewBuilder private var photoButtons: some View {
        Button { requestCamera() } label: { Label("Camera", systemImage: "camera") }
            .buttonStyle(.bordered).accessibilityIdentifier("food.camera")
        PhotosPicker(selection: $selectedPhotos, maxSelectionCount: max(1, MealPhoto.maximumCount - model.photos.count), selectionBehavior: .ordered, matching: .images, photoLibrary: .shared()) {
            Label("Photo library", systemImage: "photo.on.rectangle")
        }.buttonStyle(.bordered).accessibilityIdentifier("food.photos")
    }
    private var estimateSection: some View {
        Section {
            if model.canPrepareExistingEntryRefinement {
                Button { model.prepareExistingEntryRefinement() } label: {
                    Label("Refine saved entry with AI", systemImage: "sparkles")
                }.buttonStyle(.bordered).accessibilityIdentifier("food.prepareRefinement")
            }
            if model.draft == nil {
                TextField("Portions, brands, cooking details…", text: $model.description, axis: .vertical)
                    .lineLimit(1...4).disabled(model.busy).accessibilityIdentifier("food.description")
            } else if let question = model.followUpQuestion {
                LabeledContent("One question") {
                    Text(question).multilineTextAlignment(.trailing)
                }
                TextField("Short answer", text: $model.clarification)
                    .lineLimit(1).disabled(model.busy).accessibilityIdentifier("food.answer")
                if model.clarification.count > model.answerLimit {
                    Text("Keep the answer under \(model.answerLimit) characters.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            } else {
                TextField("Add details or corrections…", text: $model.clarification, axis: .vertical)
                    .lineLimit(1...4).disabled(model.busy).accessibilityIdentifier("food.description")
            }
            if model.busy {
                HStack { ProgressView("Estimating…"); Spacer(); Button("Cancel") { model.cancelRequest() } }
            } else {
                HStack {
                    Button { prepareUpload() } label: {
                        Label(model.draft == nil ? "Estimate nutrition" :
                                (model.followUpQuestion == nil ? (model.isExistingMeal ? "Refine estimate" : "Update estimate") : "Answer"), systemImage: "viewfinder")
                    }.disabled(!model.canRequest || importing || inputs.parsed != model.total).accessibilityIdentifier("food.estimate")
                    Spacer()
                    Button { sheet = .settings } label: { Image(systemName: "gearshape").frame(minWidth: 44, minHeight: 44) }
                        .accessibilityLabel("AI settings").buttonStyle(.borderless)
                }
            }
        } footer: {
            if model.followUpQuestion != nil { Text("Answer briefly. The next estimate may ask one more question only if it would materially improve calories.") }
            else if model.canPrepareExistingEntryRefinement { Text("Your saved values are protected. Choose Refine saved entry with AI, add a short correction, then review and Save the result.") }
            else if model.hasLockedFoods { Text("Locked values won’t change. Unlock them in Breakdown.") }
            else { Text("Optional. Enter values below or approve an AI estimate.") }
        }
    }
    private var nutritionSection: some View {
        Section {
            NutritionFields(inputs: nutritionBinding, onEditingEnded: { model.finishManualEditing() }, focused: $focusedNutrient)
                .disabled(model.busy || importing)
            if model.total.containsFood {
                HStack {
                    Button("Half") { model.scalePortion(by: 0.5) }.buttonStyle(.bordered).disabled(!model.canScale(by: 0.5))
                        .accessibilityIdentifier("food.half")
                    Button("Double") { model.scalePortion(by: 2) }.buttonStyle(.bordered).disabled(!model.canScale(by: 2))
                        .accessibilityIdentifier("food.double")
                }.disabled(importing)
            }
            if !model.manualInputValid {
                Text("Use a decimal point or comma, without thousands separators.").font(.caption).foregroundStyle(.secondary)
            }
        } header: { Text("Nutrition · amount eaten") }
    }
    @ViewBuilder private var breakdownSection: some View {
        if let draft = model.draft {
            Section {
                DisclosureGroup("Breakdown · \(draft.estimate.items.count)") { foodBreakdown(draft) }
                    .accessibilityIdentifier("food.breakdown")
                ForEach(Array(draft.estimate.nutritionReviewWarnings.enumerated()), id: \.offset) { _, warning in
                    Notice(text: warning, symbol: "exclamationmark.circle")
                }
                if !draft.estimate.assumptions.isEmpty {
                    DisclosureGroup("Assumptions") {
                        ForEach(Array(draft.estimate.assumptions.enumerated()), id: \.offset) { _, text in Text(text).font(.footnote) }
                    }
                }
            }
        }
    }
    @ViewBuilder private func foodBreakdown(_ draft: EstimateDraft) -> some View {
        ForEach(draft.estimate.items) { food in
            HStack(alignment: .top, spacing: 12) {
                Button { sheet = .ingredient(food) } label: {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(food.name).foregroundStyle(Theme.ink)
                        Text(food.portion).font(.caption).foregroundStyle(Theme.muted)
                        Text("\(food.nutrition.calories.wholeNumber) kcal · \(food.nutrition.protein.displayNumber) g protein")
                            .font(.system(.caption, design: .monospaced)).foregroundStyle(Theme.muted)
                    }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityHint("Edit values, see sources or remove")
                Button { model.toggleLock(food.id) } label: {
                    Image(systemName: draft.lockedItemIDs.contains(food.id) ? "lock.fill" : "lock.open")
                        .frame(minWidth: 44, minHeight: 44)
                }.buttonStyle(.borderless)
                    .accessibilityLabel(draft.lockedItemIDs.contains(food.id) ? "Unlock \(food.name) for AI edits" : "Protect \(food.name) from AI edits")
            }.padding(.vertical, 6).disabled(model.busy || importing)
        }
        Button("Add food") { sheet = .ingredient(model.addBlankFood()) }
            .disabled(model.busy || importing || draft.estimate.items.count >= 15)
    }
    private var checkSection: some View {
        let projection = FoodCheckProjection(current: diary.total, candidate: model.total, targets: diary.state.targets)
        return Section {
            if inputs.parsed?.containsFood == true {
                ForEach(Nutrient.allCases) { nutrient in
                    LabeledContent(nutrient.title, value: "\(projection.current[nutrient].displayNumber) → \(projection.projected[nutrient].displayNumber) \(nutrient.unit)")
                }
                Button("Log this food…") { mode = .log }.disabled(!model.canSave || importing)
                    .accessibilityIdentifier("food.useCheck")
            }
        } header: { Text("With this food") }
          footer: { Text("Not logged. Close to discard, or Log this food to save.") }
    }
    private var loggingSection: some View {
        Section {
            Picker("Meal", selection: $model.meal) { ForEach(MealKind.allCases) { Text($0.rawValue).tag($0) } }
                // Avoid the Form's navigation-link picker, which restores its
                // scroll position to the top after a meal is selected.
                .pickerStyle(.menu)
            EntryTimeFields(date: $model.date, zoneID: $model.zoneID, confirmedZone: $model.confirmedZone, legacy: model.timezoneNeedsReview)
            Toggle(isOn: $model.makeTemplate) {
                Label("Save as a usual", systemImage: "bookmark")
            }
            DisclosureGroup("More options") {
                TextField("Notes", text: $model.note, axis: .vertical).lineLimit(1...4)
                if !model.photos.isEmpty { Toggle("Keep photos attached", isOn: $model.keepPhotos) }
                if model.original != nil { Button("Delete food", role: .destructive) { confirmDelete = true } }
            }
            if model.total.containsFood, let issue = model.saveIssue { Notice(text: issue, symbol: "exclamationmark.circle") }
        } header: { Text("Details") }
          footer: { Text(diary.state.healthEnabled ? "Save syncs calories and macros to Apple Health. Photos stay here." : "Saved locally. Connect Apple Health in Settings to sync.") }
          .disabled(model.busy || importing)
    }
    private func ingredientRemoval(for food: EstimatedFood) -> (() -> Void)? {
        guard model.draft?.estimate.items.contains(where: { $0.id == food.id }) == true else { return nil }
        return { model.remove(food.id) }
    }
    private func prepareUpload() {
        guard inputs.parsed == model.total, !importing else { return }
        model.finishManualEditing()
        do { let config = try EstimatorKeychain.load(); _ = try config.endpoint(); uploadConfiguration = config; confirmUpload = true }
        catch { model.error = error.localizedDescription }
    }
    private func requestCamera() {
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            model.error = "No camera available. Choose a photo instead."; return
        }
        Task {
            switch AVCaptureDevice.authorizationStatus(for: .video) {
            case .authorized: camera = true
            case .notDetermined:
                if await AVCaptureDevice.requestAccess(for: .video) { camera = true } else { cameraDenied = true }
            default: cameraDenied = true
            }
        }
    }
    private func importPhotos(_ items: [PhotosPickerItem]) {
        importTask?.cancel()
        let ticket = photoImport.begin()
        let available = max(0, MealPhoto.maximumCount - model.photos.count)
        importTask = Task {
            defer {
                if photoImport.finish(ticket) { selectedPhotos = []; importTask = nil }
            }
            do {
                var prepared: [MealPhoto] = []
                for item in items.prefix(available) {
                    try Task.checkCancellation()
                    guard let data = try await item.loadTransferable(type: Data.self) else { throw EstimateError.imageTooLarge }
                    try Task.checkCancellation()
                    prepared.append(try MealPhotoPreparation.from(data: data))
                }
                try Task.checkCancellation()
                guard photoImport.accepts(ticket), !model.busy else { return }
                model.photos.append(contentsOf: prepared)
            } catch is CancellationError { }
            catch { if photoImport.accepts(ticket) { model.error = error.localizedDescription } }
        }
    }
    private func cancelPhotoImport() {
        photoImport.cancel(); importTask?.cancel(); importTask = nil; selectedPhotos = []
    }
    private func save() {
        guard mode == .log, !saved, !importing else { return }
        model.setManualTotal(inputs.parsed)
        guard let entry = model.entry() else { model.error = model.saveIssue; return }
        // A no-op Save should not invalidate a completed day or queue Health replacements.
        if model.isExistingMeal && !model.hasChanges { dismiss(); return }
        saved = true
        if diary.saveEntry(entry, makeTemplate: model.makeTemplate) { dismiss(); onSaved?() }
        else { saved = false; model.error = diary.errorMessage; diary.errorMessage = nil }
    }
}

/// Keep the decoded thumbnail while its row identity survives; typing nutrition or notes
/// should not decode six JPEGs again. ImageIO preparation still runs only on import.
@MainActor
private struct MealPhotoTile: View {
    let photo: MealPhoto
    let number: Int
    let onOpen: () -> Void
    let onRemove: () -> Void
    @State private var image: UIImage?
    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 5) {
                Group {
                    if let image { Image(uiImage: image).resizable().scaledToFill() }
                    else { Rectangle().fill(Theme.rule).overlay { Image(systemName: "photo").foregroundStyle(Theme.muted) } }
                }.frame(width: 88, height: 88).clipped().clipShape(RoundedRectangle(cornerRadius: 8))
                Text("\(number) · \(photo.role.title)").font(.caption).foregroundStyle(Theme.muted)
                    .lineLimit(2).frame(width: 88, alignment: .leading)
            }
        }.buttonStyle(.plain).accessibilityLabel("Photo \(number), \(photo.role.title)")
            .accessibilityHint("Edit photo details or remove")
            .contextMenu { Button("Remove photo", role: .destructive, action: onRemove) }
            .task(id: photo.id) { image = UIImage(data: photo.jpeg) }
            .onChange(of: photo.jpeg) { _, data in image = UIImage(data: data) }
    }
}

@MainActor
private struct MealPhotoDetails: View {
    @Environment(\.dismiss) private var dismiss
    let original: MealPhoto
    let onDelete: () -> Void
    let onSave: (MealPhoto) -> Void
    @State private var photo: MealPhoto
    @State private var discard = false
    init(photo: MealPhoto, onDelete: @escaping () -> Void, onSave: @escaping (MealPhoto) -> Void) {
        original = photo; self.onDelete = onDelete; self.onSave = onSave
        _photo = State(initialValue: photo)
    }
    var body: some View {
        NavigationStack {
            Form {
                if let image = UIImage(data: photo.jpeg) {
                    Section { Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 280).frame(maxWidth: .infinity) }
                }
                Section {
                    Picker("Shows", selection: $photo.role) { ForEach(MealPhotoRole.allCases) { Text($0.title).tag($0) } }
                    TextField("What should we know?", text: $photo.caption, axis: .vertical).lineLimit(2...4)
                } footer: { Text("For example: half the packet, or the same plate from another angle.") }
                Section { Button("Remove photo", role: .destructive) { onDelete(); dismiss() } }
            }.instrumentForm().navigationTitle("Photo details").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { if photo != original { discard = true } else { dismiss() } } }
                    ToolbarItem(placement: .confirmationAction) { Button("Done") { onSave(photo); dismiss() }.disabled(!photo.isValid) }
                    ToolbarItemGroup(placement: .keyboard) {
                        Spacer()
                        Button("Done") { dismissKeyboard() }
                    }
                }
                .interactiveDismissDisabled(photo != original)
                .confirmationDialog("Discard changes?", isPresented: $discard, titleVisibility: .visible) {
                    Button("Discard", role: .destructive) { dismiss() }
                }
        }
    }
}

@MainActor
struct SavedFoodPicker: View {
    @EnvironmentObject private var diary: DiaryStore
    @Environment(\.dismiss) private var dismiss
    let replacing: Bool
    let onSelect: (FoodTemplate) -> Void
    @State private var search = ""
    @State private var pending: FoodTemplate?
    @State private var editingUsual: FoodTemplate?
    private var foods: [FoodTemplate] {
        diary.state.templates.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) }
    }
    var body: some View {
        NavigationStack {
            List {
                if foods.isEmpty { Text(search.isEmpty ? "No saved foods." : "No matches.").foregroundStyle(.secondary) }
                ForEach(foods) { food in
                    Button {
                        if replacing { pending = food } else { choose(food) }
                    } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(food.name).foregroundStyle(Theme.ink)
                            Text("\(food.nutrition.calories.wholeNumber) kcal · \(food.nutrition.protein.wholeNumber) g protein")
                                .font(.caption).foregroundStyle(.secondary)
                        }.padding(.vertical, 4)
                    }.accessibilityIdentifier("food.savedChoice")
                    .swipeActions(edge: .leading) {
                        Button {
                            editingUsual = food
                        } label: {
                            Label("Edit", systemImage: "pencil")
                        }
                        .tint(Theme.accent)
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            diary.removeTemplate(food.id)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }.searchable(text: $search, prompt: "Find a food")
                .instrumentForm().navigationTitle("Your usuals").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
                .confirmationDialog("Replace the current food?", isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }), titleVisibility: .visible) {
                    Button("Replace") { if let food = pending { choose(food) }; pending = nil }
                    Button("Cancel", role: .cancel) { pending = nil }
                } message: { Text("The food and nutrition will change. Photos, time and notes will stay.") }
                .sheet(item: $editingUsual) { food in
                    UsualEditor(template: food)
                }
        }
    }
    private func choose(_ food: FoodTemplate) { onSelect(food); dismiss() }
}

@MainActor
struct FoodHistoryPicker: View {
    @EnvironmentObject private var diary: DiaryStore
    @Environment(\.dismiss) private var dismiss
    let replacing: Bool
    let excludingID: UUID?
    let onSelect: (FoodEntry) -> Void
    @State private var search = ""
    @State private var pending: FoodEntry?

    var body: some View {
        let meals = DiaryMath.foodHistory(in: diary.state.entries, query: search,
            excludingID: excludingID, deletedIDs: diary.state.deletedIDs("food"))
        NavigationStack {
            List {
                if !meals.isEmpty {
                    Section {
                        ForEach(meals) { entry in
                            Button {
                                if replacing { pending = entry } else { choose(entry) }
                            } label: {
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(entry.name).foregroundStyle(Theme.ink)
                                    Text(EntryClock.label(date: entry.date, clock: entry.clock))
                                        .font(.caption).foregroundStyle(Theme.muted)
                                    Text("\(entry.meal.rawValue) · \(entry.nutrition.calories.wholeNumber) kcal · \(entry.nutrition.protein.wholeNumber) g protein\(entry.isEstimate ? " · Estimated" : "")")
                                        .font(.caption).foregroundStyle(Theme.muted)
                                    if !entry.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                        Text(entry.note).font(.caption).foregroundStyle(Theme.muted).lineLimit(2)
                                    }
                                }.padding(.vertical, 4)
                            }.accessibilityIdentifier("food.historyChoice")
                        }
                    } header: {
                        Text("Newest first")
                    } footer: {
                        Text("Choose a meal to fill your draft, then review the serving and save. Your usuals stay separate.")
                    }
                }
            }
            .overlay {
                if meals.isEmpty {
                    if search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        ContentUnavailableView(excludingID == nil ? "No meal history yet" : "No other meals yet", systemImage: "clock.arrow.circlepath",
                            description: Text("Meals you log appear here so you can use them again, separate from your usuals."))
                    } else {
                        ContentUnavailableView.search(text: search)
                    }
                }
            }
            .searchable(text: $search, prompt: "Names, ingredients, notes")
            .instrumentForm().navigationTitle("Meal history").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .confirmationDialog("Replace the current food?", isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }), titleVisibility: .visible) {
                Button("Replace") { if let entry = pending { choose(entry) }; pending = nil }
                Button("Cancel", role: .cancel) { pending = nil }
            } message: {
                Text("The food and nutrition will change. Photos, time and notes will stay. The previous meal won’t change.")
            }
        }
    }
    private func choose(_ entry: FoodEntry) { onSelect(entry); dismiss() }
}
