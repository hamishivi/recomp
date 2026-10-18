import Foundation
import Combine

@MainActor
final class DiaryStore: ObservableObject {
    @Published private(set) var state = AppState()
    @Published private(set) var selectedDay = Calendar.current.startOfDay(for: Date())
    @Published private(set) var healthSamples: [HealthNutritionSample] = []
    @Published private(set) var healthBodySamples: [HealthBodySample] = []
    @Published private(set) var bodyWritable: Set<BodyMetric> = []
    @Published private(set) var dxaWritable: Set<DXAHealthMetric> = []
    @Published private(set) var writable: Set<Nutrient> = []
    @Published private(set) var isSyncing = false
    @Published private(set) var isRefreshing = false
    @Published private(set) var lastRefreshed: Date?
    @Published private(set) var syncMessage = ""
    @Published private(set) var readWarning = ""
    @Published private(set) var weightWarning = ""
    @Published private(set) var loadFailure: String?
    @Published var errorMessage: String?
    let health: HealthKitService
    private var file: StateFile
    private var syncAgain = false
    private var refreshGeneration = 0
    private var lastCalendarDay = Calendar.current.startOfDay(for: Date())
    private var lastTimeZone = TimeZone.current.identifier
    private var started = false
    private var foregroundInFlight = false
    var didCommit: ((AppState) -> Void)?

    private let isPrimaryAppDiary: Bool
    private(set) var lastLoadedModificationDate: Date?

    init(fileURL: URL? = nil, health: HealthKitService? = nil) {
        self.isPrimaryAppDiary = (fileURL == nil)
        self.health = health ?? HealthKitService()
        file = StateFile(url: fileURL ?? StateFile.defaultURL())
        reloadLocalFile()
    }
    func reloadLocalFile() {
        do {
            state = try file.load()
            lastLoadedModificationDate = file.lastModified
            loadFailure = nil
            if isPrimaryAppDiary && !UserDefaults.standard.bool(forKey: "hasConfiguredWidgetNumbers") {
                UserDefaults.standard.set(true, forKey: "hasConfiguredWidgetNumbers")
                if !state.widgetPreferences.showNumbers {
                    state.widgetPreferences.showNumbers = true
                    _ = commit { $0.widgetPreferences.showNumbers = true }
                }
            }
        }
        catch { loadFailure = error.localizedDescription }
    }

    var isUsingICloud: Bool {
        file.url.path.contains("Mobile Documents") || file.url.path.contains("ubiquity")
    }

    func checkForExternalSync() {
        guard let onDisk = file.lastModified else { return }
        if lastLoadedModificationDate.map({ onDisk > $0 }) ?? true {
            reloadLocalFile()
            didCommit?(state)
        }
    }

    /// The optional destination supports isolated storage tests. Production uses
    /// the configured local/iCloud URL and switches only after a successful read.
    func switchToStorage(useICloud: Bool, destination: URL? = nil) -> Bool {
        guard !isSyncing && !isRefreshing else {
            errorMessage = "Finish syncing before switching storage."; return false
        }
        guard let targetURL = destination ?? (useICloud ? StateFile.iCloudDriveURL : StateFile.localURL) else {
            errorMessage = "iCloud Drive is unavailable. Your current diary is unchanged."; return false
        }
        do {
            let targetFile = StateFile(url: targetURL)
            if !FileManager.default.fileExists(atPath: targetURL.path) { try targetFile.save(state) }
            let targetState = try targetFile.load()
            // No mutations to the active file, preferences or state before validation.
            file = targetFile
            state = targetState
            lastLoadedModificationDate = targetFile.lastModified
            loadFailure = nil
            UserDefaults.standard.set(useICloud ? "icloud" : "local", forKey: "recomp_storage_mode")
            refreshGeneration += 1
            healthSamples = []; healthBodySamples = []; lastRefreshed = nil
            readWarning = ""; weightWarning = ""
            didCommit?(state)
            return true
        } catch { errorMessage = error.localizedDescription; return false }
    }
    @discardableResult
    func mergeExternalState(_ incoming: AppState) -> Bool {
        guard let merged = state.mergedIfValid(with: incoming) else {
            errorMessage = "The diaries could not be merged. Check concurrent edits, conflicting scale names or record limits. Re-save the intended food or measurement on one device to resolve a version conflict."; return false
        }
        return commit { $0 = merged }
    }
    private var nutritionDeletionIdentities: [DeletionTask] {
        let pending = Set(state.deletions.map(\.id))
        return state.deletions + state.deletedIDs("food").subtracting(pending).map { DeletionTask(id: $0) }
    }
    var dayEntries: [FoodEntry] {
        DiaryMath.entries(on: selectedDay, in: state.entries).sorted { $0.date < $1.date }
    }
    var total: Nutrition {
        DiaryMath.mergedTotal(entries: state.entries, deletions: nutritionDeletionIdentities, samples: healthSamples,
                              ownBundleID: health.ownBundleID, day: selectedDay,
                              includeHealth: state.healthEnabled && state.includeOtherSources)
    }
    var remaining: Nutrition { state.targets - total }
    var otherHealthSamples: [HealthNutritionSample] {
        DiaryMath.externalSamples(healthSamples, entries: state.entries, deletions: nutritionDeletionIdentities, ownBundleID: health.ownBundleID)
            .filter { DiaryMath.healthSampleIsOnDay($0, day: selectedDay) }
    }
    var otherTotal: Nutrition { DiaryMath.healthTotal(otherHealthSamples, day: selectedDay) }
    var pendingEntries: Int { state.entries.filter { !SyncIdentity.pendingNutrients(for: $0).isEmpty }.count }
    var bodyPoints: [BodyPoint] {
        BodyMath.merged(local: state.measurements,
            health: healthBodySamples.filter {
                !state.ignoredHealthBodyIDs.contains($0.id) &&
                !($0.sourceBundleID == health.ownBundleID && $0.localMeasurementID.map { state.deletedIDs("body").contains($0) } == true)
            },
            deletions: state.bodyDeletions, ownBundleID: health.ownBundleID, scaleAssignments: state.healthBodyScaleAssignments)
    }
    var maintenanceReport: MaintenanceReport { MaintenanceEngine.evaluate(state: state, points: bodyPoints) }
    var trendSummary: TrendSummary {
        TrendSummaryCalculator.calculate(
            entries: state.entries,
            targets: state.targets,
            bodyPoints: bodyPoints,
            maintenanceReport: maintenanceReport,
            startingMaintenance: state.adaptive.startingMaintenance,
            units: state.measurementUnits
        )
    }
    var expendedSoFarForSelectedDay: (expended: Double, fraction: Double) {
        TrendSummaryCalculator.dayExpended(dailyBurn: trendSummary.estimatedDailyBurn, for: selectedDay)
    }
    func intradayBurnCurve(workouts: [WorkoutRecord] = [], steps: [StepDay] = [], stepIntervals: [StepInterval] = [], now: Date = Date()) -> IntradayBurnCurve {
        let cutoff = min(now, DiaryMath.dayInterval(containing: selectedDay).end)
        let weight = ScaleMath.latestWeightSeries(bodyPoints, now: cutoff).last
        let inputs = energyInputs(for: selectedDay, now: now)
        var curve = IntradayBurnCalculator.calculate(
            dailyBurn: trendSummary.estimatedDailyBurn,
            for: selectedDay, now: now, workouts: workouts, steps: steps,
            stepIntervals: stepIntervals, entries: dayEntries, weightKG: weight?.value ?? 75, energyInputs: inputs
        )
        if weight == nil { curve.modelNote += " No weight available: using a provisional 75 kg." }
        if inputs == nil {
            curve.modelNote += " Resting energy is unavailable: this background is not a BMR measurement. Add recent suitable body composition or a manual RMR in Energy model settings to enable component estimates."
        }
        return curve
    }

