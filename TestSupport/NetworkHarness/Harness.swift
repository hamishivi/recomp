import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
// Only endpoint/keychain configuration is replaced, to permit synthetic loopback HTTP.
// The production EstimationService and transport are compiled unchanged below.
private let loopbackConfiguration = EstimatorConfiguration(mode: .server, baseURL: "https://synthetic-test.invalid", accessToken: "synthetic-local-token-00000000000000000000")
private func loopbackTransport(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
    var request = request
    request.url = URL(string: ProcessInfo.processInfo.environment["RECOMP_TEST_SERVER"]! + "/v1/estimate")!
    return try await BoundedHTTPClient.data(for: request)
}

@main struct NetworkHarness {
    static func main() async throws {
        setbuf(stdout, nil)
        var count=0,failures=0
        func check(_ ok: Bool, _ label: String) {count+=1;print("\(ok ? "PASS" : "FAIL"): \(label)");if !ok {failures+=1}}
        func input(_ mode:String)->EstimateRequest {EstimateRequest(description:mode, clarification:"", images:[], currentEstimate:nil, lockedItemIDs:[], excludedFoods:[])}
        func request(_ mode:String) async throws -> MealEstimate {try await EstimationService.estimate(input(mode),configuration:loopbackConfiguration,transport:loopbackTransport)}
        func stats() async throws -> [String:Any] {
            let url=URL(string:ProcessInfo.processInfo.environment["RECOMP_TEST_SERVER"]!+"/stats")!
            let(data,_)=try await URLSession.shared.data(from:url)
            return try JSONSerialization.jsonObject(with:data) as! [String:Any]
        }
        let success = try await request("ok")
        check(success.total.calories==200,"actual client decodes a successful localhost response")
        for mode in ["large-length","large-stream","redirect","invalid-json","wrong-type","bad-photo","server-error"] {
            do {_ = try await request(mode);check(false,"reject \(mode)")}
            catch {check(true,"reject \(mode)")}
            if mode.hasPrefix("large") {
                try await Task.sleep(nanoseconds:30_000_000)
                let state = try await stats()[mode] as! [String:Any]
                check((state["chunks"] as! Int)<15,"\(mode) stops transfer before buffering full body")
                check(state["closed"] as? Bool == true,"\(mode) closes rejected response")
            }
        }
        let after = try await stats()
        check((after["redirectHits"] as? Int ?? 0)==0,"redirect target receives no request or bearer token")
        let pending=Task { try await request("cancel") }
        for _ in 0..<100 { if (try await stats()["cancel"]) != nil { break }; try await Task.sleep(nanoseconds:5_000_000) }
        pending.cancel()
        do {_ = try await pending.value;check(false,"cancelled request fails")}
        catch {check(true,"cancelled request fails")}
        try await Task.sleep(nanoseconds:50_000_000)
        let cancelled = try await stats()["cancel"] as! [String:Any]
        check(cancelled["closed"] as? Bool==true,"Swift task cancellation closes active HTTP transfer")
        let recovery=try await request("recovery")
        check(recovery.total.calories==200,"client recovers after oversized, failed and cancelled requests")

        let exact = try await request("exact-size")
        check(exact.total.calories == 200, "exact 250,000-byte valid JSON response is accepted")
        do { _ = try await request("gzip-large"); check(false, "decompressed response is bounded") }
        catch { check(true, "decompressed response is bounded") }
        // Exercise cancellation racing completion across many independent sessions.
        let burst = (0..<100).map { index in Task { try await request("stress-\(index)") } }
        for index in stride(from: 0, to: burst.count, by: 2) { burst[index].cancel() }
        var completed = 0, correctUncancelled = 0
        for (index, task) in burst.enumerated() {
            do {
                let meal = try await task.value; completed += 1
                if index % 2 == 1 && meal.total.calories == 200 { correctUncancelled += 1 }
            } catch { completed += 1 }
        }
        check(correctUncancelled == 50, "all 50 uncancelled requests succeed during cancellation stress")
        check(completed == 100, "100 cancellation/completion races terminate without a stuck continuation")
        let preCancelled = Task {
            // Let the cancellation flag be set, then still ENTER the production client.
            try? await Task.sleep(nanoseconds: 10_000_000)
            return try await request("pre-cancelled")
        }
        preCancelled.cancel()
        do { _ = try await preCancelled.value; check(false, "pre-cancelled task is rejected") }
        catch { check(true, "pre-cancelled task is rejected") }
        let finalStats = try await stats()
        check(finalStats["pre-cancelled"] == nil, "pre-cancellation sends no HTTP request")
        #if RECOMP_BOUNDED_TRANSPORT
        var timeoutRequest = URLRequest(url: URL(string: ProcessInfo.processInfo.environment["RECOMP_TEST_SERVER"]! + "/v1/estimate")!)
        timeoutRequest.httpMethod = "POST"
        timeoutRequest.httpBody = try JSONEncoder().encode(input("timeout"))
        let began = Date()
        do {
            _ = try await BoundedHTTPClient.data(for: timeoutRequest, requestTimeout: 2, resourceTimeout: 0.5)
            check(false, "overall timeout stops a trickling response")
        } catch { check((error as? URLError)?.code == .timedOut, "overall deadline returns the timedOut error") }
        check(Date().timeIntervalSince(began) < 5, "overall timeout is not reset by each received byte")
        #endif
        print("NETWORK: \(count) checks, \(failures) failures")
        if failures>0 {exit(1)}
    }
}
