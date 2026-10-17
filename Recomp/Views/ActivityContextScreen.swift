import SwiftUI

@MainActor
struct ActivityContextScreen: View {
    @EnvironmentObject private var diary: DiaryStore
    @EnvironmentObject private var activity: ActivityModel
    @Environment(\.dismiss) private var dismiss
    @State private var confirmConnect = false
    @State private var editingEvent: ContextEvent?
    private var preferences: ActivityPreferences { diary.state.activityPreferences }
    private var workouts: [WorkoutRecord] { ActivityMath.workouts(activity.readout.workouts, preferences: preferences) }
    private var nights: [SleepNight] { ActivityMath.sleepNights(activity.readout.sleep, sourceID: preferences.sleepSourceID) }
    private var duplicates: Set<UUID> { ActivityMath.possibleDuplicateIDs(workouts) }
    private var days: [Date] {
        let c = Calendar.current
        return Array(Set(workouts.map { c.startOfDay(for: $0.start) } + activity.readout.steps.map(\.date) + nights.map(\.date))).sorted(by: >)
    }
    var body: some View {
        Form {
            Section {
                Text("Keep recording runs in Strava and lifting in Strong. Recomp reads workout summaries, steps and sleep that are available in Apple Health.")
                Text("Steps and workout details feed Recomp’s own expenditure model, using your weight and typical activity. Apple calorie estimates are not read. Food targets never change automatically. No workout data is sent to the meal AI service.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Apple Health connection") {
                if preferences.enabled {
                    Button("Refresh available history") { Task { await activity.refresh(enabled: true) } }.disabled(activity.busy)
                    Button("Review permissions") { confirmConnect = true }
                    Button("Pause activity reads") { change { $0.enabled = false } }
                } else { Button("Connect workouts, steps & sleep") { confirmConnect = true } }
                if activity.busy { ProgressView("Reading available data…") }
                if let date = activity.readout.refreshedAt {
                    Text("Read through \(date.formatted(date: .abbreviated, time: .shortened)). Up to 30 days; today's data may be partial.").font(.caption)
                }
                Text("Empty data can mean no records, denied access or an app that has not synced. A completed permission prompt does not prove access. Pausing clears Recomp's in-memory activity view; it does not change Health or revoke permissions.")
                    .font(.caption).foregroundStyle(.secondary)
                DisclosureGroup("Strava / Strong setup") {
                    Text("Strava: Settings → Manage Apps and Devices → Health → enable Send to Health. Strong: Profile → Settings → App Integrations → Apple Health → Connect. Enable workout sharing in each app, then allow Recomp to read workouts.")
                    Text("This connection imports Health workout summaries, not Strong's exercise names, individual sets, reps or lifted weights. Keep those details in Strong. No direct Strava/Strong OAuth or cloud API is used, and Recomp never creates another workout copy.")
                    Text("If the same session exists from your Watch and Strava, select one writer or hide a duplicate here. Hidden copies remain in Apple Health.")
                }.font(.caption)
            }
            if preferences.enabled {
                Section("Sources & copies") {
                    Picker("Workouts", selection: Binding(get: { preferences.workoutSourceID }, set: { id in change { $0.workoutSourceID = id } })) {
                        Text("All readable sources").tag(Optional<String>.none)
                        ForEach(activity.workoutSources) { Text($0.name).tag(Optional($0.id)) }
                        if let selected = preferences.workoutSourceID, !activity.workoutSources.contains(where: { $0.id == selected }) {
                            Text("Selected source unavailable").tag(Optional(selected))
                        }
                    }
                    Picker("Sleep source", selection: Binding(get: { preferences.sleepSourceID }, set: { id in change { $0.sleepSourceID = id } })) {
                        Text(activity.sleepSources.count > 1 ? "Choose one source" : "Automatic if only one source").tag(Optional<String>.none)
                        ForEach(activity.sleepSources) { Text($0.name).tag(Optional($0.id)) }
                        if let selected = preferences.sleepSourceID, !activity.sleepSources.contains(where: { $0.id == selected }) {
                            Text("Selected source unavailable").tag(Optional(selected))
                        }
                    }
                    if !duplicates.isEmpty { Text("\(duplicates.count) workout records may contain copies. Review the marked rows before treating counts as sessions.").font(.caption) }
                    if !preferences.hiddenWorkoutIDs.isEmpty {
                        DisclosureGroup("Hidden workouts (\(preferences.hiddenWorkoutIDs.count))") {
                            ForEach(activity.readout.workouts.filter { preferences.hiddenWorkoutIDs.contains($0.id) }) { w in
                                Button("Restore \(w.title) · \(w.start.formatted(date: .abbreviated, time: .shortened)) · \(w.source.name)") { change { $0.hiddenWorkoutIDs.remove(w.id) } }
                            }
                            Button("Clear all local workout hiding") { change { $0.hiddenWorkoutIDs = [] } }
                        }.font(.caption)
                    }
                    Text("Steps use HealthKit's merged daily totals. Sleep counts the union of asleep intervals within one source, excluding in-bed and awake intervals. A night is the noon-to-noon window ending on its displayed date; missing days stay missing.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let comparison = ActivityMath.stepComparison(activity.readout.steps) {
                    Section("Routine context") { Text(comparison).font(.subheadline) }
                }
                if !activity.readout.warnings.isEmpty {
                    Section("Coverage notes") { ForEach(Array(activity.readout.warnings.enumerated()), id: \.offset) { _, message in Text(message).font(.caption) } }
                }
                Section("Available history") {
                    if days.isEmpty { Text("No readable activity yet. Check sharing in Strava, Strong and Apple Health.").foregroundStyle(.secondary) }
                    ForEach(days.prefix(30), id: \.self) { day in
                        DisclosureGroup(day.formatted(date: .abbreviated, time: .omitted) + (Calendar.current.isDateInToday(day) ? " · partial" : "")) {
                            if let step = activity.readout.steps.first(where: { Calendar.current.isDate($0.date, inSameDayAs: day) }) {
                                LabeledContent("Steps", value: step.count.formatted(.number.precision(.fractionLength(0)).grouping(.never)))
                            }
                            if let sleep = nights.first(where: { Calendar.current.isDate($0.date, inSameDayAs: day) }) {
                                LabeledContent("Sleep · \(sleep.source.name)", value: "\((sleep.seconds/3600).formatted(.number.precision(.fractionLength(1)))) h")
                            }
                            ForEach(workouts.filter { Calendar.current.isDate($0.start, inSameDayAs: day) }) { workout in
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("\(workout.title) · \((workout.duration/60).formatted(.number.precision(.fractionLength(0)).grouping(.never))) min").font(.headline)
                                    Text("\(workout.start.formatted(date: .omitted, time: .shortened)) · \(workout.source.name)").font(.caption)
                                    if let distance = workout.distanceMetres, distance > 0 {
                                        Text("\((distance/1000).formatted(.number.precision(.fractionLength(2)))) km").font(.system(.caption, design: .monospaced))
                                    }
                                    if duplicates.contains(workout.id) { Text("Possible duplicate from another writer").font(.caption).foregroundStyle(Theme.accent) }
                                    Button("Hide this record in Recomp") { change { $0.hiddenWorkoutIDs.insert(workout.id) } }.font(.caption)
                                }.padding(.vertical, 5)
                            }
                        }
                    }
                }
            }
            Section("Context notes") {
                Button("Add context") { editingEvent = ContextEvent(start: Date(), end: Date(), kind: .other) }
                ForEach(diary.state.contextEvents.sorted { $0.start > $1.start }) { event in
                    Button { editingEvent = event } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(event.kind.title).foregroundStyle(Theme.ink)
                            Text("\(event.start.formatted(date: .abbreviated, time: .omitted)) – \(event.end.formatted(date: .abbreviated, time: .omitted))").font(.caption)
                            if !event.note.isEmpty { Text(event.note).font(.caption).foregroundStyle(.secondary) }
                        }
                    }
                }
                Text("Notes annotate your history; they do not diagnose causes, alter weights or automatically exclude intake. Use the existing day/measurement exclusions when appropriate.").font(.caption).foregroundStyle(.secondary)
            }
        }
        .instrumentForm().navigationTitle("Activity & context").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
            }
        }
        .refreshable { await activity.refresh(enabled: preferences.enabled) }
        .sheet(item: $editingEvent) { ContextEditor(event: $0) }
        .confirmationDialog("Read activity from Apple Health?", isPresented: $confirmConnect, titleVisibility: .visible) {
            Button("Request read access") {
                Task { await activity.connect(using: diary) }
            }
        } message: { Text("Read workouts, steps and sleep only, for your local activity timeline and expenditure estimate. No workouts will be written or deleted. Review each permission separately.") }
        .alert("Activity needs attention", isPresented: Binding(get: { activity.error != nil }, set: { if !$0 { activity.error = nil } })) {
            Button("OK", role: .cancel) { activity.error = nil }
        } message: { Text(activity.error ?? "") }
    }
    private func change(_ edit: (inout ActivityPreferences) -> Void) { var p = preferences; edit(&p); diary.setActivityPreferences(p) }
}

