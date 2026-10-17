import SwiftUI
import Charts
import PDFKit
import UniformTypeIdentifiers

private struct DXAValueRequest: Identifiable {
    var id = UUID()
    var value: DXAValue
}

@MainActor
struct DXAScansScreen: View {
    @EnvironmentObject private var diary: DiaryStore
    @State private var adding = false
    @State private var exporting = false
    @State private var trendMetric: DXAMetric = .bodyFat
    private var scans: [DXAScan] { diary.state.dxaScans.sorted { $0.scanDay > $1.scanDay } }
    var body: some View {
        List {
            Section {
                SectionHeading(title: "Scan log", detail: "DEXA / DXA")
                Text("Import a PDF, paste report text, or enter results. Review each value before saving.")
                    .foregroundStyle(Theme.muted)
                Button { adding = true } label: { Label("Add scan", systemImage: "doc.badge.plus") }
                    .disabled(diary.loadFailure != nil)
            }
            DXAHealthConnectionSection()
            if scans.count > 1 {
                Section("Total-body scan history") {
                    Picker("Metric", selection: $trendMetric) {
                        ForEach([DXAMetric.bodyFat, .fatMass, .leanSoftTissue, .totalMass, .boneMineralContent]) { Text($0.title).tag($0) }
                    }
                    Chart {
                        ForEach(scans.reversed()) { scan in
                            if let value = scan.value(trendMetric) {
                                PointMark(x: .value("Scan date", scan.date), y: .value(trendMetric.canonicalUnit, value.canonicalValue))
                                    .foregroundStyle(Theme.accent)
                            }
                        }
                    }.frame(height: 170).instrumentChart()
                    Text("Individual scans, not an interpolated daily trend. Units: \(trendMetric.canonicalUnit). Open a scan for changes within an explicitly assigned comparison group.")
                        .font(.caption).foregroundStyle(Theme.muted)
                }
            }
            Section("Reports") {
                if scans.isEmpty {
                    ContentUnavailableView("No scans yet", systemImage: "doc.text.magnifyingglass", description: Text("No sample scans are added to your diary."))
                }
                ForEach(scans) { scan in
                    NavigationLink { DXAScanDetail(scanID: scan.id) } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(scan.provider).font(.headline)
                            Text(scan.scanDay).font(.system(.subheadline, design: .monospaced))
                            if let fat = scan.value(.bodyFat) { Text("\(fat.value.dxaNumber)% total body fat").foregroundStyle(Theme.muted) }
                            if !scan.comparisonGroup.isEmpty { Text(scan.comparisonGroup).font(.caption).foregroundStyle(Theme.muted) }
                        }.padding(.vertical, 4)
                    }
                }
            }
            Section {
                Text("Scan measurements stay separate from home and girlfriend’s scales. Importing never changes daily targets, calibrates body-fat scales, or sends report content to the food-estimation server. Compatible values go to Apple Health only after you review sharing for that scan.")
                Text("Use a consistent scanner and protocol when comparing scans. A matching label is your annotation, not a verification of calibration. Reported lean tissue is not a direct muscle measurement.")
            }.font(.caption).foregroundStyle(Theme.muted)
            if !scans.isEmpty { Section { Button("Export scan values as CSV") { exporting = true } } }
        }
        .instrumentForm().navigationTitle("DEXA scans").navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $adding) { DXAScanEditor(scan: nil) }
        .fileExporter(isPresented: $exporting, document: CSVDocument(text: DXACSV.make(scans)),
                      contentType: .commaSeparatedText, defaultFilename: "Recomp-DXA-values") { result in
            if case .failure = result { diary.errorMessage = "The scan CSV could not be exported." }
        }
    }
}

