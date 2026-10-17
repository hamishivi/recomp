import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

enum EstimationService {
    typealias Transport = (URLRequest) async throws -> (Data, HTTPURLResponse)

    /// The injectable transport is for deterministic tests. Production always uses
    /// BoundedHTTPClient: fixed direct host, no redirects, no retries, bounded body.
    static func estimate(_ input: EstimateRequest, configuration: EstimatorConfiguration,
                         transport: Transport = { try await BoundedHTTPClient.data(for: $0) }) async throws -> MealEstimate {
        try Task.checkCancellation()
        let url = try configuration.endpoint()
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(configuration.bearerToken)", forHTTPHeaderField: "Authorization")
        request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
        if configuration.mode == .directOpenAI {
            request.httpBody = try DirectAIContract.body(for: input, model: configuration.model, reasoningEffort: configuration.reasoningEffort)
        } else { request.httpBody = try JSONEncoder().encode(input) }
        try Task.checkCancellation()
        let (data, http) = try await transport(request)
        try Task.checkCancellation()
        guard http.statusCode == 200 else {
            if configuration.mode == .directOpenAI { throw DirectAIContract.error(forHTTPStatus: http.statusCode) }
            // The optional private server retains its bounded, sanitized error recipe.
            guard http.mimeType?.lowercased() == "application/json" else { throw EstimateError.invalidResponse }
            struct ErrorBody: Decodable { let error: String }
            let error = try? JSONDecoder().decode(ErrorBody.self, from: data)
            throw EstimateError.rejected(String((error?.error ?? "Server request failed (\(http.statusCode)). Check the server address and try again.").prefix(500)))
        }
        guard http.mimeType?.lowercased() == "application/json" else { throw EstimateError.invalidResponse }
        if configuration.mode == .directOpenAI { return try DirectAIContract.decode(data, for: input) }
        let result: MealEstimate
        do { result = try JSONDecoder().decode(MealEstimate.self, from: data) }
        catch { throw EstimateError.invalidResponse }
        guard result.isValid, !result.items.contains(where: { item in
            item.evidence?.contains(where: { ($0.photoNumber ?? 0) > input.images.count }) == true
        }) else { throw EstimateError.invalidResponse }
        return result
    }
}
