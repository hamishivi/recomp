import Foundation

enum Nutrient: String, Codable, CaseIterable, Identifiable, Sendable {
    case calories, protein, carbs, fat
    var id: String { rawValue }
    var title: String {
        switch self {
        case .calories: return "Calories"
        case .protein: return "Protein"
        case .carbs: return "Carbs"
        case .fat: return "Fat"
        }
    }
    var unit: String { self == .calories ? "kcal" : "g" }
}

struct Nutrition: Codable, Equatable, Sendable {
    var calories: Double = 0
    var protein: Double = 0
    var carbs: Double = 0
    var fat: Double = 0
    static let zero = Nutrition()
    static let startingTargets = Nutrition(calories: 2500, protein: 170, carbs: 285, fat: 75)

    subscript(_ nutrient: Nutrient) -> Double {
        get {
            switch nutrient {
            case .calories: return calories
            case .protein: return protein
            case .carbs: return carbs
            case .fat: return fat
            }
        }
        set {
            switch nutrient {
            case .calories: calories = newValue
            case .protein: protein = newValue
            case .carbs: carbs = newValue
            case .fat: fat = newValue
            }
        }
    }
    var macroCalories: Double { 4 * protein + 4 * carbs + 9 * fat }
    var isValid: Bool {
        Nutrient.allCases.allSatisfy { self[$0].isFinite && self[$0] >= 0 && self[$0] <= 1_000_000 }
    }
    var containsFood: Bool { isValid && Nutrient.allCases.contains { self[$0] > 0 } }
    func scaled(by multiplier: Double) -> Nutrition {
        Nutrition(calories: calories * multiplier, protein: protein * multiplier,
                  carbs: carbs * multiplier, fat: fat * multiplier)
    }
    static func + (lhs: Nutrition, rhs: Nutrition) -> Nutrition {
        Nutrition(calories: lhs.calories + rhs.calories, protein: lhs.protein + rhs.protein,
                  carbs: lhs.carbs + rhs.carbs, fat: lhs.fat + rhs.fat)
    }
    static func - (lhs: Nutrition, rhs: Nutrition) -> Nutrition {
        Nutrition(calories: lhs.calories - rhs.calories, protein: lhs.protein - rhs.protein,
                  carbs: lhs.carbs - rhs.carbs, fat: lhs.fat - rhs.fat)
    }
}

enum MealKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case breakfast = "Breakfast", lunch = "Lunch", dinner = "Dinner", snack = "Snack"
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .breakfast: return "sunrise"
        case .lunch: return "sun.max"
        case .dinner: return "moon"
        case .snack: return "carrot"
        }
    }
    static func suggested(at date: Date, calendar: Calendar = .current) -> MealKind {
        switch calendar.component(.hour, from: date) {
        case 5..<11: return .breakfast
        case 11..<16: return .lunch
        case 16..<22: return .dinner
        default: return .snack
        }
    }
}

struct FoodEntry: Identifiable, Codable, Equatable, Sendable {
    var id: UUID = UUID()
    var name: String
    var date: Date
    var meal: MealKind
    var nutrition: Nutrition
    var isEstimate: Bool = false
    var note: String = ""
    var version: Int = 1
    // A receipt means this version was exported. It does not prove it still exists
    // if the user later removes the sample directly in Apple Health.
    var exportedVersions: [String: Int] = [:]
    var lastExportedAt: Date?
    var aiDraft: EstimateDraft?
    var photos: [MealPhoto]?
    var clock: EntryClock?
    var exportCount: Int {
        Nutrient.allCases.filter { exportedVersions[$0.rawValue] == version }.count
    }
    var isValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && name.count <= 200 &&
        note.count <= 2000 && nutrition.containsFood && date.timeIntervalSince1970.isFinite &&
        (clock?.isValid(for: date) ?? true) &&
        version > 0 && version < Int.max &&
        exportedVersions.allSatisfy { Nutrient(rawValue: $0.key) != nil && $0.value > 0 && $0.value <= version } &&
        (photos == nil || (photos!.count <= MealPhoto.maximumCount && photos!.allSatisfy(\.isValid) && Set(photos!.map(\.id)).count == photos!.count)) &&
        (aiDraft == nil || (aiDraft!.isValid && aiDraft!.estimate.total == nutrition))
    }
}

