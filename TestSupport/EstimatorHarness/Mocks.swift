import Foundation
// Explicit test doubles; no real UI, network or permission checks.
protocol ObservableObject: AnyObject {}
@propertyWrapper struct Published<Value> { var wrappedValue: Value }
@MainActor enum EstimationService {
    static var received: EstimateRequest?
    static var response = MealEstimate(title: "Synthetic meal", items: [EstimatedFood(id: "food", name: "Synthetic", portion: "1 serving", nutrition: Nutrition(calories: 200, protein: 20, carbs: 15, fat: 7))])
    static var fail = false
    static func estimate(_ input: EstimateRequest, configuration: EstimatorConfiguration) async throws -> MealEstimate {
        received = input
        await Task.yield()
        if fail { throw EstimateError.invalidResponse }
        return response
    }
}
