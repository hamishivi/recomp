import SwiftUI
import Charts

/// Display preferences only. No diary migration or Health permission is involved.
enum AppAppearance: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var colorScheme: ColorScheme? {
        switch self { case .system: return nil; case .light: return .light; case .dark: return .dark }
    }
    static let storageKey = "recomp.interface.appearance"
}

/// Asset colors supply light, dark, and increased-contrast variants.
/// Accent is the accessible text/control tint. Signal is for filled controls and markers.
enum Theme {
    static let background = Color("Canvas")
    static let surface = Color("Panel")
    static let ink = Color("Ink")
    static let muted = Color("Muted")
    static let rule = Color("Rule")
    static let accent = Color("AccentColor")
    static let signal = Color("Signal")
    static let buttonInk = Color(red: 0.08, green: 0.09, blue: 0.07)
    static func ringColor(_ nutrient: Nutrient) -> Color {
        switch nutrient {
        case .calories: return Color("RingCalories")
        case .protein: return Color("RingProtein")
        case .carbs: return Color("RingCarbs")
        case .fat: return Color("RingFat")
        }
    }
    static let chartColors: [Color] = [ink, accent, muted]
}

struct Surface: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Theme.rule, lineWidth: 1)
                    .allowsHitTesting(false).accessibilityHidden(true)
            }
    }
}

struct InstrumentForm: ViewModifier {
    func body(content: Content) -> some View {
        content.scrollContentBackground(.hidden).scrollDismissesKeyboard(.interactively).background(Theme.background)
    }
}

struct InstrumentChart: ViewModifier {
    func body(content: Content) -> some View {
        content
            .chartForegroundStyleScale(range: Theme.chartColors)
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { _ in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(Theme.rule)
                    AxisValueLabel().font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(Theme.muted)
                }
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                    AxisTick(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(Theme.rule)
                    AxisValueLabel().font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(Theme.muted)
                }
            }
    }
}

extension View {
    func surface() -> some View { modifier(Surface()) }
    func instrumentForm() -> some View { modifier(InstrumentForm()) }
    func instrumentChart() -> some View { modifier(InstrumentChart()) }
    /// Keeps the system button's focus, pressed, disabled, and accessibility behaviour.
    func instrumentPrimary() -> some View {
        buttonStyle(.borderedProminent).tint(Theme.signal).foregroundStyle(Theme.buttonInk)
            .buttonBorderShape(.roundedRectangle(radius: 8)).controlSize(.large)
    }
}

/// Borders, spacing and sentence-case headings establish hierarchy.
struct SectionHeading: View {
    let title: String
    var detail = ""
    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                heading
                Spacer(minLength: 8)
                if !detail.isEmpty { Text(detail).font(.system(.caption, design: .monospaced)).foregroundStyle(Theme.muted) }
            }
            VStack(alignment: .leading, spacing: 6) {
                heading
                if !detail.isEmpty { Text(detail).font(.caption).foregroundStyle(Theme.muted) }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title + (detail.isEmpty ? "" : ", " + detail))
        .accessibilityAddTraits(.isHeader)
    }
    private var heading: some View {
        Text(title).font(.headline).foregroundStyle(Theme.ink)
    }
}

struct InstrumentValue: View {
    let value: String
    let unit: String
    var approximate = false
    @ScaledMetric(relativeTo: .largeTitle) private var size: CGFloat = 56
    @Environment(\.dynamicTypeSize) private var dynamicType
    var body: some View {
        let layout = dynamicType.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 8))
        layout {
            Text((approximate ? "≈ " : "") + value)
                .font(.system(size: size, weight: .regular, design: .monospaced))
                .tracking(-2).foregroundStyle(Theme.ink)
                .lineLimit(1).minimumScaleFactor(0.5)
                .layoutPriority(1)
            Text(unit).font(.system(.subheadline, design: .monospaced)).foregroundStyle(Theme.muted)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel((approximate ? "Approximately " : "") + value + " " + unit)
    }
}

struct InstrumentDatum: View {
    let title: String
    let value: String
    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).foregroundStyle(Theme.muted)
                Spacer(minLength: 16)
                Text(value).fontDesign(.monospaced).foregroundStyle(Theme.ink)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(title).foregroundStyle(Theme.muted)
                Text(value).fontDesign(.monospaced).foregroundStyle(Theme.ink)
            }
        }.font(.subheadline).accessibilityElement(children: .combine)
    }
}

/// Non-interactive ruler. Accessible meaning is supplied by the containing readout.
/// No animation, target celebration, red overflow state, or calorie "score".
struct RulerMeter: View {
    let value: Double
    let target: Double
    private var fraction: Double { min(max(value / max(target, 1), 0), 1) }
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Rectangle().fill(Theme.rule).frame(height: 1)
                Rectangle().fill(Theme.ink).frame(width: geometry.size.width * fraction, height: 2)
                HStack(spacing: 0) {
                    ForEach(0..<21, id: \.self) { index in
                        Rectangle().fill(Theme.muted).frame(width: 1, height: index % 5 == 0 ? 12 : 6)
                        if index != 20 { Spacer(minLength: 0) }
                    }
                }
                Rectangle().fill(Theme.accent).frame(width: 3, height: 20)
                    .offset(x: max(0, (geometry.size.width - 3) * fraction))
            }.frame(height: 24)
        }.frame(height: 24).accessibilityHidden(true).allowsHitTesting(false)
    }
}