@MainActor
struct DXAScanDetail: View {
    @EnvironmentObject private var diary: DiaryStore
    @Environment(\.dismiss) private var dismiss
    let scanID: UUID
    @State private var editing = false
    @State private var deleting = false
    private var scan: DXAScan? { diary.state.dxaScans.first { $0.id == scanID } }
    var body: some View {
        Group {
            if let scan {
                List {
                    Section {
                        SectionHeading(title: scan.provider, detail: scan.scanDay)
                        if !scan.scanner.isEmpty { LabeledContent("Scanner", value: scan.scanner) }
                        LabeledContent("Comparison group", value: scan.comparisonGroup.isEmpty ? "Unassigned" : scan.comparisonGroup)
                        Text("These are transcribed report values, not a medical interpretation.").font(.caption).foregroundStyle(Theme.muted)
                    }
                    DXAScanHealthSection(scan: scan)
                    Section("Reviewed results") {
                        ForEach(scan.values) { value in
                            VStack(alignment: .leading, spacing: 6) {
                                LabeledContent(value.metric.title) { Text("\(value.value.dxaNumber) \(value.unit.title)").fontDesign(.monospaced) }
                                Text(value.region).font(.caption).foregroundStyle(Theme.muted)
                                if let comparison = DXATrends.previousDifference(for: value, scan: scan, scans: diary.state.dxaScans) {
                                    let unit = value.metric == .bodyFat ? "percentage points" : value.metric.canonicalUnit
                                    Text("\(comparison.difference >= 0 ? "+" : "")\(comparison.difference.dxaNumber) \(unit) vs \(comparison.previousDay)")
                                        .font(.caption).foregroundStyle(Theme.muted)
                                }
                                if !value.sourceExcerpt.isEmpty {
                                    DisclosureGroup("Source text (before edits)") { Text(value.sourceExcerpt).font(.caption).textSelection(.enabled) }.font(.caption)
                                }
                            }.padding(.vertical, 4)
                        }
                    }
                    if !scan.notes.isEmpty { Section("Notes") { Text(scan.notes).textSelection(.enabled) } }
                    if let data = scan.retainedPDF {
                        Section("Original report") {
                            NavigationLink("View or export retained PDF") { DXAPDFScreen(data: data, title: scan.sourceFilename) }
                        }
                    } else if !scan.sourceFilename.isEmpty {
                        Section("Source") { Text("\(scan.sourceFilename) · PDF not retained. Your original in Files is unchanged.").font(.caption) }
                    }
                    Section {
                        Text("Differences are shown only for the same metric, site and assigned comparison group. They do not establish significant tissue change or which device is correct. Unconfirmed lean definitions are not compared.")
                            .font(.caption).foregroundStyle(Theme.muted)
                        Button("Edit scan") { editing = true }
                        Button("Delete scan", role: .destructive) { deleting = true }
                    }
                }.instrumentForm()
                .sheet(isPresented: $editing) { DXAScanEditor(scan: scan) }
            } else { ContentUnavailableView("Scan removed", systemImage: "doc") }
        }
        .navigationTitle("Scan results").navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Delete this scan and any retained PDF?", isPresented: $deleting, titleVisibility: .visible) {
            Button("Delete scan", role: .destructive) { if diary.removeDXAScan(scanID) { dismiss() } }
        } message: { Text("Your source document in Files and scale readings stay unchanged. This scan’s Recomp-owned Health exports are queued for removal. Cleanup needs DEXA syncing on and the corresponding write permissions.") }
    }
}