struct FoodTemplate: Identifiable, Codable, Equatable, Sendable {
    var id: UUID = UUID()
    var name: String
    var nutrition: Nutrition
    var isEstimate: Bool
    var note: String = ""

    func entry(at date: Date) -> FoodEntry {
        FoodEntry(name: name, date: date, meal: .suggested(at: date), nutrition: nutrition,
                  isEstimate: isEstimate, note: note)
    }
    static let starters: [FoodTemplate] = [
        FoodTemplate(name: "12 oz whole-milk latte", nutrition: Nutrition(calories: 180, protein: 10, carbs: 14, fat: 9), isEstimate: true, note: "Plain latte, no syrup. Milk volume and type change the estimate."),
        FoodTemplate(name: "Protein powder + water", nutrition: Nutrition(calories: 120, protein: 24, carbs: 3, fat: 1.5), isEstimate: true, note: "Assumes one scoop. Brand and serving were not confirmed; check your label."),
        FoodTemplate(name: "Little Thai chicken combo", nutrition: Nutrition(calories: 1050, protein: 38, carbs: 140, fat: 35), isEstimate: true, note: "Rough conversation estimate, not restaurant nutrition. Assumes chicken curry, rice, tofu pad Thai and spring rolls. About 900–1,200 kcal depending on portions; edit to match your meal."),
        FoodTemplate(name: "Two fried eggs", nutrition: Nutrition(calories: 200, protein: 13, carbs: 1, fat: 15), isEstimate: true, note: "Includes a modest allowance for cooking oil. Roughly 180–220 kcal."),
        FoodTemplate(name: "Core Power Elite 42 g shake", nutrition: Nutrition(calories: 230, protein: 42, carbs: 9, fat: 3.5), isEstimate: true, note: "Product inferred from our conversation. Check bottle size and flavour: label values may differ.")
    ]
}

struct DeletionTask: Identifiable, Codable, Equatable, Sendable {
    var id: UUID // The removed meal's stable identifier.
    var completedNutrients: Set<Nutrient> = []
    var isComplete: Bool { completedNutrients.count == Nutrient.allCases.count }
}

struct AppState: Codable, Equatable, Sendable {
    var schemaVersion: Int = 8
    var deletedRecords: [String: Set<UUID>] = [:]
    var removedReviews: [String: Date] = [:]
    var activityPreferences = ActivityPreferences()
    var contextEvents: [ContextEvent] = []
    var widgetPreferences = WidgetPreferences()
    var targets: Nutrition = .startingTargets
    var entries: [FoodEntry] = []
    var templates: [FoodTemplate] = FoodTemplate.starters
    var deletions: [DeletionTask] = []
    var healthEnabled: Bool = false
    var includeOtherSources: Bool = true
    var dxaScans: [DXAScan] = []
    var dxaHealthEnabled = false
    var dxaHealthLinks: [DXAHealthLink] = []
    var measurements: [BodyMeasurement] = []
    var bodyDeletions: [BodyDeletion] = []
    var bodyHealthEnabled = false
    var measurementUnits: MeasurementUnits = .metric
    var dayReviews: [DayReview] = []
    var adaptive = AdaptiveSettings()
    var targetRevisions: [TargetRevision] = []
    var maintenanceHistory: [MaintenanceSnapshot] = []
    var ignoredHealthBodyIDs: Set<UUID> = []
    var scaleLocations: [ScaleLocation] = ScaleLocation.starters
    var lastScaleLocationID: UUID?
    var maintenanceScaleLocationID: UUID? // nil: automatic, within-scale comparisons.
    var healthBodyScaleAssignments: [String: UUID] = [:] // Local annotations, never Health writes.
    var isValid: Bool {
        schemaVersion == 8 && syncDeletionsAreValid && photoAttachmentsAreValid && activityPreferences.isValid &&
        contextEvents.count <= 10_000 && contextEvents.allSatisfy(\.isValid) && Set(contextEvents.map(\.id)).count == contextEvents.count && dxaHealthIsValid && dxaScansAreValid && scaleLocationsAreValid && measurements.allSatisfy(\.isValid) &&
        Set(measurements.map(\.id)).count == measurements.count &&
        Set(bodyDeletions.map(\.id)).count == bodyDeletions.count &&
        Set(measurements.map(\.id)).isDisjoint(with: Set(bodyDeletions.map(\.id))) &&
        bodyDeletions.allSatisfy { $0.metric.healthSupported } &&
        dayReviews.allSatisfy(\.isValid) && Set(dayReviews.map(\.id)).count == dayReviews.count && adaptive.isValid &&
        targetRevisions.allSatisfy { $0.before.isValid && $0.after.isValid && $0.after.calories > 0 } &&
        maintenanceHistory.allSatisfy { $0.calories.isFinite && $0.lower.isFinite && $0.upper.isFinite && $0.lower <= $0.calories && $0.calories <= $0.upper } && targets.isValid && targets.calories > 0 &&
        entries.allSatisfy(\.isValid) && Set(entries.map(\.id)).count == entries.count &&
        templates.allSatisfy { !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.name.count <= 200 && $0.note.count <= 2000 && $0.nutrition.containsFood } &&
        Set(templates.map(\.id)).count == templates.count &&
        Set(deletions.map(\.id)).count == deletions.count &&
        Set(entries.map(\.id)).isDisjoint(with: Set(deletions.map(\.id)))
    }
}

