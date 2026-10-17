import Foundation

enum EstimateConfidence: String, Codable, CaseIterable, Sendable {
    case low, medium, high
}

/// Nutrition is for the described portion, not per 100 g. Confidence is a model
/// judgement, not a calibrated probability or a medical measurement.
struct EstimatedFood: Codable, Identifiable, Equatable, Sendable {
    var id: String = UUID().uuidString
    var name: String
    var portion: String
    var nutrition: Nutrition
    var confidence: EstimateConfidence = .low
    var assumptions: [String] = []
    var evidence: [FoodEvidence]?
    var isValid: Bool {
        !id.isEmpty && id.count <= 80 && !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        name.count <= 160 && !portion.isEmpty && portion.count <= 240 &&
        nutrition.isValid && nutrition.calories <= 20_000 &&
        [nutrition.protein, nutrition.carbs, nutrition.fat].allSatisfy { $0 <= 3000 } &&
        (evidence == nil || (evidence!.count <= 8 && evidence!.allSatisfy(\.isValid))) &&
        assumptions.count <= 8 && assumptions.allSatisfy { $0.count <= 400 }
    }
    func scaled(by factor: Double) -> EstimatedFood? {
        guard factor.isFinite, factor > 0, factor <= 20 else { return nil }
        var result = self
        result.nutrition = nutrition.scaled(by: factor)
        result.portion = String("\(InputNumber.editString(factor)) × (\(portion))".prefix(240))
        return result.isValid ? result : nil
    }
}

struct MealEstimate: Codable, Equatable, Sendable {
    var title: String
    var items: [EstimatedFood]
    var assumptions: [String] = []
    /// The model may request one concise, high-impact clarification before a
    /// later refinement. Keeping this as an array preserves older saved drafts.
    var questions: [String] = []
    init(title: String, items: [EstimatedFood], assumptions: [String] = [], questions: [String] = []) {
        self.title = title
        self.items = items
        self.assumptions = assumptions
        self.questions = Array(questions.prefix(1))
    }
    private enum CodingKeys: String, CodingKey { case title, items, assumptions, questions }
    /// Versions before the one-question flow could persist several passive
    /// questions. Retain only the first when opening those drafts.
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        title = try values.decode(String.self, forKey: .title)
        items = try values.decode([EstimatedFood].self, forKey: .items)
        assumptions = try values.decodeIfPresent([String].self, forKey: .assumptions) ?? []
        questions = Array((try values.decodeIfPresent([String].self, forKey: .questions) ?? []).prefix(1))
    }
    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(title, forKey: .title)
        try values.encode(items, forKey: .items)
        try values.encode(assumptions, forKey: .assumptions)
        try values.encode(questions, forKey: .questions)
    }
    var followUpQuestion: String? {
        guard let question = questions.first?.trimmingCharacters(in: .whitespacesAndNewlines), !question.isEmpty else { return nil }
        return question
    }
    var total: Nutrition { items.reduce(.zero) { $0 + $1.nutrition } }
    var isValid: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && title.count <= 160 &&
        items.count <= 15 && items.allSatisfy(\.isValid) && Set(items.map(\.id)).count == items.count &&
        assumptions.count <= 10 && assumptions.allSatisfy { $0.count <= 400 } &&
        questions.count <= 1 && questions.allSatisfy {
            !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.count <= 180
        } && total.isValid
    }
    /// A review hint, never a correction: labels, fibre and alcohol can legitimately
    /// differ from 4/4/9. Check per item so opposite errors cannot cancel in totals.
    var nutritionReviewWarnings: [String] {
        items.compactMap { item in
            let difference = abs(item.nutrition.calories - item.nutrition.macroCalories)
            guard difference > max(50, item.nutrition.calories * 0.20) else { return nil }
            return "\(item.name): calories differ substantially from protein/carbs/fat. Check the serving and units; label rounding, fibre or alcohol may explain the difference."
        }
    }
    var canLog: Bool { isValid && !items.isEmpty && total.containsFood }
}