@MainActor
struct ContextEditor: View {
    @EnvironmentObject private var diary: DiaryStore
    @Environment(\.dismiss) private var dismiss
    @State var event: ContextEvent
    @State private var confirmDelete = false
    var body: some View {
        NavigationStack {
            Form {
                Picker("Context", selection: $event.kind) { ForEach(ContextKind.allCases) { Text($0.title).tag($0) } }
                DatePicker("From", selection: $event.start, in: ...Date(), displayedComponents: .date)
                DatePicker("Through", selection: $event.end, in: event.start...max(Date(), event.start), displayedComponents: .date)
                TextField("Notes (optional)", text: $event.note, axis: .vertical).lineLimit(3...7)
                Text("Annotations only. No automatic calorie or measurement adjustment.").font(.caption)
                if diary.state.contextEvents.contains(where: { $0.id == event.id }) {
                    Button("Delete context note", role: .destructive) { confirmDelete = true }
                }
            }
            .instrumentForm().navigationTitle("Context note").navigationBarTitleDisplayMode(.inline)
            .onChange(of: event.start) { _, date in if event.end < date { event.end = date } }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") {
                    let c = Calendar.current
                    event.start = c.startOfDay(for: event.start)
                    event.end = (c.date(byAdding: .day, value: 1, to: c.startOfDay(for: event.end)) ?? event.end).addingTimeInterval(-1)
                    if diary.saveContext(event) { dismiss() }
                }.disabled(!event.isValid) }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { dismissKeyboard() }
                }
            }
            .confirmationDialog("Delete this note?", isPresented: $confirmDelete) {
                Button("Delete", role: .destructive) { diary.removeContext(event.id); dismiss() }
            }
        }
    }
}
