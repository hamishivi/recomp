import Foundation

@main struct PolishHarness {
    @MainActor static func main() async throws {
        var checks = 0, failures = 0
        func check(_ condition: @autoclosure () -> Bool, _ name: String) {
            checks += 1
            if condition() { print("PASS: \(name)") }
            else { failures += 1; print("FAIL: \(name)") }
        }
        func settle(_ model: MealEstimatorModel) async {
            for _ in 0..<5000 { if !model.busy { return }; await Task.yield() }
        }
        let now = Date().addingTimeInterval(-120)
        let verified = FoodTemplate(name: "Labelled shake", nutrition: Nutrition(calories: 230, protein: 42, carbs: 9, fat: 3.5), isEstimate: false)
        let estimated = FoodTemplate(name: "Curry", nutrition: Nutrition(calories: 900, protein: 40, carbs: 100, fat: 38), isEstimate: true)
        let a = MealEstimatorModel(date: now)
        a.useTemplate(verified)
        a.useTemplate(estimated)
        a.undo()
        check(a.total == verified.nutrition && a.foodName == verified.name, "undo restores saved food values and name")
        check(!a.estimated, "undo restores saved food verified status")
        check(a.description == verified.name, "undo restores matching food context, not replacement context")

        let big = MealEstimatorModel(date: now)
        big.rename("Large batch")
        let large = Nutrition(calories: 25_000, protein: 3500)
        big.setManualTotal(large)
        big.useTemplate(verified)
        big.undo()
        check(big.total == large && big.foodName == "Large batch", "undo restores manual values outside the AI schema")

        let photo = MealPhoto(jpeg: Data([0xff,0xd8,0x01,0xff,0xd9]), role: .nutritionLabel)
        let item = EstimatedFood(id: "shake", name: "Shake", portion: "one bottle", nutrition: verified.nutrition,
            evidence: [FoodEvidence(kind: .label, photoNumber: 1, detail: "Label, one bottle")])
        var entry = FoodEntry(name: "Shake", date: now, meal: .snack, nutrition: item.nutrition)
        entry.aiDraft = EstimateDraft(estimate: MealEstimate(title: "Shake", items: [item]), context: "Shake")
        entry.photos = [photo]
        let lock = MealEstimatorModel(date: now, original: entry)
        lock.toggleLock(item.id); lock.undo()
        check(lock.draft?.estimate.items.first?.evidence?.first?.photoNumber == 1,
              "undo of lock preserves unchanged photo references")
        check(!lock.hasChanges, "toggle lock then undo leaves original meal unchanged")
        lock.photos = []
        check(lock.draft?.estimate.items.first?.evidence?.first?.photoNumber == nil,
              "removed photo cannot leave a visible stale source number")

        let dup = MealEstimatorModel(date: now)
        dup.rename("Meal"); dup.photos = [photo, photo]
        check(!dup.canRequest, "duplicate photo identities are rejected before AI request")

        let clocks = MealEstimatorModel(date: now)
        clocks.useTemplate(verified); clocks.zoneID = "not/a/timezone"
        check(!clocks.canSave, "invalid entry timezone disables saving, rather than silently doing nothing")

        let overflow = MealEstimatorModel(date: now)
        overflow.rename("Recipe")
        overflow.description = String(repeating: "a", count: 8001)
        overflow.setManualTotal(verified.nutrition)
        check(overflow.draft == nil, "overlong typed context is not silently truncated into an AI draft")

        let verifiedAI = MealEstimatorModel(date: now)
        verifiedAI.useTemplate(verified)
        verifiedAI.clarification = "Add a banana"
        verifiedAI.begin(configuration: EstimatorConfiguration()); await settle(verifiedAI)
        check(verifiedAI.estimated, "new AI response is estimated")
        verifiedAI.undo()
        check(!verifiedAI.estimated && verifiedAI.total == verified.nutrition,
              "undo of AI response restores earlier verified values and status")

        let empty = MealEstimatorModel(date: now)
        empty.rename("Typing test"); empty.setManualTotal(verified.nutrition); empty.finishManualEditing()
        empty.setManualTotal(nil)
        let revision = empty.inputRevision
        empty.undo()
        check(empty.inputRevision > revision && empty.manualInputValid && empty.total == verified.nutrition,
              "undo invalid text requests a field reset even with identical numeric totals")
        empty.setManualTotal(nil); empty.useTemplate(estimated); empty.undo()
        check(empty.manualInputValid && empty.total == verified.nutrition,
              "undo of replacement repairs invalid input to its last valid total")

        let removal = MealEstimatorModel(date: now, original: entry)
        removal.remove(item.id)
        check(removal.total == .zero && !removal.history.isEmpty && !removal.canSave, "last-food removal keeps an undo checkpoint")
        removal.undo()
        check(removal.total == entry.nutrition && removal.canSave, "undo restores the last removed food")
        let originalCheckpointCount = removal.history.count
        removal.toggleLock("missing"); removal.remove("missing")
        check(removal.history.count == originalCheckpointCount && removal.draft?.isValid == true, "unknown IDs do not corrupt locks or history")
        check(!removal.editorLock(for: item), "unchanged unlocked food opens unlocked")
        check(removal.editorLock(for: removal.addBlankFood()), "new manual ingredient opens protected")

        let same = MealEstimatorModel(date: now)
        same.useTemplate(verified); same.setManualTotal(nil)
        let sameRevision = same.inputRevision
        same.useTemplate(verified)
        check(same.inputRevision > sameRevision && same.canSave, "same-value template replaces malformed field text")

        var two = entry
        let second = EstimatedFood(id: "banana", name: "Banana", portion: "1 banana", nutrition: Nutrition(calories: 100, protein: 1, carbs: 25))
        two.aiDraft!.estimate.items.append(second)
        two.nutrition = two.aiDraft!.estimate.total
        let scaling = MealEstimatorModel(date: now, original: two)
        scaling.scalePortion(by: 0.5)
        check(scaling.draft?.estimate.items.map(\.id) == [item.id, second.id], "portion scaling preserves ingredient identities")
        check(scaling.total == two.nutrition.scaled(by: 0.5), "portion scaling sums the individual scaled ingredients")
        check(scaling.draft?.estimate.items[1].portion == "0.5 × (1 banana)", "portion descriptions reflect the scale")
        check(scaling.draft?.lockedItemIDs == [item.id, second.id], "explicit scaled portions are protected from AI reversal")
        check(!scaling.estimated && scaling.entry()?.id == entry.id, "known fraction keeps verification and saved meal identity")
        scaling.undo()
        check(scaling.total == two.nutrition && scaling.draft == two.aiDraft, "undo scaling restores exact breakdown and sources")
        check(scaling.photos == [photo] && scaling.date == now, "undo leaves photo and timestamp alone")
        check(!scaling.canScale(by: .nan) && !scaling.canScale(by: -1) && !scaling.canScale(by: 0), "invalid portion factors disabled")
        scaling.setManualTotal(Nutrition(calories: 1_000_000))
        check(!scaling.canScale(by: 2), "portion overflow disabled before altering the fields")
        let beforeOverflow = scaling.total; scaling.scalePortion(by: 2)
        check(scaling.total == beforeOverflow, "rejected scaling preserves the last valid total")
        scaling.scalePortion(by: 0.5)
        check(scaling.total.calories == 500_000 && scaling.canSave, "manual amounts above the AI range still scale safely")

        let changedPhotos = MealEstimatorModel(date: now, original: entry)
        changedPhotos.toggleLock(item.id)
        changedPhotos.photos = [MealPhoto(jpeg: photo.jpeg, role: .plate)]
        changedPhotos.undo()
        check(changedPhotos.draft?.estimate.items[0].evidence?.first?.photoNumber == nil, "undo never restores a number against replacement photos")

        let stale = MealEstimatorModel(date: now)
        stale.rename("Plate"); stale.photos = [photo]
        EstimationService.held = true
        stale.begin(configuration: EstimatorConfiguration())
        for _ in 0..<5000 { if EstimationService.waiting != nil { break }; await Task.yield() }
        check(EstimationService.waiting != nil, "AI request held deterministically before response")
        stale.photos = []
        EstimationService.release(); await settle(stale)
        check(stale.total == .zero && stale.error != nil, "response cannot overwrite draft after its photo set changes")
        check(stale.history.isEmpty, "discarded late response creates no undo state")

        let future = MealEstimatorModel(date: now)
        future.useTemplate(verified); future.date = Date().addingTimeInterval(86400)
        check(!future.canSave && future.saveIssue != nil, "future food has an actionable validation message")
        future.date = Date(timeIntervalSince1970: .infinity)
        check(!future.canSave && future.entry() == nil, "nonfinite dates cannot create a food entry")

        let many = MealEstimatorModel(date: now)
        for i in 1...40 { many.useTemplate(FoodTemplate(name: "Food \(i)", nutrition: Nutrition(calories: Double(i)), isEstimate: false)) }
        check(many.history.count == 20, "undo retains at most twenty nutritional checkpoints")
        for _ in 0..<20 { many.undo() }
        check(many.foodName == "Food 20" && many.total.calories == 20 && many.history.isEmpty, "bounded undo stack restores sequential values")
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("polish-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = DiaryStore(fileURL: dir.appendingPathComponent("diary.json"), health: HealthKitService())
        let roundtrip = MealEstimatorModel(date: now, original: entry)
        roundtrip.scalePortion(by: 0.5)
        check(store.saveEntry(roundtrip.entry()!, makeTemplate: false), "scaled food saves using actual coordinator/filesystem")
        let reloaded = DiaryStore(fileURL: dir.appendingPathComponent("diary.json"), health: HealthKitService())
        check(reloaded.state.entries[0].nutrition == entry.nutrition.scaled(by: 0.5) && reloaded.state.entries[0].photos == [photo],
              "scaled food, sources and photos survive a real disk reload")
        print("\(checks) polish regressions; \(failures) failures. Actual composer; mocked AI and observation.")
        if failures > 0 { exit(1) }
    }
}