    func restingEnergy(asOf date: Date = Date(), settings: EnergySettings? = nil) -> RestingEnergyEstimate? {
        RestingEnergyCalculator.resolve(settings: settings ?? state.energySettings,
            points: bodyPoints, scans: state.dxaScans, asOf: date)
    }
    private func energyInputs(for day: Date, now: Date) -> EnergyInputs? {
        let range = DiaryMath.dayInterval(containing: day)
        let cutoff = min(now, range.end)
        guard let resting = restingEnergy(asOf: cutoff) else { return nil }
        let run = CoverageMath.latestRun(state.dayReviews, now: cutoff, lookbackDays: 15)
        let days = (run.interval?.duration ?? 0) / CoverageMath.day
        let typical = !run.conflict && days >= 7
            ? run.reviews.reduce(Nutrition.zero) { $0 + $1.total }.scaled(by: 1 / days) : state.targets
        let ended = state.dayReviews.filter { $0.isValid && $0.confirmedAt <= now &&
            $0.coverageInterval.map { $0.end <= now } == true
        }.sorted { $0.coverageInterval!.start < $1.coverageInterval!.start }
        let overlaps = ended.filter { $0.coverageInterval!.start < cutoff && $0.coverageInterval!.end > range.start }
        let conflict = zip(overlaps, overlaps.dropFirst()).contains { $0.coverageInterval!.end > $1.coverageInterval!.start }
        let complete = cutoff > range.start && !conflict && !overlaps.contains(where: \.excludedFromAnalysis) &&
            CoverageMath.total(overlaps, from: range.start, to: cutoff) != nil
        let report = MaintenanceEngine.evaluate(state: state, points: bodyPoints, now: cutoff)
        let fresh = report.end.map { cutoff.timeIntervalSince($0) >= 0 && cutoff.timeIntervalSince($0) <= 4 * CoverageMath.day } ?? false
        let stable = report.estimate.map { value in
            guard let low = report.lower, let high = report.upper else { return false }
            return high - low <= value * 0.6
        } ?? false
        let meals = ThermicEffect.events(entries: state.entries, samples: healthSamples,
            deletions: nutritionDeletionIdentities, bundleID: health.ownBundleID,
            includesHealth: state.healthEnabled && state.includeOtherSources,
            from: range.start.addingTimeInterval(-ThermicEffect.duration), through: cutoff)
        return EnergyInputs(resting: resting, settings: state.energySettings, meals: meals,
            typicalNutrition: typical, confirmedFoodDays: run.conflict ? 0 : days,
            foodCoverageComplete: complete, maintenanceAnchor: fresh && stable ? report.estimate : nil)
    }

    var energyBalanceSoFar: Double {
        total.calories - expendedSoFarForSelectedDay.expended
    }
    var normalReviewInterval: DateInterval? {
        let zones = Set(dayEntries.compactMap { $0.clock?.timeZoneID })
        guard zones.count <= 1 else { return nil }
        let zone = zones.first.flatMap(TimeZone.init(identifier:)) ?? .current
        let cal = EntryClock.calendar(in: zone)
        guard let date = EntryClock.displayDate(DayReview.key(selectedDay), calendar: cal) else { return nil }
        return DiaryMath.dayInterval(containing: date, calendar: cal)
    }
    var normalReviewZone: String { dayEntries.first?.clock?.timeZoneID ?? TimeZone.current.identifier }
    var selectedDayReview: DayReview? {
        state.dayReviews.first { $0.coverageID == nil && $0.dayKey == DayReview.key(selectedDay) && $0.timeZoneID == normalReviewZone }
    }
    var canConfirmDay: Bool {
        guard total.calories > 0, loadFailure == nil, let interval = normalReviewInterval else { return false }
        let preview = CoverageMath.preview(entries: state.entries, samples: healthSamples, deletions: nutritionDeletionIdentities,
            bundleID: health.ownBundleID, interval: interval, includesHealth: state.healthEnabled && state.includeOtherSources)
        // A stable civil-date page can contain two occurrences of a date after a
        // flight. Never certify that page as an ordinary 24-hour interval.
        return Set(preview.localEntries.map(\.id)) == Set(dayEntries.map(\.id)) &&
            Nutrient.allCases.allSatisfy { abs(preview.total[$0] - total[$0]) < 0.01 } &&
            (!(state.healthEnabled && state.includeOtherSources) || (!isRefreshing && lastRefreshed != nil && readWarning.isEmpty))
    }
    var latestDiaryDate: Date {
        let key = (state.entries.compactMap { $0.clock?.dayKey } + [DayReview.key(Date())]).max()!
        return EntryClock.displayDate(key) ?? Date()
    }
    var hasMixedDiaryZones: Bool { Set(dayEntries.compactMap { $0.clock?.timeZoneID }).count > 1 }
    var pendingBodyEntries: Int { state.measurements.filter(\.needsExport).count }