/// Four intake rings, outside-in: calories, protein, carbs, fat.
/// Tracks stop at a full circle; exact numbers below show any excess without a red warning.
struct IntakeRings: View {
    let total: Nutrition
    let targets: Nutrition
    var approximate = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        GeometryReader { geometry in
            let side = min(geometry.size.width, geometry.size.height)
            let width = side * 0.041
            let gap = side * 0.024
            ZStack {
                ForEach(Array(Nutrient.allCases.enumerated()), id: \.element) { index, nutrient in
                    let inset = width / 2 + CGFloat(index) * (width + gap)
                    let progress = IntakeRingProgress(value: total[nutrient], target: targets[nutrient])
                    ZStack {
                        Circle().stroke(Theme.ringColor(nutrient).opacity(0.15), lineWidth: width)
                        if progress.fraction > 0 {
                            Circle().trim(from: 0, to: CGFloat(progress.fraction))
                                .stroke(Theme.ringColor(nutrient), style: StrokeStyle(lineWidth: width, lineCap: .round))
                                .rotationEffect(.degrees(-90))
                                .animation(reduceMotion ? nil : .easeOut(duration: 0.25), value: progress.fraction)
                        }
                    }.padding(inset)
                }
                VStack(spacing: 4) {
                    Text((approximate ? "≈ " : "") + total.calories.wholeNumber)
                        .font(.system(size: side * 0.13, weight: .medium, design: .monospaced))
                        .lineLimit(1).minimumScaleFactor(0.5)
                    Text("kcal").font(.caption).foregroundStyle(Theme.muted)
                }.frame(width: side * 0.45)
            }.frame(width: side, height: side)
        }.aspectRatio(1, contentMode: .fit)
            .accessibilityHidden(true).allowsHitTesting(false)
    }
}

struct NutritionSummary: View {
    let total: Nutrition
    let targets: Nutrition
    var includesEstimates = false
    @Environment(\.dynamicTypeSize) private var dynamicType
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if dynamicType.isAccessibilitySize {
                stacked
            } else {
                // Prefer the compact instrument panel; let the system fall back rather than
                // shrinking labels when the screen or text size cannot fit both columns.
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 16) {
                        IntakeRings(total: total, targets: targets, approximate: includesEstimates)
                            .frame(width: 128, height: 128)
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(Nutrient.allCases) { nutrient in compactRow(nutrient) }
                        }.frame(minWidth: 176)
                    }.fixedSize(horizontal: true, vertical: false)
                    stacked
                }.frame(maxWidth: .infinity)
            }
            if includesEstimates { Text("Includes estimates").font(.caption).foregroundStyle(Theme.muted) }
        }.surface().accessibilityIdentifier("home.nutrition")
    }
    private var stacked: some View {
        VStack(spacing: 16) {
            IntakeRings(total: total, targets: targets, approximate: includesEstimates)
                .frame(maxWidth: dynamicType.isAccessibilitySize ? 160 : 190).frame(maxWidth: .infinity)
            VStack(spacing: 10) {
                ForEach(Nutrient.allCases) { nutrient in
                    row(nutrient)
                    if nutrient != .fat { Divider().overlay(Theme.rule) }
                }
            }
        }
    }
    private func balance(_ nutrient: Nutrient) -> String {
        let progress = IntakeRingProgress(value: total[nutrient], target: targets[nutrient])
        guard let remaining = progress.remaining else { return "No target" }
        if remaining == 0 { return "At target" }
        let value = abs(remaining) < 1 ? "<1" : abs(remaining).wholeNumber
        return "\(value) \(nutrient.unit) \(remaining < 0 ? "over" : "left")"
    }
    private func readout(_ nutrient: Nutrient) -> String {
        let progress = IntakeRingProgress(value: total[nutrient], target: targets[nutrient])
        let target = progress.hasTarget ? targets[nutrient].wholeNumber : "—"
        let value = nutrient == .calories ? total[nutrient].wholeNumber : total[nutrient].displayNumber
        return "\(value) / \(target) \(nutrient.unit)"
    }
    private func accessibilityText(_ nutrient: Nutrient) -> String {
        let target = IntakeRingProgress(value: total[nutrient], target: targets[nutrient]).hasTarget
            ? ", target \(targets[nutrient].displayNumber) \(nutrient.unit)" : ""
        return "\(nutrient.title), \(total[nutrient].displayNumber) \(nutrient.unit) logged\(target), \(balance(nutrient))"
    }
    private func compactRow(_ nutrient: Nutrient) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 5) {
                Circle().fill(Theme.ringColor(nutrient)).frame(width: 7, height: 7).accessibilityHidden(true)
                Text(nutrient.title).font(.caption).foregroundStyle(Theme.muted)
                Spacer(minLength: 8)
                Text(balance(nutrient)).font(.caption2).foregroundStyle(Theme.muted)
            }
            Text(readout(nutrient)).font(.system(.subheadline, design: .monospaced)).foregroundStyle(Theme.ink)
        }.accessibilityElement(children: .ignore).accessibilityLabel(accessibilityText(nutrient))
    }
    private func row(_ nutrient: Nutrient) -> some View {
        let layout = dynamicType.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 12))
        return layout {
            HStack(spacing: 8) {
                Circle().fill(Theme.ringColor(nutrient)).frame(width: 8, height: 8).accessibilityHidden(true)
                Text(nutrient.title).font(.subheadline)
            }.frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: dynamicType.isAccessibilitySize ? .leading : .trailing, spacing: 3) {
                Text(readout(nutrient)).font(.system(.subheadline, design: .monospaced)).foregroundStyle(Theme.ink)
                Text(balance(nutrient)).font(.caption).foregroundStyle(Theme.muted)
            }
        }.accessibilityElement(children: .ignore).accessibilityLabel(accessibilityText(nutrient))
    }
}