@MainActor
struct DXAScanEditor: View {
    @EnvironmentObject private var diary: DiaryStore
    @Environment(\.dismiss) private var dismiss
    @State private var draft: DXAScan
    @State private var date: Date
    @State private var text = ""
    @State private var candidates: [DXACandidate] = []
    @State private var pdfData: Data?
    @State private var keepPDF: Bool
    @State private var importing = false
    @State private var busy = false
    @State private var hasSearched = false
    @State private var reviewed = false
    @State private var valueEditor: DXAValueRequest?
    @State private var problem: String?
    @State private var discard = false
    @State private var importTask: Task<Void, Never>?
    private let existing: Bool
    init(scan: DXAScan?) {
        existing = scan != nil
        let d = scan ?? DXAScan(scanDay: DXAScan.day(Date()))
        _draft = State(initialValue: d)
        let parts = d.scanDay.split(separator: "-").compactMap { Int($0) }
        let localDate = parts.count == 3 ? Calendar.current.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: 12)) : nil
        _date = State(initialValue: min(localDate ?? Date(), Date()))
        _pdfData = State(initialValue: d.retainedPDF)
        _keepPDF = State(initialValue: d.retainedPDF != nil)
    }
    var body: some View {
        NavigationStack {
            Form {
                reportSection
                Section("Scan identity") {
                    DatePicker("Scan date, not report/birth date", selection: $date, in: ...Date(), displayedComponents: .date)
                        .onChange(of: date) { _, new in draft.scanDay = DXAScan.day(new); reviewed = false }
                    TextField("Provider / clinic (required)", text: $draft.provider).onChange(of: draft.provider) { _, _ in reviewed = false }
                    TextField("Scanner model / device (optional)", text: $draft.scanner).onChange(of: draft.scanner) { _, _ in reviewed = false }
                    TextField("Comparison group, e.g. clinic + scanner", text: $draft.comparisonGroup)
                        .onChange(of: draft.comparisonGroup) { _, _ in reviewed = false }
                    if !comparisonGroups.isEmpty {
                        Menu("Use an existing comparison group") {
                            ForEach(comparisonGroups, id: \.self) { name in Button(name) { draft.comparisonGroup = name; reviewed = false } }
                        }
                    }
                    Text("Use the same group only for comparable scanner/protocol results. This is separate from weigh-in location tags. Leaving it blank disables scan-to-scan differences.")
                        .font(.caption).foregroundStyle(Theme.muted)
                }
                resultsSection
                Section("Notes") { TextField("Report context, preparation, fields not captured…", text: $draft.notes, axis: .vertical).lineLimit(3...8) }
                Section {
                    if diary.dxaHealthLink(draft.id)?.selectedMetrics.isEmpty == false {
                        Text("Saving also updates this scan’s selected Health exports. Removed or no-longer-compatible values are queued for deletion from Health.").font(.caption).foregroundStyle(Theme.muted)
                    }
                    ForEach(draft.reviewNotes, id: \.self) { Text($0).foregroundStyle(Theme.accent) }
                    Toggle("I checked the date, sites, units and every result against the report", isOn: $reviewed)
                    Text("Saving records these results locally. It does not change calorie targets or infer muscle gain. New scans remain private until Health sharing is reviewed; existing shared fields follow your saved choices. The full extracted text is discarded; accepted source lines are retained.")
                        .font(.caption).foregroundStyle(Theme.muted)
                }
            }
            .instrumentForm().navigationTitle(existing ? "Edit DEXA scan" : "Add DEXA scan").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { discard = true } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { save() }.disabled(!reviewed || busy || draft.values.isEmpty || diary.loadFailure != nil) }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { dismissKeyboard() }
                }
            }
            .interactiveDismissDisabled()
            .fileImporter(isPresented: $importing, allowedContentTypes: [.pdf]) { result in
                switch result {
                case .success(let url): importReport(url)
                case .failure: problem = "The report could not be selected. No results were changed."
                }
            }
            .sheet(item: $valueEditor) { request in
                DXAValueEditor(value: request.value) { value in
                    if draft.values.contains(where: { $0.id != value.id && $0.key == value.key }) {
                        problem = "That metric and site already have a value. Edit the existing row instead."; return false
                    }
                    if let index = draft.values.firstIndex(where: { $0.id == value.id }) { draft.values[index] = value }
                    else { draft.values.append(value) }
                    reviewed = false; return true
                }
            }
            .alert("Check scan import", isPresented: Binding(get: { problem != nil }, set: { if !$0 { problem = nil } })) {
                Button("OK") { problem = nil }
            } message: { Text(problem ?? "") }
            .confirmationDialog("Discard unsaved scan changes?", isPresented: $discard, titleVisibility: .visible) {
                Button("Discard changes", role: .destructive) { importTask?.cancel(); dismiss() }
            }
            .onDisappear { importTask?.cancel() }
        }
    }
    private var comparisonGroups: [String] {
        Array(Set(diary.state.dxaScans.map(\.comparisonGroup).filter { !$0.isEmpty })).sorted()
    }
    private var reportSection: some View {
        Section {
            Button { importing = true } label: { Label(pdfData == nil ? "Import report PDF" : "Choose another PDF", systemImage: "doc.badge.plus") }.disabled(busy)
            if busy { ProgressView("Reading on this device…") }
            if let pdfData {
                NavigationLink("View imported PDF") { DXAPDFScreen(data: pdfData, title: draft.sourceFilename) }
                Toggle("Keep a local copy of the PDF", isOn: $keepPDF)
                Text("Optional. The original can contain your name and medical details. A retained copy uses the diary's file protection and is lost on uninstall; it is not a cloud backup.")
                    .font(.caption).foregroundStyle(Theme.muted)
            }
            DisclosureGroup("Paste or inspect report text") {
                TextEditor(text: $text).frame(minHeight: 140).font(.system(.caption, design: .monospaced))
                    .accessibilityLabel("DEXA report text")
                    .onChange(of: text) { _, _ in candidates = []; hasSearched = false }
                Button("Find labelled values") { findValues() }.disabled(busy || text.isEmpty)
                Text("Works with clear, single-line labels and explicit units. Tables, historical columns, image-only PDFs and ambiguous formatting require manual entry. Dates are always chosen by you.")
                    .font(.caption).foregroundStyle(Theme.muted)
            }
            if hasSearched {
                Text(candidates.isEmpty ? "No unambiguous labelled values found. View the PDF and add results manually." : "\(candidates.count) candidates. Tap a line, check its metric and site, then add it.")
                    .font(.caption).foregroundStyle(Theme.muted)
                ForEach(candidates) { candidate in
                    Button { var value = candidate.value; value.id = UUID(); valueEditor = DXAValueRequest(value: value) } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(candidate.value.sourceExcerpt).font(.caption).multilineTextAlignment(.leading)
                            Text("Review as \(candidate.value.metric.title)").font(.caption2).foregroundStyle(Theme.muted)
                        }
                    }
                }
            }
            Text("Nothing from this importer is sent to the AI server. New PDFs replace only the draft's source; previously reviewed values are kept for you to reconcile.")
                .font(.caption).foregroundStyle(Theme.muted)
        } header: { Text("01 / Report") }
    }
    private var resultsSection: some View {
        Section {
            ForEach(draft.values) { value in
                Button { valueEditor = DXAValueRequest(value: value) } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        LabeledContent(value.metric.title, value: "\(value.value.dxaNumber) \(value.unit.title)")
                        Text(value.region).font(.caption).foregroundStyle(Theme.muted)
                    }.foregroundStyle(Theme.ink)
                }
                .swipeActions { Button("Remove", role: .destructive) { draft.values.removeAll { $0.id == value.id }; reviewed = false } }
            }
            Button { valueEditor = DXAValueRequest(value: DXAValue(metric: .bodyFat, region: "", value: 0, unit: .percent)) } label: {
                Label("Add result manually", systemImage: "plus")
            }
        } header: { Text("02 / Values to save") } footer: {
            Text("Add totals and regions as separate entries. Total body, subtotal, trunk, arms and legs are not interchangeable. Swipe to remove a result.")
        }
    }
    private func findValues() {
        guard text.count <= DXATextParser.maxCharacters else { problem = "Use at most 100,000 characters; paste just the relevant report pages."; return }
        candidates = DXATextParser.candidates(in: text); hasSearched = true
    }
    private func importReport(_ url: URL) {
        busy = true
        importTask?.cancel()
        importTask = Task {
            do {
                let report = try await Task.detached(priority: .userInitiated) { try DXAReportReader.read(url) }.value
                guard !Task.isCancelled else { return }
                if diary.state.dxaScans.contains(where: { $0.id != draft.id && $0.sourceSHA256 == report.sha256 }) {
                    problem = "This PDF is already linked to a saved scan. Cancel and open that scan to edit it."; busy = false; return
                }
                pdfData = report.data; draft.sourceFilename = report.filename; draft.sourceSHA256 = report.sha256
                text = report.text; keepPDF = false; reviewed = false
                // Find is explicit so edits to the source text never leave stale candidates selected.
                candidates = []; hasSearched = false
                if report.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    problem = "This PDF has no selectable text. Open its preview and add values manually; OCR is not included."
                } else if report.textTruncated { problem = "Only the first report pages fit the text limit. Review the full PDF and enter any missing results manually." }
            } catch {
                if !Task.isCancelled { problem = error.localizedDescription }
            }
            busy = false
        }
    }
    private func save() {
        var scan = draft
        scan.provider = scan.provider.trimmingCharacters(in: .whitespacesAndNewlines)
        scan.comparisonGroup = scan.comparisonGroup.trimmingCharacters(in: .whitespacesAndNewlines)
        scan.retainedPDF = keepPDF ? pdfData : nil; scan.reviewed = reviewed
        guard scan.isValid else { problem = "Enter a provider, valid scan date and at least one reviewed result. Use each metric/site once; shorten overly long notes."; return }
        if diary.saveDXAScan(scan) { dismiss() }
        else { problem = diary.errorMessage ?? "The scan was not saved."; diary.errorMessage = nil }
    }
}

