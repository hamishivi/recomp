import Foundation
// Controllable fake provider, deliberately no network call or platform framework.
@MainActor enum EstimationService {
    static var received: EstimateRequest?
    static var response = MealEstimate(title: "Synthetic meal", items: [EstimatedFood(id: "food", name: "Synthetic", portion: "1 serving", nutrition: Nutrition(calories: 200, protein: 20, carbs: 15, fat: 7))])
    static var fail = false
    static var held = false
    static var waiting: CheckedContinuation<Void, Never>?
    static func estimate(_ input: EstimateRequest, configuration: EstimatorConfiguration) async throws -> MealEstimate {
        received = input
        if held { await withCheckedContinuation { waiting = $0 } } else { await Task.yield() }
        if fail { throw EstimateError.invalidResponse }
        return response
    }
    static func release() { held = false; let continuation = waiting; waiting = nil; continuation?.resume() }
}
