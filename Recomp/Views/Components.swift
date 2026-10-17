import SwiftUI

extension Double {
    var displayNumber: String { formatted(.number.precision(.fractionLength(0...1))) }
    var wholeNumber: String { formatted(.number.precision(.fractionLength(0))) }
}

struct Notice: View {
    var text: String
    var symbol = "info.circle"
    var body: some View {
        Label(text, systemImage: symbol)
            .font(.footnote).foregroundStyle(Theme.muted)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#if canImport(UIKit)
import UIKit

extension View {
    @MainActor
    func dismissKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}
#endif

struct NutritionInputs {
    var values: [Nutrient: String]
    init(_ nutrition: Nutrition) {
        values = Dictionary(uniqueKeysWithValues: Nutrient.allCases.map { ($0, InputNumber.editString(nutrition[$0])) })
    }
    subscript(_ nutrient: Nutrient) -> String {
        get { values[nutrient] ?? "" }
        set { values[nutrient] = newValue }
    }
    var parsed: Nutrition? {
        var result = Nutrition.zero
        for nutrient in Nutrient.allCases {
            let text = self[nutrient].trimmingCharacters(in: .whitespacesAndNewlines)
            if text.isEmpty {
                result[nutrient] = 0
            } else {
                guard let number = InputNumber.parse(text) else { return nil }
                result[nutrient] = number
            }
        }
        return result
    }
    mutating func scale(_ factor: Double) {
        if let parsed { self = NutritionInputs(parsed.scaled(by: factor)) }
    }
}

struct NutritionFields: View {
    @Binding var inputs: NutritionInputs
    var onEditingEnded: () -> Void = {}
    var focused: FocusState<Nutrient?>.Binding
    @State private var overwriteOnNextInput: Nutrient?

    private func sanitize(_ old: String, _ new: String) -> String {
        let trimmed = new.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "" }
        if old == "0" {
            if trimmed.count == 2 && trimmed.hasPrefix("0") && trimmed != "0." && trimmed != "0," {
                return String(trimmed.dropFirst())
            }
            if trimmed.count == 2 && trimmed.hasSuffix("0") && trimmed != ".0" && trimmed != ",0" {
                return String(trimmed.dropLast())
            }
        }
        if trimmed.count > 1 && trimmed.hasPrefix("0") && !trimmed.hasPrefix("0.") && !trimmed.hasPrefix("0,") {
            let nonZero = trimmed.drop(while: { $0 == "0" })
            return nonZero.isEmpty ? "0" : String(nonZero)
        }
        return trimmed
    }

    var body: some View {
        ForEach(Nutrient.allCases) { nutrient in
            HStack {
                Text(nutrient.title)
                Spacer()
                TextField("0", text: Binding(
                    get: { inputs[nutrient] },
                    set: { newRaw in
                        let shouldOverwrite = (overwriteOnNextInput == nutrient)
                        overwriteOnNextInput = nil
                        let effectiveNew = InputNumber.overwriteOrAppend(old: inputs[nutrient], new: newRaw, shouldOverwrite: shouldOverwrite)
                        inputs[nutrient] = sanitize(inputs[nutrient], effectiveNew)
                    }
                ))
                .fontDesign(.monospaced).multilineTextAlignment(.trailing).keyboardType(.decimalPad)
                .focused(focused, equals: nutrient)
                .frame(maxWidth: 110)
                .accessibilityLabel("\(nutrient.title), \(nutrient.unit)")
                .accessibilityIdentifier("nutrition.\(nutrient.rawValue)")
                Text(nutrient.unit).foregroundStyle(.secondary).frame(width: 32, alignment: .trailing)
            }
        }
        .onAppear {
            overwriteOnNextInput = focused.wrappedValue
        }
        .onChange(of: focused.wrappedValue) { old, new in
            overwriteOnNextInput = new
            if let new, inputs[new] == "0" {
                inputs[new] = ""
            }
            if let old, old != new {
                if inputs[old].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    inputs[old] = "0"
                }
                onEditingEnded()
            }
        }
    }
}