@MainActor
private struct DXAValueEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State private var value: DXAValue
    @State private var number: String
    @State private var error: String?
    let saveValue: (DXAValue) -> Bool
    init(value: DXAValue, saveValue: @escaping (DXAValue) -> Bool) {
        _value = State(initialValue: value)
        _number = State(initialValue: value.sourceExcerpt.isEmpty && value.value == 0 ? "" : InputNumber.editString(value.value))
        self.saveValue = saveValue
    }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Metric", selection: $value.metric) { ForEach(DXAMetric.allCases) { Text($0.title).tag($0) } }
                        .onChange(of: value.metric) { _, metric in if !metric.units.contains(value.unit), let first = metric.units.first { value.unit = first } }
                    TextField("Value", text: $number).keyboardType(.numbersAndPunctuation).fontDesign(.monospaced)
                    Picker("As printed", selection: $value.unit) { ForEach(value.metric.units) { Text($0.title).tag($0) } }
                    Text("Changing units does not convert the number. Enter the value and unit as printed. No thousands separators; decimal point or decimal comma is accepted.")
                        .font(.caption).foregroundStyle(Theme.muted)
                }
                Section("Anatomical site / region (required)") {
                    TextField("e.g. Total body, Left arm, L1–L4", text: $value.region)
                    Menu("Common regions") {
                        ForEach(["Total body", "Subtotal (excluding head)", "Left arm", "Right arm", "Arms", "Left leg", "Right leg", "Legs", "Trunk", "Head", "Android", "Gynoid", "VAT", "Android/gynoid", "Whole person"], id: \.self) { name in
                            Button(name) { value.region = name }
                        }
                    }
                    Text(value.metric.explanation).font(.caption).foregroundStyle(Theme.muted)
                }
                if !value.sourceExcerpt.isEmpty { Section("Original source line (before any edits)") { Text(value.sourceExcerpt).textSelection(.enabled) } }
                if let error { Section { Text(error).foregroundStyle(Theme.accent) } }
            }
            .instrumentForm().navigationTitle("Review result").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Use value") { save() } }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { dismissKeyboard() }
                }
            }
        }
    }
    private func save() {
        let raw = number.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !(raw.contains(",") && raw.contains(".")), let v = Double(raw.replacingOccurrences(of: ",", with: ".")) else { error = "Enter a number without thousands separators."; return }
        var result = value; result.value = v; result.region = value.region.trimmingCharacters(in: .whitespacesAndNewlines)
        guard result.isValid else { error = "Check the metric, site, value and units. These are input checks, not health ranges."; return }
        if saveValue(result) { dismiss() } else { error = "That metric and site already exist. Edit the existing result instead." }
    }
}

