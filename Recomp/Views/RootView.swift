import SwiftUI
import Combine

@MainActor
struct RootView: View {
    @EnvironmentObject private var diary: DiaryStore
    @Environment(\.scenePhase) private var scenePhase
    @State private var tab = 0
    @State private var selectedSection: AppSection? = .today
    @EnvironmentObject private var activity: ActivityModel
    @State private var quickAction: QuickAction?
    private let minute = Timer.publish(every: 60, on: .main, in: .common).autoconnect()
    var body: some View {
        #if targetEnvironment(macCatalyst)
        macNavigationSplitView
            .task {
                diary.didCommit = { state in WidgetPublisher.publish(state) }
                WidgetPublisher.publish(diary.state)
                await diary.start()
                await activity.refresh(enabled: diary.state.activityPreferences.enabled)
            }
            .onChange(of: diary.state.activityPreferences.enabled) { _, enabled in
                Task { await activity.refresh(enabled: enabled) }
            }
            .onOpenURL { url in
                guard url.scheme == "recomp", url.query == nil, url.user == nil else { return }
                diary.selectDay(Date()); selectedSection = .today; tab = 0
                quickAction = QuickAction(rawValue: url.host ?? "")
            }
            .sheet(item: $quickAction) { action in
                switch action {
                case .log: FoodEditor(entry: FoodEntry(name: "", date: Date(), meal: .suggested(at: Date()), nutrition: .zero), isEditing: false)
                case .check: MealEstimatorView(date: Date(), mode: .check)
                case .weigh: MeasurementEditor(record: nil, units: diary.state.measurementUnits, defaultLocationID: diary.state.lastScaleLocationID)
                }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { Task {
                    await diary.foreground(); WidgetPublisher.publish(diary.state)
                    await activity.refresh(enabled: diary.state.activityPreferences.enabled)
                } }
            }
            .onReceive(minute) { _ in if scenePhase == .active { diary.checkDayRollover(); diary.checkForExternalSync(); WidgetPublisher.publish(diary.state) } }
            .alert("Could not complete", isPresented: Binding(get: { diary.errorMessage != nil }, set: { if !$0 { diary.errorMessage = nil } })) {
                Button("OK", role: .cancel) { diary.errorMessage = nil }
            } message: { Text(diary.errorMessage ?? "") }
        #else
        TabView(selection: $tab) {
            TodayView(selectedTab: $tab).tabItem { Label("Today", systemImage: "rectangle.grid.1x2") }.tag(0)
            BodyScreen().tabItem { Label("Body", systemImage: "scalemass") }.tag(3)
            ProgressScreen().tabItem { Label("Trends", systemImage: "chart.xyaxis.line") }.tag(1)
            MaintenanceScreen().tabItem { Label("Maintenance", systemImage: "equal.square") }.tag(4)
            SettingsScreen().tabItem { Label("Settings", systemImage: "slider.horizontal.3") }.tag(2)
        }
        .task {
            diary.didCommit = { state in WidgetPublisher.publish(state) }
            WidgetPublisher.publish(diary.state)
            await diary.start()
            await activity.refresh(enabled: diary.state.activityPreferences.enabled)
        }
        .onChange(of: diary.state.activityPreferences.enabled) { _, enabled in
            Task { await activity.refresh(enabled: enabled) }
        }
        .onOpenURL { url in
            guard url.scheme == "recomp", url.query == nil, url.user == nil else { return }
            diary.selectDay(Date()); tab = 0
            quickAction = QuickAction(rawValue: url.host ?? "")
        }
        .sheet(item: $quickAction) { action in
            switch action {
            case .log: FoodEditor(entry: FoodEntry(name: "", date: Date(), meal: .suggested(at: Date()), nutrition: .zero), isEditing: false)
            case .check: MealEstimatorView(date: Date(), mode: .check)
            case .weigh: MeasurementEditor(record: nil, units: diary.state.measurementUnits, defaultLocationID: diary.state.lastScaleLocationID)
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task {
                await diary.foreground(); WidgetPublisher.publish(diary.state)
                await activity.refresh(enabled: diary.state.activityPreferences.enabled)
            } }
        }
        .onReceive(minute) { _ in if scenePhase == .active { diary.checkDayRollover(); diary.checkForExternalSync(); WidgetPublisher.publish(diary.state) } }
        .alert("Could not complete", isPresented: Binding(get: { diary.errorMessage != nil }, set: { if !$0 { diary.errorMessage = nil } })) {
            Button("OK", role: .cancel) { diary.errorMessage = nil }
        } message: { Text(diary.errorMessage ?? "") }
        #endif
    }

