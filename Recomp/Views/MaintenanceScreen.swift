import SwiftUI
import Charts

@MainActor
struct MaintenanceScreen: View {
    @EnvironmentObject private var diary: DiaryStore
    @EnvironmentObject private var activity: ActivityModel
    @State private var settings = false
    @State private var proposal: Nutrition?
    var body: some View {
        // One fit per rendering pass, shared by summary and recommendation.
        // Do not retain a stale cached proposal across edits or Health refreshes.
        let report = diary.maintenanceReport
        return NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    MaintenanceSummary(report: report, initialGuess: diary.state.adaptive.startingMaintenance)
                    recommendationCard(report: report)
                    scaleCard
                    activityCard
                    if !diary.state.maintenanceHistory.isEmpty { historyCard }
                    recentDaysCard
                    NavigationLink("Travel & food coverage") { TravelCoverageScreen() }
                    NavigationLink { MaintenanceMethodView() } label: {
                        Label("How the estimate works", systemImage: "function").font(.headline)
                    }.padding(.vertical, 8)
                }.padding(18).frame(maxWidth: 640).frame(maxWidth: .infinity)
            }
            .background(Theme.background).navigationTitle("Maintenance").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button { settings = true } label: { Image(systemName: "slider.horizontal.3") }.accessibilityLabel("Maintenance settings") } }
            .onAppear { diary.rememberMaintenance() }
            .refreshable { await diary.synchronize(); diary.rememberMaintenance() }
            .sheet(isPresented: $settings) { AdaptiveSettingsView(settings: diary.state.adaptive) }
            .confirmationDialog("Apply these daily targets?", isPresented: Binding(get: { proposal != nil }, set: { if !$0 { proposal = nil } }), titleVisibility: .visible) {
                Button("Apply reviewed targets") { if let proposal { _ = diary.applyRecommendation(proposal) }; proposal = nil }
            } message: {
                if let proposal {
                    Text("\(proposal.calories.wholeNumber) kcal · \(proposal.protein.wholeNumber) g protein · \(proposal.carbs.wholeNumber) g carbs · \(proposal.fat.wholeNumber) g fat. This changes your diary targets and records the old values. Reassess after at least 14 days, not after one meal.")
                }
            }
        }
    }
    private var activityCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeading(title: "Routine context")
            NavigationLink("Workouts, steps, sleep & notes") { ActivityContextScreen() }
            if diary.state.activityPreferences.enabled, let comparison = ActivityMath.stepComparison(activity.readout.steps, now: Date()) {
                Text(comparison).font(.caption).foregroundStyle(.secondary)
            }
            let cutoff = Calendar.current.date(byAdding: .day, value: -42, to: Date()) ?? Date()
            ForEach(Array(diary.state.contextEvents.filter { $0.end >= cutoff }.sorted { $0.start > $1.start }.prefix(3))) { event in
                Text("\(event.kind.title) · \(event.start.formatted(date: .abbreviated, time: .omitted))").font(.caption)
            }
            Text("Activity is context only. It does not add calories or change targets.")
                .font(.caption).foregroundStyle(.secondary)
        }.surface()
    }
    private var scaleCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeading(title: "Weigh-in scales")
            Picker("Use for maintenance", selection: Binding(get: { diary.state.maintenanceScaleLocationID }, set: { _ = diary.setMaintenanceScale($0) })) {
                Text("All scales · compared separately").tag(Optional<UUID>.none)
                ForEach(diary.state.scaleLocations) { location in
                    Text(location.name + (location.archived ? " (archived)" : "")).tag(Optional(location.id))
                }
            }
            Text("Compares changes within each scale, never jumps between scales.")
                .font(.caption).foregroundStyle(Theme.muted)
            DisclosureGroup("Scale requirements") {
                Text("Each included scale needs repeated readings across at least a week, and at least one must span 21 days. Choose one scale to use only its readings.")
                    .font(.caption).foregroundStyle(Theme.muted).padding(.top, 8)
            }.font(.caption)
            NavigationLink("Manage scales & locations") { ScaleLocationsScreen() }
        }.surface()
    }
    private func recommendationCard(report: MaintenanceReport) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeading(title: "Targets", detail: diary.state.adaptive.goal.title.lowercased())
            Text(report.recommendationTitle).font(.title2.weight(.medium))
            Text(report.recommendation).font(.subheadline).foregroundStyle(.secondary)
            if let new = report.proposal {
                ForEach(Nutrient.allCases) { metric in
                    HStack {
                        Text(metric.title); Spacer()
                        Text("\(diary.state.targets[metric].wholeNumber) → \(new[metric].wholeNumber) \(metric.unit)").monospacedDigit()
                    }.font(.subheadline)
                }
                Button("Review target change") { proposal = new }
                    .instrumentPrimary()
            }
            if !diary.state.adaptive.guidanceEnabled {
                Button("Configure fitness suggestions") { settings = true }
            }
            Text("No automatic adjustments. Small changes are limited to 100–150 kcal and spaced at least 14 days apart. These are conservative app rules, not validated clinical thresholds.")
                .font(.caption).foregroundStyle(.secondary)
            if let latest = diary.state.targetRevisions.last {
                Divider()
                Text("Last target change: \(latest.date.formatted(date: .abbreviated, time: .omitted)) · \(latest.reason)")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }.frame(maxWidth: .infinity, alignment: .leading).surface()
    }
    private var historyCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeading(title: "Estimate history")
            let history = diary.state.maintenanceHistory.sorted { $0.date < $1.date }
            Chart(history) { snapshot in
                PointMark(x: .value("Date", snapshot.date), y: .value("Estimated kcal", snapshot.calories)).foregroundStyle(Theme.ink).symbolSize(20)
                LineMark(x: .value("Date", snapshot.date), y: .value("Estimated kcal", snapshot.calories)).foregroundStyle(Theme.accent)
            }.frame(height: 180).instrumentChart().chartYScale(domain: .automatic(includesZero: false))
            Text("One local snapshot per day after enough data exists. These are historical calculations, not measured metabolic rates. Editing old records can change today's estimate; earlier snapshots remain an audit trail, not revalidated results. Snapshots from before version 1.3 used the older, non-scale-aware model. CSV includes the scale context for new snapshots.")
                .font(.caption).foregroundStyle(.secondary)
            if !diary.state.targetRevisions.isEmpty {
                DisclosureGroup("Target-change history") {
                    ForEach(Array(diary.state.targetRevisions.sorted { $0.date > $1.date }.prefix(20))) { revision in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(revision.date, format: .dateTime.month(.abbreviated).day().year()).font(.caption)
                            Text("\(revision.before.calories.wholeNumber) → \(revision.after.calories.wholeNumber) kcal").font(.subheadline)
                            Text(revision.reason).font(.caption).foregroundStyle(.secondary)
                        }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 5)
                    }
                }
            }
        }.surface()
    }
    private var recentDaysCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeading(title: "Completed food days")
            Text("Past days with logged meals automatically count when the day is done.")
                .font(.subheadline).foregroundStyle(.secondary)
            if diary.state.dayReviews.isEmpty {
                Text("No completed days yet.").font(.caption).foregroundStyle(.secondary)
            }
            ForEach(Array(diary.state.dayReviews.sorted { $0.dayKey > $1.dayKey }.prefix(10))) { review in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(review.dayKey)
                        if review.timeZoneID != TimeZone.current.identifier { Text(review.timeZoneID).font(.caption2).foregroundStyle(.secondary) }
                    }
                    Spacer()
                    Text(review.excludedFromAnalysis ? "Excluded" : "\(review.total.calories.wholeNumber) kcal").foregroundStyle(.secondary)
                }.font(.caption)
            }
            Text("Review and mark each food day complete in Today. Confirmed intervals are matched by actual time; gaps break coverage and exclusions pause analysis.")
                .font(.caption).foregroundStyle(.secondary)
        }.surface()
    }
}