    @discardableResult
    func restoreBackup(_ payload: BackupPayload) -> Bool {
        guard !isSyncing && !isRefreshing else { errorMessage = BackupError.busy.localizedDescription; return false }
        do {
            let restored = try payload.restoredState(over: state, bundleID: health.ownBundleID)
            guard commit({ $0 = restored }) else { return false }
            refreshGeneration += 1
            healthSamples = []; healthBodySamples = []; lastRefreshed = nil
            readWarning = ""; weightWarning = ""; syncMessage = "Restored locally; reconnect Health after reviewing your diary."
            return true
        } catch { errorMessage = error.localizedDescription; return false }
    }
    @discardableResult
    func setActivityPreferences(_ preferences: ActivityPreferences) -> Bool {
        guard preferences.isValid else { errorMessage = "Check activity source settings."; return false }
        return commit { $0.activityPreferences = preferences }
    }
    func setWidgetNumbers(_ shown: Bool) { _ = commit { $0.widgetPreferences.showNumbers = shown } }
    @discardableResult
    func saveContext(_ event: ContextEvent) -> Bool {
        guard event.isValid else { errorMessage = "Check the context dates and notes."; return false }
        return commit { next in
            next.contextEvents.removeAll { $0.id == event.id }
            next.contextEvents.append(event)
        }
    }
    func removeContext(_ id: UUID) { _ = commit { $0.recordDeletion(id, kind: "context"); $0.contextEvents.removeAll { $0.id == id } } }

