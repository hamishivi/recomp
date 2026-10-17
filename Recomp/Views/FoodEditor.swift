import SwiftUI

/// All entry points share the same food form. A shortcut is a new entry, not an edit.
@MainActor
struct FoodEditor: View {
    let entry: FoodEntry
    var isEditing = false
    var body: some View {
        MealEstimatorView(date: entry.date, entry: isEditing ? entry : nil,
                          seed: isEditing ? nil : entry)
    }
}

@MainActor
struct GoalsEditor: View {
    @EnvironmentObject private var diary: DiaryStore
    @Environment(\.dismiss) private var dismiss
    @State private var inputs: NutritionInputs
    @State private var saveError: String?
    @FocusState private var focusedNutrient: Nutrient?

    // Target estimation state
    @State private var selectedGoal: FitnessGoal = .recomp
    @State private var weightInput: String = ""
    @State private var showEstimateSuccess: Bool = false

    init(targets: Nutrition) { _inputs = State(initialValue: NutritionInputs(targets)) }

    private var parsedWeightKG: Double {
        let val = InputNumber.parse(weightInput) ?? 75.0
        return diary.state.measurementUnits.canonical(val, metric: .weight)
    }

    private var estimatedTargets: Nutrition {
        let kg = max(35, min(250, parsedWeightKG))
        // Protein aims for 2.0g per kg of body weight
        let protein = max(60, min(350, ((kg * 2.0) / 5).rounded() * 5))
        // Fat aims for ~0.8g per kg, clamped between 45 and 110g
        let fat = max(45, min(110, ((kg * 0.8) / 5).rounded() * 5))

        // Baseline maintenance calories
        let baselineMaintenance: Double
        if let estimate = diary.maintenanceReport.estimate, estimate.isFinite, (1500...4500).contains(estimate) {
            baselineMaintenance = estimate
        } else {
            baselineMaintenance = max(1600, min(4500, (kg * 33.0 / 50).rounded() * 50))
        }

        // Adjust for fitness goal
        let targetCalories: Double
        switch selectedGoal {
        case .recomp:
            targetCalories = (baselineMaintenance / 50).rounded() * 50
        case .gentleLoss:
            targetCalories = max(1400, ((baselineMaintenance - 400) / 50).rounded() * 50)
        case .maintain:
            targetCalories = (baselineMaintenance / 50).rounded() * 50
        case .slowGain:
            targetCalories = min(5000, ((baselineMaintenance + 250) / 50).rounded() * 50)
        }

        // Carbs take the remaining calorie balance: (Calories - 4*P - 9*F) / 4
        let remainingForCarbs = max(200, targetCalories - (protein * 4) - (fat * 9))
        let carbs = max(50, ((remainingForCarbs / 4) / 5).rounded() * 5)

        return Nutrition(calories: targetCalories, protein: protein, carbs: carbs, fat: fat)
    }

    private func applyEstimate() {
        let est = estimatedTargets
        inputs = NutritionInputs(est)
        focusedNutrient = nil
        dismissKeyboard()
        withAnimation { showEstimateSuccess = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            showEstimateSuccess = false
        }
    }

    private func adjust(_ nutrient: Nutrient, by delta: Double) {
        let current = Double(inputs[nutrient]) ?? inputs.parsed?[nutrient] ?? 0
        let new = max(0, current + delta)
        inputs[nutrient] = InputNumber.editString(new)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Daily targets") {
                    NutritionFields(inputs: $inputs, focused: $focusedNutrient)
                }

