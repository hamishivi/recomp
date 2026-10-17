import Foundation

@main struct ComposerHarness {
    @MainActor static func main() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("recomp-composer-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        var checks = 0, failures = 0
        func check(_ value: @autoclosure () -> Bool, _ name: String) {
            checks += 1
            if value() { print("PASS: \(name)") } else { failures += 1; print("FAIL: \(name)") }
        }
        func settle(_ model: MealEstimatorModel) async {
            for _ in 0..<5000 { if !model.busy { return }; await Task.yield() }
        }
        let now = Date().addingTimeInterval(-120)
        let h = HealthKitService()
        let store = DiaryStore(fileURL: dir.appendingPathComponent("diary.json"), health: h)
        let calories = Nutrition(calories: 230, protein: 42, carbs: 9, fat: 3.5)
        // Framed byte fixture only; no claim of UIKit image decoding.
        let photo = MealPhoto(jpeg: Data([0xff,0xd8,0x01,0xff,0xd9]), role: .nutritionLabel, caption: "one bottle")
        let model = MealEstimatorModel(date: now)
        check(!model.canSave && model.entry() == nil, "blank form cannot log")
        check(!model.hasChanges, "blank form closes without a discard prompt")
        model.rename("Protein shake")
        model.photos = [photo]
        check(model.canRequest && !model.canSave, "name and photo allow AI but cannot save empty nutrition")
        model.setManualTotal(calories)
        check(model.canSave && model.entry()?.nutrition == calories, "manual nutrition is immediately savable without AI")
        check(model.draft?.lockedItemIDs.count == 1, "entered totals create one protected aggregate")
        check(EstimationService.received == nil, "adding text, photo and manual totals never calls AI")
        check(store.state.entries.isEmpty && h.foodSaves.isEmpty, "editing/checking leaves diary and Health untouched")
        model.setEstimated(false)
        let candidate = model.entry()!
        check(candidate.photos == [photo] && !candidate.isEstimate, "manual reviewed photo meal preserves values and photo")
        check(model.entry()?.id == candidate.id, "repeated draft inspection keeps one stable new ID")
        check(store.saveEntry(candidate, makeTemplate: true), "one explicit save commits meal and usual")
        check(store.state.entries.count == 1 && h.foodSaves.isEmpty, "one local entry, no writes with Health off")
        let saved = store.state.entries[0]
        let reopened = MealEstimatorModel(date: now, original: saved)
        check(reopened.total == calories && reopened.foodName == saved.name && reopened.photos == [photo], "reopening restores name, totals and photos")
        check(!reopened.hasChanges && !reopened.estimated, "opening a verified food does not mark it changed/estimated")
        reopened.setManualTotal(nil)
        check(!reopened.canSave && !reopened.canRequest && reopened.entry() == nil, "invalid field blocks save and AI; old total cannot leak through")
        reopened.setManualTotal(calories)
        check(reopened.canSave, "correcting an invalid field back to original re-enables save")
        reopened.setManualTotal(Nutrition(calories: -1))
        check(!reopened.canSave, "negative manual values rejected")
        reopened.setManualTotal(calories.scaled(by: 0.5))
        check(reopened.total.calories == 115 && reopened.entry()?.aiDraft?.estimate.total == reopened.total, "scaled total and breakdown stay consistent")
        check(reopened.entry()?.id == saved.id && reopened.photos == [photo], "editing retains original meal ID and attachments")
        reopened.setEstimated(false)
        check(store.saveEntry(reopened.entry()!, makeTemplate: false) && store.state.entries.count == 1, "editing replaces the same diary entry")
        check(store.state.entries[0].version > saved.version, "editing goes through normal versioning")
        let reload = DiaryStore(fileURL: dir.appendingPathComponent("diary.json"), health: HealthKitService())
        check(reload.state.entries[0].nutrition.calories == 115 && reload.state.entries[0].photos == [photo], "edited photo meal survives real file round trip")
        let blankSeed = FoodEntry(name: "", date: now, meal: .lunch, nutrition: .zero)
        let fromLogButton = MealEstimatorModel(date: now, seed: blankSeed)
        fromLogButton.rename("Manual label"); fromLogButton.setManualTotal(calories)
        check(!fromLogButton.estimated && fromLogButton.canSave, "blank home seed does not mislabel manual label entry as AI")
        let originalPhotoCount = reopened.photos.count
        reopened.keepPhotos = false
        check(reopened.entry()?.photos == nil && reopened.photos.count == originalPhotoCount, "retention switch drops saved copy, not editable session")
        reopened.keepPhotos = true
        let template = FoodTemplate(name: "Latte", nutrition: Nutrition(calories: 180, protein: 10, carbs: 14, fat: 9), isEstimate: true)
        reopened.note = "commute"; reopened.zoneID = "Australia/Sydney"; reopened.meal = .snack
        let originalID = reopened.entry()!.id
        reopened.useTemplate(template)
        check(reopened.foodName == "Latte" && reopened.total == template.nutrition && reopened.estimated, "saved food populates name/numbers/estimate flag")
        check(reopened.photos == [photo] && reopened.note == "commute" && reopened.zoneID == "Australia/Sydney" && reopened.date == now && reopened.meal == .snack, "usual selection retains photos, notes, meal and capture time")
        check(reopened.entry()?.id == originalID && store.state.entries.count == 1, "usual choice changes draft only and retains edit identity")
        let new1 = MealEstimatorModel(date: now), new2 = MealEstimatorModel(date: now)
        new1.useTemplate(template); new2.useTemplate(template)
        check(new1.entry()?.id != new2.entry()?.id, "two uses of a usual produce distinct new meal IDs")
        let seeded = MealEstimatorModel(date: now, seed: template.entry(at: now))
        check(!seeded.isExistingMeal && seeded.entry()?.nutrition == template.nutrition, "shortcut seed is a new food, not a saved entry to overwrite")
        let corrected = MealEstimatorModel(date: now, original: saved)
        corrected.photos = Array(repeating: photo, count: 2)
        check(!corrected.canSave, "duplicate attachment IDs block saving")
        corrected.photos = (0..<7).map { _ in MealPhoto(jpeg: photo.jpeg) }
        check(!corrected.canSave && !corrected.canRequest, "seven-photo inputs block save/request")
        let big = MealEstimatorModel(date: now)
        big.rename(String(repeating: "n", count: 190)); big.setManualTotal(Nutrition(calories: 25000, protein: 3500))
        check(big.canSave && big.entry()?.name.count == 190 && big.entry()?.aiDraft == nil, "manual input keeps legacy name/nutrient limits beyond AI limits")
        big.photos = [photo]
        check(!big.canRequest, "large manual totals cannot be silently replaced by an unseeded AI request")
        big.rename(String(repeating: "n", count: 201))
        check(!big.canSave, "oversized food name blocked")
        let ai = MealEstimatorModel(date: now)
        ai.rename("Chicken curry"); ai.description = "Half the rice"; ai.photos = [photo]
        ai.begin(configuration: EstimatorConfiguration()); await settle(ai)
        check(EstimationService.received?.description.contains("Chicken curry") == true && EstimationService.received?.description.contains("Half the rice") == true, "AI gets typed food name and details")
        check(ai.total == EstimationService.response.total && ai.foodName == EstimationService.response.title && ai.estimated && ai.canSave, "AI fills the same editable form and marks estimate")
        ai.setManualTotal(Nutrition(calories: 333, protein: 22, carbs: 33, fat: 12))
        check(ai.draft?.estimate.items.count == 1 && ai.draft?.estimate.total == ai.total, "aggregate correction removes stale ingredient sums")
        let locked = ai.draft!.estimate.items[0]
        ai.clarification = "Please review"; ai.begin(configuration: EstimatorConfiguration()); await settle(ai)
        check(ai.draft?.estimate.items.first(where: {$0.id == locked.id})?.nutrition == locked.nutrition, "AI refinements retain manual protected values")
        let before = ai.total
        ai.clarification = "Try again"; EstimationService.fail = true
        ai.begin(configuration: EstimatorConfiguration()); await settle(ai)
        check(ai.total == before && ai.error != nil, "failed AI request leaves manual totals intact")
        EstimationService.fail = false
        ai.begin(configuration: EstimatorConfiguration()); ai.cancelRequest(); await Task.yield()
        check(ai.total == before && !ai.busy, "cancelled AI request cannot overwrite food")
        let questioning = MealEstimatorModel(date: now)
        questioning.rename("Pasta"); questioning.description = "Pasta with sauce"; questioning.photos = [photo]
        EstimationService.response = MealEstimate(title: "Pasta", items: [EstimatedFood(id: "pasta", name: "Pasta", portion: "1 bowl", nutrition: Nutrition(calories: 500, protein: 18, carbs: 75, fat: 14))], questions: ["How many bowls did you eat?"])
        questioning.begin(configuration: EstimatorConfiguration()); await settle(questioning)
        check(questioning.followUpQuestion == "How many bowls did you eat?" && !questioning.canRequest, "AI presents one question and waits for a reply")
        questioning.clarification = String(repeating: "x", count: 161)
        check(!questioning.canRequest, "question answer has a short limit")
        questioning.clarification = "One and a half"
        check(questioning.canRequest, "short answer enables the next refinement round")
        EstimationService.response.questions = ["Was cheese added?"]
        questioning.begin(configuration: EstimatorConfiguration()); await settle(questioning)
        check(EstimationService.received?.clarification == "One and a half" && questioning.followUpQuestion == "Was cheese added?", "answer is sent and the model may ask one next question")
        let afterTheFact = MealEstimatorModel(date: now, original: saved)
        check(afterTheFact.canPrepareExistingEntryRefinement && afterTheFact.hasLockedFoods, "saved entries require an explicit opt-in before AI may revise protected totals")
        afterTheFact.prepareExistingEntryRefinement()
        afterTheFact.clarification = "It was made with whole milk"
        check(!afterTheFact.hasLockedFoods && afterTheFact.canRequest, "explicit refinement unlocks the saved total and accepts a short correction")
        EstimationService.response = MealEstimate(title: "Protein shake", items: [EstimatedFood(id: "revised-shake", name: "Protein shake", portion: "1 bottle", nutrition: Nutrition(calories: 410, protein: 42, carbs: 25, fat: 14))])
        afterTheFact.begin(configuration: EstimatorConfiguration()); await settle(afterTheFact)
        check(afterTheFact.total.calories == 410 && afterTheFact.entry()?.id == saved.id && afterTheFact.hasChanges, "after-the-fact AI refinement updates the existing meal for review before save")
        check(store.state.entries.count == 1, "AI/check examples have not logged any additional entries")
        let undo = MealEstimatorModel(date: now, original: saved)
        undo.setManualTotal(calories.scaled(by: 2)); undo.undo()
        check(undo.total == saved.nutrition && undo.foodName == saved.name, "undo restores numbers and title after aggregate edit")
        let noPhotos = MealEstimatorModel(date: now)
        noPhotos.rename("Known label"); noPhotos.setManualTotal(calories); noPhotos.setEstimated(false)
        check(noPhotos.canSave && noPhotos.entry()?.photos == nil, "manual logging without photos remains available")

        let oldItems = [
            EstimatedFood(id: "old-rice", name: "Brown rice", portion: "1 cup", nutrition: Nutrition(calories: 210, protein: 5, carbs: 44, fat: 2),
                          evidence: [FoodEvidence(kind: .visual, photoNumber: 1, detail: "Rice in the old photo.")]),
            EstimatedFood(id: "old-chicken", name: "Chicken", portion: "150 g", nutrition: Nutrition(calories: 250, protein: 46, fat: 6))
        ]
        let oldEstimate = MealEstimate(title: "Chicken bowl", items: oldItems, questions: ["Was there extra sauce?"])
        var historySource = FoodEntry(name: "Chicken bowl", date: now.addingTimeInterval(-800 * 86400), meal: .dinner,
            nutrition: oldEstimate.total, isEstimate: true, note: "Old meal notes", version: 9,
            exportedVersions: ["calories": 9], lastExportedAt: now.addingTimeInterval(-86400),
            aiDraft: EstimateDraft(estimate: oldEstimate, context: "An old photo description", excludedFoods: ["Sauce"]),
            photos: [photo])
        historySource.clock = EntryClock(date: historySource.date, timeZoneID: "Europe/London")
        let sourceBefore = historySource, diaryBeforeHistory = store.state
        let fromHistory = MealEstimatorModel(date: now)
        let currentPhoto = MealPhoto(jpeg: photo.jpeg, caption: "Today's photo")
        fromHistory.note = "Today's notes"; fromHistory.meal = .snack
        fromHistory.zoneID = "Australia/Sydney"; fromHistory.photos = [currentPhoto]
        fromHistory.useHistoricalFood(historySource)
        let historyCopy = fromHistory.entry()!
        check(fromHistory.foodName == historySource.name && fromHistory.total == historySource.nutrition && fromHistory.estimated, "history copies recorded nutrition and estimate status")
        check(historyCopy.id != historySource.id && fromHistory.entry()?.id == historyCopy.id, "history gets one stable fresh entry identity")
        check(historyCopy.date == now && historyCopy.meal == .snack && historyCopy.clock?.timeZoneID == "Australia/Sydney", "history retains the current date, meal and timezone")
        check(historyCopy.note == "Today's notes" && historyCopy.photos == [currentPhoto] && !fromHistory.makeTemplate, "history preserves current notes/photos without creating a favourite")
        check(historyCopy.version == 1 && historyCopy.exportedVersions.isEmpty && historyCopy.lastExportedAt == nil, "history never copies source version or Health receipts")
        check(fromHistory.draft?.estimate.items.map(\.nutrition) == oldItems.map(\.nutrition) && fromHistory.draft?.lockedItemIDs.count == 2, "history preserves and protects the ingredient breakdown")
        check(Set(fromHistory.draft!.estimate.items.map(\.id)).isDisjoint(with: Set(oldItems.map(\.id))), "copied ingredients have fresh IDs")
        check(fromHistory.draft!.estimate.items.allSatisfy { $0.evidence?.allSatisfy { $0.kind == .details && $0.photoNumber == nil } == true }, "historical photo evidence is replaced with copy provenance")
        check(fromHistory.followUpQuestion == nil && fromHistory.draft?.excludedFoods.isEmpty == true && fromHistory.description == historySource.name, "old AI follow-up and context do not leak into the new meal")
        check(historySource == sourceBefore && store.state == diaryBeforeHistory && h.foodSaves.isEmpty, "history selection leaves source, favourites, diary and Health untouched")
        fromHistory.scalePortion(by: 0.5)
        check(fromHistory.total == historySource.nutrition.scaled(by: 0.5) && fromHistory.draft?.estimate.items.count == 2, "historical meal portions can be adjusted without losing the breakdown")
        fromHistory.undo(); fromHistory.undo()
        check(fromHistory.total == .zero && fromHistory.foodName.isEmpty && fromHistory.photos == [currentPhoto] && fromHistory.note == "Today's notes", "undo returns to the prior draft while keeping today's attachments and notes")
        let revision = fromHistory.inputRevision
        fromHistory.setManualTotal(nil); fromHistory.useHistoricalFood(historySource)
        check(fromHistory.manualInputValid && fromHistory.canSave && fromHistory.inputRevision > revision, "history repairs invalid manual fields through the canonical input revision")
        let editingHistory = MealEstimatorModel(date: now, original: saved)
        editingHistory.useHistoricalFood(historySource)
        check(editingHistory.entry()?.id == saved.id && editingHistory.date == saved.date, "history in an editor keeps the entry being edited")
        editingHistory.undo()
        check(editingHistory.total == saved.nutrition && editingHistory.foodName == saved.name && !editingHistory.estimated, "undo history restores the existing meal and verified status")
        let historyStore = DiaryStore(fileURL: dir.appendingPathComponent("history.json"), health: HealthKitService())
        let usualsBefore = historyStore.state.templates
        check(historyStore.saveEntry(historySource, makeTemplate: false) && historyStore.saveEntry(fromHistory.entry()!, makeTemplate: fromHistory.makeTemplate), "only explicit Save logs a reused meal")
        check(historyStore.state.entries.count == 2 && historyStore.state.templates == usualsBefore, "saving from history adds a separate diary entry without adding a favourite")
        let reloadedHistory = DiaryStore(fileURL: dir.appendingPathComponent("history.json"), health: HealthKitService())
        check(reloadedHistory.state.entries.count == 2 && reloadedHistory.state.entries.contains { $0.id == fromHistory.entry()?.id }, "historical copies survive file round trip alongside the source")
        let largeHistory = MealEstimatorModel(date: now)
        largeHistory.useHistoricalFood(FoodEntry(name: String(repeating: "n", count: 190), date: now, meal: .lunch, nutrition: Nutrition(calories: 25000, protein: 3500)))
        check(largeHistory.canSave && largeHistory.foodName.count == 190 && largeHistory.entry()?.aiDraft == nil, "history supports legal manual values outside the AI schema")
        let noHistoryPhotos = MealEstimatorModel(date: now)
        noHistoryPhotos.useHistoricalFood(historySource)
        check(noHistoryPhotos.photos.isEmpty && noHistoryPhotos.entry()?.photos == nil, "old photos are never silently copied into a new meal")
        check(failures == 0, "all composer scenarios complete")
        print("\(checks) composer checks; \(failures) failures. Production models/store; observation, Health and AI are test doubles. No native UI.")
        if failures > 0 { exit(1) }
    }
}