    func start() async {
        guard !started else { return }
        started = true
        await foreground()
    }
    func foreground() async {
        // SwiftUI's initial task and active-scene notification can overlap. A
        // duplicate foreground is not a data edit requiring another queue drain.
        // synchronize() still retains its existing syncAgain semantics for edits.
        guard !foregroundInFlight else { return }
        foregroundInFlight = true
        defer { foregroundInFlight = false }
        if loadFailure != nil { reloadLocalFile() } else { checkForExternalSync() }
        checkDayRollover()
        if state.healthEnabled || state.bodyHealthEnabled || state.dxaHealthEnabled { await synchronize() }
        rememberMaintenance()
    }
    func checkDayRollover() {
        let today = Calendar.current.startOfDay(for: Date())
        let timezoneChanged = TimeZone.current.identifier != lastTimeZone
        if today != lastCalendarDay || timezoneChanged {
            // Follow today across midnight; don't pull the user away from a deliberately selected past day.
            if selectedDay == lastCalendarDay { selectDay(today) }
            else if timezoneChanged {
                let oldZone = TimeZone(identifier: lastTimeZone) ?? .current
                let key = DayReview.key(selectedDay, calendar: EntryClock.calendar(in: oldZone))
                if let restored = EntryClock.displayDate(key) { selectDay(restored) }
            }
            lastCalendarDay = today
            lastTimeZone = TimeZone.current.identifier
        }
    }
    func selectDay(_ date: Date) {
        // Invalidate in-flight reads synchronously, not when the queued refresh happens
        // to start. A response for the previous date must not certify this date complete.
        refreshGeneration += 1
        isRefreshing = false
        readWarning = ""
        selectedDay = Calendar.current.startOfDay(for: min(date, max(Date(), latestDiaryDate)))
        healthSamples = []
        lastRefreshed = nil
        Task { await refreshHealth() }
    }
    func shiftDay(_ delta: Int) {
        if let next = Calendar.current.date(byAdding: .day, value: delta, to: selectedDay) { selectDay(next) }
    }
    var defaultEntryZone: String {
        Calendar.current.isDateInToday(selectedDay) ? TimeZone.current.identifier : normalReviewZone
    }
    func defaultEntryDate() -> Date {
        if Calendar.current.isDateInToday(selectedDay) { return Date() }
        let cal = EntryClock.calendar(in: TimeZone(identifier: defaultEntryZone) ?? .current)
        guard let day = EntryClock.displayDate(DayReview.key(selectedDay), calendar: cal),
              let noon = cal.date(bySettingHour: 12, minute: 0, second: 0, of: day) else { return Date() }
        return min(noon, Date())
    }
    @discardableResult
    private func commit(_ update: (inout AppState) -> Void) -> Bool {
        guard loadFailure == nil else {
            errorMessage = "Saving is paused to protect your original diary. \(loadFailure ?? "")"
            return false
        }
        var next = state
        update(&next)
        do {
            try file.save(next) // Disk first: failed saves never pretend to have been committed.
            state = next
            lastLoadedModificationDate = file.lastModified
            didCommit?(next)
            return true
        } catch { errorMessage = error.localizedDescription; return false }
    }
    @discardableResult
    func saveEntry(_ proposed: FoodEntry, makeTemplate: Bool) -> Bool {
        var proposed = proposed
        let previous = state.entries.first { $0.id == proposed.id }
        if proposed.clock == nil || (proposed.clock == previous?.clock && previous?.date != proposed.date) {
            proposed.clock = EntryClock.updated(previous?.clock, from: previous?.date, to: proposed.date)
        }
        guard proposed.isValid, proposed.clock != nil, proposed.date <= Date() else {
            errorMessage = "Enter a name, valid nutrition values and a date that is not in the future. Use Check food for food you have not eaten."; return false
        }
        let retainedBytes = state.entries.filter { $0.id != proposed.id }.reduce(0) { sum, entry in
            sum + (entry.photos ?? []).reduce(0) { $0 + $1.jpeg.count }
        } + (proposed.photos ?? []).reduce(0) { $0 + $1.jpeg.count }
        guard retainedBytes <= 48 * 1024 * 1024 else {
            errorMessage = "Retained meal photos have reached the 48 MiB limit. Turn off Keep photos for this meal, or remove older attachments after backing up. No food was saved."; return false
        }
        let success = commit { next in
            let previousDate = next.entries.first(where: { $0.id == proposed.id })?.date
            next.invalidateReviews(for: [proposed.date] + [previousDate].compactMap { $0 })
            var entry = proposed
            if let index = next.entries.firstIndex(where: { $0.id == proposed.id }) {
                let old = next.entries[index]
                entry.version = old.version + 1
                entry.exportedVersions = old.exportedVersions
                entry.lastExportedAt = old.lastExportedAt
                next.entries[index] = entry
            } else {
                entry.version = 1
                entry.exportedVersions = [:]
                entry.lastExportedAt = nil
                next.entries.append(entry)
            }
            if makeTemplate {
                let template = FoodTemplate(name: entry.name, nutrition: entry.nutrition, isEstimate: entry.isEstimate, note: entry.note)
                if let index = next.templates.firstIndex(where: { $0.name.caseInsensitiveCompare(entry.name) == .orderedSame }) {
                    next.templates[index] = template
                } else { next.templates.append(template) }
            }
        }
        if success {
            rememberMaintenance()
            if state.healthEnabled { Task { await synchronize() } }
        }
        return success
    }
    func removeEntry(_ id: UUID) {
        guard state.entries.contains(where: { $0.id == id }) else { return }
        let success = commit { next in
            if let entry = next.entries.first(where: { $0.id == id }) { next.invalidateReviews(for: [entry.date]) }
            next.recordDeletion(id, kind: "food")
            next.entries.removeAll { $0.id == id }
            // Queue even if no receipt was persisted: a Health save may have succeeded before a crash.
            if !next.deletions.contains(where: { $0.id == id }) { next.deletions.append(DeletionTask(id: id)) }
        }
        if success {
            rememberMaintenance()
            if state.healthEnabled { Task { await synchronize() } }
        }
    }
    func removeTemplate(_ id: UUID) { _ = commit { $0.recordDeletion(id, kind: "template"); $0.templates.removeAll { $0.id == id } } }
    @discardableResult
    func saveUsualFromEntry(_ entry: FoodEntry) -> Bool {
        let trimmedName = entry.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty, entry.nutrition.containsFood else { return false }
        let template = FoodTemplate(name: trimmedName, nutrition: entry.nutrition, isEstimate: entry.isEstimate, note: entry.note)
        return commit { next in
            if let index = next.templates.firstIndex(where: { $0.name.caseInsensitiveCompare(trimmedName) == .orderedSame }) {
                next.templates[index] = template
            } else {
                next.templates.append(template)
            }
        }
    }
    @discardableResult
    func saveTemplate(_ updated: FoodTemplate) -> Bool {
        let trimmedName = updated.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty, trimmedName.count <= 200, updated.note.count <= 2000, updated.nutrition.containsFood else {
            errorMessage = "Enter a name and valid nutrition values for this saved food."
            return false
        }
        var clean = updated
        clean.name = trimmedName
        return commit { next in
            if let index = next.templates.firstIndex(where: { $0.id == clean.id }) {
                next.templates[index] = clean
            } else if let index = next.templates.firstIndex(where: { $0.name.caseInsensitiveCompare(trimmedName) == .orderedSame }) {
                next.templates[index] = clean
            } else {
                next.templates.append(clean)
            }
        }
    }
    func isUsual(name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        return state.templates.contains(where: { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame })
    }
    @discardableResult
    func setTargets(_ nutrition: Nutrition) -> Bool {
        guard nutrition.isValid, nutrition.calories > 0 else { errorMessage = "Enter positive calories and nonnegative macro targets."; return false }
        return commit { $0.recordTargets(nutrition, at: Date(), reason: "Manually edited targets") }
    }
    func setIncludeOtherSources(_ included: Bool) {
        _ = commit { $0.includeOtherSources = included }
        // Historical confirmations remain explicit snapshots. Changing today's display
        // source does not retroactively rewrite an approved intake history.
    }
    func connectHealth() async {
        do {
            try await health.requestAccess()
            guard commit({ $0.healthEnabled = true }) else { return }
            await synchronize()
        } catch { errorMessage = error.localizedDescription }
    }
    func connectAllHealth() async {
        do {
            try await health.requestAllAccess()
            guard commit({
                $0.healthEnabled = true
                $0.bodyHealthEnabled = true
            }) else { return }
            await synchronize()
        } catch { errorMessage = error.localizedDescription }
    }
    func pauseHealth() {
        // Stop future reads/writes but leave already-exported data in Apple Health.
        guard commit({
            $0.healthEnabled = false; $0.bodyHealthEnabled = false; $0.dxaHealthEnabled = false
            $0.activityPreferences.enabled = false
        }) else { return }
        refreshGeneration += 1
        isRefreshing = false
        healthSamples = []; healthBodySamples = []; lastRefreshed = nil
        readWarning = ""; weightWarning = ""
        rememberMaintenance()
    }
    func refreshHealth() async {
        guard state.healthEnabled || state.bodyHealthEnabled, loadFailure == nil else { return }
        refreshGeneration += 1
        let generation = refreshGeneration
        let day = selectedDay
        isRefreshing = true
        writable = health.writableNutrients
        bodyWritable = health.writableBodyMetrics
        let nutrition = state.healthEnabled ? await health.readNutrition(day: day) : NutritionReadResult()
        let body = await health.readBody(includeComposition: state.bodyHealthEnabled)
        guard generation == refreshGeneration, selectedDay == day, state.healthEnabled || state.bodyHealthEnabled else {
            if generation == refreshGeneration { isRefreshing = false }
            return
        }
        healthSamples = nutrition.samples
        readWarning = nutrition.warnings.joined(separator: "\n")
        healthBodySamples = body.samples.filter { !$0.isRecompDXA }
        weightWarning = body.warnings.joined(separator: "\n")
        lastRefreshed = Date()
        isRefreshing = false
        rememberMaintenance()
    }
    func synchronize() async {
        guard state.healthEnabled || state.bodyHealthEnabled || state.dxaHealthEnabled, loadFailure == nil else { return }
        guard !isSyncing else { syncAgain = true; return }
        isSyncing = true
        defer { isSyncing = false }
        var failures = Set<String>()
        repeat {
            syncAgain = false
            writable = health.writableNutrients
            // Tombstones survive restarts and permission failures; process them before meal writes.
            for deletion in state.deletions {
                for nutrient in Nutrient.allCases where !deletion.completedNutrients.contains(nutrient) {
                    guard state.healthEnabled else { break }
                    guard writable.contains(nutrient) else { continue }
                    do {
                        try await health.removeMetric(entryID: deletion.id, nutrient: nutrient)
                        guard commit({ next in
                            if let index = next.deletions.firstIndex(where: { $0.id == deletion.id }) {
                                next.deletions[index].completedNutrients.insert(nutrient)
                                if next.deletions[index].isComplete { next.deletions.remove(at: index) }
                            }
                        }) else { return }
                    } catch { failures.insert(error.localizedDescription) }
                }
            }
            let snapshot = state.entries
            for entry in snapshot {
                for nutrient in SyncIdentity.pendingNutrients(for: entry) {
                    guard state.healthEnabled else { break }
                    guard writable.contains(nutrient), let current = state.entries.first(where: { $0.id == entry.id }) else { continue }
                    guard current.version == entry.version else { syncAgain = true; break }
                    do {
                        try await health.upsert(entry, nutrient: nutrient)
                        // If edited while awaiting HealthKit, retain the older receipt; the new version stays pending.
                        guard commit({ next in
                            if let index = next.entries.firstIndex(where: { $0.id == entry.id }) {
                                next.entries[index].exportedVersions[nutrient.rawValue] = max(
                                    next.entries[index].exportedVersions[nutrient.rawValue] ?? 0, entry.version)
                                next.entries[index].lastExportedAt = Date()
                            }
                        }) else { return }
                    } catch { failures.insert(error.localizedDescription) }
                }
            }
            if state.bodyHealthEnabled {
                bodyWritable = health.writableBodyMetrics
                for deletion in state.bodyDeletions {
                    guard state.bodyHealthEnabled else { break }
                    guard bodyWritable.contains(deletion.metric) else { continue }
                    do {
                        try await health.removeBody(deletion)
                        guard commit({ $0.bodyDeletions.removeAll { $0.id == deletion.id } }) else { return }
                    } catch { failures.insert(error.localizedDescription) }
                }
                for record in state.measurements.filter(\.needsExport) {
                    guard state.bodyHealthEnabled else { break }
                    guard bodyWritable.contains(record.metric), let current = state.measurements.first(where: { $0.id == record.id }) else { continue }
                    guard current.version == record.version else { syncAgain = true; continue }
                    do {
                        try await health.upsertBody(record)
                        guard commit({ next in
                            if let index = next.measurements.firstIndex(where: { $0.id == record.id }) {
                                next.measurements[index].exportedVersion = max(next.measurements[index].exportedVersion, record.version)
                            }
                        }) else { return }
                    } catch { failures.insert(error.localizedDescription) }
                }
            }
            if state.dxaHealthEnabled {
                dxaWritable = health.writableDXAMetrics
                for linkSnapshot in state.dxaHealthLinks {
                    let scan = state.dxaScans.first { $0.id == linkSnapshot.id }
                    let desired = linkSnapshot.desiredValues(scan: scan)
                    for metric in linkSnapshot.pendingMetrics(scan: scan) {
                        guard state.dxaHealthEnabled else { break }
                        guard dxaWritable.contains(metric) else { continue }
                        // Never initiate a stale operation after an edit, deselection or deletion.
                        guard state.dxaHealthLinks.first(where: { $0.id == linkSnapshot.id })?.version == linkSnapshot.version else {
                            syncAgain = true; break
                        }
                        let candidate = desired.first { $0.metric == metric }
                        if candidate != nil {
                            // Disk-first attempt marker: deletion remains possible even if Health saved
                            // successfully but the process died before recording the receipt.
                            guard commit({ next in
                                if let i = next.dxaHealthLinks.firstIndex(where: { $0.id == linkSnapshot.id }) {
                                    next.dxaHealthLinks[i].attemptedMetrics.insert(metric)
                                }
                            }) else { return }
                        }
                        do {
                            if let candidate, let scan {
                                try await health.upsertDXA(scanID: scan.id, scanDay: scan.scanDay, link: linkSnapshot, candidate: candidate)
                            } else {
                                try await health.removeDXA(scanID: linkSnapshot.id, metric: metric)
                            }
                            guard commit({ next in
                                if let i = next.dxaHealthLinks.firstIndex(where: { $0.id == linkSnapshot.id }) {
                                    next.dxaHealthLinks[i].completedVersions[metric.rawValue] = max(
                                        next.dxaHealthLinks[i].completedVersions[metric.rawValue] ?? 0, linkSnapshot.version)
                                    next.dxaHealthLinks[i].lastExportedAt = Date()
                                }
                            }) else { return }
                        } catch { failures.insert(error.localizedDescription) }
                    }
                }
            }
            // A save may arrive while these reads suspend. Drain that request too;
            // previously syncAgain was set here but the loop had already finished.
            if state.healthEnabled || state.bodyHealthEnabled { await refreshHealth() }
        } while syncAgain && (state.healthEnabled || state.bodyHealthEnabled || state.dxaHealthEnabled)
        syncMessage = failures.sorted().joined(separator: "\n")
    }

