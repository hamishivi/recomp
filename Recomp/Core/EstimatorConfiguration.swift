import Foundation

/// Credentials are encoded ONLY into the app's private Keychain item, never AppState,
/// backups, widgets, URLs or the source project. Direct mode is personal BYOK, not
/// a credential-distribution mechanism for an App Store app.
enum EstimatorMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case directOpenAI, server
    var id: String { rawValue }
    var title: String { self == .directOpenAI ? "Direct · personal API key" : "My server · advanced" }
}

enum DirectAIModel: String, Codable, CaseIterable, Identifiable, Sendable {
    case terra = "gpt-5.6-terra"
    case luna = "gpt-5.6-luna"
    case sol = "gpt-5.6-sol"
    case o3Mini = "o3-mini"
    case o1 = "o1"
    case standard = "gpt-4.1"
    case mini = "gpt-4.1-mini"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .terra: return "GPT-5.6 Terra · balanced (recommended)"
        case .luna: return "GPT-5.6 Luna · fast & economical"
        case .sol: return "GPT-5.6 Sol · deep reasoning flagship"
        case .o3Mini: return "o3-mini · STEM & nutrition reasoning"
        case .o1: return "o1 · advanced reasoning"
        case .standard: return "GPT-4.1 · high capacity"
        case .mini: return "GPT-4.1 mini · legacy economical"
        }
    }

    var supportsReasoning: Bool {
        switch self {
        case .terra, .luna, .sol, .o3Mini, .o1: return true
        case .standard, .mini: return false
        }
    }
}

enum ReasoningEffort: String, Codable, CaseIterable, Identifiable, Sendable {
    case none = "none"
    case low = "low"
    case medium = "medium"
    case high = "high"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: return "Off · direct output without reasoning"
        case .low: return "Low · quick reasoning"
        case .medium: return "Medium · balanced reasoning (recommended)"
        case .high: return "High · deep multi-step reasoning"
        }
    }
}

struct EstimatorConfiguration: Codable, Equatable, Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    var mode: EstimatorMode = .directOpenAI
    var baseURL = ""
    var accessToken = ""
    var apiKey = ""
    var model: DirectAIModel = .terra
    var reasoningEffort: ReasoningEffort = .medium
    var personalKeyAcknowledged = false

    init(mode: EstimatorMode = .directOpenAI, baseURL: String = "", accessToken: String = "",
         apiKey: String = "", model: DirectAIModel = .terra, reasoningEffort: ReasoningEffort = .medium,
         personalKeyAcknowledged: Bool = false) {
        self.mode = mode; self.baseURL = baseURL; self.accessToken = accessToken
        self.apiKey = apiKey; self.model = model; self.reasoningEffort = reasoningEffort
        self.personalKeyAcknowledged = personalKeyAcknowledged
    }
    private enum CodingKeys: String, CodingKey { case mode, baseURL, accessToken, apiKey, model, reasoningEffort, personalKeyAcknowledged }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        baseURL = try c.decodeIfPresent(String.self, forKey: .baseURL) ?? ""
        accessToken = try c.decodeIfPresent(String.self, forKey: .accessToken) ?? ""
        // Preserve an existing server setup; do not quietly switch its destination.
        mode = try c.decodeIfPresent(EstimatorMode.self, forKey: .mode) ??
            ((!baseURL.isEmpty || !accessToken.isEmpty) ? .server : .directOpenAI)
        apiKey = try c.decodeIfPresent(String.self, forKey: .apiKey) ?? ""
        model = try c.decodeIfPresent(DirectAIModel.self, forKey: .model) ?? .terra
        reasoningEffort = try c.decodeIfPresent(ReasoningEffort.self, forKey: .reasoningEffort) ?? .medium
        personalKeyAcknowledged = try c.decodeIfPresent(Bool.self, forKey: .personalKeyAcknowledged) ?? false
    }
    static var allowLocalHTTP: Bool {
        #if DEBUG && targetEnvironment(simulator)
        return true
        #else
        return false
        #endif
    }
    var description: String { "EstimatorConfiguration(mode: \(mode.rawValue), credentials: <redacted>)" }
    var debugDescription: String { description }
    var bearerToken: String { mode == .directOpenAI ? apiKey : accessToken }
    var destinationDescription: String {
        if mode == .directOpenAI { return "OpenAI (api.openai.com) directly" }
        return "\(URL(string: baseURL)?.host ?? "your server") and its OpenAI provider"
    }
    func endpoint() throws -> URL {
        switch mode {
        case .directOpenAI:
            guard personalKeyAcknowledged else {
                throw EstimateError.rejected("Review the personal API-key warning in Settings → Photo & text estimates first.")
            }
            guard apiKey.hasPrefix("sk-"), (20...512).contains(apiKey.utf8.count), Self.headerSafe(apiKey) else {
                throw EstimateError.rejected("Enter your own OpenAI API key in Photo & text estimates. Do not use a ChatGPT password or a server access token.")
            }
            // Never let a configurable host, redirect or previous server receive this key.
            return URL(string: "https://api.openai.com/v1/responses")!
        case .server:
            guard !baseURL.isEmpty, (32...1024).contains(accessToken.utf8.count), Self.headerSafe(accessToken) else {
                throw EstimateError.notConfigured
            }
            guard !accessToken.hasPrefix("sk-") else {
                throw EstimateError.rejected("The server option needs RECOMP_ACCESS_TOKEN, not an OpenAI key. Choose Direct to use your personal API key on this phone.")
            }
            return try EstimateEndpoint.validated(baseURL, allowLocalHTTP: Self.allowLocalHTTP).appendingPathComponent("v1/estimate")
        }
    }
    private static func headerSafe(_ value: String) -> Bool {
        value.utf8.allSatisfy { $0 >= 33 && $0 <= 126 }
    }
    func normalizedForSaving() throws -> Self {
        var value = self
        value.baseURL = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        value.accessToken = accessToken.trimmingCharacters(in: .whitespacesAndNewlines)
        value.apiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.mode == .directOpenAI { value.baseURL = ""; value.accessToken = "" }
        else { value.apiKey = ""; value.personalKeyAcknowledged = false }
        _ = try value.endpoint()
        return value
    }
}