    #if targetEnvironment(macCatalyst)
    private var macNavigationSplitView: some View {
        NavigationSplitView {
            macSidebar
        } detail: {
            detailView(for: selectedSection ?? .today)
        }
        .navigationSplitViewStyle(.balanced)
    }

    private var macSidebar: some View {
        List(selection: $selectedSection) {
            Section("Dashboard") {
                Label("Today", systemImage: "sun.max.fill").tag(AppSection.today)
                Label("Trends", systemImage: "chart.xyaxis.line").tag(AppSection.trends)
                Label("Maintenance", systemImage: "equal.square").tag(AppSection.maintenance)
            }

            Section("Body & Composition") {
                Label("Body & DXA", systemImage: "scalemass.fill").tag(AppSection.body)
            }

            Section("Preferences") {
                Label("Settings & Sync", systemImage: "slider.horizontal.3").tag(AppSection.settings)
            }

            Section("Quick Actions") {
                Button { quickAction = .log } label: {
                    Label("Log food", systemImage: "plus.circle.fill")
                }
                .keyboardShortcut("n", modifiers: .command)

                Button { quickAction = .check } label: {
                    Label("Check food", systemImage: "magnifyingglass")
                }

                Button { quickAction = .weigh } label: {
                    Label("Record weight", systemImage: "scalemass")
                }
                .keyboardShortcut("w", modifiers: [.command, .shift])
            }
        }
        .frame(minWidth: 200, idealWidth: 230, maxWidth: 280)
    }

    @ViewBuilder
    private func detailView(for section: AppSection) -> some View {
        switch section {
        case .today:
            TodayView(selectedTab: Binding(get: { selectedSection?.rawValue ?? 0 }, set: { if let s = AppSection(rawValue: $0) { selectedSection = s } }))
        case .trends:
            ProgressScreen()
        case .maintenance:
            MaintenanceScreen()
        case .body:
            BodyScreen()
        case .settings:
            SettingsScreen()
        }
    }
    #endif
}

enum AppSection: Int, CaseIterable, Identifiable {
    case today = 0
    case trends = 1
    case settings = 2
    case body = 3
    case maintenance = 4

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .today: return "Today"
        case .trends: return "Trends"
        case .settings: return "Settings"
        case .body: return "Body & DXA"
        case .maintenance: return "Maintenance"
        }
    }

    var icon: String {
        switch self {
        case .today: return "sun.max.fill"
        case .trends: return "chart.xyaxis.line"
        case .settings: return "slider.horizontal.3"
        case .body: return "scalemass.fill"
        case .maintenance: return "equal.square"
        }
    }
}

enum QuickAction: String, Identifiable {
    case log, check, weigh
    var id: String { rawValue }
}

struct EditorRequest: Identifiable {
    let id = UUID()
    let entry: FoodEntry
    var isEditing = false
}

