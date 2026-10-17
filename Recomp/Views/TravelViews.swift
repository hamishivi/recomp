import SwiftUI

struct EntryTimeFields: View {
    @Binding var date: Date
    @Binding var zoneID: String
    @Binding var confirmedZone: Bool
    var legacy = false
    @State private var chooseZone = false
    private var zone: TimeZone { TimeZone(identifier: zoneID) ?? .current }
    var body: some View {
        DatePicker("When", selection: $date, in: ...Date(), displayedComponents: [.date, .hourAndMinute])
            .environment(\.timeZone, zone).environment(\.calendar, EntryClock.calendar(in: zone))
        if legacy && !confirmedZone {
            Text("This older entry had no recorded timezone. Its display was frozen during upgrade, not recovered from GPS. Check the timezone before confirming it.")
                .font(.caption).foregroundStyle(.secondary)
            Toggle("I checked this entry's timezone", isOn: $confirmedZone)
        }
        DisclosureGroup("Timezone & details") {
            Button { chooseZone = true } label: { LabeledContent("Entry timezone", value: zoneID) }
            Text("This date stays fixed when you travel. Changing timezone keeps the same instant.")
                .font(.caption).foregroundStyle(.secondary)
            DatePicker("Exact time · UTC", selection: $date, in: ...Date(), displayedComponents: [.date, .hourAndMinute])
                .environment(\.timeZone, EntryClock.utc.timeZone).environment(\.calendar, EntryClock.utc)
            Text("Use UTC to distinguish repeated hours when daylight saving ends.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .sheet(isPresented: $chooseZone) {
            TimeZonePicker(zoneID: $zoneID) { confirmedZone = true }
        }
    }
}

struct TimeZonePicker: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var zoneID: String
    var didChoose: () -> Void = {}
    @State private var search = ""
    private var zones: [String] {
        TimeZone.knownTimeZoneIdentifiers.filter { search.isEmpty || $0.replacingOccurrences(of: "_", with: " ").localizedCaseInsensitiveContains(search) }
    }
    var body: some View {
        NavigationStack {
            List {
                Button("Use device timezone · \(TimeZone.current.identifier)") {
                    zoneID = TimeZone.current.identifier; didChoose(); dismiss()
                }
                ForEach(zones, id: \.self) { id in
                    Button { zoneID = id; didChoose(); dismiss() } label: {
                        HStack {
                            Text(id.replacingOccurrences(of: "_", with: " ")); Spacer()
                            if id == zoneID { Image(systemName: "checkmark") }
                        }
                    }
                }
            }.searchable(text: $search, prompt: "City or timezone")
                .navigationTitle("Timezone").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }
}

@MainActor
struct TravelCoverageScreen: View {
    @EnvironmentObject private var diary: DiaryStore
    @State private var editor: CoverageRequest?
    @State private var removing: DayReview?
    private var reviews: [DayReview] { diary.state.dayReviews.sorted { ($0.coverageInterval?.start ?? .distantPast) > ($1.coverageInterval?.start ?? .distantPast) } }
    var body: some View {
        List {
            Section {
                Text("Your diary keeps each meal's original local date. Maintenance uses confirmed, non-overlapping real hours, so flight days can be shorter or longer than 24 hours.")
                Button("Review a food / travel interval") { editor = CoverageRequest(review: nil) }
                    .accessibilityIdentifier("travel.review")
                Text("No GPS or itinerary is recorded. After flying, use Continue from last confirmation and check that every meal in those hours is present. Missing hours are not assumed to be fasting.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Confirmed coverage") {
                if reviews.isEmpty { Text("No confirmed food intervals yet.").foregroundStyle(.secondary) }
                ForEach(reviews) { review in
                    if let interval = review.coverageInterval {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("\(review.dayKey) · \(review.timeZoneID)").font(.headline)
                            Text("\(interval.duration / 3600, specifier: "%.1f") hours · \(review.total.calories.wholeNumber) kcal\(review.excludedFromAnalysis ? " · excluded" : "")")
                                .font(.system(.subheadline, design: .monospaced))
                            Text("\(interval.start.formatted(date: .abbreviated, time: .shortened)) → \(interval.end.formatted(date: .abbreviated, time: .shortened)) (shown in \(TimeZone.current.identifier))")
                                .font(.caption).foregroundStyle(.secondary)
                            if !review.note.isEmpty { Text(review.note).font(.caption) }
                            HStack {
                                Button("Review / replace") { editor = CoverageRequest(review: review) }
                                Spacer()
                                Button("Mark incomplete", role: .destructive) { removing = review }
                            }.buttonStyle(.borderless)
                        }.padding(.vertical, 4)
                    }
                }
            }
            Section("Travel details") {
                Text("A repeated date may contain more food than an ordinary day. Your daily target remains a normal-day reference—not a rule to skip food on a long flight or eat more on a short day.")
                Text("Older entries with inferred timezones are labelled assumed. Edit their Entry timezone to correct them. Imported Health records without timezone metadata remain view-local; use exact-time coverage review for maintenance.")
                Text("Steps, sleep and workouts still use the current viewing timezone. They are context only and do not change the maintenance equation.")
            }.font(.caption).foregroundStyle(.secondary)
        }.instrumentForm().navigationTitle("Travel & food coverage").navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editor) { request in CoverageEditor(review: request.review) }
        .alert("Remove this confirmation?", isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } })) {
            Button("Mark incomplete", role: .destructive) { if let removing { diary.removeCoverage(removing.id) }; removing = nil }
            Button("Cancel", role: .cancel) { removing = nil }
        } message: { Text("Your food stays in the diary. Only the completeness snapshot is removed, so these hours will need review again.") }
    }
}

