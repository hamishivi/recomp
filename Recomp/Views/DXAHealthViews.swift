import SwiftUI

@MainActor
struct DXAHealthConnectionSection: View {
    @EnvironmentObject private var diary: DiaryStore
    @State private var requesting = false
    var body: some View {
        Section("Apple Health · DEXA") {
            LabeledContent("Scan syncing", value: diary.state.dxaHealthEnabled ? "On" : "Paused / not connected")
            LabeledContent("Pending values / removals", value: "\(diary.pendingDXAMetrics)")
            Button(diary.state.dxaHealthEnabled ? "Review Health permissions" : "Connect DEXA to Apple Health") {
                requesting = true
                Task { await diary.connectDXAHealth(); requesting = false }
            }.disabled(requesting || !diary.health.isAvailable || diary.loadFailure != nil)
            if requesting { ProgressView("Requesting permissions…") }
            if diary.state.dxaHealthEnabled {
                Button("Sync reviewed scans now") { Task { await diary.synchronize() } }.disabled(diary.isSyncing)
                Button("Pause DEXA syncing") { diary.pauseDXAHealth() }
            }
            if diary.isSyncing { ProgressView("Syncing…") }
            if !diary.syncMessage.isEmpty { Text(diary.syncMessage).font(.caption).foregroundStyle(Theme.accent) }
            Text("Connecting alone shares no unapproved scans. Open each scan → Review Health sharing. Weight, body fat and compatible lean body mass can be shared; the PDF and other report fields stay here.")
                .font(.caption).foregroundStyle(Theme.muted)
            Text("Paused syncing leaves existing Health samples intact. Pending removals need syncing on and write permission. Updates run while the app is open, not in the background.")
                .font(.caption).foregroundStyle(Theme.muted)
        }
    }
}

@MainActor
struct DXAScanHealthSection: View {
    @EnvironmentObject private var diary: DiaryStore
    let scan: DXAScan
    @State private var reviewing = false
    @State private var removing = false
    private var link: DXAHealthLink? { diary.dxaHealthLink(scan.id) }
    var body: some View {
        Section("Apple Health") {
            if let link, !link.selectedMetrics.isEmpty {
                ForEach(DXAHealthMetric.allCases.filter { link.selectedMetrics.contains($0) }) { metric in
                    LabeledContent(metric.title, value: status(metric, link: link))
                }
            } else { Text("No values selected for sharing.").foregroundStyle(Theme.muted) }
            if let link, !link.pendingMetrics(scan: scan).isEmpty {
                Text("\(link.pendingMetrics(scan: scan).count) value(s) or removal(s) pending\(diary.state.dxaHealthEnabled ? "" : " · syncing paused").")
                    .font(.caption).foregroundStyle(Theme.muted)
            }
            Button { reviewing = true } label: { Label("Review Health sharing", systemImage: "heart.text.clipboard") }
                .disabled(diary.loadFailure != nil)
            if let link, !link.selectedMetrics.isEmpty {
                Button("Remove this scan's Health exports", role: .destructive) { removing = true }
            }
            Text("Edits in Recomp update selected compatible values. Removing a selected result queues removal of its old Health sample. Scan weights never enter Recomp's scale-based maintenance model.")
                .font(.caption).foregroundStyle(Theme.muted)
            Text("“Write confirmed” is a receipt, not continuous verification. Deleting or editing a sample in Health does not change this scan; save sharing choices again to republish it. Another app's independent copy is not automatically deduplicated.")
                .font(.caption).foregroundStyle(Theme.muted)
        }
        .sheet(isPresented: $reviewing) { DXAHealthReviewScreen(scan: scan, link: link) }
        .confirmationDialog("Remove this scan's exports from Apple Health?", isPresented: $removing, titleVisibility: .visible) {
            Button("Remove Health exports", role: .destructive) { diary.removeDXAHealthExports(scan.id) }
        } message: {
            Text("The scan stays in Recomp. Only this scan's samples written by Recomp are queued for removal. If syncing is paused or permission is denied, cleanup waits until you reconnect.")
        }
    }
    private func status(_ metric: DXAHealthMetric, link: DXAHealthLink) -> String {
        if link.desiredValues(scan: scan).first(where: { $0.metric == metric }) == nil { return "Unavailable in report" }
        if link.completedVersions[metric.rawValue] == link.version { return "Write confirmed" }
        if !diary.state.dxaHealthEnabled { return "Pending · paused" }
        if !diary.dxaWritable.contains(metric) { return "Pending · permission" }
        return "Pending"
    }
}