/// Persist only the reviewed text and breakdown, NEVER image bytes or credentials.
/// Optional on FoodEntry, so original 1.0 diaries decode without a migration.
struct EstimateDraft: Codable, Equatable, Sendable {
    var estimate: MealEstimate
    var context: String = ""
    var lockedItemIDs: Set<String> = []
    var excludedFoods: [String] = []
    var isValid: Bool {
        estimate.isValid && context.count <= 8000 && excludedFoods.count <= 30 &&
        excludedFoods.allSatisfy { $0.count <= 160 } &&
        lockedItemIDs.isSubset(of: Set(estimate.items.map(\.id)))
    }
    mutating func clearPhotoReferences() {
        estimate.items = estimate.items.map { item in
            var item = item
            item.evidence = item.evidence?.map { evidence in
                var evidence = evidence; evidence.photoNumber = nil; return evidence
            }
            return item
        }
    }
    mutating func edit(_ food: EstimatedFood, locked: Bool = true) {
        guard food.isValid else { return }
        if let index = estimate.items.firstIndex(where: { $0.id == food.id }) {
            estimate.items[index] = food
        } else if estimate.items.count < 15 { estimate.items.append(food) }
        else { return }
        if locked { lockedItemIDs.insert(food.id) } else { lockedItemIDs.remove(food.id) }
    }
    mutating func remove(_ id: String) {
        if let food = estimate.items.first(where: { $0.id == id }) {
            excludedFoods = Array((excludedFoods + [food.name]).suffix(30))
        }
        estimate.items.removeAll { $0.id == id }
        lockedItemIDs.remove(id)
    }
    /// Protect manual edits locally as well as on the proxy. Never trust a model
    /// to honour locks, IDs, arithmetic or output validation on its own.
    func refined(with response: MealEstimate, clarification: String) throws -> EstimateDraft {
        guard response.isValid else { throw EstimateError.invalidResponse }
        var next = self
        next.estimate = response
        for prior in estimate.items where lockedItemIDs.contains(prior.id) {
            var food = prior
            food.evidence = food.evidence?.map { var e = $0; e.photoNumber = nil; return e }
            if let index = next.estimate.items.firstIndex(where: { $0.id == food.id }) {
                next.estimate.items[index] = food
            } else { next.estimate.items.append(food) }
        }
        next.lockedItemIDs.formIntersection(Set(next.estimate.items.map(\.id)))
        let detail = clarification.trimmingCharacters(in: .whitespacesAndNewlines)
        if !detail.isEmpty { next.context = context.isEmpty ? detail : context + "\nCorrection: " + detail }
        guard next.isValid else { throw EstimateError.invalidResponse }
        return next
    }
}

struct EstimateImage: Encodable, Sendable {
    let base64: String
    var role: MealPhotoRole = .automatic
    var caption: String = ""
}
struct EstimateRequest: Encodable, Sendable {
    let description: String
    let clarification: String
    let images: [EstimateImage]
    let currentEstimate: MealEstimate?
    let lockedItemIDs: [String]
    let excludedFoods: [String]
}

enum EstimateError: LocalizedError {
    case invalidResponse, invalidEndpoint, notConfigured, rejected(String), imageTooLarge
    var errorDescription: String? {
        switch self {
        case .invalidResponse: return "The service returned an invalid estimate. Your current draft has not changed. Try adding clearer food or portion details."
        case .invalidEndpoint: return "Enter an HTTPS server address without a query, password or fragment. Only a debug iOS Simulator build may use http://localhost."
        case .notConfigured: return "Set up AI in Settings → Photo & text estimates first: use your personal API key or an optional server. Manual food logging still works."
        case .rejected(let message): return message
        case .imageTooLarge: return "This photo could not be prepared. Choose a smaller or clearer image."
        }
    }
}

enum EstimateEndpoint {
    static func validated(_ text: String, allowLocalHTTP: Bool = false) throws -> URL {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let parts = URLComponents(string: clean), let host = parts.host, !host.isEmpty,
              parts.user == nil, parts.password == nil, parts.query == nil, parts.fragment == nil,
              let url = parts.url else { throw EstimateError.invalidEndpoint }
        let local = ["localhost", "127.0.0.1", "[::1]", "::1"].contains(host.lowercased())
        guard parts.scheme?.lowercased() == "https" ||
                (allowLocalHTTP && local && parts.scheme?.lowercased() == "http") else {
            throw EstimateError.invalidEndpoint
        }
        return url
    }
}
