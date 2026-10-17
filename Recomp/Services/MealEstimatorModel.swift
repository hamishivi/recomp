import Foundation
import Combine

/// Undo stores the complete food edit, not only its optional AI breakdown.
/// Photos/time/notes are independent: undoing nutrition never removes attachments or moves a meal.
struct FoodEditSnapshot {
    var action: String
    var name: String
    var total: Nutrition
    var draft: EstimateDraft?
    var description: String
    var clarification: String
    var estimateOverride: Bool?
    var usedAI: Bool
    var photoRevision: UUID
    var lastSubmittedPhotoRevision: UUID
}

@MainActor
final class MealEstimatorModel: ObservableObject {
    @Published var foodName = ""
    @Published private(set) var total = Nutrition.zero
    @Published private(set) var manualInputValid = true
    @Published private(set) var estimateOverride: Bool?
    @Published var description = ""
    @Published var clarification = ""
    @Published var photos: [MealPhoto] = [] {
        didSet {
            guard observingPhotos, photos != oldValue else { return }
            photoRevision = UUID()
            // Source numbers are positional. Invalidate them as soon as evidence changes,
            // not only on save or the next AI request.
            draft?.clearPhotoReferences()
        }
    }
    @Published private(set) var draft: EstimateDraft?
    @Published private(set) var previousTotal: Nutrition?
    @Published private(set) var busy = false
    @Published private(set) var history: [FoodEditSnapshot] = []
    /// A canonical replacement can repair invalid field text even when the total is unchanged.
    @Published private(set) var inputRevision = 0
    @Published var error: String?
    @Published var date: Date
    @Published var zoneID: String
    @Published var confirmedZone: Bool
    @Published var meal: MealKind
    @Published var note: String
    @Published var makeTemplate = false
    @Published var keepPhotos = true
    private var observingPhotos = false
    private var photoRevision = UUID()
    private var lastSubmittedPhotoRevision = UUID()
    private var requestTask: Task<Void, Never>?
    private var requestGeneration = 0
    private var usedAI = false
    private let entryID: UUID
    private let initialDraft: EstimateDraft?
    private let initialDescription: String
    private let seed: FoodEntry?
    private var composingManually = false
    let original: FoodEntry?
    private static let photoReviewDetail = "Review the updated photo evidence without reapplying earlier corrections."

    var estimated: Bool {
        estimateOverride ?? ((original ?? seed).map { $0.isEstimate || usedAI || $0.nutrition != total } ?? (usedAI || draft != nil))
    }
    var isExistingMeal: Bool { original != nil }
    var followUpQuestion: String? { draft?.estimate.followUpQuestion }
    var answerLimit: Int { 160 }
    /// A saved manual total is protected until the person explicitly opts in to
    /// letting a later AI refinement change it.
    var hasLockedFoods: Bool { !(draft?.lockedItemIDs.isEmpty ?? true) }
    var canPrepareExistingEntryRefinement: Bool { isExistingMeal && !busy && hasLockedFoods }
    var timezoneNeedsReview: Bool { original?.clock?.needsReview == true }
    var undoTitle: String { history.last.map { "Undo \($0.action)" } ?? "Undo" }
    func setEstimated(_ value: Bool) { guard !busy else { return }; estimateOverride = value }

    init(date: Date, original: FoodEntry? = nil, seed: FoodEntry? = nil) {
        self.original = original
        self.seed = seed.flatMap { $0.nutrition.containsFood ? $0 : nil }
        let starting = original ?? seed
        self.foodName = starting?.name ?? ""
        self.total = starting?.nutrition ?? .zero
        self.entryID = original?.id ?? UUID()
        self.date = starting?.date ?? date
        self.zoneID = starting?.clock?.timeZoneID ?? TimeZone.current.identifier
        self.confirmedZone = starting?.clock?.needsReview != true
        self.meal = starting?.meal ?? .suggested(at: date)
        self.note = starting?.note ?? ""
        var startingDraft = starting?.aiDraft
        if startingDraft == nil, let original = starting {
            let item = EstimatedFood(id: original.id.uuidString + ".aggregate", name: String(original.name.prefix(160)),
                portion: "Recorded meal total", nutrition: original.nutrition,
                assumptions: ["Saved meal total."],
                evidence: [FoodEvidence(kind: .details, detail: "Saved values. Unlock to re-estimate.")])
            let candidate = EstimateDraft(estimate: MealEstimate(title: String(original.name.prefix(160)), items: [item]),
                context: original.name, lockedItemIDs: [item.id])
            if candidate.isValid { startingDraft = candidate }
        }
        self.initialDraft = startingDraft
        self.draft = startingDraft
        self.initialDescription = starting?.aiDraft?.context ?? starting?.name ?? ""
        self.description = self.initialDescription
        self.photos = starting?.photos ?? []
        self.lastSubmittedPhotoRevision = photoRevision
        observingPhotos = true
    }

