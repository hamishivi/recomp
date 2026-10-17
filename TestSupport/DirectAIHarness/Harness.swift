import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

@main struct DirectAIHarness {
    static func main() async throws {
        setbuf(stdout, nil)
        var checks = 0, failures = 0
        func check(_ ok: Bool, _ label: String) { checks += 1; if !ok { failures += 1 }; print("\(ok ? "PASS" : "FAIL"): \(label)") }
        let key = "sk-proj-SYNTHETIC-KEY-FOR-LOCAL-TESTS-ONLY"
        let config = EstimatorConfiguration(baseURL: "https://should-not-receive-anything.invalid", accessToken: "NEVER-SEND-PROXY-KEY", apiKey: key, personalKeyAcknowledged: true)
        let base = ProcessInfo.processInfo.environment["RECOMP_TEST_SERVER"]!
        func input(_ mode: String, images: [EstimateImage] = [], current: MealEstimate? = nil, locks: [String] = []) -> EstimateRequest {
            EstimateRequest(description: mode, clarification: current == nil ? "" : "Keep my correction", images: images,
                currentEstimate: current, lockedItemIDs: locks, excludedFoods: [])
        }
        func transport(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
            guard request.url?.absoluteString == "https://api.openai.com/v1/responses",
                  request.value(forHTTPHeaderField: "Authorization") == "Bearer \(key)" else { throw EstimateError.invalidEndpoint }
            var local = request; local.url = URL(string: base + "/v1/responses")!
            return try await BoundedHTTPClient.data(for: local)
        }
        func call(_ mode: String) async throws -> MealEstimate {
            try await EstimationService.estimate(input(mode), configuration: config, transport: transport)
        }
        func stats() async throws -> [String: Int] {
            let (data, _) = try await URLSession.shared.data(from: URL(string: base + "/stats")!)
            return try JSONDecoder().decode([String: Int].self, from: data)
        }
        let result = try await call("success")
        check(result.total.calories == 70, "production direct client builds Responses request and decodes reply")
        let jpeg = Data([0xff,0xd8,0xff,0xc0,0,11,8,0,16,0,16,1,1,0x11,0,0xff,0xd9])
        let photo = EstimateImage(base64: jpeg.base64EncodedString(), role: .nutritionLabel, caption: "one serving")
        let multi = try await EstimationService.estimate(input("six", images: Array(repeating: photo, count: 6)), configuration: config, transport: transport)
        check(multi.total.calories == 70, "six evidence images use actual direct request recipe and output validator")
        for mode in ["status-401","status-403","status-429","status-500","status-400","status-404","status-413","wrong-type","large","invalid-json","incomplete","refusal","bad-photo","redirect"] {
            do { _ = try await call(mode); check(false, "reject \(mode)") }
            catch { check(!error.localizedDescription.contains("SYNTHETIC_PRIVATE_VALUE") && !error.localizedDescription.contains("PRIVATE_REFUSAL"), "reject \(mode), no raw provider error text") }
        }
        let before = try await stats()["count"]!
        var invalid = config; invalid.personalKeyAcknowledged = false
        do { _ = try await EstimationService.estimate(input("unapproved"), configuration: invalid, transport: transport); check(false, "reject unacknowledged key") }
        catch { check(true, "reject unacknowledged key") }
        do { _ = try await EstimationService.estimate(input("too-many", images: Array(repeating: photo, count: 7)), configuration: config, transport: transport); check(false, "reject seven photos") }
        catch { check(true, "reject seven photos") }
        check(try await stats()["count"] == before, "invalid settings and input send zero HTTP requests")
        let pending = Task { try await call("cancel") }
        for _ in 0..<100 { if try await stats()["count"] == before + 1 { break }; try await Task.sleep(nanoseconds: 5_000_000) }
        pending.cancel()
        do { _ = try await pending.value; check(false, "direct request cancellation") }
        catch { check(true, "direct request cancellation") }
        var corrected = result; corrected.items[0].nutrition.calories = 82
        let locked = try await EstimationService.estimate(input("locks", current: corrected, locks: ["egg"]), configuration: config, transport: transport)
        check(locked.total.calories == 82, "provider cannot overwrite locked manual totals")
        check((try await call("recovery")).total.calories == 70, "client recovers after errors and cancellation")
        let state = try await stats()
        check(state["redirectHits"] == 0, "redirect destination receives no API key or request")
        check(state["contracts"] == state["count"], "every request matches proxy prompt/schema and whitelist: independent Node assertion")
        check(state["count"] == 19, "no hidden retries, fallback calls or automatic paid requests")
        print("DIRECT AI: \(checks) checks, \(failures) failures; localhost fake provider, never OpenAI")
        if failures > 0 { exit(1) }
    }
}