extension AppState {
    enum CodingKeys: String, CodingKey {
        case deletedRecords, removedReviews
        case activityPreferences, contextEvents, widgetPreferences
        case dxaScans, dxaHealthEnabled, dxaHealthLinks
        case schemaVersion, targets, entries, templates, deletions, healthEnabled, includeOtherSources
        case measurements, bodyDeletions, bodyHealthEnabled, measurementUnits, dayReviews, adaptive
        case targetRevisions, maintenanceHistory, ignoredHealthBodyIDs
        case scaleLocations, lastScaleLocationID, maintenanceScaleLocationID, healthBodyScaleAssignments
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let version = try c.decode(Int.self, forKey: .schemaVersion)
        guard (1...8).contains(version) else { throw StateFileError.invalidData }
        schemaVersion = 8
        deletedRecords = try c.decodeIfPresent([String: Set<UUID>].self, forKey: .deletedRecords) ?? [:]
        removedReviews = try c.decodeIfPresent([String: Date].self, forKey: .removedReviews) ?? [:]
        activityPreferences = try c.decodeIfPresent(ActivityPreferences.self, forKey: .activityPreferences) ?? ActivityPreferences()
        contextEvents = try c.decodeIfPresent([ContextEvent].self, forKey: .contextEvents) ?? []
        widgetPreferences = try c.decodeIfPresent(WidgetPreferences.self, forKey: .widgetPreferences) ?? WidgetPreferences()
        targets = try c.decode(Nutrition.self, forKey: .targets)
        entries = try c.decode([FoodEntry].self, forKey: .entries)
        templates = try c.decode([FoodTemplate].self, forKey: .templates)
        deletions = try c.decode([DeletionTask].self, forKey: .deletions)
        healthEnabled = try c.decode(Bool.self, forKey: .healthEnabled)
        includeOtherSources = try c.decode(Bool.self, forKey: .includeOtherSources)
        dxaScans = try c.decodeIfPresent([DXAScan].self, forKey: .dxaScans) ?? []
        dxaHealthEnabled = try c.decodeIfPresent(Bool.self, forKey: .dxaHealthEnabled) ?? false
        dxaHealthLinks = try c.decodeIfPresent([DXAHealthLink].self, forKey: .dxaHealthLinks) ?? []
        measurements = try c.decodeIfPresent([BodyMeasurement].self, forKey: .measurements) ?? []
        bodyDeletions = try c.decodeIfPresent([BodyDeletion].self, forKey: .bodyDeletions) ?? []
        bodyHealthEnabled = try c.decodeIfPresent(Bool.self, forKey: .bodyHealthEnabled) ?? false
        measurementUnits = try c.decodeIfPresent(MeasurementUnits.self, forKey: .measurementUnits) ?? .metric
        dayReviews = try c.decodeIfPresent([DayReview].self, forKey: .dayReviews) ?? []
        adaptive = try c.decodeIfPresent(AdaptiveSettings.self, forKey: .adaptive) ?? AdaptiveSettings()
        targetRevisions = try c.decodeIfPresent([TargetRevision].self, forKey: .targetRevisions) ?? []
        maintenanceHistory = try c.decodeIfPresent([MaintenanceSnapshot].self, forKey: .maintenanceHistory) ?? []
        ignoredHealthBodyIDs = try c.decodeIfPresent(Set<UUID>.self, forKey: .ignoredHealthBodyIDs) ?? []
        scaleLocations = try c.decodeIfPresent([ScaleLocation].self, forKey: .scaleLocations) ?? ScaleLocation.starters
        lastScaleLocationID = try c.decodeIfPresent(UUID.self, forKey: .lastScaleLocationID)
        maintenanceScaleLocationID = try c.decodeIfPresent(UUID.self, forKey: .maintenanceScaleLocationID)
        healthBodyScaleAssignments = try c.decodeIfPresent([String: UUID].self, forKey: .healthBodyScaleAssignments) ?? [:]
        if version < 7 { migrateEntryClocks(fallback: .current) }
        if version < 8 {
            for task in deletions { recordDeletion(task.id, kind: "food") }
            for task in bodyDeletions { recordDeletion(task.id, kind: "body") }
            for link in dxaHealthLinks where !dxaScans.contains(where: { $0.id == link.id }) {
                recordDeletion(link.id, kind: "dxa")
            }
        }
    }
}