    // DXA stays outside scale analysis. Only separately approved Health links are updated.
    // Import/save alone does not create a Health link or authorize export.
    @discardableResult
    func saveDXAScan(_ scan: DXAScan) -> Bool {
        guard scan.isValid, scan.scanDay <= DXAScan.day(Date()) else {
            errorMessage = "Review the scan date, provider, sites, units and values before saving."; return false
        }
        if let hash = scan.sourceSHA256, state.dxaScans.contains(where: { $0.id != scan.id && $0.sourceSHA256 == hash }) {
            errorMessage = "This exact PDF is already linked to a saved scan. Open that scan to edit it rather than importing a duplicate."; return false
        }
        let bytes = state.dxaScans.filter { $0.id != scan.id }.reduce(0) { $0 + ($1.retainedPDF?.count ?? 0) }
        guard bytes + (scan.retainedPDF?.count ?? 0) <= DXAScan.maxAllPDFBytes else {
            errorMessage = "The local PDF allowance is full (48 MB). Save values without a PDF, or remove retained PDFs from older scans."; return false
        }
        let success = commit { next in
            let old = next.dxaScans.first { $0.id == scan.id }
            if let i = next.dxaScans.firstIndex(where: { $0.id == scan.id }) { next.dxaScans[i] = scan }
            else { next.dxaScans.append(scan) }
            if let i = next.dxaHealthLinks.firstIndex(where: { $0.id == scan.id }),
               old?.scanDay != scan.scanDay || old.map({ DXAHealthMapping.plan($0) }) != DXAHealthMapping.plan(scan) {
                next.dxaHealthLinks[i].version += 1
                let link = next.dxaHealthLinks[i]
                if let date = DXAHealthTime.date(day: scan.scanDay, timeZoneID: link.timeZoneID, preserving: link.date) {
                    next.dxaHealthLinks[i].date = date
                } else if let noon = DXAHealthTime.date(day: scan.scanDay, timeZoneID: link.timeZoneID) {
                    next.dxaHealthLinks[i].date = noon
                    next.dxaHealthLinks[i].timeIsApproximate = true
                }
            }
        }
        if success && state.dxaHealthEnabled { Task { await synchronize() } }
        return success
    }
    @discardableResult
    func removeDXAScan(_ id: UUID) -> Bool {
        guard state.dxaScans.contains(where: { $0.id == id }) else { return false }
        let success = commit { next in
            next.recordDeletion(id, kind: "dxa")
            next.dxaScans.removeAll { $0.id == id }
            if let i = next.dxaHealthLinks.firstIndex(where: { $0.id == id }) {
                next.dxaHealthLinks[i].selectedMetrics = []
                next.dxaHealthLinks[i].version += 1
            }
        }
        if success && state.dxaHealthEnabled { Task { await synchronize() } }
        return success
    }
    var pendingDXAMetrics: Int {
        state.dxaHealthLinks.reduce(0) { count, link in
            count + link.pendingMetrics(scan: state.dxaScans.first { $0.id == link.id }).count
        }
    }
    func dxaHealthLink(_ scanID: UUID) -> DXAHealthLink? { state.dxaHealthLinks.first { $0.id == scanID } }
    func connectDXAHealth() async {
        do {
            try await health.requestDXAAccess()
            guard commit({ $0.dxaHealthEnabled = true }) else { return }
            // Request completion is not a grant; individual metrics can remain pending.
            await synchronize()
        } catch { errorMessage = error.localizedDescription }
    }
    func pauseDXAHealth() { _ = commit { $0.dxaHealthEnabled = false } }
    @discardableResult
    func configureDXAHealth(reviewedScan: DXAScan, metrics: Set<DXAHealthMetric>, date: Date,
                            timeZoneID: String, timeIsApproximate: Bool) -> Bool {
        guard state.dxaScans.first(where: { $0.id == reviewedScan.id }) == reviewedScan else {
            errorMessage = "The scan changed. Reopen the Health review before sharing."; return false
        }
        guard metrics.isSubset(of: Set(DXAHealthMapping.plan(reviewedScan).candidates.map(\.metric))),
              DXAHealthTime.day(date, timeZoneID: timeZoneID) == reviewedScan.scanDay, date <= Date() else {
            errorMessage = "Select compatible whole-body values and a non-future time on the scan date."; return false
        }
        let success = commit { next in
            if let i = next.dxaHealthLinks.firstIndex(where: { $0.id == reviewedScan.id }) {
                next.dxaHealthLinks[i].version += 1
                next.dxaHealthLinks[i].selectedMetrics = metrics
                next.dxaHealthLinks[i].date = date
                next.dxaHealthLinks[i].timeZoneID = timeZoneID
                next.dxaHealthLinks[i].timeIsApproximate = timeIsApproximate
            } else {
                next.dxaHealthLinks.append(DXAHealthLink(id: reviewedScan.id, selectedMetrics: metrics,
                    date: date, timeZoneID: timeZoneID, timeIsApproximate: timeIsApproximate))
            }
        }
        if success && state.dxaHealthEnabled { Task { await synchronize() } }
        return success
    }
    @discardableResult
    func removeDXAHealthExports(_ id: UUID) -> Bool {
        guard state.dxaHealthLinks.contains(where: { $0.id == id }) else { return false }
        let success = commit { next in
            if let i = next.dxaHealthLinks.firstIndex(where: { $0.id == id }) {
                next.dxaHealthLinks[i].selectedMetrics = []
                next.dxaHealthLinks[i].version += 1
            }
        }
        if success && state.dxaHealthEnabled { Task { await synchronize() } }
        return success
    }

