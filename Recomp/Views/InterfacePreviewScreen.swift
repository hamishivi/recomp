import SwiftUI

/// A read-only design gallery, with no DiaryStore, HealthKit, or estimation-service access.
/// The data never enters the user's diary. The same readouts are used by the real screens.
struct InterfacePreviewScreen: View {
    enum Page: String, CaseIterable, Identifiable {
        case food = "Food", burn = "Burn", body = "Body", maintenance = "Maintenance"
        var id: String { rawValue }
    }
    @State private var page = Page.food
    private let food = Nutrition(calories: 1780, protein: 127, carbs: 167, fat: 64)
    private let demo = AdaptiveDemo.scales.data()
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Notice(text: "Sample data. Nothing is saved.", symbol: "rectangle.on.rectangle")
                Picker("Preview screen", selection: $page) {
                    ForEach(Page.allCases) { Text($0.rawValue).tag($0) }
                }.pickerStyle(.segmented)
                switch page {
                case .food:
                    NutritionSummary(total: food, targets: .startingTargets, includesEstimates: true)

                    SectionHeading(title: "Food diary", detail: "example")
                    FoodLedgerRow(entry: FoodEntry(name: "Chicken curry & rice", date: Date(), meal: .lunch,
                                                  nutrition: Nutrition(calories: 900, protein: 40, carbs: 110, fat: 33),
                                                  isEstimate: true), status: "Sample entry")
                case .burn:
                    BurnChartPreview()
                case .body:
                    VStack(alignment: .leading, spacing: 16) {
                        SectionHeading(title: "Measurements", detail: "weight")
                        ScaleTrendPlot(points: demo.points, metric: .weight, units: .metric,
                                       locations: demo.state.scaleLocations)
                    }.surface()
                    Text("Two synthetic scales have different baselines. Their lines remain separate.")
                        .font(.footnote).foregroundStyle(Theme.muted)
                case .maintenance:
                    MaintenanceSummary(report: MaintenanceEngine.evaluate(state: demo.state, points: demo.points),
                                       initialGuess: 2700)
                    Text("This example has no Apply control. Your actual estimate is in the Maintenance tab.")
                        .font(.footnote).foregroundStyle(Theme.muted)
                }
            }.padding(18).frame(maxWidth: 640).frame(maxWidth: .infinity)
        }.background(Theme.background).navigationTitle("Interface preview").navigationBarTitleDisplayMode(.inline)
    }
}

/// Isolated fixtures for inspecting chart interaction, day states and text sizes.
private struct BurnChartPreview: View {
    enum DayState: String, CaseIterable, Identifiable {
        case current = "In progress", complete = "Complete", upcoming = "Upcoming"
        var id: String { rawValue }
    }
    @State private var dayState = DayState.current
    @State private var includeActivity = true
    private var day: Date {
        Calendar.current.date(from: DateComponents(year: 2026, month: 9, day: 25))!
    }
    private var now: Date {
        switch dayState {
        case .current: return day.addingTimeInterval(14 * 3600 + 37 * 60)
        case .complete: return Calendar.current.date(byAdding: .day, value: 1, to: day)!
        case .upcoming: return day.addingTimeInterval(-3600)
        }
    }
    private var curve: IntradayBurnCurve {
        let source = ActivitySource(id: "preview", name: "Sample data")
        let runStart = day.addingTimeInterval(7 * 3600 + 7 * 60)
        let shortStart = day.addingTimeInterval(11 * 3600 + 8 * 60)
        let workouts = [
            WorkoutRecord(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
                          start: runStart, end: runStart.addingTimeInterval(42 * 60), duration: 42 * 60,
                          kind: "running", title: "Morning run", distanceMetres: 7000, source: source),
            WorkoutRecord(id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
                          start: shortStart, end: shortStart.addingTimeInterval(6 * 60), duration: 6 * 60,
                          kind: "strength", title: "Short strength session", source: source)
        ]
        let steps = [(8, 1500.0), (9, 2100.0), (12, 1200.0), (13, 2300.0)].map { hour, count in
            let start = day.addingTimeInterval(Double(hour) * 3600)
            return StepInterval(start: start, end: start.addingTimeInterval(3600), count: count)
        }
        let history = (1...7).map {
            StepDay(date: Calendar.current.date(byAdding: .day, value: -$0, to: day)!, count: 8000)
        }
        return IntradayBurnCalculator.calculate(dailyBurn: 2400, for: day, now: now,
            workouts: includeActivity ? workouts : [], steps: includeActivity ? history : [],
            stepIntervals: includeActivity ? steps : [], weightKG: 75,
            energyInputs: includeActivity ? EnergyInputs(
                resting: RestingEnergyEstimate(kcalPerDay: 1666, date: day.addingTimeInterval(-86400),
                    source: "Cunningham 1991 · synthetic 60 kg fat-free mass", fatFreeMassKG: 60),
                meals: [DigestionEvent(date: day.addingTimeInterval(8 * 3600), kcal: 80)],
                typicalNutrition: .startingTargets) : nil)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Picker("Sample day", selection: $dayState) {
                ForEach(DayState.allCases) { Text($0.rawValue).tag($0) }
            }.pickerStyle(.segmented)
            Toggle("Include sample activity", isOn: $includeActivity).font(.subheadline)
            IntradayBurnChart(curve: curve, now: now).id(dayState)
        }
        .surface()
    }
}

#if DEBUG
/// Open the Xcode canvas for this file. These use the real native SwiftUI components,
/// unlike the separate, clearly labelled HTML design reference shipped in Design/.
struct InstrumentDesignPreviews: PreviewProvider {
    static var previews: some View {
        Group {
            NavigationStack { InterfacePreviewScreen() }.tint(Theme.accent)
                .preferredColorScheme(.light).previewDisplayName("Light / native components")
            NavigationStack { InterfacePreviewScreen() }.tint(Theme.accent)
                .preferredColorScheme(.dark).previewDisplayName("Dark / native components")
            NavigationStack { InterfacePreviewScreen() }.tint(Theme.accent)
                .preferredColorScheme(.light).environment(\.dynamicTypeSize, .accessibility3)
                .previewDisplayName("Accessibility / large text")
            VStack(spacing: 16) {
                NutritionSummary(total: .zero, targets: .startingTargets)

            }.padding().background(Theme.background).preferredColorScheme(.light)
                .previewDisplayName("Empty diary / no invented data")
        }
    }
}
#endif
