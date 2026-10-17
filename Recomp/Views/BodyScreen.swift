import SwiftUI
import Charts

private struct BodyEditorRequest: Identifiable {
    let id = UUID()
    var record: BodyMeasurement?
}

@MainActor
struct BodyScreen: View {
    @EnvironmentObject private var diary: DiaryStore
    @State private var metric: BodyMetric = .weight
    @State private var range = 90
    @State private var editor: BodyEditorRequest?
    @State private var hideReading: BodyPoint?
    @State private var importedTag: BodyPoint?
    @State private var scaleFilter: ScaleFilter = .all
    private var points: [BodyPoint] {
        let start = Calendar.current.date(byAdding: .day, value: -range, to: Date()) ?? Date()
        return diary.bodyPoints.filter { $0.metric == metric && $0.date >= start && $0.date <= Date() && scaleFilter.includes($0) }
    }
    private var units: MeasurementUnits { diary.state.measurementUnits }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    chartCard
                    Button { editor = BodyEditorRequest() } label: {
                        Label("Log measurements", systemImage: "plus").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 8)
                    }.instrumentPrimary().disabled(diary.loadFailure != nil)
                    NavigationLink { DXAScansScreen() } label: {
                        HStack {
                            Label("DEXA scans", systemImage: "doc.text.magnifyingglass")
                            Spacer()
                            Text("\(diary.state.dxaScans.count) reports").font(.system(.caption, design: .monospaced))
                            Image(systemName: "chevron.right").font(.caption)
                        }.padding(.vertical, 10)
                    }
                    historyCard
                    NavigationLink { HealthSettingsScreen() } label: {
                        HStack {
                            Label("Apple Health", systemImage: "heart.fill")
                                .foregroundStyle(diary.state.bodyHealthEnabled ? Theme.accent : Theme.ink)
                            Spacer()
                            Text(diary.state.bodyHealthEnabled ? "\(diary.bodyWritable.count)/3 write permissions" : "Not connected")
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(Theme.muted)
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(Theme.muted)
                        }.padding(.vertical, 4)
                    }
                    Notice(text: "Use comparable conditions and the same measuring method. Record body fat as reported by your device or test; this app does not infer it from photos or treat changes as exact muscle/fat gains.")
                }.padding(18).frame(maxWidth: 640).frame(maxWidth: .infinity)
            }
            .background(Theme.background).navigationTitle("Body").navigationBarTitleDisplayMode(.inline)
            .refreshable { await diary.synchronize() }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink { ScaleLocationsScreen() } label: { Image(systemName: "tag").accessibilityLabel("Manage scales and locations") }
                }
            }
            .sheet(item: $editor) { request in MeasurementEditor(record: request.record, units: units, defaultLocationID: diary.state.lastScaleLocationID) }
            .sheet(item: $importedTag) { point in ImportedScaleEditor(point: point) }
            .confirmationDialog("Hide this imported reading?", isPresented: Binding(get: { hideReading != nil }, set: { if !$0 { hideReading = nil } }), titleVisibility: .visible) {
                Button("Hide in Recomp", role: .destructive) {
                    if let reading = hideReading { diary.ignoreHealthMeasurement(reading.id) }; hideReading = nil
                }
            } message: { Text("This does not delete anything from Apple Health. Restore hidden readings using the button below the history.") }
        }
    }
    private var chartCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeading(title: "Measurements", detail: "logbook")
            HStack {
                Picker("Measurement", selection: $metric) { ForEach(BodyMetric.allCases) { Text($0.title).tag($0) } }
                Spacer()
                Text(units.unit(for: metric)).foregroundStyle(.secondary)
            }
            Picker("History window", selection: $range) {
                Text("30 days").tag(30); Text("90 days").tag(90); Text("180 days").tag(180)
            }.pickerStyle(.segmented)
            ScaleFilterPicker(selection: $scaleFilter)
            ScaleTrendPlot(points: points, metric: metric, units: units, locations: diary.state.scaleLocations)
            DisclosureGroup("Reading sources") {
                Text("Local entries take priority over imports within the same scale/day. Excluded readings remain in history. Imported history covers up to 180 days. Manage scale labels using the tag button above.")
                    .font(.caption).foregroundStyle(Theme.muted).padding(.top, 8)
            }.font(.caption)
        }.surface()
    }
    private var historyCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeading(title: "History", detail: metric.title.lowercased())
            if points.isEmpty { Text("No readings in this period.").foregroundStyle(.secondary) }
            ForEach(Array(points.reversed())) { point in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("\(units.display(point.value, metric: metric).displayNumber) \(units.unit(for: metric))").font(.system(.title3, design: .monospaced))
                        Spacer()
                        Text(EntryClock.label(date: point.date, clock: point.clock)).font(.caption).foregroundStyle(.secondary)
                    }
                    Label(ScaleMath.locationName(point.scaleLocationID, locations: diary.state.scaleLocations), systemImage: "tag")
                        .font(.system(.caption, design: .monospaced)).foregroundStyle(Theme.muted)
                    HStack {
                        Text([point.source, point.method, point.excludedFromTrend ? "Excluded from trends" : ""].filter { !$0.isEmpty }.joined(separator: " · "))
                            .font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        if point.isLocal {
                            Button("Edit") { if let record = diary.state.measurements.first(where: { $0.id == point.id }) { editor = BodyEditorRequest(record: record) } }
                        } else {
                            Button("Tag") { importedTag = point }.font(.subheadline).frame(minWidth: 44, minHeight: 44)
                            Button("Hide") { hideReading = point }.font(.subheadline).frame(minWidth: 44, minHeight: 44)
                        }
                    }
                }.padding(.vertical, 6)
                Divider()
            }
            if !diary.state.ignoredHealthBodyIDs.isEmpty {
                Button("Restore \(diary.state.ignoredHealthBodyIDs.count) hidden Health readings") { diary.restoreIgnoredHealthMeasurements() }.font(.caption)
            }
            Text("Edit imported values in Apple Health or their source app. No samples from other apps are deleted by Recomp.")
                .font(.caption).foregroundStyle(.secondary)
        }.surface()
    }
}