                Section("Quick adjust") {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Calories")
                                .font(.subheadline).foregroundStyle(Theme.ink)
                            Spacer()
                            Button("-100") { adjust(.calories, by: -100) }.buttonStyle(.bordered).controlSize(.small)
                            Button("-50") { adjust(.calories, by: -50) }.buttonStyle(.bordered).controlSize(.small)
                            Button("+50") { adjust(.calories, by: 50) }.buttonStyle(.bordered).controlSize(.small)
                            Button("+100") { adjust(.calories, by: 100) }.buttonStyle(.bordered).controlSize(.small)
                        }
                        Divider()
                        HStack {
                            Text("Protein")
                                .font(.subheadline).foregroundStyle(Theme.ink)
                            Spacer()
                            Button("-10g") { adjust(.protein, by: -10) }.buttonStyle(.bordered).controlSize(.small)
                            Button("-5g") { adjust(.protein, by: -5) }.buttonStyle(.bordered).controlSize(.small)
                            Button("+5g") { adjust(.protein, by: 5) }.buttonStyle(.bordered).controlSize(.small)
                            Button("+10g") { adjust(.protein, by: 10) }.buttonStyle(.bordered).controlSize(.small)
                        }
                        Divider()
                        HStack {
                            Text("Carbs")
                                .font(.subheadline).foregroundStyle(Theme.ink)
                            Spacer()
                            Button("-20g") { adjust(.carbs, by: -20) }.buttonStyle(.bordered).controlSize(.small)
                            Button("-10g") { adjust(.carbs, by: -10) }.buttonStyle(.bordered).controlSize(.small)
                            Button("+10g") { adjust(.carbs, by: 10) }.buttonStyle(.bordered).controlSize(.small)
                            Button("+20g") { adjust(.carbs, by: 20) }.buttonStyle(.bordered).controlSize(.small)
                        }
                        Divider()
                        HStack {
                            Text("Fat")
                                .font(.subheadline).foregroundStyle(Theme.ink)
                            Spacer()
                            Button("-10g") { adjust(.fat, by: -10) }.buttonStyle(.bordered).controlSize(.small)
                            Button("-5g") { adjust(.fat, by: -5) }.buttonStyle(.bordered).controlSize(.small)
                            Button("+5g") { adjust(.fat, by: 5) }.buttonStyle(.bordered).controlSize(.small)
                            Button("+10g") { adjust(.fat, by: 10) }.buttonStyle(.bordered).controlSize(.small)
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section("Estimate targets (2g/kg protein)") {
                    Picker("Goal", selection: $selectedGoal) {
                        ForEach(FitnessGoal.allCases) { Text($0.title).tag($0) }
                    }
                    HStack {
                        Text("Body weight")
                        Spacer()
                        TextField("Weight", text: $weightInput)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 90)
                        Text(diary.state.measurementUnits.unit(for: .weight))
                            .foregroundStyle(.secondary)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Calculated: \(estimatedTargets.calories.wholeNumber) kcal · \(estimatedTargets.protein.wholeNumber)g P · \(estimatedTargets.carbs.wholeNumber)g C · \(estimatedTargets.fat.wholeNumber)g F")
                            .font(.system(.footnote, design: .monospaced))
                            .foregroundStyle(Theme.ink)
                        Text("• Protein: exactly 2.0 g/kg body weight\n• Fat: ~0.8 g/kg body weight\n• Carbs: fills remaining energy balance")
                            .font(.caption)
                            .foregroundStyle(Theme.muted)
                    }
                    .padding(.vertical, 2)
                    Button {
                        applyEstimate()
                    } label: {
                        HStack {
                            Image(systemName: showEstimateSuccess ? "checkmark" : "wand.and.stars")
                            Text(showEstimateSuccess ? "Estimate applied!" : "Set to estimate")
                        }
                        .frame(maxWidth: .infinity, minHeight: 36)
                    }
                    .buttonStyle(.borderedProminent)
                }

                Section {
                    if let parsed = inputs.parsed {
                        LabeledContent("Calories implied by macros", value: "\(parsed.macroCalories.wholeNumber) kcal")
                        let cal = max(1, parsed.macroCalories)
                        let proPct = Int(round((parsed.protein * 4 / cal) * 100))
                        let carbPct = Int(round((parsed.carbs * 4 / cal) * 100))
                        let fatPct = Int(round((parsed.fat * 9 / cal) * 100))
                        LabeledContent("Macro distribution", value: "\(proPct)% P · \(carbPct)% C · \(fatPct)% F")
                    }
                    Text("Small differences between macro calories and your calorie target are fine.")
                    Text("Exercise does not automatically raise targets. Use trends, not a single day.")
                    Text("Current targets appear on all dates. Changes are saved in Maintenance history.")
                }.font(.footnote).foregroundStyle(.secondary)
            }
            .instrumentForm()
            .navigationTitle("Your targets").navigationBarTitleDisplayMode(.inline)
            .onAppear {
                selectedGoal = diary.state.adaptive.goal
                if weightInput.isEmpty {
                    let units = diary.state.measurementUnits
                    let latestKG = diary.bodyPoints.filter { $0.metric == .weight }.sorted(by: { $0.date > $1.date }).first?.value ?? 75.0
                    let displayWeight = units.display(latestKG, metric: .weight)
                    weightInput = InputNumber.editString(displayWeight)
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        guard let parsed = inputs.parsed else { return }
                        if diary.setTargets(parsed) {
                            if diary.state.adaptive.goal != selectedGoal {
                                var adaptive = diary.state.adaptive
                                adaptive.goal = selectedGoal
                                _ = diary.saveAdaptiveSettings(adaptive)
                            }
                            dismiss()
                        }
                        else { saveError = diary.errorMessage; diary.errorMessage = nil }
                    }.disabled(inputs.parsed == nil || (inputs.parsed?.calories ?? 0) <= 0)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        focusedNutrient = nil
                        dismissKeyboard()
                    }
                }
            }
            .alert("Could not save", isPresented: Binding(get: { saveError != nil }, set: { if !$0 { saveError = nil } })) {
                Button("OK", role: .cancel) { saveError = nil }
            } message: { Text(saveError ?? "") }
        }
    }
}