extension AppState {
    func merging(with other: AppState) -> AppState {
        mergedIfValid(with: other) ?? self
    }
    func mergedIfValid(with other: AppState) -> AppState? {
        guard isValid, other.isValid else { return nil }
        var merged = self
        for (kind, ids) in other.deletedRecords { merged.deletedRecords[kind, default: []].formUnion(ids) }
        for task in deletions + other.deletions { merged.recordDeletion(task.id, kind: "food") }
        for task in bodyDeletions + other.bodyDeletions { merged.recordDeletion(task.id, kind: "body") }
        merged.removedReviews = removedReviews.merging(other.removedReviews) { max($0, $1) }

        // 1. Deletions
        var seenDeletions = Set<UUID>()
        var combinedDeletions: [DeletionTask] = []
        for d in self.deletions + other.deletions {
            if seenDeletions.insert(d.id).inserted {
                combinedDeletions.append(d)
            }
        }
        // Queue Health cleanup on this device even when the peer has already
        // completed its own cleanup. Durable deletion identities are separate.
        for entry in entries where merged.deletedIDs("food").contains(entry.id) && seenDeletions.insert(entry.id).inserted {
            combinedDeletions.append(DeletionTask(id: entry.id))
        }
        merged.deletions = combinedDeletions
        let deletedEntryIDs = merged.deletedIDs("food")

        // 2. Food Entries
        var entryMap: [UUID: FoodEntry] = [:]
        for entry in self.entries {
            if !deletedEntryIDs.contains(entry.id) {
                entryMap[entry.id] = entry
            }
        }
        for entry in other.entries {
            guard !deletedEntryIDs.contains(entry.id) else { continue }
            if let existing = entryMap[entry.id] {
                if entry.version > existing.version {
                    entryMap[entry.id] = entry
                } else if entry.version == existing.version {
                    var a = existing, b = entry
                    a.exportedVersions = [:]; a.lastExportedAt = nil
                    b.exportedVersions = [:]; b.lastExportedAt = nil
                    guard a == b else { return nil } // Concurrent edits need review, not an arbitrary winner.
                    var combined = existing
                    combined.exportedVersions = existing.exportedVersions.merging(entry.exportedVersions) { max($0, $1) }
                    combined.lastExportedAt = [existing.lastExportedAt, entry.lastExportedAt].compactMap { $0 }.max()
                    entryMap[entry.id] = combined
                }
            } else {
                entryMap[entry.id] = entry
            }
        }
        merged.entries = entryMap.values.sorted { $0.date == $1.date ? $0.id.uuidString < $1.id.uuidString : $0.date < $1.date }

        // 3. Body Deletions
        var seenBodyDeletions = Set<UUID>()
        var combinedBodyDeletions: [BodyDeletion] = []
        for d in self.bodyDeletions + other.bodyDeletions {
            if d.metric.healthSupported && seenBodyDeletions.insert(d.id).inserted {
                combinedBodyDeletions.append(d)
            }
        }
        for reading in measurements where reading.metric.healthSupported && merged.deletedIDs("body").contains(reading.id) && seenBodyDeletions.insert(reading.id).inserted {
            combinedBodyDeletions.append(BodyDeletion(id: reading.id, metric: reading.metric))
        }
        merged.bodyDeletions = combinedBodyDeletions
        let deletedBodyIDs = merged.deletedIDs("body")

        // 4. Body Measurements
        var measurementMap: [UUID: BodyMeasurement] = [:]
        for m in self.measurements {
            if !deletedBodyIDs.contains(m.id) {
                measurementMap[m.id] = m
            }
        }
        for m in other.measurements {
            guard !deletedBodyIDs.contains(m.id) else { continue }
            if let old = measurementMap[m.id], old.version == m.version {
                var a = old, b = m; a.exportedVersion = 0; b.exportedVersion = 0
                guard a == b else { return nil }
                var combined = old; combined.exportedVersion = max(old.exportedVersion, m.exportedVersion)
                measurementMap[m.id] = combined
            } else if measurementMap[m.id] == nil || m.version > measurementMap[m.id]!.version {
                measurementMap[m.id] = m
            }
        }
        merged.measurements = measurementMap.values.sorted { $0.date < $1.date }

        // 5. Food Templates
        var seenTemplateIDs = Set<UUID>()
        var combinedTemplates: [FoodTemplate] = []
        for t in self.templates + other.templates {
            if !merged.deletedIDs("template").contains(t.id) && seenTemplateIDs.insert(t.id).inserted {
                combinedTemplates.append(t)
            }
        }
        merged.templates = combinedTemplates

        // 6. Context Events
        var seenContextIDs = Set<UUID>()
        var combinedContext: [ContextEvent] = []
        for c in self.contextEvents + other.contextEvents {
            if !merged.deletedIDs("context").contains(c.id) && seenContextIDs.insert(c.id).inserted && c.isValid {
                combinedContext.append(c)
            }
        }
        merged.contextEvents = combinedContext.sorted { $0.start < $1.start }

        // 7. Scale Locations
        var seenLocationIDs = Set<UUID>()
        var combinedLocations: [ScaleLocation] = []
        for loc in self.scaleLocations + other.scaleLocations {
            if seenLocationIDs.insert(loc.id).inserted && loc.isValid {
                combinedLocations.append(loc)
            }
        }
        merged.scaleLocations = combinedLocations

        // 8. DXA Scans
        var seenScanIDs = Set<UUID>()
        var combinedScans: [DXAScan] = []
        for s in self.dxaScans + other.dxaScans {
            if !merged.deletedIDs("dxa").contains(s.id) && seenScanIDs.insert(s.id).inserted && s.isValid {
                combinedScans.append(s)
            }
        }
        merged.dxaScans = combinedScans.sorted { $0.date < $1.date }
        for i in merged.dxaHealthLinks.indices where merged.deletedIDs("dxa").contains(merged.dxaHealthLinks[i].id) {
            if !merged.dxaHealthLinks[i].selectedMetrics.isEmpty {
                guard merged.dxaHealthLinks[i].version < Int.max - 1 else { return nil }
                merged.dxaHealthLinks[i].selectedMetrics = []
                merged.dxaHealthLinks[i].version += 1
            }
        }

        // 9. Day Reviews
        var reviews: [String: DayReview] = [:]
        for review in dayReviews + other.dayReviews {
            guard merged.removedReviews[review.id].map({ review.confirmedAt > $0 }) ?? true else { continue }
            if let old = reviews[review.id] {
                if old.confirmedAt == review.confirmedAt && old != review { return nil }
                if review.confirmedAt > old.confirmedAt { reviews[review.id] = review }
            } else { reviews[review.id] = review }
        }
        merged.dayReviews = reviews.values.sorted { $0.confirmedAt < $1.confirmedAt }

        // 10. Target Revisions
        var seenRevisions = Set<UUID>()
        var combinedRevisions: [TargetRevision] = []
        for rev in self.targetRevisions + other.targetRevisions {
            if seenRevisions.insert(rev.id).inserted && rev.before.isValid && rev.after.isValid {
                combinedRevisions.append(rev)
            }
        }
        merged.targetRevisions = combinedRevisions.sorted { $0.date < $1.date }

        // 11. Maintenance History
        var seenSnapshots = Set<String>()
        var combinedSnapshots: [MaintenanceSnapshot] = []
        for snap in self.maintenanceHistory + other.maintenanceHistory {
            if seenSnapshots.insert(snap.id).inserted {
                combinedSnapshots.append(snap)
            }
        }
        merged.maintenanceHistory = combinedSnapshots.sorted { $0.date < $1.date }

        // 12. Targets & Preferences
        // Revision counts do not indicate recency (an old device can have a
        // longer history). Only a newer explicit target change wins.
        let localTargetDate = targetRevisions.map(\.date).max() ?? .distantPast
        let remoteTargetDate = other.targetRevisions.map(\.date).max() ?? .distantPast
        if remoteTargetDate > localTargetDate, other.targets.isValid {
            merged.targets = other.targets
        }
        merged.healthBodyScaleAssignments = self.healthBodyScaleAssignments.merging(other.healthBodyScaleAssignments) { a, _ in a }
        merged.ignoredHealthBodyIDs = self.ignoredHealthBodyIDs.union(other.ignoredHealthBodyIDs)
        merged.activityPreferences.hiddenWorkoutIDs = self.activityPreferences.hiddenWorkoutIDs.union(other.activityPreferences.hiddenWorkoutIDs)

        // Remote food edits/deletions/additions must invalidate affected reviews
        // on both replicas. A peer snapshot may predate the winning food version.
        let after = Dictionary(uniqueKeysWithValues: merged.entries.map { ($0.id, $0) })
        var changedDates: [Date] = []
        for source in [self, other] {
            let before = Dictionary(uniqueKeysWithValues: source.entries.map { ($0.id, $0) })
            for id in Set(before.keys).union(after.keys) {
                let old = before[id], new = after[id]
                if old?.nutrition != new?.nutrition || old?.date != new?.date || old?.clock != new?.clock || old?.isEstimate != new?.isEstimate {
                    if let old { changedDates.append(old.date) }
                    if let new { changedDates.append(new.date) }
                }
            }
        }
        merged.invalidateReviews(for: changedDates)
        if !changedDates.isEmpty { merged.maintenanceHistory = [] }
        return merged.isValid ? merged : nil
    }
}

