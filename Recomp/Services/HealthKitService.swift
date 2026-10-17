import Foundation
import HealthKit

struct NutritionReadResult {
    var samples: [HealthNutritionSample] = []
    var warnings: [String] = []
}

enum HealthSyncError: LocalizedError {
    case unavailable, permissionNotGranted(String), failed(String)
    var errorDescription: String? {
        switch self {
        case .unavailable: return "Apple Health is not available on this device. You can still use the local diary."
        case .permissionNotGranted(let nutrient): return "Writing \(nutrient.lowercased()) is not allowed. Review permissions in Apple Health."
        case .failed(let message): return message
        }
    }
}

/// Foreground integration only. No server, API keys, background delivery, or Health data upload.
@MainActor
final class HealthKitService {
    private let store = HKHealthStore()
    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }
    var ownBundleID: String { Bundle.main.bundleIdentifier ?? "com.example.recomp" }
    static func type(_ nutrient: Nutrient) -> HKQuantityType {
        let id: HKQuantityTypeIdentifier
        switch nutrient {
        case .calories: id = .dietaryEnergyConsumed
        case .protein: id = .dietaryProtein
        case .carbs: id = .dietaryCarbohydrates
        case .fat: id = .dietaryFatTotal
        }
        return HKObjectType.quantityType(forIdentifier: id)!
    }
    static func unit(_ nutrient: Nutrient) -> HKUnit {
        nutrient == .calories ? .kilocalorie() : .gram()
    }
    var writableNutrients: Set<Nutrient> {
        guard isAvailable else { return [] }
        return Set(Nutrient.allCases.filter { store.authorizationStatus(for: Self.type($0)) == .sharingAuthorized })
    }
    func requestAccess() async throws {
        guard isAvailable else { throw HealthSyncError.unavailable }
        let write = Set<HKSampleType>(Nutrient.allCases.map { Self.type($0) as HKSampleType })
        var read = Set<HKObjectType>(Nutrient.allCases.map { Self.type($0) as HKObjectType })
        read.insert(HKObjectType.quantityType(forIdentifier: .bodyMass)!)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            store.requestAuthorization(toShare: write, read: read) { success, error in
                if let error { continuation.resume(throwing: error) }
                else if success { continuation.resume(returning: ()) }
                else { continuation.resume(throwing: HealthSyncError.failed("The permission request did not complete.")) }
            }
        }
        // Completing this request does NOT prove the user granted read or write access.
    }
    func requestAllAccess() async throws {
        guard isAvailable else { throw HealthSyncError.unavailable }
        let nutrientWrite = Set<HKSampleType>(Nutrient.allCases.map { Self.type($0) as HKSampleType })
        let bodyTypes = BodyMetric.allCases.compactMap { Self.bodyType($0) }
        let bodyWrite = Set<HKSampleType>(bodyTypes.map { $0 as HKSampleType })
        let write = nutrientWrite.union(bodyWrite)

        var read = Set<HKObjectType>(Nutrient.allCases.map { Self.type($0) as HKObjectType })
        for type in bodyTypes { read.insert(type as HKObjectType) }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            store.requestAuthorization(toShare: write, read: read) { success, error in
                if let error { continuation.resume(throwing: error) }
                else if success { continuation.resume(returning: ()) }
                else { continuation.resume(throwing: HealthSyncError.failed("The permission request did not complete.")) }
            }
        }
    }
    func upsert(_ entry: FoodEntry, nutrient: Nutrient) async throws {
        guard writableNutrients.contains(nutrient) else { throw HealthSyncError.permissionNotGranted(nutrient.title) }
        guard entry.nutrition[nutrient] > 0 else {
            // Clearing a value must remove an older nonzero sample, not leave it in Health.
            try await removeMetric(entryID: entry.id, nutrient: nutrient)
            return
        }
        var metadata: [String: Any] = [
            HKMetadataKeySyncIdentifier: SyncIdentity.sampleID(entryID: entry.id, nutrient: nutrient),
            HKMetadataKeySyncVersion: NSNumber(value: entry.version),
            HKMetadataKeyWasUserEntered: true,
            HKMetadataKeyFoodType: entry.name,
            SyncIdentity.entryMetadataKey: entry.id.uuidString,
            SyncIdentity.estimateMetadataKey: entry.isEstimate
        ]
        if let zone = entry.clock?.healthTimeZoneID { metadata[HKMetadataKeyTimeZone] = zone }
        if let clock = entry.clock { metadata["com.recomp.diaryDay"] = clock.dayKey }
        let sample = HKQuantitySample(type: Self.type(nutrient),
                                      quantity: HKQuantity(unit: Self.unit(nutrient), doubleValue: entry.nutrition[nutrient]),
                                      start: entry.date, end: entry.date, metadata: metadata)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            store.save(sample) { success, error in
                if let error { continuation.resume(throwing: error) }
                else if success { continuation.resume(returning: ()) }
                else { continuation.resume(throwing: HealthSyncError.failed("Apple Health did not confirm the save.")) }
            }
        }
    }
    func removeMetric(entryID: UUID, nutrient: Nutrient) async throws {
        guard writableNutrients.contains(nutrient) else { throw HealthSyncError.permissionNotGranted(nutrient.title) }
        let identifier = SyncIdentity.sampleID(entryID: entryID, nutrient: nutrient)
        let idPredicate = HKQuery.predicateForObjects(withMetadataKey: HKMetadataKeySyncIdentifier, allowedValues: [identifier])
        let sourcePredicate = HKQuery.predicateForObjects(from: HKSource.default())
        let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [idPredicate, sourcePredicate])
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            // Deletes only this app's sample for this meal and nutrient. Safe to retry.
            store.deleteObjects(of: Self.type(nutrient), predicate: predicate) { success, _, error in
                if let error { continuation.resume(throwing: error) }
                else if success { continuation.resume(returning: ()) }
                else { continuation.resume(throwing: HealthSyncError.failed("Apple Health did not confirm the deletion.")) }
            }
        }
    }
    func readNutrition(day: Date) async -> NutritionReadResult {
        let local = DiaryMath.dayInterval(containing: day)
        // Source timezone metadata can put an event on this civil date even when
        // its instant is outside the viewer's midnight boundaries. Filter on readout.
        return await readNutrition(interval: DateInterval(start: local.start.addingTimeInterval(-36 * 3600), end: local.end.addingTimeInterval(36 * 3600)))
    }
    func readNutrition(interval: DateInterval) async -> NutritionReadResult {
        guard isAvailable else { return NutritionReadResult(warnings: [HealthSyncError.unavailable.localizedDescription]) }
        var result = NutritionReadResult()
        for nutrient in Nutrient.allCases {
            do {
                let samples = try await query(Self.type(nutrient), from: interval.start, to: interval.end)
                result.samples += samples.compactMap { sample in
                    guard sample.startDate >= interval.start, sample.startDate < interval.end else { return nil }
                    let value = sample.quantity.doubleValue(for: Self.unit(nutrient))
                    guard value.isFinite, value >= 0 else { return nil }
                    let rawID = sample.metadata?[SyncIdentity.entryMetadataKey] as? String
                    return HealthNutritionSample(id: sample.uuid, date: sample.startDate, nutrient: nutrient, value: value,
                                                 sourceName: sample.sourceRevision.source.name,
                                                 sourceBundleID: sample.sourceRevision.source.bundleIdentifier,
                                                 localEntryID: rawID.flatMap { UUID(uuidString: $0) },
                                                 clock: (sample.metadata?[HKMetadataKeyTimeZone] as? String).flatMap { EntryClock(date: sample.startDate, timeZoneID: $0, provenance: .healthMetadata) })
                }
            } catch {
                result.warnings.append("\(nutrient.title): \(error.localizedDescription)")
            }
        }
        return result
    }
    func readWeights(now: Date = Date()) async throws -> [WeightReading] {
        guard isAvailable else { throw HealthSyncError.unavailable }
        let start = Calendar.current.date(byAdding: .day, value: -60, to: now) ?? now.addingTimeInterval(-60 * 86400)
        let samples = try await query(HKObjectType.quantityType(forIdentifier: .bodyMass)!, from: start, to: now)
        return samples.compactMap { sample in
            guard !isDXASample(sample) else { return nil }
            let kg = sample.quantity.doubleValue(for: .gramUnit(with: .kilo))
            guard kg.isFinite, kg > 0 else { return nil }
            return WeightReading(id: sample.uuid, date: sample.startDate, kilograms: kg)
        }
    }
    static func bodyType(_ metric: BodyMetric) -> HKQuantityType? {
        let identifier: HKQuantityTypeIdentifier
        switch metric {
        case .weight: identifier = .bodyMass
        case .bodyFat: identifier = .bodyFatPercentage
        case .waist: identifier = .waistCircumference
        default: return nil
        }
        return HKObjectType.quantityType(forIdentifier: identifier)
    }
    static func bodyUnit(_ metric: BodyMetric) -> HKUnit {
        switch metric {
        case .weight: return .gramUnit(with: .kilo)
        case .bodyFat: return .percent()
        default: return .meterUnit(with: .centi)
        }
    }
    var writableBodyMetrics: Set<BodyMetric> {
        guard isAvailable else { return [] }
        return Set(BodyMetric.allCases.filter {
            guard let type = Self.bodyType($0) else { return false }
            return store.authorizationStatus(for: type) == .sharingAuthorized
        })
    }
    func requestBodyAccess() async throws {
        guard isAvailable else { throw HealthSyncError.unavailable }
        let types = BodyMetric.allCases.compactMap { Self.bodyType($0) }
        let write = Set<HKSampleType>(types.map { $0 as HKSampleType })
        let read = Set<HKObjectType>(types.map { $0 as HKObjectType })
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
            store.requestAuthorization(toShare: write, read: read) { success, error in
                if let error { c.resume(throwing: error) }
                else if success { c.resume(returning: ()) }
                else { c.resume(throwing: HealthSyncError.failed("The measurement permission request did not complete.")) }
            }
        }
    }
    func upsertBody(_ record: BodyMeasurement) async throws {
        guard let type = Self.bodyType(record.metric), writableBodyMetrics.contains(record.metric) else {
            throw HealthSyncError.permissionNotGranted(record.metric.title)
        }
        var metadata: [String: Any] = [
            HKMetadataKeySyncIdentifier: BodyMath.syncID(id: record.id, metric: record.metric),
            HKMetadataKeySyncVersion: NSNumber(value: record.version),
            HKMetadataKeyWasUserEntered: true,
            BodyMath.metadataKey: record.id.uuidString
        ]
        if let zone = record.clock?.healthTimeZoneID { metadata[HKMetadataKeyTimeZone] = zone }
        if let clock = record.clock { metadata["com.recomp.diaryDay"] = clock.dayKey }
        let quantity = HKQuantity(unit: Self.bodyUnit(record.metric), doubleValue: BodyMath.healthValue(record.value, metric: record.metric))
        let sample = HKQuantitySample(type: type, quantity: quantity, start: record.date, end: record.date, metadata: metadata)
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
            store.save(sample) { success, error in
                if let error { c.resume(throwing: error) }
                else if success { c.resume(returning: ()) }
                else { c.resume(throwing: HealthSyncError.failed("Apple Health did not confirm the measurement save.")) }
            }
        }
    }
    func removeBody(_ deletion: BodyDeletion) async throws {
        guard let type = Self.bodyType(deletion.metric), writableBodyMetrics.contains(deletion.metric) else {
            throw HealthSyncError.permissionNotGranted(deletion.metric.title)
        }
        let identifier = BodyMath.syncID(id: deletion.id, metric: deletion.metric)
        let id = HKQuery.predicateForObjects(withMetadataKey: HKMetadataKeySyncIdentifier, allowedValues: [identifier])
        let own = HKQuery.predicateForObjects(from: HKSource.default())
        let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [id, own])
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
            store.deleteObjects(of: type, predicate: predicate) { success, _, error in
                if let error { c.resume(throwing: error) }
                else if success { c.resume(returning: ()) }
                else { c.resume(throwing: HealthSyncError.failed("Apple Health did not confirm the measurement deletion.")) }
            }
        }
    }
    func readBody(includeComposition: Bool, now: Date = Date()) async -> (samples: [HealthBodySample], warnings: [String]) {
        guard isAvailable else { return ([], [HealthSyncError.unavailable.localizedDescription]) }
        let from = Calendar.current.date(byAdding: .day, value: -180, to: now) ?? now.addingTimeInterval(-180 * 86400)
        let metrics: [BodyMetric] = includeComposition ? [.weight, .bodyFat, .waist] : [.weight]
        var result: [HealthBodySample] = []
        var warnings: [String] = []
        for metric in metrics {
            guard let type = Self.bodyType(metric) else { continue }
            do {
                let samples = try await query(type, from: from, to: now)
                result += samples.compactMap { sample in
                    let value = BodyMath.fromHealth(sample.quantity.doubleValue(for: Self.bodyUnit(metric)), metric: metric)
                    guard metric.accepts(value), sample.startDate >= from, sample.startDate <= now else { return nil }
                    let localID = sample.metadata?[BodyMath.metadataKey] as? String
                    return HealthBodySample(id: sample.uuid, date: sample.startDate, metric: metric, value: value,
                        sourceName: sample.sourceRevision.source.name, sourceBundleID: sample.sourceRevision.source.bundleIdentifier,
                        localMeasurementID: localID.flatMap { UUID(uuidString: $0) }, clock: (sample.metadata?[HKMetadataKeyTimeZone] as? String).flatMap { EntryClock(date: sample.startDate, timeZoneID: $0, provenance: .healthMetadata) },
                        isRecompDXA: isDXASample(sample))
                }
            } catch { warnings.append("\(metric.title): \(error.localizedDescription)") }
        }
        return (result, warnings)
    }
    private func isDXASample(_ sample: HKQuantitySample) -> Bool {
        DXAHealthIdentity.isOwnScanExport(source: sample.sourceRevision.source.bundleIdentifier,
            ownBundleID: ownBundleID, scanID: sample.metadata?[DXAHealthIdentity.scanMetadataKey] as? String,
            syncID: sample.metadata?[HKMetadataKeySyncIdentifier] as? String)
    }
    static func dxaType(_ metric: DXAHealthMetric) -> HKQuantityType {
        let identifier: HKQuantityTypeIdentifier
        switch metric {
        case .weight: identifier = .bodyMass
        case .bodyFat: identifier = .bodyFatPercentage
        case .leanBodyMass: identifier = .leanBodyMass
        }
        return HKObjectType.quantityType(forIdentifier: identifier)!
    }
    static func dxaUnit(_ metric: DXAHealthMetric) -> HKUnit {
        metric == .bodyFat ? .percent() : .gramUnit(with: .kilo)
    }
    var writableDXAMetrics: Set<DXAHealthMetric> {
        guard isAvailable else { return [] }
        return Set(DXAHealthMetric.allCases.filter { store.authorizationStatus(for: Self.dxaType($0)) == .sharingAuthorized })
    }
    func requestDXAAccess() async throws {
        guard isAvailable else { throw HealthSyncError.unavailable }
        let write = Set<HKSampleType>(DXAHealthMetric.allCases.map { Self.dxaType($0) as HKSampleType })
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
            // Export only: do not ask for unrelated read permissions or claim a full report can be recovered.
            store.requestAuthorization(toShare: write, read: []) { success, error in
                if let error { c.resume(throwing: error) }
                else if success { c.resume(returning: ()) }
                else { c.resume(throwing: HealthSyncError.failed("The DEXA permission request did not complete.")) }
            }
        }
    }
    func upsertDXA(scanID: UUID, scanDay: String, link: DXAHealthLink, candidate: DXAHealthCandidate) async throws {
        guard writableDXAMetrics.contains(candidate.metric) else { throw HealthSyncError.permissionNotGranted(candidate.metric.title) }
        guard link.isValid, link.id == scanID, link.selectedMetrics.contains(candidate.metric), candidate.value.isFinite,
              candidate.value >= 0, link.date <= Date(), DXAHealthTime.day(link.date, timeZoneID: link.timeZoneID) == scanDay else {
            throw HealthSyncError.failed("The reviewed DEXA export is invalid. Check its time and values.")
        }
        let metadata: [String: Any] = [
            HKMetadataKeySyncIdentifier: DXAHealthIdentity.sampleID(scanID: scanID, metric: candidate.metric),
            HKMetadataKeySyncVersion: NSNumber(value: link.version),
            HKMetadataKeyWasUserEntered: true,
            HKMetadataKeyTimeZone: link.timeZoneID,
            DXAHealthIdentity.scanMetadataKey: scanID.uuidString,
            DXAHealthIdentity.methodMetadataKey: "DXA",
            DXAHealthIdentity.basisMetadataKey: candidate.basis.rawValue,
            DXAHealthIdentity.dayMetadataKey: scanDay,
            DXAHealthIdentity.approximateTimeMetadataKey: link.timeIsApproximate
        ]
        // No PDF, clinic name, scanner serial, source excerpts or notes are exported.
        let sample = HKQuantitySample(type: Self.dxaType(candidate.metric),
            quantity: HKQuantity(unit: Self.dxaUnit(candidate.metric), doubleValue: candidate.metric.healthValue(candidate.value)),
            start: link.date, end: link.date, metadata: metadata)
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
            store.save(sample) { success, error in
                if let error { c.resume(throwing: error) }
                else if success { c.resume(returning: ()) }
                else { c.resume(throwing: HealthSyncError.failed("Apple Health did not confirm the DEXA save.")) }
            }
        }
    }
    func removeDXA(scanID: UUID, metric: DXAHealthMetric) async throws {
        guard writableDXAMetrics.contains(metric) else { throw HealthSyncError.permissionNotGranted(metric.title) }
        let identifier = HKQuery.predicateForObjects(withMetadataKey: HKMetadataKeySyncIdentifier,
            allowedValues: [DXAHealthIdentity.sampleID(scanID: scanID, metric: metric)])
        let source = HKQuery.predicateForObjects(from: HKSource.default())
        let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [identifier, source])
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
            store.deleteObjects(of: Self.dxaType(metric), predicate: predicate) { success, _, error in
                if let error { c.resume(throwing: error) }
                else if success { c.resume(returning: ()) }
                else { c.resume(throwing: HealthSyncError.failed("Apple Health did not confirm the DEXA removal.")) }
            }
        }
    }
    private func query(_ type: HKQuantityType, from: Date, to: Date) async throws -> [HKQuantitySample] {
        let predicate = HKQuery.predicateForSamples(withStart: from, end: to, options: .strictStartDate)
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit,
                                      sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]) { _, samples, error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume(returning: (samples as? [HKQuantitySample]) ?? []) }
            }
            store.execute(query)
        }
    }
}
