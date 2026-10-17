import Foundation
import HealthKit

/// Read-only Health bridge. Strava and Strong remain the recording apps. No workout writes or route access.
@MainActor
final class ActivityHealthService {
    private let store = HKHealthStore()
    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }
    func requestAccess() async throws {
        guard isAvailable else { throw HealthSyncError.unavailable }
        let read: Set<HKObjectType> = [HKObjectType.workoutType(), HKObjectType.quantityType(forIdentifier: .stepCount)!,
                                      HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!]
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
            store.requestAuthorization(toShare: [], read: read) { success, error in
                if let error { c.resume(throwing: error) }
                else if success { c.resume(returning: ()) }
                else { c.resume(throwing: HealthSyncError.failed("The activity permission request did not finish.")) }
            }
        }
    }
    func read(now: Date = Date()) async -> ActivityReadout {
        guard isAvailable else { return ActivityReadout(warnings: [HealthSyncError.unavailable.localizedDescription]) }
        let from = Calendar.current.date(byAdding: .day, value: -30, to: Calendar.current.startOfDay(for: now)) ?? now.addingTimeInterval(-30 * 86400)
        var result = ActivityReadout()
        do {
            let samples = try await samples(HKObjectType.workoutType(), from: from, to: now, limit: 5001)
            if samples.count > 5000 { result.warnings.append("Workout history exceeded the 5,000-record limit; only the most recent records are shown.") }
            result.workouts = samples.prefix(5000).compactMap { value in
                guard let w = value as? HKWorkout, w.startDate >= from, w.startDate <= now else { return nil }
                let kind = Self.activity(w.workoutActivityType)
                let record = WorkoutRecord(id: w.uuid, start: w.startDate, end: min(w.endDate, now), duration: w.duration,
                    kind: kind.0, title: kind.1, distanceMetres: w.totalDistance?.doubleValue(for: .meter()),
                    source: ActivitySource(id: w.sourceRevision.source.bundleIdentifier, name: w.sourceRevision.source.name))
                return record.isValid ? record : nil
            }
        } catch { result.warnings.append("Workouts: \(error.localizedDescription)") }
        do {
            result.stepIntervals = try await readStepIntervals(from: from, to: now)
            result.steps = Dictionary(grouping: result.stepIntervals, by: { Calendar.current.startOfDay(for: $0.start) })
                .map { StepDay(date: $0.key, count: $0.value.reduce(0) { $0 + $1.count }) }.sorted { $0.date < $1.date }
        }
        catch { result.warnings.append("Steps: \(error.localizedDescription)") }
        do {
            let type = HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!
            let values = try await samples(type, from: from.addingTimeInterval(-86400), to: now, limit: 50001)
            if values.count > 50000 { result.warnings.append("Sleep history exceeded the 50,000-sample limit; older intervals may be missing.") }
            let asleep: Set<Int> = [HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
                HKCategoryValueSleepAnalysis.asleepCore.rawValue, HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
                HKCategoryValueSleepAnalysis.asleepREM.rawValue]
            result.sleep = values.prefix(50000).compactMap { sample in
                guard let s = sample as? HKCategorySample, asleep.contains(s.value), s.endDate > s.startDate,
                      s.startDate < now else { return nil }
                return SleepInterval(start: s.startDate, end: min(s.endDate, now),
                    source: ActivitySource(id: s.sourceRevision.source.bundleIdentifier, name: s.sourceRevision.source.name))
            }
        } catch { result.warnings.append("Sleep: \(error.localizedDescription)") }
        result.refreshedAt = now
        return result
    }
    private static func activity(_ type: HKWorkoutActivityType) -> (String, String) {
        switch type {
        case .running: return ("running", "Run")
        case .walking: return ("walking", "Walk")
        case .cycling: return ("cycling", "Ride")
        case .traditionalStrengthTraining, .functionalStrengthTraining: return ("strength", "Strength training")
        case .hiking: return ("hiking", "Hike")
        case .swimming: return ("swimming", "Swim")
        case .yoga: return ("yoga", "Yoga")
        default: return ("activity-\(type.rawValue)", "Workout")
        }
    }
    private func samples(_ type: HKSampleType, from: Date, to: Date, limit: Int) async throws -> [HKSample] {
        let predicate = HKQuery.predicateForSamples(withStart: from, end: to, options: [])
        return try await withCheckedThrowingContinuation { c in
            let q = HKSampleQuery(sampleType: type, predicate: predicate, limit: limit,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)]) { _, samples, error in
                if let error { c.resume(throwing: error) } else { c.resume(returning: samples ?? []) }
            }
            store.execute(q)
        }
    }
    private func readStepIntervals(from: Date, to: Date) async throws -> [StepInterval] {
        let type = HKObjectType.quantityType(forIdentifier: .stepCount)!
        let predicate = HKQuery.predicateForSamples(withStart: from, end: to, options: [])
        return try await withCheckedThrowingContinuation { c in
            let q = HKStatisticsCollectionQuery(quantityType: type, quantitySamplePredicate: predicate, options: .cumulativeSum,
                anchorDate: from, intervalComponents: DateComponents(hour: 1))
            q.initialResultsHandler = { _, collection, error in
                if let error { c.resume(throwing: error); return }
                var rows: [StepInterval] = []
                collection?.enumerateStatistics(from: from, to: to) { statistic, _ in
                    if let count = statistic.sumQuantity()?.doubleValue(for: .count()) {
                        let row = StepInterval(start: statistic.startDate, end: min(statistic.endDate, to), count: count)
                        if row.isValid { rows.append(row) }
                    }
                }
                c.resume(returning: rows)
            }
            // HealthKit's merged statistics—not naive addition of phone/watch samples.
            store.execute(q)
        }
    }
}
