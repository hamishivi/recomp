import SwiftUI

@MainActor
struct EstimatedFoodEditor: View {
    @Environment(\.dismiss) private var dismiss
    let original: EstimatedFood
    let onSave: (EstimatedFood, Bool) -> Void
    let onDelete: (() -> Void)?
    private let initialLock: Bool
    @State private var name: String
    @State private var portion: String
    @State private var inputs: NutritionInputs
    @State private var locked: Bool
    @State private var lockWasChosen = false
    @State private var factor = "1"
    @FocusState private var factorFocused: Bool
    @State private var overwriteFactor = false
    @State private var confirmDiscard = false
    @State private var confirmDelete = false
    @FocusState private var focusedNutrient: Nutrient?
    init(food: EstimatedFood, locked: Bool = true, onDelete: (() -> Void)? = nil,
         onSave: @escaping (EstimatedFood, Bool) -> Void) {
        original = food; self.onSave = onSave; self.onDelete = onDelete; initialLock = locked
        _name = State(initialValue: food.name); _portion = State(initialValue: food.portion)
        _inputs = State(initialValue: NutritionInputs(food.nutrition)); _locked = State(initialValue: locked)
    }
    private var changedValues: Bool { name != original.name || portion != original.portion || inputs.parsed != original.nutrition }
    private var hasChanges: Bool { changedValues || locked != initialLock }
    private var value: EstimatedFood? {
        guard let parsed = inputs.parsed else { return nil }
        var food = original
        food.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        food.portion = portion.trimmingCharacters(in: .whitespacesAndNewlines)
        food.nutrition = parsed
        if changedValues {
            food.confidence = .low; food.evidence = nil; food.assumptions = ["Manually edited."]
        }
        return food.isValid ? food : nil
    }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Food", text: $name)
                    TextField("Amount eaten, e.g. 150 g cooked rice", text: $portion, axis: .vertical)
                }
                Section("Nutrition for this amount") { NutritionFields(inputs: $inputs, focused: $focusedNutrient) }
                Section {
                    HStack {
                        TextField("1", text: Binding(
                            get: { factor },
                            set: { new in
                                let shouldOverwrite = overwriteFactor
                                overwriteFactor = false
                                factor = InputNumber.overwriteOrAppend(old: factor, new: new, shouldOverwrite: shouldOverwrite)
                            }
                        ))
                        .focused($factorFocused)
                        .keyboardType(.decimalPad).accessibilityLabel("Portion multiplier")
                        Button("Apply") {
                            if let n = InputNumber.parse(factor) { scale(n); factor = "1"; dismissKeyboard() }
                        }.disabled(InputNumber.parse(factor).flatMap { value?.scaled(by: $0) } == nil)
                    }
                    HStack {
                        Button("Half") { scale(0.5) }.buttonStyle(.bordered).disabled(value?.scaled(by: 0.5) == nil)
                        Button("Double") { scale(2) }.buttonStyle(.bordered).disabled(value?.scaled(by: 2) == nil)
                    }
                } header: {
                    Text("Portion")
                } footer: {
                    Text("Changing the description alone won’t change nutrition.")
                }
                Section {
                    Toggle("Protect from AI changes", isOn: Binding(get: { locked }, set: { locked = $0; lockWasChosen = true }))
                } footer: { Text("Manual edits are protected unless you unlock them.") }
                if let evidence = original.evidence, !evidence.isEmpty, !changedValues {
                    Section {
                        DisclosureGroup("Sources") {
                            ForEach(Array(evidence.enumerated()), id: \.offset) { _, source in
                                Text("\(source.photoNumber.map { "Photo \($0): " } ?? "")\(source.detail)").font(.footnote)
                            }
                        }
                    }
                }
                if onDelete != nil { Section { Button("Remove food", role: .destructive) { confirmDelete = true } } }
            }
            .instrumentForm()
            .navigationTitle(original.name.isEmpty ? "Add food" : "Edit food").navigationBarTitleDisplayMode(.inline)
            .onChange(of: changedValues) { _, changed in if changed && !lockWasChosen { locked = true } }
            .onChange(of: factorFocused) { _, new in overwriteFactor = new }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { if hasChanges { confirmDiscard = true } else { dismiss() } } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") { if let value { onSave(value, locked); dismiss() } }.disabled(value == nil)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        focusedNutrient = nil
                        dismissKeyboard()
                    }
                }
            }
            .interactiveDismissDisabled(hasChanges)
            .confirmationDialog("Discard changes?", isPresented: $confirmDiscard, titleVisibility: .visible) {
                Button("Discard", role: .destructive) { dismiss() }
            }
            .confirmationDialog("Remove this food?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Remove", role: .destructive) { onDelete?(); dismiss() }
            } message: { Text("Removes it from this draft. You can Undo before saving.") }
        }
    }
    private func scale(_ factor: Double) {
        guard let food = value, let scaled = food.scaled(by: factor) else { return }
        inputs = NutritionInputs(scaled.nutrition); portion = scaled.portion
    }
}