    func startManual() {
        guard !busy, draft == nil else { return }
        draft = EstimateDraft(estimate: MealEstimate(title: foodName.isEmpty ? "Food" : String(foodName.prefix(160)), items: []), context: description)
    }
    private var photosValid: Bool {
        photos.count <= MealPhoto.maximumCount && photos.allSatisfy(\.isValid) && Set(photos.map(\.id)).count == photos.count
    }
    var canRequest: Bool {
        guard !busy, manualInputValid, !(total.containsFood && draft == nil),
              foodName.count <= 200, photosValid, clarification.count <= 2000 else { return false }
        if let draft {
            let supplied = clarification.trimmingCharacters(in: .whitespacesAndNewlines)
            if followUpQuestion != nil && (supplied.isEmpty || supplied.count > answerLimit) { return false }
            let details = supplied.isEmpty ? Self.photoReviewDetail : supplied
            return (!supplied.isEmpty || photoRevision != lastSubmittedPhotoRevision) &&
                draft.context.count + details.count + 13 <= 8000 && draft.isValid
        }
        return initialContext.count <= 8000 && (!initialContext.isEmpty || !photos.isEmpty)
    }
    private var initialContext: String {
        let detail = description.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = foodName.trimmingCharacters(in: .whitespacesAndNewlines)
        return detail.isEmpty ? name : name.isEmpty || detail == name ? detail : name + "\n" + detail
    }
    /// Shared by button validation and the form; never silently discard invalid values or clocks.
    var saveIssue: String? {
        if !manualInputValid { return "Check the nutrition numbers." }
        if !total.containsFood { return "Enter nutrition or estimate it from photos or details." }
        if foodName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "Add a food name." }
        if foodName.count > 200 { return "Keep the food name under 200 characters." }
        if note.count > 2000 { return "Keep notes under 2,000 characters." }
        if description.count > 8000 || (draft == nil && initialContext.count > 8000) { return "Shorten the food details to 8,000 characters." }
        if EntryClock(date: date, timeZoneID: zoneID) == nil { return "Check the entry date and timezone." }
        if date > Date() { return "Food must be logged at a past or current time." }
        if !photosValid { return "Check the photos. Choose up to six different attachments." }
        return nil
    }
    var canSave: Bool { !busy && saveIssue == nil }
    var hasChanges: Bool {
        if let original {
            return foodName != original.name || total != original.nutrition || !manualInputValid || estimated != original.isEstimate ||
                draft != initialDraft || description != initialDescription || (keepPhotos ? photos : []) != (original.photos ?? []) || !clarification.isEmpty ||
                date != original.date || zoneID != (original.clock?.timeZoneID ?? TimeZone.current.identifier) ||
                (original.clock?.needsReview == true && confirmedZone) || meal != original.meal || note != original.note || makeTemplate
        }
        return draft != nil || !foodName.isEmpty || total.containsFood || !manualInputValid || !photos.isEmpty ||
            !description.isEmpty || !clarification.isEmpty || !note.isEmpty || makeTemplate
    }

    private func checkpoint(_ action: String) -> FoodEditSnapshot {
        FoodEditSnapshot(action: action, name: foodName, total: total, draft: draft, description: description,
            clarification: clarification, estimateOverride: estimateOverride, usedAI: usedAI,
            photoRevision: photoRevision, lastSubmittedPhotoRevision: lastSubmittedPhotoRevision)
    }
    private func pushHistory(_ old: FoodEditSnapshot) { history = Array((history + [old]).suffix(20)) }
    private func replacedNutrition() {
        manualInputValid = true; composingManually = false; inputRevision &+= 1
    }

    func begin(configuration: EstimatorConfiguration) {
        guard canRequest else { return }
        let before = checkpoint("estimate")
        let snapshot = draft
        var details = clarification.trimmingCharacters(in: .whitespacesAndNewlines)
        if snapshot != nil && details.isEmpty { details = Self.photoReviewDetail }
        let submittedPhotos = photos
        let submittedRevision = photoRevision
        let context = snapshot?.context ?? initialContext
        let input = EstimateRequest(description: context, clarification: snapshot == nil ? "" : details,
            images: submittedPhotos.map { EstimateImage(base64: $0.jpeg.base64EncodedString(), role: $0.role, caption: $0.caption) },
            currentEstimate: snapshot?.estimate, lockedItemIDs: Array(snapshot?.lockedItemIDs ?? []).sorted(), excludedFoods: snapshot?.excludedFoods ?? [])
        requestGeneration &+= 1
        let generation = requestGeneration
        busy = true; error = nil
        requestTask = Task {
            do {
                let response = try await EstimationService.estimate(input, configuration: configuration)
                try Task.checkCancellation()
                guard generation == requestGeneration else { return }
                guard photoRevision == submittedRevision else { throw EstimateError.rejected("Photos changed. Review them and estimate again.") }
                let next: EstimateDraft
                if let snapshot { next = try snapshot.refined(with: response, clarification: details) }
                else {
                    next = EstimateDraft(estimate: response, context: context)
                    guard next.isValid else { throw EstimateError.invalidResponse }
                }
                pushHistory(before); previousTotal = before.total; draft = next
                usedAI = true; estimateOverride = nil
                foodName = next.estimate.title; total = next.estimate.total
                lastSubmittedPhotoRevision = submittedRevision; clarification = ""
                replacedNutrition()
            } catch is CancellationError { }
            catch {
                if generation == requestGeneration && !Task.isCancelled {
                    self.error = (error as? URLError)?.code == .notConnectedToInternet ?
                        "You’re offline. Your draft is unchanged; manual editing still works." : error.localizedDescription
                }
            }
            if generation == requestGeneration { busy = false; requestTask = nil }
        }
    }
    func cancelRequest() {
        requestGeneration &+= 1; requestTask?.cancel(); requestTask = nil; busy = false
    }
    func edit(_ food: EstimatedFood, locked: Bool) {
        guard !busy, var next = draft else { return }
        guard food.isValid else { error = "Check the food values and portion."; return }
        let old = checkpoint("food edit")
        next.edit(food, locked: locked)
        guard next.isValid else { error = "Check the food values and portion."; return }
        guard next != draft else { return }
        pushHistory(old); previousTotal = total; draft = next
        total = next.estimate.total; estimateOverride = nil
        if foodName.isEmpty { foodName = next.estimate.title }
        replacedNutrition()
    }
    func editorLock(for food: EstimatedFood) -> Bool {
        guard let draft, draft.estimate.items.contains(where: { $0.id == food.id }) else { return true }
        return draft.lockedItemIDs.contains(food.id)
    }
    func addBlankFood() -> EstimatedFood { EstimatedFood(name: "", portion: "1 serving", nutrition: .zero) }
    func remove(_ id: String) {
        guard !busy, var next = draft, next.estimate.items.contains(where: { $0.id == id }) else { return }
        pushHistory(checkpoint("remove food")); previousTotal = total; next.remove(id); draft = next
        total = next.estimate.total; estimateOverride = nil; replacedNutrition()
    }
    func toggleLock(_ id: String) {
        guard !busy, var next = draft, next.estimate.items.contains(where: { $0.id == id }) else { return }
        pushHistory(checkpoint("lock change"))
        if next.lockedItemIDs.contains(id) { next.lockedItemIDs.remove(id) } else { next.lockedItemIDs.insert(id) }
        draft = next; composingManually = false
    }
    /// Makes an existing logged meal eligible for a deliberate AI correction.
    /// This is never done implicitly: tapping the action is the person's consent
    /// to replace the currently protected saved values after they review the result.
    func prepareExistingEntryRefinement() {
        guard canPrepareExistingEntryRefinement, var next = draft else { return }
        pushHistory(checkpoint("prepare refinement"))
        next.lockedItemIDs.removeAll()
        draft = next
        composingManually = false
    }
    func rename(_ text: String) {
        guard !busy else { return }
        foodName = text
        draft?.estimate.title = text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Food" : String(text.prefix(160))
    }

    /// Group consecutive typing as one undo step. The view retains invalid text until corrected.
    func setManualTotal(_ value: Nutrition?) {
        guard !busy else { return }
        guard let value, value.isValid else {
            if !composingManually { pushHistory(checkpoint("nutrition edit")); previousTotal = total }
            composingManually = true; manualInputValid = false; return
        }
        manualInputValid = true
        guard value != total else { return }
        if !composingManually { pushHistory(checkpoint("nutrition edit")); previousTotal = total }
        let context = draft?.context ?? initialContext
        total = value; composingManually = true
        let item = EstimatedFood(id: entryID.uuidString + ".manual", name: foodName.isEmpty ? "Food" : String(foodName.prefix(160)),
            portion: "Entered total", nutrition: value,
            evidence: [FoodEvidence(kind: .details, detail: "Manually entered values.")])
        let next = EstimateDraft(estimate: MealEstimate(title: item.name, items: value.containsFood ? [item] : []),
            context: context, lockedItemIDs: value.containsFood ? [item.id] : [])
        // Large manual values remain valid locally, but never send a truncated/partial draft to AI.
        draft = next.isValid ? next : nil
        if original == nil && seed == nil && !usedAI { estimateOverride = false }
        else if original?.nutrition != value { estimateOverride = nil }
    }
    func finishManualEditing() { composingManually = false }

    func canScale(by factor: Double) -> Bool {
        !busy && manualInputValid && factor.isFinite && factor > 0 && factor <= 20 &&
            total.containsFood && total.scaled(by: factor).containsFood
    }
    /// Scaling is an explicit portion edit. Keep the ingredient identities and proportionally
    /// scale each one instead of collapsing a reviewed breakdown into a single anonymous total.
    func scalePortion(by factor: Double) {
        guard canScale(by: factor), factor != 1 else { return }
        let old = checkpoint("portion change")
        let oldEstimated = estimated
        let scaledTotal = total.scaled(by: factor)
        if var next = draft {
            let items = next.estimate.items.compactMap { $0.scaled(by: factor) }
            if items.count == next.estimate.items.count {
                next.estimate.items = items
                next.lockedItemIDs = Set(items.map(\.id))
                if next.isValid {
                    pushHistory(old); previousTotal = total; draft = next
                    total = next.estimate.total; estimateOverride = oldEstimated; replacedNutrition(); return
                }
            }
        }
        // Values outside the AI schema are still legal manual entries. Keep them undoable.
        composingManually = false
        setManualTotal(scaledTotal)
        estimateOverride = oldEstimated; replacedNutrition()
    }

    func useTemplate(_ template: FoodTemplate) {
        guard !busy, template.nutrition.containsFood, !template.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, template.name.count <= 200 else { return }
        pushHistory(checkpoint("saved food")); previousTotal = total
        foodName = template.name; total = template.nutrition; estimateOverride = template.isEstimate
        let item = EstimatedFood(name: String(template.name.prefix(160)), portion: "Saved serving", nutrition: template.nutrition,
            evidence: [FoodEvidence(kind: .details, detail: "Saved food values.")])
        let next = EstimateDraft(estimate: MealEstimate(title: item.name, items: [item]), context: template.name, lockedItemIDs: [item.id])
        draft = next.isValid ? next : nil
        description = template.name; clarification = ""; replacedNutrition()
    }
    func undo() {
        guard !busy, let old = history.popLast() else { return }
        previousTotal = total
        var restored = old.draft
        if old.photoRevision != photoRevision { restored?.clearPhotoReferences() }
        draft = restored; total = old.total; foodName = old.name
        description = old.description; clarification = old.clarification
        estimateOverride = old.estimateOverride; usedAI = old.usedAI
        lastSubmittedPhotoRevision = old.lastSubmittedPhotoRevision
        replacedNutrition()
    }
    func entry() -> FoodEntry? {
        guard canSave, let clock = EntryClock.updated(original?.clock, from: original?.date, to: date, zoneID: zoneID, confirmed: confirmedZone) else { return nil }
        var entry = original ?? FoodEntry(id: entryID, name: foodName, date: date, meal: meal, nutrition: total)
        entry.name = foodName.trimmingCharacters(in: .whitespacesAndNewlines)
        entry.clock = clock; entry.date = date; entry.meal = meal; entry.nutrition = total
        entry.isEstimate = estimated; entry.note = note
        entry.aiDraft = draft?.isValid == true && draft?.estimate.total == total && entry.name.count <= 160 ? draft : nil
        entry.aiDraft?.estimate.title = entry.name
        entry.photos = keepPhotos && !photos.isEmpty ? photos : nil
        if !keepPhotos { entry.aiDraft?.clearPhotoReferences() }
        return entry.isValid ? entry : nil
    }
}