    @discardableResult
    func saveMeasurements(_ proposed: [BodyMeasurement]) -> Bool {
        let proposed = proposed.map { input -> BodyMeasurement in
            var value = input
            let old = state.measurements.first { $0.id == value.id }
            if value.clock == nil || (value.clock == old?.clock && old?.date != value.date) {
                value.clock = EntryClock.updated(old?.clock, from: old?.date, to: value.date)
            }
            return value
        }
        guard !proposed.isEmpty, proposed.allSatisfy({ $0.isValid && $0.clock != nil && $0.date <= Date() }),
              Set(proposed.map(\.id)).count == proposed.count else {
            errorMessage = "Enter valid measurements, no future dates, and at least one value."; return false
        }
        // The metric is immutable for an existing ID, so edits cannot orphan old Health types.
        guard proposed.allSatisfy({ value in state.measurements.first(where: { $0.id == value.id }).map { $0.metric == value.metric } ?? true }) else {
            errorMessage = "Add a new entry to change the measurement type."; return false
        }
        let success = commit { next in
            // Only new check-ins update the next-entry default; editing history does not.
            if let fresh = proposed.first(where: { candidate in !next.measurements.contains(where: { $0.id == candidate.id }) }) {
                next.lastScaleLocationID = fresh.scaleLocationID
            }
            for proposed in proposed {
                var value = proposed
                if let index = next.measurements.firstIndex(where: { $0.id == value.id }) {
                    let old = next.measurements[index]
                    value.version = old.version + 1; value.exportedVersion = old.exportedVersion
                    next.measurements[index] = value
                } else {
                    value.version = 1; value.exportedVersion = 0
                    next.measurements.append(value)
                }
            }
        }
        if success {
            rememberMaintenance()
            if state.bodyHealthEnabled { Task { await synchronize() } }
        }
        return success
    }
    func removeMeasurement(_ id: UUID) {
        guard let record = state.measurements.first(where: { $0.id == id }) else { return }
        let success = commit { next in
            next.recordDeletion(id, kind: "body")
            next.measurements.removeAll { $0.id == id }
            if record.metric.healthSupported && !next.bodyDeletions.contains(where: { $0.id == id }) {
                next.bodyDeletions.append(BodyDeletion(id: id, metric: record.metric))
            }
        }
        if success {
            rememberMaintenance()
            if state.bodyHealthEnabled { Task { await synchronize() } }
        }
    }
    @discardableResult
    func saveScaleLocation(_ location: ScaleLocation) -> Bool {
        guard location.isValid, !state.scaleLocations.contains(where: {
            $0.id != location.id && ScaleLocation.nameKey($0.name) == ScaleLocation.nameKey(location.name)
        }) else { errorMessage = "Use a unique scale/location name, up to 60 characters."; return false }
        let success = commit { next in
            if let index = next.scaleLocations.firstIndex(where: { $0.id == location.id }) {
                next.scaleLocations[index] = location
            } else { next.scaleLocations.append(location) }
            if location.archived && next.lastScaleLocationID == location.id { next.lastScaleLocationID = nil }
        }
        if success { rememberMaintenance() }
        return success
    }
    @discardableResult
    func createScaleLocation(name: String) -> UUID? {
        let location = ScaleLocation(name: name.trimmingCharacters(in: .whitespacesAndNewlines))
        return saveScaleLocation(location) ? location.id : nil
    }
    @discardableResult
    func assignHealthScale(_ id: UUID, locationID: UUID?) -> Bool {
        guard healthBodySamples.contains(where: { $0.id == id }),
              locationID.map({ id in state.scaleLocations.contains { $0.id == id } }) ?? true else {
            errorMessage = "Refresh the imported reading and choose an existing scale."; return false
        }
        let success = commit { $0.healthBodyScaleAssignments[id.uuidString] = locationID }
        if success { rememberMaintenance() }
        return success
    }
    @discardableResult
    func setMaintenanceScale(_ id: UUID?) -> Bool {
        guard id.map({ id in state.scaleLocations.contains { $0.id == id } }) ?? true else { return false }
        let success = commit { $0.maintenanceScaleLocationID = id }
        if success { rememberMaintenance() }
        return success
    }
    func ignoreHealthMeasurement(_ id: UUID) { _ = commit { $0.ignoredHealthBodyIDs.insert(id) }; rememberMaintenance() }
    func restoreIgnoredHealthMeasurements() { _ = commit { $0.ignoredHealthBodyIDs = [] }; rememberMaintenance() }
    func setMeasurementUnits(_ units: MeasurementUnits) { _ = commit { $0.measurementUnits = units } }
    func connectBodyHealth() async {
        do {
            try await health.requestBodyAccess()
            guard commit({ $0.bodyHealthEnabled = true }) else { return }
            await synchronize()
        } catch { errorMessage = error.localizedDescription }
    }
    func pauseBodyHealth() {
        guard commit({ $0.bodyHealthEnabled = false }) else { return }
        healthBodySamples = state.healthEnabled ? healthBodySamples.filter { $0.metric == .weight } : []
        refreshGeneration += 1; isRefreshing = false
        rememberMaintenance()
    }
    @discardableResult
    func confirmSelectedDay(excluded: Bool, note: String) -> Bool {
        guard canConfirmDay, note.count <= 1000 else {
            errorMessage = "Log the day's food and resolve any Health read errors before confirming."; return false
        }
        guard let interval = normalReviewInterval else { return false }
        let preview = CoverageMath.preview(entries: state.entries, samples: healthSamples, deletions: nutritionDeletionIdentities,
            bundleID: health.ownBundleID, interval: interval, includesHealth: state.healthEnabled && state.includeOtherSources)
        let review = DayReview(dayKey: DayReview.key(selectedDay), timeZoneID: normalReviewZone,
            confirmedAt: Date(), total: preview.total, estimatedCalorieFraction: preview.estimatedFraction,
            includedHealth: preview.includesHealth, excludedFromAnalysis: excluded, note: note, intakeEvents: preview.events)
        guard !state.dayReviews.contains(where: { $0.id != review.id && $0.coverageInterval.map { CoverageMath.overlaps($0, interval) } == true }) else {
            errorMessage = "These hours are already partly confirmed. Use Travel & food coverage to review and replace overlapping confirmations."; return false
        }
        let success = commit { next in
            next.dayReviews.removeAll { $0.id == review.id }; next.dayReviews.append(review)
        }
        if success { rememberMaintenance() }
        return success
    }
    func unconfirmSelectedDay() {
        guard let review = selectedDayReview else { return }
        _ = commit { $0.recordReviewRemoval(review.id); $0.dayReviews.removeAll { $0.id == review.id } }; rememberMaintenance()
    }
    func previewCoverage(interval: DateInterval, includesHealth: Bool) async -> CoveragePreview {
        guard CoverageMath.validInterval(interval) else {
            return CoveragePreview(interval: interval, localEntries: [], events: [], includesHealth: includesHealth, warnings: ["Choose a positive interval of at most seven days."])
        }
        if includesHealth && !state.healthEnabled {
            return CoveragePreview(interval: interval, localEntries: [], events: [], includesHealth: true, warnings: ["Connect nutrition Health access before including other apps."])
        }
        let result = includesHealth ? await health.readNutrition(interval: interval) : NutritionReadResult()
        let warnings = result.warnings + (includesHealth && !state.healthEnabled ? ["Health was paused. Review again."] : [])
        return CoverageMath.preview(entries: state.entries, samples: result.samples, deletions: nutritionDeletionIdentities,
            bundleID: health.ownBundleID, interval: interval, includesHealth: includesHealth, warnings: warnings)
    }
    @discardableResult
    func confirmCoverage(_ preview: CoveragePreview, timeZoneID: String, excluded: Bool,
                         note: String, replacingOverlaps: Bool, now: Date = Date()) -> Bool {
        guard preview.warnings.isEmpty, CoverageMath.validInterval(preview.interval), preview.interval.end <= now,
              TimeZone(identifier: timeZoneID) != nil, preview.total.calories > 0,
              !preview.includesHealth || state.healthEnabled else {
            errorMessage = "Refresh the coverage preview and check its times. Only ended, reviewed intervals with food can be confirmed."; return false
        }
        let current = state.entries.filter { CoverageMath.contains(preview.interval, $0.date) }.sorted { $0.date < $1.date }
        guard current == preview.localEntries else {
            errorMessage = "Food changed while this review was open. Refresh the preview before confirming."; return false
        }
        let conflicting = state.dayReviews.filter { $0.coverageInterval.map { CoverageMath.overlaps($0, preview.interval) } == true }
        guard conflicting.isEmpty || replacingOverlaps else {
            errorMessage = "Review the overlapping confirmations and explicitly allow replacement. Hours cannot be counted twice."; return false
        }
        let zone = TimeZone(identifier: timeZoneID) ?? .current
        let review = DayReview(dayKey: DayReview.key(preview.interval.start, calendar: EntryClock.calendar(in: zone)),
            timeZoneID: timeZoneID, confirmedAt: now, total: preview.total, estimatedCalorieFraction: preview.estimatedFraction,
            includedHealth: preview.includesHealth, excludedFromAnalysis: excluded, note: note,
            coverageID: UUID(), coverageStart: preview.interval.start, coverageEnd: preview.interval.end, intakeEvents: preview.events)
        guard review.isValid else { errorMessage = "The coverage snapshot is invalid; no records were changed."; return false }
        let success = commit { next in
            let ids = Set(conflicting.map(\.id)); for id in ids { next.recordReviewRemoval(id) }; next.dayReviews.removeAll { ids.contains($0.id) }
            next.dayReviews.append(review)
        }
        if success { rememberMaintenance() }
        return success
    }
    func removeCoverage(_ id: String) {
        if commit({ $0.recordReviewRemoval(id); $0.dayReviews.removeAll { $0.id == id } }) { rememberMaintenance() }
    }
    @discardableResult
    func saveAdaptiveSettings(_ settings: AdaptiveSettings) -> Bool {
        guard settings.isValid else { errorMessage = "Check the maintenance, protein and fat settings."; return false }
        return commit { next in
            var settings = settings
            // First-time enabling does not require two extra weeks after collecting a baseline.
            let numericalChange = settings.goal != next.adaptive.goal || settings.proteinPerKG != next.adaptive.proteinPerKG || settings.fatGrams != next.adaptive.fatGrams
            settings.lastChangedAt = numericalChange ? Date() : next.adaptive.lastChangedAt
            next.adaptive = settings
        }
    }
    @discardableResult
    func saveEnergySettings(_ settings: EnergySettings, now: Date = Date()) -> Bool {
        guard settings.isValid, settings.manualRestingDate.map({ $0 <= now }) ?? true else {
            errorMessage = "Check resting energy, its date, and the movement assumptions."; return false
        }
        return commit { next in
            var saved = settings
            saved.updatedAt = now
            next.energySettings = saved
        }
    }
    @discardableResult
    func applyRecommendation(_ proposal: Nutrition) -> Bool {
        // Recompute on apply: a preview cannot apply after intervening data/target changes.
        let current = maintenanceReport
        guard current.proposal == proposal else {
            errorMessage = "The recommendation changed. Review the latest data before applying it."; return false
        }
        return commit { $0.recordTargets(proposal, at: Date(), reason: current.recommendationTitle) }
    }
    func rememberMaintenance() {
        let r = maintenanceReport
        let today = Calendar.current.startOfDay(for: Date())
        let todayID = TimeZone.current.identifier + ":" + DayReview.key(today)
        guard let estimate = r.estimate, let lower = r.lower, let upper = r.upper,
              let from = r.start, let through = r.end, let average = r.averageIntake, let slope = r.kgPerWeek else {
            if state.maintenanceHistory.contains(where: { $0.id == todayID }) {
                _ = commit { $0.maintenanceHistory.removeAll { $0.id == todayID } }
            }
            return
        }
        let snapshot = MaintenanceSnapshot(id: TimeZone.current.identifier + ":" + DayReview.key(today), date: today,
            from: from, through: through, calories: estimate, lower: lower, upper: upper,
            averageIntake: average.calories, weightKGPerWeek: slope, completeDays: r.completedDays, scaleContext: r.scaleContext)
        guard state.maintenanceHistory.first(where: { $0.id == snapshot.id }) != snapshot else { return }
        _ = commit { next in
            next.maintenanceHistory.removeAll { $0.id == snapshot.id }; next.maintenanceHistory.append(snapshot)
            next.maintenanceHistory = Array(next.maintenanceHistory.sorted { $0.date < $1.date }.suffix(365))
        }
    }
}