struct MaintenanceSummary: View {
    let report: MaintenanceReport
    let initialGuess: Double
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SectionHeading(title: "Maintenance", detail: "trend estimate")
            if let estimate = report.estimate {
                InstrumentValue(value: estimate.wholeNumber, unit: "kcal/day", approximate: true)
                Text(report.title).font(.subheadline.weight(.medium))
                if let low = report.lower, let high = report.upper {
                    InstrumentDatum(title: "Sensitivity range", value: "\(low.wholeNumber)–\(high.wholeNumber)")
                    Text("Illustration, not a confidence interval.").font(.caption).foregroundStyle(Theme.muted)
                }
            } else {
                InstrumentValue(value: "—", unit: "kcal/day")
                Text("Waiting for comparable logs").font(.title3.weight(.medium))
                InstrumentDatum(title: "Starting guess", value: "\(initialGuess.wholeNumber) kcal/day")
                Text("The starting guess is not learned from your logs.").font(.caption).foregroundStyle(Theme.muted)
            }
            Text(report.message).font(.subheadline).foregroundStyle(Theme.muted)
            Divider().overlay(Theme.rule)
            InstrumentDatum(title: "Confirmed intervals", value: String(report.completedDays))
            if let days = report.elapsedDays { InstrumentDatum(title: "Elapsed days", value: String(format: "%.1f", days)) }
            InstrumentDatum(title: "Weigh-in days", value: String(report.weightDays))
            if let avg = report.averageIntake {
                InstrumentDatum(title: "Average logged intake", value: "\(avg.calories.wholeNumber) kcal/day")
                InstrumentDatum(title: "Average protein", value: "\(avg.protein.wholeNumber) g/day")
            }
            if let rate = report.kgPerWeek {
                InstrumentDatum(title: "Weight trend", value: String(format: "%+.2f kg/week", rate))
            }
            if let waist = report.waistChangeCM {
                InstrumentDatum(title: "Comparable waist change", value: String(format: "%+.1f cm", waist))
            }
            if !report.scaleNotice.isEmpty { Notice(text: report.scaleNotice, symbol: "tag") }
            DisclosureGroup("Window, sources & limitations") {
                VStack(alignment: .leading, spacing: 12) {
                    if let start = report.start, let end = report.end {
                        Text("\(start.formatted(date: .abbreviated, time: .omitted)) → \(end.formatted(date: .abbreviated, time: .omitted)) (final morning)")
                    }
                    if !report.scaleContext.isEmpty { Text(report.scaleContext) }
                    ForEach(report.caveats, id: \.self) { Notice(text: $0) }
                }.font(.caption).foregroundStyle(Theme.muted).padding(.top, 10)
            }.font(.subheadline)
        }.surface()
    }
}