@MainActor
struct TodayView: View {
    @EnvironmentObject private var diary: DiaryStore
    @EnvironmentObject private var activity: ActivityModel
    @Environment(\.dynamicTypeSize) private var dynamicType
    @Binding var selectedTab: Int
    @AppStorage("dismissedHealthBanner") private var dismissedHealthBanner = false
    @State private var editor: EditorRequest?
    @State private var showCheck = false
    @State private var showWeigh = false
    @State private var showActivity = false
    var body: some View {
        NavigationStack {
            ScrollView {
                desktopOrMobileContent
            }
            .background(Theme.background)
            .navigationTitle("").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) { dayPicker }
                #if targetEnvironment(macCatalyst)
                ToolbarItemGroup(placement: .primaryAction) {
                    Button {
                        newEntry()
                    } label: {
                        Label("Log food", systemImage: "plus")
                    }
                    .help("Log food (⌘N)")

                    Button {
                        showWeigh = true
                    } label: {
                        Label("Weigh", systemImage: "scalemass")
                    }
                    .help("Record weight (⇧⌘W)")
                }
                #endif
            }
            .refreshable { await diary.synchronize() }
            .sheet(item: $editor) { request in FoodEditor(entry: request.entry, isEditing: request.isEditing) }
            .sheet(isPresented: $showCheck) { MealEstimatorView(date: diary.defaultEntryDate(), mode: .check) }
            .sheet(isPresented: $showWeigh) { MeasurementEditor(record: nil, units: diary.state.measurementUnits, defaultLocationID: diary.state.lastScaleLocationID) }
            .sheet(isPresented: $showActivity) { NavigationStack { ActivityContextScreen() } }
        }
    }

    @ViewBuilder
    private var desktopOrMobileContent: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 20) {
                VStack(alignment: .leading, spacing: 18) {
                    if let error = diary.loadFailure {
                        Notice(text: "Diary could not be loaded. Saving is paused to protect it. \(error)", symbol: "exclamationmark.triangle").surface()
                    }
                    NutritionSummary(total: diary.total, targets: diary.state.targets,
                                     includesEstimates: diary.dayEntries.contains(where: \.isEstimate) || !diary.otherHealthSamples.isEmpty)
                    entryActions
                    foodLog
                    DayCompletionCard()
                }
                .frame(minWidth: 300, maxWidth: .infinity)

                VStack(alignment: .leading, spacing: 18) {
                    trendingSummaryCard
                    if !diary.state.healthEnabled && !diary.state.bodyHealthEnabled {
                        if !dismissedHealthBanner { healthConnectCard }
                    } else {
                        healthNote
                    }
                }
                .frame(minWidth: 300, maxWidth: .infinity)
            }
            .padding(.horizontal, 24)
            .padding(.top, 14)
            .padding(.bottom, 32)
            .frame(maxWidth: 1100)
            .frame(maxWidth: .infinity)

            VStack(alignment: .leading, spacing: 18) {
                if let error = diary.loadFailure {
                    Notice(text: "Diary could not be loaded. Saving is paused to protect it. \(error)", symbol: "exclamationmark.triangle").surface()
                }
                NutritionSummary(total: diary.total, targets: diary.state.targets,
                                 includesEstimates: diary.dayEntries.contains(where: \.isEstimate) || !diary.otherHealthSamples.isEmpty)
                entryActions
                trendingSummaryCard
                foodLog
                DayCompletionCard()
                if !diary.state.healthEnabled && !diary.state.bodyHealthEnabled {
                    if !dismissedHealthBanner { healthConnectCard }
                } else {
                    healthNote
                }
            }
            .padding(.horizontal, 18).padding(.top, 8).padding(.bottom, 32)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
    }
    private var dayPicker: some View {
        HStack(spacing: 4) {
            Button { diary.shiftDay(-1) } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Previous day")

            DatePicker("Log date", selection: Binding(get: { diary.selectedDay }, set: { diary.selectDay($0) }),
                       in: ...max(Date(), diary.latestDiaryDate), displayedComponents: .date)
                .labelsHidden()
                .datePickerStyle(.compact)
                .accessibilityLabel("Choose diary date")

            Button { diary.shiftDay(1) } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(diary.selectedDay >= diary.latestDiaryDate)
            .accessibilityLabel("Next day")
        }
        .foregroundStyle(Theme.ink)
        .fixedSize()
    }
    private var entryActions: some View {
        let layout = dynamicType.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: 10)) : AnyLayout(HStackLayout(spacing: 10))
        return layout {
            Button { newEntry() } label: {
                Label("Log food", systemImage: "plus").frame(maxWidth: .infinity, minHeight: 44)
            }.instrumentPrimary().accessibilityIdentifier("food.log")
            Button { showCheck = true } label: {
                Label("Check food", systemImage: "magnifyingglass").frame(minHeight: 44)
            }.buttonStyle(.bordered).controlSize(.large).accessibilityIdentifier("food.check")
        }.disabled(diary.loadFailure != nil)
    }
    private var trendingSummaryCard: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            trendingSummaryCard(at: context.date)
        }
    }
    private func trendingSummaryCard(at now: Date) -> some View {
        let trend = diary.trendSummary
        let userWorkouts = ActivityMath.workouts(activity.readout.workouts, preferences: diary.state.activityPreferences)
        let burnCurve = diary.intradayBurnCurve(workouts: userWorkouts, steps: activity.readout.steps, stepIntervals: activity.readout.stepIntervals, now: now)
        let dayExpended = (expended: burnCurve.expendedSoFar, fraction: burnCurve.fraction)
        let intradayBalance = diary.total.calories - burnCurve.expendedSoFar
        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                SectionHeading(title: "Trends & Energy", detail: "7-day glance")
                Spacer()
                Button {
                    selectedTab = 1
                } label: {
                    HStack(spacing: 3) {
                        Text("See trends")
                        Image(systemName: "arrow.right")
                    }
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Theme.ink)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Open Trends tab")
            }

            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("MAINTENANCE")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(Theme.muted)
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text("\(trend.estimatedDailyBurn.wholeNumber)")
                            .font(.title3.weight(.bold).monospacedDigit())
                            .foregroundStyle(Theme.ink)
                        Text("kcal/d")
                            .font(.caption2)
                            .foregroundStyle(Theme.muted)
                    }
                    Text(trend.isBurnLearned ? "Learned" : "Baseline")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(trend.isBurnLearned ? Theme.accent : Theme.muted)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background((trend.isBurnLearned ? Theme.accent : Theme.muted).opacity(0.12))
                        .clipShape(Capsule())

                    if dayExpended.fraction > 0 && dayExpended.fraction < 0.999 {
                        Text("~\(dayExpended.expended.wholeNumber) so far (\(Int(dayExpended.fraction * 100))%)")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(Theme.muted)
                            .lineLimit(1).minimumScaleFactor(0.75)
                        let delta = burnCurve.deltaVsLinear
                        if abs(delta) >= 15 {
                            let sign = delta >= 0 ? "+" : ""
                            let paceColor = delta >= 20 ? Color.green : (delta <= -250 ? Color.orange : Theme.muted)
                            Text("\(sign)\(delta.wholeNumber) vs usual pace")
                                .font(.system(size: 9, weight: .medium, design: .monospaced))
                                .foregroundStyle(paceColor)
                                .lineLimit(1)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Divider().frame(height: 48).overlay(Theme.rule)

                VStack(alignment: .leading, spacing: 3) {
                    Text("AVG INTAKE")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(Theme.muted)
                    if trend.loggedDaysCount > 0 {
                        HStack(alignment: .firstTextBaseline, spacing: 2) {
                            Text("\(trend.recentAverageCalories.wholeNumber)")
                                .font(.title3.weight(.bold).monospacedDigit())
                                .foregroundStyle(Theme.ink)
                            Text("kcal/d")
                                .font(.caption2)
                                .foregroundStyle(Theme.muted)
                        }
                        let delta = trend.calorieDeltaVsTarget
                        let deltaStr = delta >= 0 ? "+\(delta.wholeNumber)" : "\(delta.wholeNumber)"
                        Text("\(deltaStr) vs target")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(Theme.muted)
                            .lineLimit(1).minimumScaleFactor(0.75)
                    } else {
                        Text("—")
                            .font(.title3.weight(.bold))
                            .foregroundStyle(Theme.muted)
                        Text("No meals")
                            .font(.system(size: 10))
                            .foregroundStyle(Theme.muted)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Divider().frame(height: 48).overlay(Theme.rule)

                VStack(alignment: .leading, spacing: 3) {
                    Text("WEIGHT")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(Theme.muted)
                    if let weight = trend.latestWeight {
                        HStack(alignment: .firstTextBaseline, spacing: 2) {
                            Text(String(format: "%.1f", weight))
                                .font(.title3.weight(.bold).monospacedDigit())
                                .foregroundStyle(Theme.ink)
                            Text(trend.weightUnit)
                                .font(.caption2)
                                .foregroundStyle(Theme.muted)
                        }
                        if let rate = trend.weightChangeRatePerWeek {
                            let sign = rate > 0 ? "+" : ""
                            Text(String(format: "%@%.1f %@/wk", sign, rate, trend.weightUnit))
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(rate < 0 ? Color.green : (rate > 0 ? Color.orange : Theme.muted))
                                .lineLimit(1).minimumScaleFactor(0.75)
                        } else {
                            Text("Stable")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(Theme.muted)
                        }
                    } else {
                        Text("—")
                            .font(.title3.weight(.bold))
                            .foregroundStyle(Theme.muted)
                        Text("No weight")
                            .font(.system(size: 10))
                            .foregroundStyle(Theme.muted)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, 4)

            Divider().overlay(Theme.rule)

            IntradayBurnChart(curve: burnCurve, now: now)

            Divider().overlay(Theme.rule)

            HStack(spacing: 8) {
                let isDeficit = intradayBalance < -50
                let isSurplus = intradayBalance > 50
                Image(systemName: isDeficit ? "arrow.down.forward" : (isSurplus ? "arrow.up.forward" : "equal"))
                    .font(.caption.weight(.bold))
                    .foregroundStyle(isDeficit ? Color.green : (isSurplus ? Color.orange : Theme.muted))

                VStack(alignment: .leading, spacing: 2) {
                    if dayExpended.fraction > 0 && dayExpended.fraction < 0.999 {
                        if isDeficit {
                            Text("\(abs(intradayBalance).wholeNumber) kcal deficit so far today")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Theme.ink)
                        } else if isSurplus {
                            Text("\(intradayBalance.wholeNumber) kcal surplus vs burn so far")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Theme.ink)
                        } else {
                            Text("Even pace with metabolic burn so far")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Theme.ink)
                        }
                        Text("\(diary.total.calories.wholeNumber) kcal eaten vs ~\(dayExpended.expended.wholeNumber) kcal burned (\(Int(dayExpended.fraction * 100))% of day)")
                            .font(.caption2)
                            .foregroundStyle(Theme.muted)
                    } else {
                        let balance = trend.dailyEnergyBalance
                        if balance < -50 {
                            Text("\(abs(balance).wholeNumber) kcal/day 7-day deficit")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Theme.ink)
                        } else if balance > 50 {
                            Text("\(balance.wholeNumber) kcal/day 7-day surplus")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Theme.ink)
                        } else {
                            Text("Balanced daily energy")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Theme.ink)
                        }

                        let kgRate = (balance * 7.0) / 7700.0
                        let displayRate = trend.weightUnit == "lb" ? (kgRate / 0.45359237) : kgRate
                        if abs(displayRate) >= 0.05 {
                            let sign = displayRate > 0 ? "+" : ""
                            Text(String(format: "Implies %@%.2f %@/wk based on energy balance", sign, displayRate, trend.weightUnit))
                                .font(.caption2)
                                .foregroundStyle(Theme.muted)
                        } else {
                            Text("Implies near weight maintenance")
                                .font(.caption2)
                                .foregroundStyle(Theme.muted)
                        }
                    }
                }
                Spacer()
            }
            .padding(10)
            .background(Theme.background)
            .cornerRadius(6)

            if !diary.state.activityPreferences.enabled {
                Button {
                    showActivity = true
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "figure.run")
                            .font(.body)
                            .foregroundStyle(Theme.accent)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Connect steps & workouts")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Theme.ink)
                            Text("Import from Apple Health, Watch, Strong & Strava to estimate expenditure from your movement")
                                .font(.system(size: 10))
                                .foregroundStyle(Theme.muted)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Theme.muted)
                    }
                    .padding(10)
                    .background(Theme.background)
                    .cornerRadius(6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(Theme.accent.opacity(0.35), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityHint("Connect Apple Health steps and workouts")
            } else {
                Button {
                    showActivity = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "figure.run")
                            .font(.caption2)
                            .foregroundStyle(Theme.accent)
                        let workoutCount = userWorkouts.filter { Calendar.current.isDate($0.start, inSameDayAs: diary.selectedDay) }.count
                        let stepCount = burnCurve.stepCount
                        let stepText = stepCount > 0 ? "\(Int(stepCount.rounded())) steps" : "Steps connected"
                        let workoutText = workoutCount > 0 ? "\(workoutCount) workout\(workoutCount == 1 ? "" : "s")" : "Workouts connected"
                        Text("\(stepText) · \(workoutText)")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(Theme.ink)
                        Spacer()
                        Text("Activity & context")
                            .font(.system(size: 10))
                            .foregroundStyle(Theme.muted)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(Theme.muted)
                    }
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                }
                .buttonStyle(.plain)
                .accessibilityHint("View activity and context details")
            }
        }
        .surface()
    }
    private var foodLog: some View {
        VStack(alignment: .leading, spacing: 18) {
            SectionHeading(title: "Food", detail: diary.dayEntries.isEmpty ? "" : "\(diary.dayEntries.count) \(diary.dayEntries.count == 1 ? "entry" : "entries")")
            if diary.dayEntries.isEmpty {
                Text("No food logged.").font(.subheadline).foregroundStyle(Theme.muted).padding(.vertical, 12)
            } else {
                ForEach(MealKind.allCases) { kind in
                    let entries = diary.dayEntries.filter { $0.meal == kind }
                    if !entries.isEmpty {
                        VStack(alignment: .leading, spacing: 0) {
                            Text(kind.rawValue.uppercased())
                                .font(.system(.caption, design: .monospaced)).tracking(1).foregroundStyle(Theme.muted)
                                .padding(.bottom, 10).accessibilityAddTraits(.isHeader)
                            Divider().overlay(Theme.rule)
                            ForEach(entries) { entry in
                                Button { editor = EditorRequest(entry: entry, isEditing: true) } label: {
                                    FoodLedgerRow(entry: entry, status: entryStatus(entry))
                                }.buttonStyle(.plain)
                                    .accessibilityHint("Edit this meal")
                                    .accessibilityIdentifier("food.entry")
                                    .contextMenu {
                                        Button {
                                            editor = EditorRequest(entry: entry, isEditing: true)
                                        } label: {
                                            Label("Edit meal", systemImage: "pencil")
                                        }
                                        Button {
                                            _ = diary.saveUsualFromEntry(entry)
                                        } label: {
                                            Label(diary.isUsual(name: entry.name) ? "Saved in usuals" : "Save as usual",
                                                  systemImage: diary.isUsual(name: entry.name) ? "bookmark.fill" : "bookmark")
                                        }
                                        .disabled(diary.isUsual(name: entry.name))
                                        Button(role: .destructive) {
                                            diary.removeEntry(entry.id)
                                        } label: {
                                            Label("Delete meal", systemImage: "trash")
                                        }
                                    }
                                    .swipeActions(edge: .leading) {
                                        Button {
                                            _ = diary.saveUsualFromEntry(entry)
                                        } label: {
                                            Label("Save as usual", systemImage: "bookmark")
                                        }
                                        .tint(Theme.accent)
                                    }
                                    .swipeActions(edge: .trailing) {
                                        Button(role: .destructive) {
                                            diary.removeEntry(entry.id)
                                        } label: {
                                            Label("Delete", systemImage: "trash")
                                        }
                                    }
                                Divider().overlay(Theme.rule)
                            }
                        }
                    }
                }
            }
            if diary.state.healthEnabled && diary.state.includeOtherSources && !diary.otherHealthSamples.isEmpty {
                DisclosureGroup("Additional Apple Health nutrition") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("\(diary.otherTotal.calories.wholeNumber) kcal · P \(diary.otherTotal.protein.wholeNumber) · C \(diary.otherTotal.carbs.wholeNumber) · F \(diary.otherTotal.fat.wholeNumber) g")
                            .font(.system(.caption, design: .monospaced))
                        Text(Array(Set(diary.otherHealthSamples.map(\.sourceName))).sorted().joined(separator: ", "))
                        Text("Included in totals. Edit in the source app or Health. Without source timezone data, dates follow this device.")
                    }.font(.caption).foregroundStyle(Theme.muted).padding(.top, 8)
                }.font(.subheadline)
            }
        }.surface()
    }
    private var healthConnectCard: some View {
        HStack(alignment: .center, spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color.pink.opacity(0.15))
                    .frame(width: 38, height: 38)
                Image(systemName: "heart.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(.pink)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text("Sync with Apple Health")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.ink)
                Text("Write back logged meals and body weight.")
                    .font(.caption)
                    .foregroundStyle(Theme.muted)
            }
            Spacer(minLength: 8)
            Button("Connect") {
                Task { await diary.connectAllHealth() }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            Button {
                dismissedHealthBanner = true
            } label: {
                Image(systemName: "xmark")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(Theme.muted)
                    .padding(6)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss Apple Health prompt")
        }
        .surface()
    }
    private var healthNote: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "heart.fill")
                    .font(.caption)
                    .foregroundStyle(.pink)
                if diary.isSyncing || diary.isRefreshing {
                    ProgressView("Updating Apple Health…").font(.caption)
                } else if let date = diary.lastRefreshed {
                    Text("Apple Health synced · \(date.formatted(date: .omitted, time: .shortened))")
                        .font(.caption).foregroundStyle(Theme.muted)
                } else {
                    Text("Apple Health connected")
                        .font(.caption).foregroundStyle(Theme.muted)
                }
                Spacer()
                if diary.pendingEntries > 0 || diary.pendingBodyEntries > 0 {
                    Button("Sync now") {
                        Task { await diary.synchronize() }
                    }
                    .font(.caption.weight(.medium))
                    .disabled(diary.isSyncing)
                }
            }
            if !diary.readWarning.isEmpty {
                Notice(text: "Some Health data could not be read. Totals may be incomplete. \(diary.readWarning)", symbol: "exclamationmark.triangle")
            }
            if diary.pendingEntries > 0 || diary.pendingBodyEntries > 0 || !diary.state.deletions.isEmpty || !diary.state.bodyDeletions.isEmpty {
                let parts = [
                    diary.pendingEntries > 0 ? "\(diary.pendingEntries) \(diary.pendingEntries == 1 ? "meal" : "meals")" : nil,
                    diary.pendingBodyEntries > 0 ? "\(diary.pendingBodyEntries) \(diary.pendingBodyEntries == 1 ? "weight" : "weights")" : nil,
                    (!diary.state.deletions.isEmpty || !diary.state.bodyDeletions.isEmpty) ? "\(diary.state.deletions.count + diary.state.bodyDeletions.count) deletions" : nil
                ].compactMap { $0 }
                Notice(text: "\(parts.joined(separator: ", ")) pending export. Check Health permissions or retry.")
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private func entryStatus(_ entry: FoodEntry) -> String {
        if !diary.state.healthEnabled || entry.exportCount == 4 { return "" }
        return "Health pending · \(entry.exportCount)/4 values"
    }
    private func newEntry() {
        let date = diary.defaultEntryDate()
        editor = EditorRequest(entry: FoodEntry(name: "", date: date, meal: .suggested(at: date), nutrition: .zero))
    }
}