@MainActor
struct MeasurementEditor: View {
    @EnvironmentObject private var diary: DiaryStore
    @Environment(\.dismiss) private var dismiss
    let record: BodyMeasurement?
    @State private var date: Date
    @State private var zoneID: String
    @State private var confirmedZone: Bool
    @State private var units: MeasurementUnits
    @State private var inputs: [BodyMetric: String]
    @State private var method: String
    @State private var note: String
    @State private var excluded: Bool
    @State private var deletePrompt = false
    @State private var scaleLocationID: UUID?
    @FocusState private var focusedMetric: BodyMetric?
    @State private var overwriteOnNextInput: BodyMetric?
    init(record: BodyMeasurement?, units: MeasurementUnits, defaultLocationID: UUID? = nil) {
        self.record = record
        _scaleLocationID = State(initialValue: record == nil ? defaultLocationID : record?.scaleLocationID)
        _date = State(initialValue: record?.date ?? Date())
        _zoneID = State(initialValue: record?.clock?.timeZoneID ?? TimeZone.current.identifier)
        _confirmedZone = State(initialValue: record?.clock?.needsReview != true)
        _units = State(initialValue: units)
        _inputs = State(initialValue: record.map { [$0.metric: InputNumber.editString(units.display($0.value, metric: $0.metric))] } ?? [:])
        _method = State(initialValue: record?.method ?? "")
        _note = State(initialValue: record?.note ?? "")
        _excluded = State(initialValue: record?.excludedFromTrend ?? false)
    }
    private var metrics: [BodyMetric] { record.map { [$0.metric] } ?? BodyMetric.allCases }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    EntryTimeFields(date: $date, zoneID: $zoneID, confirmedZone: $confirmedZone, legacy: record?.clock?.needsReview == true)
                    Picker("Units", selection: $units) { ForEach(MeasurementUnits.allCases) { Text($0.title).tag($0) } }
                        .onChange(of: units) { old, new in
                            for metric in metrics {
                                if let value = InputNumber.parse(inputs[metric] ?? "") {
                                    inputs[metric] = InputNumber.editString(new.display(old.canonical(value, metric: metric), metric: metric))
                                }
                            }
                        }
                }
                Section {
                    ForEach(metrics) { metric in
                        HStack {
                            Text(metric.title); Spacer()
                            TextField("Optional", text: Binding(
                                get: { inputs[metric] ?? "" },
                                set: { newRaw in
                                    let shouldOverwrite = (overwriteOnNextInput == metric)
                                    overwriteOnNextInput = nil
                                    inputs[metric] = InputNumber.overwriteOrAppend(old: inputs[metric] ?? "", new: newRaw, shouldOverwrite: shouldOverwrite)
                                }
                            ))
                            .fontDesign(.monospaced).keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(maxWidth: 125)
                            .focused($focusedMetric, equals: metric)
                            .accessibilityLabel("\(metric.title), \(units.unit(for: metric))")
                            .accessibilityIdentifier("measurement.\(metric.rawValue)")
                            Text(units.unit(for: metric)).foregroundStyle(.secondary)
                        }
                    }
                } header: { Text("Measurements") } footer: {
                    Text("Fill only the values you measured. Enter 19 for 19% body fat. No values are inferred, and blank fields do not erase other records.")
                }
                Section {
                    ScaleLocationPicker(selection: $scaleLocationID)
                    NavigationLink("Manage scales & locations") { ScaleLocationsScreen() }
                } header: { Text("Scale / location") } footer: {
                    Text("Applies to every measurement saved in this check-in. The last used tag is preselected for new check-ins—check it before saving. Existing untagged readings stay untagged until you edit them.")
                }
                Section("Context") {
                    TextField("Method/device, e.g. bathroom scale or tape", text: $method)
                    TextField("Notes: side, measurement location, conditions…", text: $note, axis: .vertical).lineLimit(2...5)
                    Toggle("Exclude from trends", isOn: $excluded)
                    Text(diary.state.bodyHealthEnabled
                        ? "Save syncs weight, body fat and waist to Apple Health."
                        : "Saved locally. Connect Apple Health in Settings to sync weight.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if record != nil { Section { Button("Delete measurement", role: .destructive) { deletePrompt = true } } }
            }
            .instrumentForm()
            .navigationTitle(record == nil ? "Log measurements" : "Edit measurement").navigationBarTitleDisplayMode(.inline)
            .onAppear { overwriteOnNextInput = focusedMetric }
            .onChange(of: focusedMetric) { _, new in overwriteOnNextInput = new }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { save() }.disabled(diary.loadFailure != nil) }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { dismissKeyboard() }
                }
            }
            .confirmationDialog("Delete this measurement?", isPresented: $deletePrompt, titleVisibility: .visible) {
                Button("Delete", role: .destructive) { if let record { diary.removeMeasurement(record.id) }; dismiss() }
            } message: { Text("Its Recomp-owned Health sample will be queued for removal when measurement sync and permission are enabled.") }
        }
    }
    private func save() {
        guard method.count <= 100, note.count <= 1000 else { diary.errorMessage = "Shorten the method or notes."; return }
        var records: [BodyMeasurement] = []
        for metric in metrics {
            let text = (inputs[metric] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if text.isEmpty { continue }
            guard let number = InputNumber.parse(text), metric.accepts(units.canonical(number, metric: metric)) else {
                diary.errorMessage = "Check \(metric.title.lowercased()) and its units. Enter a valid measurement, not a fraction for body-fat percentage."; return
            }
            var value = record ?? BodyMeasurement(date: date, metric: metric, value: 0)
            value.scaleLocationID = scaleLocationID
            value.clock = EntryClock.updated(record?.clock, from: record?.date, to: date, zoneID: zoneID, confirmed: confirmedZone)
            value.date = date; value.value = units.canonical(number, metric: metric)
            value.method = method.trimmingCharacters(in: .whitespacesAndNewlines); value.note = note; value.excludedFromTrend = excluded
            records.append(value)
        }
        if diary.saveMeasurements(records) { diary.setMeasurementUnits(units); dismiss() }
    }
}
