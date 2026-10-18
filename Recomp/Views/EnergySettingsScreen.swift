import SwiftUI

@MainActor
struct EnergySettingsScreen: View {
    @EnvironmentObject private var diary: DiaryStore
    @Environment(\.dismiss) private var dismiss
    @State private var settings: EnergySettings
    @State private var useManual: Bool
    @State private var resting: String
    @State private var recordedAt: Date
    @State private var movement: String
    @State private var steps: String
    @State private var error: String?

    init(settings: EnergySettings) {
        _settings = State(initialValue: settings)
        _useManual = State(initialValue: settings.manualRestingKcal != nil)
        _resting = State(initialValue: settings.manualRestingKcal.map(InputNumber.editString) ?? "")
        _recordedAt = State(initialValue: settings.manualRestingDate ?? Date())
        _movement = State(initialValue: InputNumber.editString(settings.untrackedMovementKcal))
        _steps = State(initialValue: InputNumber.editString(settings.usualDailySteps))
    }
    private var parsed: EnergySettings? {
        guard let allowance = InputNumber.parse(movement), let count = InputNumber.parse(steps) else { return nil }
        var result = settings
        result.untrackedMovementKcal = allowance; result.usualDailySteps = count
        if useManual {
            guard let kcal = InputNumber.parse(resting), recordedAt <= Date() else { return nil }
            result.manualRestingKcal = kcal; result.manualRestingDate = recordedAt
        } else {
            result.manualRestingKcal = nil; result.manualRestingDate = nil; result.manualRestingIsMeasured = false
        }
        return result.isValid ? result : nil
    }
    var body: some View {
        let estimate = parsed.flatMap { diary.restingEnergy(settings: $0) }
        Form {
            Section {
                if let estimate {
                    LabeledContent("Resting energy", value: "\(estimate.kcalPerDay.wholeNumber) kcal/day")
                        .accessibilityIdentifier("energy.estimate")
                    Text(estimate.source).font(.caption).foregroundStyle(Theme.muted)
                    if let ffm = estimate.fatFreeMassKG {
                        Text("Fat-free mass: \(InputNumber.editString((ffm * 10).rounded() / 10)) kg · \(estimate.date.formatted(date: .abbreviated, time: .omitted))")
                            .font(.caption).foregroundStyle(Theme.muted)
                    }
                } else {
                    Text("Resting energy unavailable").accessibilityIdentifier("energy.unavailable")
                    Text("Add suitable recent body composition or a manual resting value to enable the component model. Until then, the chart uses maintenance pace and its existing activity model.")
                        .font(.caption).foregroundStyle(Theme.muted)
                }
                Toggle("Use manual resting energy", isOn: $useManual).accessibilityIdentifier("energy.manual")
                if useManual {
                    numberField("Resting energy", text: $resting, unit: "kcal/day", identifier: "energy.resting")
                    DatePicker("Value date", selection: $recordedAt, in: ...Date(), displayedComponents: .date)
                    Toggle("Measured by indirect calorimetry", isOn: $settings.manualRestingIsMeasured)
                    Text("Mark measured only for an actual metabolic test. A DXA report may contain a calculated resting value.")
                        .font(.caption).foregroundStyle(Theme.muted)
                }
            } header: { Text("Resting metabolism · RMR") } footer: {
                Text("Automatic estimates use Cunningham’s fat-free-mass equation and reviewed data from the last 90 days. Whole-body DXA must include bone in fat-free mass. Paired weight/body-fat readings must use the same scale and method within 7 days. These are estimates; strict BMR testing conditions are not established by the app.")
            }
            Section {
                numberField("Untracked movement", text: $movement, unit: "kcal/day", identifier: "energy.movement")
                numberField("Usual daily steps", text: $steps, unit: "steps", identifier: "energy.steps")
            } header: { Text("Everyday movement · NEAT") } footer: {
                Text("Standing, chores and fidgeting aren’t reliably captured by steps. The untracked allowance starts as a guess. Suitable food, weight and activity history can replace it with a calibration residual, which also contains model and logging error. Usual steps are used for forecasts while activity history is limited.")
            }
            Section("Accounting") {
                Text("Burn = resting energy + everyday movement + net exercise + digestion.")
                Text("Exercise counts only energy above rest. Steps during workouts count once. Digestion uses food macros; incomplete food logs receive a labelled allowance from usual intake or food targets.")
                Text("Digestion timing is a coarse 8-hour assumption, and resting burn is spread evenly. Recorded activity coverage is not proof of device wear. Individual accuracy has not been validated.")
                Text("Your food targets require their usual review and Save; enabling this model does not add exercise calories to them.")
            }.font(.caption).foregroundStyle(Theme.muted)
            if parsed == nil {
                Text("Check the inputs: resting energy 500–4,500 kcal/day, untracked movement 0–1,500 kcal/day, and usual steps 0–50,000. These are input limits, not recommended values.")
                    .font(.caption).foregroundStyle(Theme.muted)
            }
        }
        .instrumentForm().navigationTitle("Energy model").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    guard let value = parsed else { return }
                    if diary.saveEnergySettings(value) { dismiss() }
                    else { error = diary.errorMessage; diary.errorMessage = nil }
                }.disabled(parsed == nil).accessibilityIdentifier("energy.save")
            }
            ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("Done") { dismissKeyboard() } }
        }
        .alert("Couldn’t save", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK", role: .cancel) { error = nil }
        } message: { Text(error ?? "") }
    }
    private func numberField(_ title: String, text: Binding<String>, unit: String, identifier: String) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack { Text(title); Spacer(); input(text, identifier: identifier).frame(width: 90); Text(unit).foregroundStyle(Theme.muted) }
            VStack(alignment: .leading) { Text(title); HStack { input(text, identifier: identifier); Text(unit).foregroundStyle(Theme.muted) } }
        }
    }
    private func input(_ text: Binding<String>, identifier: String) -> some View {
        TextField("Value", text: text).keyboardType(.decimalPad).multilineTextAlignment(.trailing)
            .accessibilityIdentifier(identifier)
    }
}
