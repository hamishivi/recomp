import Foundation
import XCTest
#if !RECOMP_NATIVE_TESTS
@testable import RecompCore
#endif

final class DirectAITests: XCTestCase {
    private let key = "sk-proj-SYNTHETIC-KEY-FOR-LOCAL-TESTS-ONLY"
    private func config() -> EstimatorConfiguration {
        EstimatorConfiguration(apiKey: key, personalKeyAcknowledged: true)
    }
    private func request(_ description: String = "One egg", images: [EstimateImage] = [], current: MealEstimate? = nil,
                         clarification: String = "", locks: [String] = []) -> EstimateRequest {
        EstimateRequest(description: description, clarification: clarification, images: images,
            currentEstimate: current, lockedItemIDs: locks, excludedFoods: [])
    }
    private func image() -> EstimateImage {
        // Minimal frame header only, not a valid rendered photo or an OCR fixture.
        let data = Data([0xff,0xd8,0xff,0xc0,0,11,8,0,16,0,16,1,1,0x11,0,0xff,0xd9])
        return EstimateImage(base64: data.base64EncodedString(), role: .nutritionLabel, caption: "half the bottle")
    }
    private func meal() -> MealEstimate {
        MealEstimate(title: "Egg", items: [EstimatedFood(id: "egg", name: "Egg", portion: "1 large",
            nutrition: Nutrition(calories: 70, protein: 6, carbs: 0, fat: 5), evidence: [])])
    }
    private func envelope(_ estimate: MealEstimate, status: String = "completed") throws -> Data {
        let text = String(decoding: try JSONEncoder().encode(estimate), as: UTF8.self)
        return try JSONSerialization.data(withJSONObject: ["status": status, "output": [["type": "message", "role": "assistant", "status": "completed", "content": [["type": "output_text", "text": text]]]]])
    }
    func testLockedPhotoEvidenceSurvivesTextOnlyRefinement() throws {
        var current = meal()
        current.items[0].evidence = [FoodEvidence(kind: .label, photoNumber: 1, detail: "70 kcal per egg")]
        let response = meal()
        let input = request(current: current, clarification: "Keep egg", locks: ["egg"])
        let decoded = try DirectAIContract.decode(envelope(response), for: input)
        XCTAssertEqual(decoded.items[0].nutrition, current.items[0].nutrition)
        XCTAssertNil(decoded.items[0].evidence?.first?.photoNumber)
        XCTAssertEqual(decoded.items[0].evidence?.first?.detail, "70 kcal per egg")
        let draft = EstimateDraft(estimate: current, lockedItemIDs: ["egg"])
        XCTAssertNil(try draft.refined(with: decoded, clarification: "Keep egg").estimate.items[0].evidence?.first?.photoNumber)
    }
    func testNewSettingsDefaultToUnconfiguredDirectMode() {
        let c = EstimatorConfiguration()
        XCTAssertEqual(c.mode, .directOpenAI)
        XCTAssertEqual(c.model, .terra)
        XCTAssertEqual(c.reasoningEffort, .medium)
        XCTAssertThrowsError(try c.endpoint())
    }
    func testLegacyServerConfigurationKeepsItsDestinationAndCredential() throws {
        let data = Data(#"{"baseURL":"https://old.example","accessToken":"synthetic-server-token-00000000000000"}"#.utf8)
        let c = try JSONDecoder().decode(EstimatorConfiguration.self, from: data)
        XCTAssertEqual(c.mode, .server)
        XCTAssertEqual(try c.endpoint().absoluteString, "https://old.example/v1/estimate")
        XCTAssertEqual(c.bearerToken, "synthetic-server-token-00000000000000")
        XCTAssertTrue(c.apiKey.isEmpty)
    }
    func testEmptyLegacySettingsDefaultToDirectWithoutInventingConsent() throws {
        let c = try JSONDecoder().decode(EstimatorConfiguration.self, from: Data(#"{"baseURL":"","accessToken":""}"#.utf8))
        XCTAssertEqual(c.mode, .directOpenAI)
        XCTAssertFalse(c.personalKeyAcknowledged)
    }
    func testUnknownModeOrModelIsRejectedRatherThanSilentlyRerouted() {
        for json in [#"{"mode":"other-provider"}"#, #"{"mode":"directOpenAI","model":"invented"}"#] {
            XCTAssertThrowsError(try JSONDecoder().decode(EstimatorConfiguration.self, from: Data(json.utf8)))
        }
    }
    func testDirectModeIgnoresOldServerURLAndUsesOnlyTheAPIKey() throws {
        var c = config(); c.baseURL = "https://not-openai.example"; c.accessToken = "other-secret"
        XCTAssertEqual(try c.endpoint().absoluteString, "https://api.openai.com/v1/responses")
        XCTAssertEqual(c.bearerToken, key)
        XCTAssertFalse(c.destinationDescription.contains("not-openai"))
    }
    func testDirectModeRequiresAcknowledgment() {
        var c = config(); c.personalKeyAcknowledged = false
        XCTAssertThrowsError(try c.endpoint())
    }
    func testRejectsInvalidOrHeaderInjectedCredentials() {
        for invalid in ["", "password", "sk-short", key + "\r\nInjected: value", key + "\u{0}", key + "\t", "sk-" + String(repeating: "a", count: 513), key + "é"] {
            var c = config(); c.apiKey = invalid
            XCTAssertThrowsError(try c.endpoint())
        }
        var server = EstimatorConfiguration(mode: .server, baseURL: "https://example.test", accessToken: key)
        XCTAssertThrowsError(try server.endpoint())
        server.accessToken = String(repeating: "a", count: 40) + "\r\nX: y"
        XCTAssertThrowsError(try server.endpoint())
    }
    func testSavingTrimsPastedWhitespaceAndDropsInactiveSecrets() throws {
        var c = config(); c.apiKey = "  \(key)\n"; c.baseURL = "old"; c.accessToken = "old-secret"
        let direct = try c.normalizedForSaving()
        XCTAssertEqual(direct.apiKey, key); XCTAssertTrue(direct.accessToken.isEmpty); XCTAssertTrue(direct.baseURL.isEmpty)
        c.mode = .server; c.baseURL = " https://example.test "; c.accessToken = String(repeating: "x", count: 40)
        let server = try c.normalizedForSaving()
        XCTAssertTrue(server.apiKey.isEmpty); XCTAssertFalse(server.personalKeyAcknowledged)
        XCTAssertEqual(server.baseURL, "https://example.test")
    }
    func testSettingsRoundTripAndDebugDescriptionRedactsSecrets() throws {
        let c = config()
        XCTAssertEqual(try JSONDecoder().decode(EstimatorConfiguration.self, from: JSONEncoder().encode(c)), c)
        XCTAssertFalse(String(describing: c).contains(key))
        XCTAssertFalse(String(reflecting: c).contains(key))
    }
    func testDirectRequestUsesStructuredOutputAndNoHostedToolsOrState() throws {
        let data = try DirectAIContract.body(for: request(), model: .mini)
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(Set(body.keys), ["model", "store", "stream", "max_output_tokens", "instructions", "input", "text"])
        XCTAssertEqual(body["model"] as? String, "gpt-4.1-mini")
        XCTAssertEqual(body["store"] as? Bool, false); XCTAssertEqual(body["stream"] as? Bool, false)
        XCTAssertEqual(body["max_output_tokens"] as? Int, 4500)
        let text = try XCTUnwrap(body["text"] as? [String: Any]); let format = try XCTUnwrap(text["format"] as? [String: Any])
        XCTAssertEqual(format["strict"] as? Bool, true)
        XCTAssertEqual(format["type"] as? String, "json_schema")
        let schema = try XCTUnwrap(format["schema"] as? [String: Any])
        XCTAssertEqual(schema["additionalProperties"] as? Bool, false)
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains(key))
    }
    func testSixPhotosKeepNumberedRolesAndCaptionsInSingleMealContext() throws {
        let data = try DirectAIContract.body(for: request(images: Array(repeating: image(), count: 6)), model: .standard)
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let input = try XCTUnwrap(body["input"] as? [[String: Any]])
        XCTAssertEqual(input.count, 1)
        let content = try XCTUnwrap(input[0]["content"] as? [[String: Any]])
        XCTAssertEqual(content.count, 7)
        let text = try XCTUnwrap(content[0]["text"] as? String)
        let context = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
        XCTAssertTrue(Set(context.keys).isSubset(of: ["description", "clarification", "currentEstimate", "lockedItemIDs", "excludedFoods", "photoEvidence"]))
        let photos = try XCTUnwrap(context["photoEvidence"] as? [[String: Any]])
        XCTAssertEqual(photos[5]["photoNumber"] as? Int, 6)
        XCTAssertEqual(photos[0]["role"] as? String, "nutritionLabel")
        XCTAssertEqual(photos[0]["caption"] as? String, "half the bottle")
        XCTAssertEqual(body["model"] as? String, "gpt-4.1")
    }
    func testNoFoodAndTooManyImagesAreRejectedBeforeNetwork() {
        XCTAssertThrowsError(try DirectAIContract.validate(request("   ")))
        XCTAssertThrowsError(try DirectAIContract.validate(request(images: Array(repeating: image(), count: 7))))
    }
    func testContextLimitsCountActualCombinedRefinement() {
        XCTAssertNoThrow(try DirectAIContract.validate(request(String(repeating: "a", count: 7986), current: meal(), clarification: "b")))
        XCTAssertThrowsError(try DirectAIContract.validate(request(String(repeating: "a", count: 7987), current: meal(), clarification: "b")))
        XCTAssertThrowsError(try DirectAIContract.validate(request(current: meal())))
        XCTAssertThrowsError(try DirectAIContract.validate(request(clarification: String(repeating: "a", count: 2001))))
    }
    func testQuestionAnswersAreBoundedForFollowUpRounds() {
        var asked = meal(); asked.questions = ["How many servings did you eat?"]
        XCTAssertNoThrow(try DirectAIContract.validate(request(current: asked, clarification: String(repeating: "a", count: 160))))
        XCTAssertThrowsError(try DirectAIContract.validate(request(current: asked, clarification: String(repeating: "a", count: 161))))
    }
    func testUnicodeCombiningSequencesCannotBypassInputScalarBound() {
        XCTAssertThrowsError(try DirectAIContract.validate(request(String(repeating: "a\u{0301}", count: 4500))))
    }
    func testUnknownAndDuplicateLocksAreRejected() {
        XCTAssertThrowsError(try DirectAIContract.validate(request(current: meal(), clarification: "half", locks: ["unknown"])))
        XCTAssertThrowsError(try DirectAIContract.validate(request(current: meal(), clarification: "half", locks: ["egg", "egg"])))
        XCTAssertNoThrow(try DirectAIContract.validate(request(current: meal(), clarification: "half", locks: ["egg"])))
    }
    func testBadJPEGEncodingDimensionsAndCaptionsAreRejected() {
        for base64 in ["invalid!", "AAAA", image().base64 + "\n", Data(repeating: 0, count: 1_500_001).base64EncodedString()] {
            XCTAssertThrowsError(try DirectAIContract.validate(request(images: [EstimateImage(base64: base64)])))
        }
        var zero = [UInt8](Data(base64Encoded: image().base64)!); zero[7] = 0; zero[8] = 0
        XCTAssertThrowsError(try DirectAIContract.validate(request(images: [EstimateImage(base64: Data(zero).base64EncodedString())])))
        var photo = image(); photo.caption = String(repeating: "x", count: 241)
        XCTAssertThrowsError(try DirectAIContract.validate(request(images: [photo])))
    }
    func testJPEGHeaderParsingHandlesEveryTruncation() {
        let bytes = Data(base64Encoded: image().base64)!
        for end in 0..<15 { XCTAssertNil(DirectAIContract.jpegDimensions(bytes.prefix(end))) }
        XCTAssertEqual(DirectAIContract.jpegDimensions(bytes)?.width, 16)
        XCTAssertNil(DirectAIContract.jpegDimensions(Data([0xff,0xd8] + Array(repeating: 0xff, count: 40))))
    }
    func testSuccessfulResponseAndNoFoodQuestionDecode() throws {
        XCTAssertEqual(try DirectAIContract.decode(envelope(meal()), for: request()), meal())
        let empty = MealEstimate(title: "No food identified", items: [], questions: ["Can you show the plate?"])
        let result = try DirectAIContract.decode(envelope(empty), for: request())
        XCTAssertEqual(result, empty); XCTAssertFalse(result.canLog)
    }
    func testDirectSchemaLimitsTheModelToOneQuestion() throws {
        let body = try DirectAIContract.body(for: request(), model: .mini)
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        let format = try XCTUnwrap(root["text"] as? [String: Any])
        let schema = try XCTUnwrap(format["format"] as? [String: Any])
        let estimate = try XCTUnwrap(schema["schema"] as? [String: Any])
        let properties = try XCTUnwrap(estimate["properties"] as? [String: Any])
        let questions = try XCTUnwrap(properties["questions"] as? [String: Any])
        XCTAssertEqual(questions["maxItems"] as? Int, 1)
    }
    func testIncompleteRefusalAndMalformedOutputsAreRejected() throws {
        for status in ["incomplete", "failed", "in_progress"] {
            XCTAssertThrowsError(try DirectAIContract.decode(envelope(meal(), status: status), for: request()))
        }
        let refusal = Data(#"{"status":"completed","output":[{"type":"message","role":"assistant","status":"completed","content":[{"type":"refusal","refusal":"SECRET RESPONSE TEXT"}]}]}"#.utf8)
        XCTAssertThrowsError(try DirectAIContract.decode(refusal, for: request())) { XCTAssertFalse($0.localizedDescription.contains("SECRET")) }
        for bad in ["{}", "null", "not-json", #"{"status":"completed","output":[]}"#] {
            XCTAssertThrowsError(try DirectAIContract.decode(Data(bad.utf8), for: request()))
        }
    }
    func testOversizedResponseAndUnexpectedRolesAreRejected() throws {
        XCTAssertThrowsError(try DirectAIContract.decode(Data(repeating: 32, count: 250_001), for: request()))
        let wrong = String(decoding: try envelope(meal()), as: UTF8.self).replacingOccurrences(of: "assistant", with: "user")
        XCTAssertThrowsError(try DirectAIContract.decode(Data(wrong.utf8), for: request()))
    }
    func testUnknownFieldsAndMissingRequiredEvidenceAreRejected() throws {
        var item = meal(); item.items[0].evidence = nil
        XCTAssertThrowsError(try DirectAIContract.decode(envelope(item), for: request()))
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(meal())) as? [String: Any]); json["invented"] = "value"
        let text = String(decoding: try JSONSerialization.data(withJSONObject: json), as: UTF8.self)
        let response: [String: Any] = ["status": "completed", "output": [["type": "message", "role": "assistant", "status": "completed", "content": [["type": "output_text", "text": text]]]]]
        XCTAssertThrowsError(try DirectAIContract.decode(JSONSerialization.data(withJSONObject: response), for: request()))
    }
    func testInvalidNutritionAndDuplicateIDsAreRejected() throws {
        var bad = meal(); bad.items[0].nutrition.calories = -1
        XCTAssertThrowsError(try DirectAIContract.decode(envelope(bad), for: request()))
        bad = meal(); bad.items.append(bad.items[0])
        XCTAssertThrowsError(try DirectAIContract.decode(envelope(bad), for: request()))
    }
    func testPhotoReferencesCannotPointOutsideCurrentEvidence() throws {
        var value = meal(); value.items[0].evidence = [FoodEvidence(kind: .label, photoNumber: 1, detail: "one serving")]
        XCTAssertThrowsError(try DirectAIContract.decode(envelope(value), for: request()))
        XCTAssertNoThrow(try DirectAIContract.decode(envelope(value), for: request(images: [image()])))
    }
    func testLockedManualValuesAreRestoredEvenWhenModelChangesOrOmitsThem() throws {
        let original = meal()
        let input = request(current: original, clarification: "keep manual values", locks: ["egg"])
        var changed = original; changed.items[0].nutrition.calories = 999
        XCTAssertEqual(try DirectAIContract.decode(envelope(changed), for: input).items, original.items)
        changed.items = []
        XCTAssertEqual(try DirectAIContract.decode(envelope(changed), for: input).items, original.items)
    }
    func testRestoringLocksCannotOverflowItemLimit() throws {
        var proposed = meal(); proposed.items = (0..<15).map { i in var f = meal().items[0]; f.id = "new-\(i)"; return f }
        XCTAssertThrowsError(try DirectAIContract.decode(envelope(proposed), for: request(current: meal(), clarification: "keep", locks: ["egg"])))
    }
    func testHTTPErrorsAreActionableAndDoNotNeedProviderBody() {
        XCTAssertTrue(DirectAIContract.error(forHTTPStatus: 401).localizedDescription.contains("API key"))
        XCTAssertTrue(DirectAIContract.error(forHTTPStatus: 429).localizedDescription.contains("billing"))
        XCTAssertTrue(DirectAIContract.error(forHTTPStatus: 403).localizedDescription.contains("region"))
        XCTAssertTrue(DirectAIContract.error(forHTTPStatus: 500).localizedDescription.contains("unchanged"))
    }
    func testTerraAndLunaUseReasoningAndExtendedTokenBudget() throws {
        for model in [DirectAIModel.terra, .luna, .sol, .o3Mini, .o1] {
            let data = try DirectAIContract.body(for: request(), model: model, reasoningEffort: .medium)
            let body = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
            XCTAssertEqual(body["model"] as? String, model.rawValue)
            XCTAssertEqual(body["max_output_tokens"] as? Int, 12000)
            let reasoning = try XCTUnwrap(body["reasoning"] as? [String: Any])
            XCTAssertEqual(reasoning["effort"] as? String, "medium")
        }
    }
    func testReasoningEffortCanBeConfiguredOrTurnedOff() throws {
        let off = try DirectAIContract.body(for: request(), model: .terra, reasoningEffort: .none)
        let offBody = try XCTUnwrap(JSONSerialization.jsonObject(with: off) as? [String: Any])
        XCTAssertNil(offBody["reasoning"])

        let high = try DirectAIContract.body(for: request(), model: .terra, reasoningEffort: .high)
        let highBody = try XCTUnwrap(JSONSerialization.jsonObject(with: high) as? [String: Any])
        let reasoning = try XCTUnwrap(highBody["reasoning"] as? [String: Any])
        XCTAssertEqual(reasoning["effort"] as? String, "high")
    }
    func testAllMainOpenAIModelsAreSupported() {
        XCTAssertEqual(DirectAIModel.allCases.count, 7)
        XCTAssertTrue(DirectAIModel.terra.supportsReasoning)
        XCTAssertTrue(DirectAIModel.luna.supportsReasoning)
        XCTAssertTrue(DirectAIModel.sol.supportsReasoning)
        XCTAssertFalse(DirectAIModel.standard.supportsReasoning)
        XCTAssertFalse(DirectAIModel.mini.supportsReasoning)
    }
}
