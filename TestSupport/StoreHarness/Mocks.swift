import Foundation

// Only for a portable coordinator check. These do NOT emulate Apple permissions or UI.
protocol ObservableObject: AnyObject {}
@propertyWrapper struct Published<Value> { var wrappedValue: Value }
struct NutritionReadResult { var samples: [HealthNutritionSample] = []; var warnings: [String] = [] }
@MainActor final class HealthKitService {
    var ownBundleID = "com.example.recomp"
    var writableNutrients: Set<Nutrient> = []
    var writableBodyMetrics: Set<BodyMetric> = []
    var writableDXAMetrics: Set<DXAHealthMetric> = []
    var dxaSaves: [(id: UUID, day: String, link: DXAHealthLink, candidate: DXAHealthCandidate)] = []
    var dxaRemovals: [(id: UUID, metric: DXAHealthMetric)] = []
    var beforeDXASave: ((UUID, DXAHealthMetric) async -> Void)?
    var failDXAWrites = false
    var failDXARemovals = false
    var failDXAAccess = false
    var isAvailable = true
    var foodSaves: [UUID] = []
    var foodRemovals: [UUID] = []
    var bodyReads: [HealthBodySample] = []
    var bodySaves: [BodyMeasurement] = []
    var bodyRemovals: [BodyDeletion] = []
    var beforeSave: ((BodyMeasurement) async -> Void)?
    var failBodyWrites = false
    var intervalReads: [DateInterval] = []
    var nutritionReadWarnings: [String] = []
    var nutritionReads: [HealthNutritionSample] = []
    var beforeNutritionRead: ((Date) async -> Void)?
    var beforeBodyRead: (() async -> Void)?
    func requestDXAAccess() async throws { if failDXAAccess { throw CocoaError(.userCancelled) } }
    func upsertDXA(scanID: UUID, scanDay: String, link: DXAHealthLink, candidate: DXAHealthCandidate) async throws {
        if failDXAWrites { throw CocoaError(.fileWriteUnknown) }
        if let callback = beforeDXASave { beforeDXASave = nil; await callback(scanID, candidate.metric) }
        dxaSaves.append((scanID, scanDay, link, candidate))
    }
    func removeDXA(scanID: UUID, metric: DXAHealthMetric) async throws {
        if failDXARemovals { throw CocoaError(.fileWriteUnknown) }
        dxaRemovals.append((scanID, metric))
    }
    func requestAccess() async throws {}
    func requestBodyAccess() async throws {}
    func requestAllAccess() async throws {}
    func readNutrition(interval: DateInterval) async -> NutritionReadResult {
        intervalReads.append(interval)
        if let callback = beforeNutritionRead { beforeNutritionRead = nil; await callback(interval.start) }
        return NutritionReadResult(samples: nutritionReads.filter { CoverageMath.contains(interval, $0.date) }, warnings: nutritionReadWarnings)
    }
    func readNutrition(day: Date) async -> NutritionReadResult {
        if let callback = beforeNutritionRead { beforeNutritionRead = nil; await callback(day) }
        return NutritionReadResult(samples: nutritionReads.filter { Calendar.current.isDate($0.date, inSameDayAs: day) })
    }
    func readBody(includeComposition: Bool) async -> (samples: [HealthBodySample], warnings: [String]) {
        if let callback = beforeBodyRead { beforeBodyRead = nil; await callback() }
        return (bodyReads, [])
    }
    func removeMetric(entryID: UUID, nutrient: Nutrient) async throws { foodRemovals.append(entryID) }
    func upsert(_ entry: FoodEntry, nutrient: Nutrient) async throws { foodSaves.append(entry.id) }
    func removeBody(_ deletion: BodyDeletion) async throws { bodyRemovals.append(deletion) }
    func upsertBody(_ body: BodyMeasurement) async throws {
        if failBodyWrites { throw CocoaError(.fileWriteUnknown) }
        if let callback = beforeSave { beforeSave = nil; await callback(body) }
        bodySaves.append(body)
    }
}
