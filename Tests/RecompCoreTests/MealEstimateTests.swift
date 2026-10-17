import XCTest
#if !RECOMP_NATIVE_TESTS
@testable import RecompCore
#endif

final class FoodHistoryTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private func entry(_ name: String, daysAgo: Double = 0, meal: MealKind = .lunch) -> FoodEntry {
        FoodEntry(name: name, date: now.addingTimeInterval(-daysAgo * 86400), meal: meal,
                  nutrition: Nutrition(calories: 400, protein: 25, carbs: 45, fat: 15))
    }
    func testHistoryIncludesOlderMealsAndSortsNewestFirst() {
        let older = entry("Old recipe", daysAgo: 800), recent = entry("Recent meal", daysAgo: 1)
        let today = entry("Today's meal")
        let records = [older, today, recent]
        XCTAssertEqual(DiaryMath.foodHistory(in: records, now: now).map(\.id), [today.id, recent.id, older.id])
        XCTAssertEqual(DiaryMath.foodHistory(in: records, query: "old recipe", now: now), [older])
        XCTAssertEqual(records, [older, today, recent])
    }
    func testHistorySearchMatchesWordsAcrossNamesIngredientsPortionsAndNotes() {
        var bowl = entry("Lunch bowl", daysAgo: 120)
        let items = [EstimatedFood(name: "Grilled chicken", portion: "150 grams", nutrition: bowl.nutrition)]
        bowl.aiDraft = EstimateDraft(estimate: MealEstimate(title: bowl.name, items: items))
        bowl.note = "Café recipe with lemon"
        XCTAssertTrue(bowl.isValid)
        for query in ["CHICKEN", "cafe", "LUNCH lemon", "bowl 150", "  grilled\n recipe  "] {
            XCTAssertEqual(DiaryMath.foodHistory(in: [bowl], query: query, now: now), [bowl], query)
        }
        XCTAssertTrue(DiaryMath.foodHistory(in: [bowl], query: "chicken pasta", now: now).isEmpty)
    }
    func testHistorySearchesMealKindWithoutRequiringItInName() {
        let eggs = entry("Eggs", meal: .breakfast)
        XCTAssertEqual(DiaryMath.foodHistory(in: [eggs], query: "eggs breakfast", now: now), [eggs])
        XCTAssertTrue(DiaryMath.foodHistory(in: [eggs], query: "dinner", now: now).isEmpty)
    }
    func testHistoryExcludesCurrentDeletedAndFutureEntries() {
        let current = entry("Editing"), deleted = entry("Deleted"), future = entry("Tomorrow", daysAgo: -1)
        let kept = entry("Saved", daysAgo: 5)
        XCTAssertEqual(DiaryMath.foodHistory(in: [current, deleted, future, kept], excludingID: current.id,
                                            deletedIDs: [deleted.id], now: now), [kept])
    }
    func testHistoryTieOrderIsStableAndBlankQueryReturnsAll() {
        var a = entry("A"), b = entry("B")
        a.id = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        b.id = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
        XCTAssertEqual(DiaryMath.foodHistory(in: [b, a], query: " \n ", now: now), [a, b])
        XCTAssertEqual(DiaryMath.foodHistory(in: [a, b], now: now), [a, b])
        XCTAssertTrue(DiaryMath.foodHistory(in: [], now: now).isEmpty)
    }
}