private struct DXAPDFView: UIViewRepresentable {
    let data: Data
    func makeUIView(context: Context) -> PDFView {
        let view = PDFView(); view.autoScales = true; view.displayMode = .singlePageContinuous
        view.document = PDFDocument(data: data); return view
    }
    func updateUIView(_ uiView: PDFView, context: Context) { }
}

private struct DXAPDFDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.pdf] }
    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else { throw CocoaError(.fileReadCorruptFile) }
        self.data = data
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}

@MainActor
private struct DXAPDFScreen: View {
    let data: Data
    let title: String
    @State private var exporting = false
    @State private var failed = false
    var body: some View {
        DXAPDFView(data: data).navigationTitle(title.isEmpty ? "DEXA report" : title).navigationBarTitleDisplayMode(.inline)
            .toolbar { Button { exporting = true } label: { Image(systemName: "square.and.arrow.up").accessibilityLabel("Export original report PDF") } }
            .fileExporter(isPresented: $exporting, document: DXAPDFDocument(data: data), contentType: .pdf, defaultFilename: "Recomp-DXA-report") { result in
                if case .failure = result { failed = true }
            }
            .alert("PDF export failed", isPresented: $failed) { Button("OK", role: .cancel) {} }
    }
}

// Scan reports often use more precision than the everyday scale / macro readouts.
private extension Double {
    var dxaNumber: String { formatted(.number.precision(.fractionLength(0...4))) }
}