@MainActor
struct AdaptiveSettingsView: View {
    @EnvironmentObject private var diary: DiaryStore
    @Environment(\.dismiss) private var dismiss
    @State private var settings: AdaptiveSettings
    @State private var guess: String
    @State private var protein: String
    @State private var fat: String
    init(settings: AdaptiveSettings) {
        _settings = State(initialValue: settings)
        _guess = State(initialValue: InputNumber.editString(settings.startingMaintenance))
        _protein = State(initialValue: InputNumber.editString(settings.proteinPerKG))
        _fat = State(initialValue: InputNumber.editString(settings.fatGrams))
    }
    var body: some View {
        NavigationStack {
            Form {
                Section("Goal") {
                    Picker("Training goal", selection: $settings.goal) { ForEach(FitnessGoal.allCases) { Text($0.title).tag($0) } }
                    Text("Recomposition tolerates stable or slowly changing weight. Falling waist measurements can support holding calories; the tool cannot establish whether muscle is being gained.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("Preferences") {
                    valueField("Starting maintenance guess", text: $guess, unit: "kcal")
                    valueField("Protein per kg", text: $protein, unit: "g/kg")
                    valueField("Preferred daily fat", text: $fat, unit: "g")
                    Text("Protein range 1.4–2.2 g/kg; default 2.0. Fat preference is used with a 0.6 g/kg product guardrail; carbohydrates use the remaining calories. These are general fitness settings, not individual medical nutrition advice. The starting guess is never passed off as a learned result.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section {
                    Toggle("Enable adult fitness suggestions", isOn: $settings.guidanceEnabled)
                } footer: {
                    Text("For adults pursuing general fitness only. Do not use adaptive suggestions during pregnancy/breastfeeding, for an eating-disorder treatment plan, or for a medically prescribed diet. Such situations need individual professional guidance. The estimate remains visible with suggestions off. All suggestions require review; nothing changes automatically.")
                }
            }
            .instrumentForm()
            .navigationTitle("Maintenance settings").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { save() } }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { dismissKeyboard() }
                }
            }
        }
    }
    private func valueField(_ title: String, text: Binding<String>, unit: String) -> some View {
        HStack { Text(title); Spacer(); TextField(unit, text: text).keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 80); Text(unit).foregroundStyle(.secondary) }
    }
    private func save() {
        guard let guess = InputNumber.parse(guess), let protein = InputNumber.parse(protein), let fat = InputNumber.parse(fat) else {
            diary.errorMessage = "Enter valid numbers for all preferences."; return
        }
        settings.startingMaintenance = guess; settings.proteinPerKG = protein; settings.fatGrams = fat
        if diary.saveAdaptiveSettings(settings) { dismiss() }
    }
}