@MainActor
struct DXAHealthReviewScreen: View {
    @EnvironmentObject private var diary: DiaryStore
    @Environment(\.dismiss) private var dismiss
    let scan: DXAScan // Immutable review snapshot; the store rejects stale approvals.
    private let hadLink: Bool
    @State private var selected: Set<DXAHealthMetric>
    @State private var date: Date
    @State private var timeZoneID: String
    @State private var approximate: Bool
    @State private var confirmed = false
    @State private var busy = false
    private var plan: DXAHealthPlan { DXAHealthMapping.plan(scan) }
    init(scan: DXAScan, link: DXAHealthLink?) {
        self.scan = scan; hadLink = link != nil
        let available = Set(DXAHealthMapping.plan(scan).candidates.map(\.metric))
        _selected = State(initialValue: (link?.selectedMetrics ?? available).intersection(available))
        let zone = link?.timeZoneID ?? TimeZone.current.identifier
        _timeZoneID = State(initialValue: zone)
        let noon = DXAHealthTime.date(day: scan.scanDay, timeZoneID: zone) ?? scan.date
        _date = State(initialValue: link?.date ?? min(noon, Date()))
        _approximate = State(initialValue: link?.timeIsApproximate ?? true)
    }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SectionHeading(title: "Share with Health", detail: scan.scanDay)
                    Text("Check the report and the exact values below. This does not share the PDF or create a bathroom-scale reading in Recomp.")
                        .foregroundStyle(Theme.muted)
                }
                Section("Whole-body values") {
                    if plan.candidates.isEmpty { Text("No compatible whole-body values. Edit the scan's sites and definitions first.") }
                    ForEach(plan.candidates) { candidate in
                        VStack(alignment: .leading, spacing: 6) {
                            Toggle(isOn: Binding(get: { selected.contains(candidate.metric) }, set: { on in
                                if on { selected.insert(candidate.metric) } else { selected.remove(candidate.metric) }
                                confirmed = false
                            })) {
                                VStack(alignment: .leading) {
                                    Text(candidate.metric.title)
                                    Text("\(candidate.value.formatted(.number.precision(.fractionLength(0...3)))) \(candidate.metric.unit)")
                                        .fontDesign(.monospaced)
                                }
                            }
                            Text(candidate.basis.explanation).font(.caption).foregroundStyle(Theme.muted)
                        }
                    }
                    ForEach(plan.warnings, id: \.self) { Text($0).font(.caption).foregroundStyle(Theme.muted) }
                    Text("Regional fat/lean, fat mass, bone density/content, T/Z-scores, visceral fat and the report's RMR are not mapped to unrelated Health types. Undefined “lean mass” is never guessed.")
                        .font(.caption).foregroundStyle(Theme.muted)
                }
                Section("Measurement time") {
                    LabeledContent("Scan date", value: scan.scanDay)
                    Picker("Scan timezone", selection: $timeZoneID) {
                        ForEach(Array(Set(TimeZone.knownTimeZoneIdentifiers + [timeZoneID])).sorted(), id: \.self) { Text($0).tag($0) }
                    }
                    .onChange(of: timeZoneID) { _, zone in
                        date = min(DXAHealthTime.date(day: scan.scanDay, timeZoneID: zone) ?? scan.date, Date())
                        approximate = true; confirmed = false
                    }
                    DatePicker("Scan time", selection: $date, displayedComponents: [.hourAndMinute])
                        .environment(\.timeZone, TimeZone(identifier: timeZoneID) ?? .current)
                        .onChange(of: date) { _, _ in confirmed = false }
                    Toggle("Time is approximate", isOn: $approximate).onChange(of: approximate) { _, _ in confirmed = false }
                    Text("For date-only reports, noon is a labelled placeholder (or the current time if earlier today). Enter the actual scan time when known. Use the clinic's timezone for travel scans.")
                        .font(.caption).foregroundStyle(Theme.muted)
                }
                Section {
                    Toggle("I reviewed the selected values and time", isOn: $confirmed)
                    Text("Saving enables syncing for these fields of this scan. Future edits update them; deselection or deleting this scan removes only its Recomp-owned exports. Other apps may include these values in their own averages. Avoid exporting a second copy through your scan provider's app.")
                        .font(.caption).foregroundStyle(Theme.muted)
                    if busy { ProgressView("Saving Health choices…") }
                }
            }
            .instrumentForm().navigationTitle("DEXA → Health").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(busy) }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(!confirmed || busy || (!hadLink && selected.isEmpty) || diary.loadFailure != nil)
                }
            }
            .interactiveDismissDisabled(busy)
            .alert("Check Health sharing", isPresented: Binding(get: { diary.errorMessage != nil }, set: { if !$0 { diary.errorMessage = nil } })) {
                Button("OK") { diary.errorMessage = nil }
            } message: { Text(diary.errorMessage ?? "") }
        }
    }
    private func save() {
        busy = true
        Task {
            // Save consent/selection first, even if authorization later fails. Never imply successful export.
            guard diary.configureDXAHealth(reviewedScan: scan, metrics: selected, date: date,
                timeZoneID: timeZoneID, timeIsApproximate: approximate) else { busy = false; return }
            if !diary.state.dxaHealthEnabled { await diary.connectDXAHealth() }
            busy = false
            if diary.errorMessage == nil { dismiss() }
        }
    }
}