struct HealthNutritionSample: Identifiable, Equatable, Sendable {
    var id: UUID
    var date: Date
    var nutrient: Nutrient
    var value: Double
    var sourceName: String
    var sourceBundleID: String
    var localEntryID: UUID?
    var clock: EntryClock?
}

struct WeightReading: Identifiable, Equatable, Sendable {
    var id: UUID
    var date: Date
    var kilograms: Double
}

struct DailyWeight: Identifiable, Equatable, Sendable {
    var date: Date
    var kilograms: Double
    var rollingAverage: Double
    var id: Date { date }
}

enum InputNumber {
    /// Decimal keyboard input; supports comma decimal separators, not thousands grouping.
    static func parse(_ text: String) -> Double? {
        let stripped = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !stripped.isEmpty, !(stripped.contains(",") && stripped.contains(".")),
              let result = Double(stripped.replacingOccurrences(of: ",", with: ".")),
              result.isFinite, result >= 0, result <= 1_000_000 else { return nil }
        return result
    }
    static func editString(_ value: Double) -> String {
        value == value.rounded() ? String(format: "%.0f", value) : String(value)
    }
    /// Replaces the existing string with freshly typed or pasted text when a numeric input field is first edited after focus,
    /// rather than appending or prefixing to the previous number.
    static func overwriteOrAppend(old: String, new: String, shouldOverwrite: Bool) -> String {
        guard shouldOverwrite, !old.isEmpty, new != old else { return new }
        if new.count < old.count {
            return new
        }
        let oldChars = Array(old)
        let newChars = Array(new)
        var prefixLen = 0
        while prefixLen < oldChars.count && oldChars[prefixLen] == newChars[prefixLen] {
            prefixLen += 1
        }
        var suffixLen = 0
        while suffixLen < (oldChars.count - prefixLen) &&
              oldChars[oldChars.count - 1 - suffixLen] == newChars[newChars.count - 1 - suffixLen] {
            suffixLen += 1
        }
        let inserted = String(newChars[prefixLen..<(newChars.count - suffixLen)])
        guard !inserted.isEmpty else { return new }
        if inserted == "." || inserted == "," {
            return "0" + inserted
        }
        return inserted
    }
}