struct FoodLedgerRow: View {
    let entry: FoodEntry
    let status: String
    @Environment(\.dynamicTypeSize) private var dynamicType
    var body: some View {
        let layout = dynamicType.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(alignment: .top, spacing: 12))
        layout {
            VStack(alignment: .leading, spacing: 5) {
                Text(entry.name).font(.body).foregroundStyle(Theme.ink)
                Text("P \(entry.nutrition.protein.displayNumber) · C \(entry.nutrition.carbs.displayNumber) · F \(entry.nutrition.fat.displayNumber) g")
                    .font(.system(.caption, design: .monospaced)).foregroundStyle(Theme.muted)
                if let clock = entry.clock, clock.timeZoneID != TimeZone.current.identifier || clock.needsReview {
                    Text(EntryClock.label(date: entry.date, clock: clock))
                        .font(.caption).foregroundStyle(Theme.muted)
                }
                if !status.isEmpty { Text(status).font(.caption).foregroundStyle(Theme.muted) }
            }.frame(maxWidth: .infinity, alignment: .leading)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(entry.isEstimate ? "≈ " : "")\(entry.nutrition.calories.wholeNumber)")
                    .font(.system(.body, design: .monospaced)).foregroundStyle(Theme.ink)
                Text("kcal").font(.system(.caption2, design: .monospaced)).foregroundStyle(Theme.muted)
            }.fixedSize(horizontal: true, vertical: false)
        }.multilineTextAlignment(.leading).padding(.vertical, 16).frame(minHeight: 44).contentShape(Rectangle())
            .accessibilityElement(children: .combine)
    }
}
