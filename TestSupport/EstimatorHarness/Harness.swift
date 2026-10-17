import Foundation
@main struct EstimatorHarness {
    @MainActor static func main() async throws {
        var checks = 0
        func check(_ result: @autoclosure () -> Bool, _ label: String) {
            precondition(result(), "FAILED: \(label)"); checks += 1; print("PASS: \(label)")
        }
        func settle(_ model: MealEstimatorModel) async { for _ in 0..<1000 { if !model.busy { return }; await Task.yield() } }
        let now = Date(), jpeg = Data([0xff,0xd8,0x01,0xff,0xd9])
        let model = MealEstimatorModel(date: now)
        check(!model.canSave && model.entry() == nil, "empty check cannot be logged")
        model.startManual(); check(model.draft != nil && !model.canSave, "manual check starts without API")
        model.edit(EstimationService.response.items[0], locked: true)
        check(model.canSave, "manual values can be reviewed")
        check(EstimationService.received == nil, "manual check performs no API call")
        model.photos = [MealPhoto(jpeg: jpeg, role: .nutritionLabel, caption: "half serving"), MealPhoto(jpeg: jpeg, role: .plate)]
        check(model.canRequest, "new photo evidence enables refinement without duplicate correction")
        model.begin(configuration: EstimatorConfiguration()); await settle(model)
        check(EstimationService.received?.images.count == 2 && EstimationService.received?.images[0].role == .nutritionLabel, "multi-photo roles sent")
        check(EstimationService.received?.images[0].caption == "half serving", "photo caption sent")
        check(model.draft!.lockedItemIDs.contains("food"), "manual lock retained through AI response")
        check(!model.canRequest, "unchanged inputs do not trigger accidental re-estimation")
        let entry = model.entry()!
        check(entry.photos?.count == 2, "confirmed entry retains photo attachments")
        let reopened = MealEstimatorModel(date: now, original: entry)
        check(reopened.photos == entry.photos && !reopened.hasChanges, "reopening retains photos and is not a new edit")
        reopened.keepPhotos = false
        check(reopened.entry()?.photos == nil, "photo retention can be disabled without losing food")
        reopened.keepPhotos = true; reopened.photos[0].caption = "new detail"
        check(reopened.canRequest, "editing a caption enables refinement")
        reopened.clarification = "only half the plate"; EstimationService.fail = true
        let before = reopened.draft
        reopened.begin(configuration: EstimatorConfiguration()); await settle(reopened)
        check(reopened.error != nil && reopened.draft == before, "failed response preserves editable draft")
        EstimationService.fail = false
        reopened.begin(configuration: EstimatorConfiguration()); reopened.cancelRequest(); await Task.yield()
        check(!reopened.busy && reopened.draft == before, "cancelled response cannot replace draft")
        let request = try JSONSerialization.jsonObject(with: JSONEncoder().encode(EstimationService.received!)) as! [String:Any]
        check(Set(request.keys).isSubset(of: ["description","clarification","images","currentEstimate","lockedItemIDs","excludedFoods"]), "request excludes targets, daily totals and Health data")
        let invalid = MealEstimatorModel(date: now); invalid.photos = (0..<7).map { _ in MealPhoto(jpeg: jpeg) }
        check(!invalid.canRequest, "seven-photo request blocked")
        print("\(checks) estimator-model checks passed. Mocked network and observation only; no native UI or live AI.")
    }
}