struct AdaptiveDemoScreen: View {
    @State private var scenario: AdaptiveDemo = .stable
    private var report: MaintenanceReport {
        let data = scenario.data()
        return MaintenanceEngine.evaluate(state: data.state, points: data.points)
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Notice(text: "DEMO — synthetic examples only. Nothing here is saved to your diary, applied to your targets, or sent to Apple Health.", symbol: "play.rectangle").surface()
                Picker("Example", selection: $scenario) { ForEach(AdaptiveDemo.allCases) { Text($0.title).tag($0) } }.pickerStyle(.menu)
                MaintenanceSummary(report: report, initialGuess: 2700)
                VStack(alignment: .leading, spacing: 12) {
                    Text(report.recommendationTitle).font(.headline)
                    Text(report.recommendation)
                    if let proposal = report.proposal {
                        Text("Example only: \(proposal.calories.wholeNumber) kcal · \(proposal.protein.wholeNumber) g protein · \(proposal.carbs.wholeNumber) g carbs · \(proposal.fat.wholeNumber) g fat")
                            .font(.subheadline).foregroundStyle(Theme.accent)
                    }
                }.surface()
            }.padding(18)
        }.background(Theme.background).navigationTitle("Example trends").navigationBarTitleDisplayMode(.inline)
    }
}

struct MaintenanceMethodView: View {
    var body: some View {
        List {
            Section("1 · Trustworthy inputs first") {
                Text("Only complete, ended, non-overlapping real-time food intervals are analysed. At least 21 elapsed days must be covered and bracketed by comparable weigh-ins. The lookback is 43 elapsed days to allow partial boundary days. Missing hours are never counted as fasting or filled with targets.")
                Text("Weights should be measured under comparable conditions, preferably in the morning before food. UTC-date buckets with median values/timestamps and a robust elapsed-time multi-week trend reduce the influence of isolated readings. At least 3 weigh-in days per week and no gap longer than 4 days are required.")
            }
            Section("Scale-aware comparisons") {
                Text("Tag the actual scale used for each check-in. Automatic analysis compares pairs of readings from the same scale only, at least 7 days apart. It fits a separate constant baseline per scale and never changes the stored weights. At least one scale must span 21 days; others need at least 3 weigh-in days spanning a week.")
                Text("Untagged readings are not pooled with tagged scales. When all readings are untagged, the legacy calculation assumes one scale per method/source and shows a warning. Tag old mixed-scale readings before relying on that result. Disagreeing scale trends suppress target changes.")
            }
            Section("2 · Estimate, not measurement") {
                Text("Estimated maintenance = confirmed calories ÷ elapsed 24-hour days − 7,700 × weight-trend change in kg per 24 hours.")
                Text("The 7,700 kcal/kg coefficient is only a short-window energy-balance approximation. Scale change includes water, gut contents and differing tissue composition; simultaneous fat loss and muscle gain can weaken this inference. This is not the NIH dynamic weight model and does not predict long-term weight loss.")
                Text("The displayed range varies intake error, trend slope and the energy coefficient. It is a sensitivity illustration, NOT a validated uncertainty bound or confidence interval. True expenditure may lie outside it.")
            }
            Section("3 · Conservative, optional suggestions") {
                Text("Recomp keeps calories steady for stable or slowly changing weight; multiple comparable waist measurements can support holding a target. Body-fat readings never drive calorie changes. Exercise calories are not added on top of the inferred maintenance.")
                Text("Suggestions require agreement between recent and longer trends, recent intake reasonably near the target, no obvious instability, and at least 14 days since a target/goal change. Changes are limited to 100–150 kcal/day and must be reviewed before applying.")
                Text("Eligibility rules, sensitivity allowances, thresholds and rate bands are unvalidated product heuristics. Rapid changes, poor data and very low implied intake suppress suggestions. The app cannot assess energy availability or know whether a target is medically appropriate.")
            }
            Section("References and limits") {
                Link("NHS · Consistent scale and weighing conditions", destination: URL(string: "https://www.england.nhs.uk/long-read/how-to-record-your-weight/") ?? URL(fileURLWithPath: "/"))
                Link("Hall et al. · Dynamic energy balance and body weight", destination: URL(string: "https://pubmed.ncbi.nlm.nih.gov/21872751/") ?? URL(fileURLWithPath: "/"))
                Link("NIDDK · Research behind the Body Weight Planner", destination: URL(string: "https://www.niddk.nih.gov/research-funding/at-niddk/labs-branches/laboratory-biological-modeling/integrative-physiology-section/research/body-weight-planner") ?? URL(fileURLWithPath: "/"))
                Link("ISSN · Protein and exercise", destination: URL(string: "https://pubmed.ncbi.nlm.nih.gov/28642676/") ?? URL(fileURLWithPath: "/"))
                Link("Smart-scale body composition accuracy study", destination: URL(string: "https://pubmed.ncbi.nlm.nih.gov/33929337/") ?? URL(fileURLWithPath: "/"))
                Text("These sources explain relevant principles and limitations. They do not validate this specific algorithm or app. Maintenance analysis runs entirely on-device and sends no measurements or Health records to the photo-estimation server.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }.instrumentForm().navigationTitle("Method & limitations").navigationBarTitleDisplayMode(.inline)
    }
}