final class MealEstimateTests: XCTestCase {
    private func rice(_ id: String = "rice") -> EstimatedFood {
        EstimatedFood(id: id, name: "Cooked rice", portion: "1 cup cooked", nutrition: Nutrition(calories: 200, protein: 4, carbs: 44, fat: 0.4))
    }
    private func chicken() -> EstimatedFood {
        EstimatedFood(id: "chicken", name: "Chicken", portion: "150 g cooked", nutrition: Nutrition(calories: 250, protein: 46, carbs: 0, fat: 6))
    }
    private func meal() -> MealEstimate { MealEstimate(title: "Chicken and rice", items: [rice(), chicken()]) }
    func testTotalsAreCalculatedFromItems() {
        XCTAssertEqual(meal().total, Nutrition(calories: 450, protein: 50, carbs: 44, fat: 6.4))
    }
    func testHalfPortionScalesEveryMacroAndPreservesID() throws {
        let half = try XCTUnwrap(rice().scaled(by: 0.5))
        XCTAssertEqual(half.id, "rice")
        XCTAssertEqual(half.nutrition, Nutrition(calories: 100, protein: 2, carbs: 22, fat: 0.2))
        XCTAssertTrue(half.portion.hasPrefix("0.5 ×"))
    }
    func testScalingRejectsUnsafeFactors() {
        for x in [0.0, -1, .infinity, .nan, 21] { XCTAssertNil(rice().scaled(by: x)) }
    }
    func testInvalidNumbersAreRejected() {
        for value in [-1.0, .infinity, .nan, 20001] {
            var food = rice(); food.nutrition.calories = value; XCTAssertFalse(food.isValid)
        }
    }
    func testDuplicateIDsRejected() { XCTAssertFalse(MealEstimate(title: "Rice", items: [rice(),rice()]).isValid) }
    func testNoFoodResponseMayAskAQuestionButCannotBeLogged() {
        let result = MealEstimate(title: "Need meal details", items: [], questions: ["What did you eat?"])
        XCTAssertTrue(result.isValid); XCTAssertFalse(result.canLog)
    }
    func testOnlyOneConciseFollowUpQuestionIsAllowed() {
        var result = MealEstimate(title: "Lunch", items: [rice()], questions: ["  How many servings did you eat?  "])
        XCTAssertTrue(result.isValid)
        XCTAssertEqual(result.followUpQuestion, "How many servings did you eat?")
        result.questions = ["First?", "Second?"]; XCTAssertFalse(result.isValid)
        result.questions = ["   "]; XCTAssertFalse(result.isValid)
        result.questions = [String(repeating: "a", count: 181)]; XCTAssertFalse(result.isValid)
    }
    func testLegacyQuestionListsMigrateToTheirFirstQuestion() throws {
        let raw = #"{"title":"Lunch","items":[],"assumptions":[],"questions":["How much?","What oil?"]}"#
        let result = try JSONDecoder().decode(MealEstimate.self, from: Data(raw.utf8))
        XCTAssertEqual(result.questions, ["How much?"])
    }
    func testZeroNutritionCannotBeLogged() {
        let result = MealEstimate(title: "Water", items: [EstimatedFood(name: "Water", portion: "1 cup", nutrition: .zero)])
        XCTAssertTrue(result.isValid); XCTAssertFalse(result.canLog)
    }
    func testBlankNamesAndOversizedTextRejected() {
        var food = rice(); food.name = " \n "; XCTAssertFalse(food.isValid)
        food = rice(); food.portion = String(repeating: "a", count: 241); XCTAssertFalse(food.isValid)
    }
    func testManualEditLocksByDefault() {
        var draft = EstimateDraft(estimate: meal())
        var edit = rice(); edit.nutrition.calories = 123
        draft.edit(edit)
        XCTAssertTrue(draft.lockedItemIDs.contains("rice")); XCTAssertEqual(draft.estimate.items[0].nutrition.calories, 123)
    }
    func testRefinementPreservesLockedValuesEvenWhenModelChangesThem() throws {
        var draft = EstimateDraft(estimate: meal(), context: "Chicken and rice")
        draft.edit(try XCTUnwrap(rice().scaled(by: 0.5)))
        var response = meal(); response.items[0].nutrition.calories = 900
        response.items[1].nutrition.calories = 300
        let next = try draft.refined(with: response, clarification: "Actually 180 g chicken")
        XCTAssertEqual(next.estimate.items[0].nutrition.calories, 100)
        XCTAssertEqual(next.estimate.items[1].nutrition.calories, 300)
        XCTAssertTrue(next.context.contains("180 g chicken"))
    }
    func testMissingLockedFoodIsRestoredExactlyOnce() throws {
        var draft = EstimateDraft(estimate: meal()); draft.edit(rice())
        let result = try draft.refined(with: MealEstimate(title: "Chicken", items:[chicken()]), clarification:"More chicken")
        XCTAssertEqual(result.estimate.items.filter { $0.id == "rice" }.count, 1)
        XCTAssertEqual(result.estimate.total.calories, 450)
    }
    func testUnlockedFoodCanBeRefined() throws {
        var draft = EstimateDraft(estimate: meal()); draft.edit(rice(), locked:false)
        var response = meal(); response.items[0] = try XCTUnwrap(rice().scaled(by:0.5))
        XCTAssertEqual(try draft.refined(with: response, clarification:"half the rice").estimate.total.calories, 350)
    }
    func testRemoveUpdatesTotalAndRemembersExcludedFood() {
        var draft = EstimateDraft(estimate: meal()); draft.edit(rice()); draft.remove("rice")
        XCTAssertEqual(draft.estimate.total.calories, 250)
        XCTAssertTrue(draft.excludedFoods.contains("Cooked rice")); XCTAssertTrue(draft.lockedItemIDs.isEmpty)
    }
    func testSnapshotSentWithoutApplyingOldCorrectionAgain() throws {
        var draft = EstimateDraft(estimate: meal(), context:"Chicken and rice")
        var half = meal(); half.items[0] = try XCTUnwrap(rice().scaled(by: 0.5))
        draft = try draft.refined(with:half, clarification:"half the rice")
        let next = try draft.refined(with:half, clarification:"Chicken was grilled")
        XCTAssertEqual(next.estimate.total.calories, 350)
    }
    func testUnknownLocksRejected() { XCTAssertFalse(EstimateDraft(estimate: meal(), lockedItemIDs:["unknown"]).isValid) }
    func testContextLimitRejectsWithoutMutatingPreviousDraft() {
        let draft = EstimateDraft(estimate: meal(), context:String(repeating:"x",count:8000))
        XCTAssertThrowsError(try draft.refined(with:meal(),clarification:"more"))
        XCTAssertEqual(draft.context.count, 8000)
    }
    func testFoodCountLimitEnforcedAfterRestoringLocks() {
        var draft = EstimateDraft(estimate: meal()); draft.edit(rice())
        let crowded = MealEstimate(title:"Foods",items:(0..<15).map { rice("id-\($0)") })
        XCTAssertThrowsError(try draft.refined(with:crowded,clarification:"more"))
    }
    func testOldFoodEntryDecodesWithoutAIDraft() throws {
        let entry = FoodEntry(name:"Eggs",date:Date(timeIntervalSince1970:0),meal:.breakfast,nutrition:Nutrition(calories:200,protein:13,carbs:1,fat:15))
        let bytes = try JSONEncoder().encode(entry)
        XCTAssertFalse(String(decoding:bytes,as:UTF8.self).contains("aiDraft"))
        let decoded = try JSONDecoder().decode(FoodEntry.self,from:bytes)
        XCTAssertEqual(entry,decoded); XCTAssertNil(decoded.aiDraft)
    }
    func testEstimatedDiaryRoundTripsAndContainsNoPhotoBytes() throws {
        var entry = FoodEntry(name:"Lunch",date:Date(),meal:.lunch,nutrition:meal().total)
        entry.aiDraft = EstimateDraft(estimate:meal(),context:"Grilled chicken")
        var state = AppState(); state.entries = [entry]
        let data = try JSONEncoder().encode(state)
        XCTAssertEqual(try JSONDecoder().decode(AppState.self,from:data),state)
        XCTAssertTrue(state.isValid)
        let text = String(decoding:data,as:UTF8.self)
        XCTAssertFalse(text.contains("base64")); XCTAssertFalse(text.contains("accessToken"))
    }
    func testStaleAggregateWithOldBreakdownRejected() {
        var entry = FoodEntry(name:"Lunch",date:Date(),meal:.lunch,nutrition:meal().total)
        entry.aiDraft = EstimateDraft(estimate:meal()); entry.nutrition.calories += 100
        XCTAssertFalse(entry.isValid)
        entry.aiDraft = nil; XCTAssertTrue(entry.isValid)
    }
    func testEstimationRequestUsesOnlyMealFields() throws {
        let request = EstimateRequest(description:"Meal",clarification:"",images:[],currentEstimate:meal(),lockedItemIDs:[],excludedFoods:[])
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with:JSONEncoder().encode(request)) as? [String:Any])
        XCTAssertEqual(Set(json.keys),Set(["description","clarification","images","currentEstimate","lockedItemIDs","excludedFoods"]))
    }
    func testHTTPSAccepted() throws { XCTAssertEqual(try EstimateEndpoint.validated("https://food.example").host,"food.example") }
    func testInsecureRemoteURLRejectedEvenInDebug() {
        for url in ["http://food.example","ftp://food.example","https://user:pass@food.example","https://food.example?secret=x","https://food.example#x","not a url"] {
            XCTAssertThrowsError(try EstimateEndpoint.validated(url,allowLocalHTTP:true),url)
        }
    }
    func testLocalHTTPAllowedOnlyExplicitly() throws {
        XCTAssertThrowsError(try EstimateEndpoint.validated("http://localhost:8787"))
        XCTAssertEqual(try EstimateEndpoint.validated("http://localhost:8787",allowLocalHTTP:true).port,8787)
        XCTAssertThrowsError(try EstimateEndpoint.validated("http://localhost.evil.example",allowLocalHTTP:true))
    }
}
