import SwiftUI
import Charts

@MainActor
struct ScaleLocationPicker: View {
    @EnvironmentObject private var diary: DiaryStore
    @Binding var selection: UUID?
    @State private var adding = false
    @State private var name = ""
    var body: some View {
        Picker("Scale / location", selection: $selection) {
            Text("Untagged").tag(Optional<UUID>.none)
            ForEach(diary.state.scaleLocations.filter { !$0.archived || $0.id == selection }) { location in
                Text(location.name + (location.archived ? " (archived)" : "")).tag(Optional(location.id))
            }
        }
        Button { name = ""; adding = true } label: { Label("New scale / location", systemImage: "plus") }
            .alert("New scale / location", isPresented: $adding) {
                TextField("e.g. Home, Girlfriend’s, Gym", text: $name)
                Button("Cancel", role: .cancel) { }
                Button("Add") { if let id = diary.createScaleLocation(name: name) { selection = id } }
            } message: { Text("Use a separate label for each physical scale. No location access is requested.") }
    }
}

@MainActor
struct ScaleFilterPicker: View {
    @EnvironmentObject private var diary: DiaryStore
    @Binding var selection: ScaleFilter
    var body: some View {
        Picker("Scale / location", selection: $selection) {
            Text("All scales · separate lines").tag(ScaleFilter.all)
            Text("Untagged only").tag(ScaleFilter.untagged)
            ForEach(diary.state.scaleLocations) { location in
                Text(location.name + (location.archived ? " (archived)" : "")).tag(ScaleFilter.location(location.id))
            }
        }
    }
}

@MainActor
struct ScaleLocationsScreen: View {
    @EnvironmentObject private var diary: DiaryStore
    @State private var editing: ScaleLocation?
    @State private var name = ""
    @State private var prompt = false
    var body: some View {
        List {
            Section {
                ForEach(diary.state.scaleLocations) { location in
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(location.name)
                            if location.archived { Text("Archived · history retained").font(.caption).foregroundStyle(.secondary) }
                        }
                        Spacer()
                        Menu {
                            Button("Rename") { editing = location; name = location.name; prompt = true }
                            Button(location.archived ? "Restore" : "Archive") {
                                var changed = location; changed.archived.toggle()
                                _ = diary.saveScaleLocation(changed)
                            }
                        } label: { Image(systemName: "ellipsis").frame(minWidth: 44, minHeight: 44).accessibilityLabel("Manage \(location.name)") }
                    }
                }
                Button { editing = nil; name = ""; prompt = true } label: { Label("Add scale / location", systemImage: "plus") }
            } header: { Text("Your scales") } footer: {
                Text("Rename a label to update its existing history. Archive a scale you no longer use; its readings and charts remain. Replacing a scale? Create a new label, rather than reusing the old one.")
            }
            Section {
                Text("Labels are manual, local-only context—not GPS locations. They are not sent to Apple Health or the photo estimator. Imported Health readings can be tagged individually in Body.")
                Text("One label should identify one physical scale. The app cannot distinguish two scales accidentally given the same label.")
            }.font(.footnote).foregroundStyle(.secondary)
        }
        .instrumentForm()
        .navigationTitle("Scales & locations").navigationBarTitleDisplayMode(.inline)
        .alert(editing == nil ? "New scale / location" : "Rename scale / location", isPresented: $prompt) {
            TextField("Name", text: $name)
            Button("Cancel", role: .cancel) { }
            Button("Save") {
                if var location = editing {
                    location.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
                    _ = diary.saveScaleLocation(location)
                } else { _ = diary.createScaleLocation(name: name) }
            }
        } message: { Text("Choose a unique name of up to 60 characters.") }
    }
}

@MainActor
struct ImportedScaleEditor: View {
    @EnvironmentObject private var diary: DiaryStore
    @Environment(\.dismiss) private var dismiss
    let point: BodyPoint
    @State private var locationID: UUID?
    init(point: BodyPoint) {
        self.point = point
        _locationID = State(initialValue: point.scaleLocationID)
    }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("\(point.metric.title): \(point.value.displayNumber) \(point.metric.canonicalUnit)")
                    Text(point.date, format: .dateTime.month(.abbreviated).day().hour().minute())
                    Text("Source: \(point.source)").foregroundStyle(.secondary)
                }
                Section {
                    ScaleLocationPicker(selection: $locationID)
                } footer: {
                    Text("This labels just this imported reading inside Recomp. It does not change the value, modify Apple Health or create a duplicate measurement. Separately imported body-fat readings need their own tag.")
                }
            }
            .instrumentForm()
            .navigationTitle("Tag imported reading").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { if diary.assignHealthScale(point.id, locationID: locationID) { dismiss() } }
                }
            }
        }
    }
}

/// Always renders a separate curve per scale/method. Never draws a line between scales.
struct ScaleTrendPlot: View {
    let points: [BodyPoint]
    let metric: BodyMetric
    let units: MeasurementUnits
    let locations: [ScaleLocation]
    var rolling = false
    private var series: [BodyScaleSeries] { ScaleMath.series(points, metric: metric, locations: locations) }
    private var latest: BodyPoint? {
        points.filter { $0.metric == metric && !$0.excludedFromTrend }.max { a, b in
            a.date == b.date ? a.id.uuidString < b.id.uuidString : a.date < b.date
        }
    }
    private func lineValue(_ day: DailyBodyPoint, group: BodyScaleSeries) -> Double {
        guard rolling else { return units.display(day.value, metric: metric) }
        let cutoff = Calendar.current.date(byAdding: .day, value: -6, to: day.date) ?? day.date
        let window = group.points.filter { $0.date >= cutoff && $0.date <= day.date }
        let value = window.reduce(0.0) { $0 + $1.value } / Double(max(1, window.count))
        return units.display(value, metric: metric)
    }
    var body: some View {
        if !series.isEmpty, let latest {
            VStack(alignment: .leading, spacing: 12) {
                InstrumentValue(value: units.display(latest.value, metric: metric).displayNumber,
                                unit: units.unit(for: metric))
                Text("Latest · \(ScaleMath.seriesLabel(latest, locations: locations)) · \(latest.date.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption).foregroundStyle(.secondary)
                Chart {
                    ForEach(series) { group in
                        ForEach(group.points) { day in
                            PointMark(x: .value("Date", day.date), y: .value(metric.title, units.display(day.value, metric: metric)))
                                .foregroundStyle(by: .value("Scale / location", group.label))
                                .symbol(by: .value("Scale / location", group.label)).symbolSize(24)
                            LineMark(x: .value("Date", day.date), y: .value(metric.title, lineValue(day, group: group)),
                                     series: .value("Scale series", group.id))
                                .foregroundStyle(by: .value("Scale / location", group.label))
                                .lineStyle(StrokeStyle(lineWidth: 1.5))
                        }
                    }
                }
                .frame(height: 210).chartYScale(domain: .automatic(includesZero: false))
                .instrumentChart()
                .chartLegend(position: .bottom, alignment: .leading)
                .accessibilityLabel("\(metric.title) in \(units.unit(for: metric)), separate series per scale or method")
                Text(rolling ? "Dots: daily medians. Lines: seven-day averages within each scale only. Missing days are not filled. No cross-scale average is displayed."
                     : "Daily medians are calculated separately per scale/method. Lines never connect different scales. Raw readings are not adjusted or calibrated.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        } else {
            ContentUnavailableView("No readings for this selection", systemImage: "scalemass",
                                   description: Text("Log a measurement, change the filter or tag an existing reading."))
        }
    }
}