struct CoverageRequest: Identifiable { var id = UUID(); var review: DayReview? }

@MainActor
struct CoverageEditor: View {
    @EnvironmentObject private var diary: DiaryStore
    @Environment(\.dismiss) private var dismiss
    let review: DayReview?
    @State private var start: Date
    @State private var end: Date
    @State private var zoneID: String
    @State private var includesHealth: Bool
    @State private var excluded: Bool
    @State private var note: String
    @State private var preview: CoveragePreview?
    @State private var loading = false
    @State private var requestID = UUID()
    @State private var confirmed = false
    @State private var replace = false
    @State private var chooseZone = false
    @State private var error: String?
    @State private var initialized = false
    init(review: DayReview?) {
        self.review = review
        let now = Date(), interval = review?.coverageInterval
        _start = State(initialValue: interval?.start ?? Calendar.current.startOfDay(for: now))
        _end = State(initialValue: min(interval?.end ?? now, now))
        _zoneID = State(initialValue: review?.timeZoneID ?? TimeZone.current.identifier)
        _includesHealth = State(initialValue: review?.includedHealth ?? false)
        _excluded = State(initialValue: review?.excludedFromAnalysis ?? false)
        _note = State(initialValue: review?.note ?? "")
    }
    private var interval: DateInterval? {
        guard start < end else { return nil }
        let i = DateInterval(start: start, end: end)
        return CoverageMath.validInterval(i) ? i : nil
    }
    private var conflicts: [DayReview] {
        guard let interval else { return [] }
        return diary.state.dayReviews.filter { $0.coverageInterval.map { CoverageMath.overlaps($0, interval) } == true }
    }
    private var previousEnd: Date? {
        diary.state.dayReviews.compactMap(\.coverageInterval).map(\.end).filter { $0 < end && $0 >= end.addingTimeInterval(-7 * CoverageMath.day) }.max()
    }
    var body: some View {
        NavigationStack {
            Form {
                Section("Actual food coverage") {
                    Button { chooseZone = true } label: { LabeledContent("Show times in", value: zoneID) }
                    DatePicker("From · included", selection: $start, in: ...Date())
                    DatePicker("Until · excluded", selection: $end, in: ...Date())
                    if let previousEnd, previousEnd != start {
                        Button("Continue from last confirmation") { start = previousEnd }
                    }
                    if start < Calendar.current.startOfDay(for: Date()), end != Calendar.current.startOfDay(for: Date()) {
                        Button("End at last device-local midnight") { end = Calendar.current.startOfDay(for: Date()) }
                        Text("Ending at your new local midnight lets ordinary day confirmations resume from that boundary.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if let interval {
                        LabeledContent("Elapsed time", value: String(format: "%.1f hours", interval.duration / 3600))
                    } else { Text("Choose an ended interval, up to seven days. Confirm ordinary days separately whenever possible.").font(.caption) }
                    Text("Use the actual boundaries of the hours you are confirming, not a guessed flight duration. Changing the display timezone does not move those boundaries.")
                        .font(.caption).foregroundStyle(.secondary)
                }.environment(\.timeZone, TimeZone(identifier: zoneID) ?? .current)
                    .environment(\.calendar, EntryClock.calendar(in: TimeZone(identifier: zoneID) ?? .current))
                Section {
                    Toggle("Include other Apple Health food", isOn: $includesHealth)
                        .disabled(!diary.state.healthEnabled && !includesHealth)
                    Button(loading ? "Reading…" : "Read food in these hours") { refresh() }
                        .disabled(loading || interval == nil)
                    Text("Read access can be denied without an error. Empty Health results do not prove nothing was eaten. Review food and duplicates yourself; Recomp's own exports are not counted twice.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let preview {
                    Section("Review before confirming") {
                        ForEach(preview.warnings, id: \.self) { Text($0).foregroundStyle(.secondary) }
                        ForEach(Nutrient.allCases) { n in LabeledContent(n.title, value: "\(preview.total[n].displayNumber) \(n.unit)") }
                        ForEach(preview.localEntries) { entry in
                            VStack(alignment: .leading) {
                                Text("\(entry.name) · \(entry.nutrition.calories.wholeNumber) kcal")
                                Text(EntryClock.label(date: entry.date, clock: entry.clock)).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        if preview.includesHealth {
                            Text("Includes \(preview.events.filter { $0.id.hasPrefix("health:") }.count) additional Health nutrient samples.").font(.caption)
                        }
                        Toggle("Every food and drink in these hours is included", isOn: $confirmed)
                    }
                }
                if !conflicts.isEmpty {
                    Section("Existing coverage overlaps") {
                        ForEach(conflicts) { r in Text("\(r.dayKey) · \(r.timeZoneID) · \(r.total.calories.wholeNumber) kcal").font(.caption) }
                        Toggle("Replace the listed confirmations", isOn: $replace)
                        Text("This replaces each listed confirmation in full, not the food records. Hours outside the new interval will need another review. No overlapping totals are added together.").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Section("Conditions") {
                    Toggle("Exclude these hours from maintenance", isOn: $excluded)
                    TextField("Travel / conditions / notes", text: $note, axis: .vertical)
                }
                Section {
                    Text("Only the reviewed snapshot is saved. Flight-day length does not automatically change your food targets. Editing any included meal invalidates its coverage—even after flying somewhere else.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }.instrumentForm().navigationTitle("Review food coverage").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { requestID = UUID(); dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Confirm") {
                        guard let preview else { return }
                        if diary.confirmCoverage(preview, timeZoneID: zoneID, excluded: excluded, note: note, replacingOverlaps: replace) { dismiss() }
                        else { error = diary.errorMessage; diary.errorMessage = nil }
                    }.disabled(!confirmed || preview == nil || loading || preview?.warnings.isEmpty == false || (!conflicts.isEmpty && !replace) || note.count > 1000)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { dismissKeyboard() }
                }
            }
            .onAppear {
                if !initialized {
                    initialized = true
                    if review == nil {
                        let range = diary.normalReviewInterval ?? DiaryMath.dayInterval(containing: diary.selectedDay)
                        start = range.start; end = min(range.end, Date()); zoneID = diary.normalReviewZone
                    }
                }
            }
            .onChange(of: start) { _, _ in invalidate() }
            .onChange(of: end) { _, _ in invalidate() }
            .onChange(of: includesHealth) { _, _ in invalidate() }
            .sheet(isPresented: $chooseZone) { TimeZonePicker(zoneID: $zoneID) }
            .alert("Review needed", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button("OK") { error = nil } } message: { Text(error ?? "") }
            .onDisappear { requestID = UUID() }
        }
    }
    private func invalidate() { requestID = UUID(); preview = nil; confirmed = false; replace = false; loading = false }
    private func refresh() {
        guard let interval else { return }
        let id = UUID(); requestID = id; loading = true; confirmed = false
        let include = includesHealth
        Task {
            let result = await diary.previewCoverage(interval: interval, includesHealth: include)
            guard requestID == id else { return }
            loading = false; preview = result
        }
    }
}
