import Foundation

enum BackupError: LocalizedError {
    case invalid, wrongPasswordOrDamaged, passwordTooShort, tooLarge, nonemptyDiary, differentApp, busy
    var errorDescription: String? {
        switch self {
        case .invalid: return "This backup is invalid or uses an unsupported version. Nothing was restored."
        case .wrongPasswordOrDamaged: return "The password is incorrect or the backup is damaged. Your diary is unchanged."
        case .passwordTooShort: return "Use a backup password of at least 12 characters (at most 256 UTF-8 bytes). Store it safely; there is no password recovery."
        case .tooLarge: return "This backup exceeds the supported size limit. Remove unneeded retained attachments or reports after keeping their originals."
        case .nonemptyDiary: return "Restore is available only in an empty diary. It will not overwrite or merge an existing log. Use an empty installation with the same bundle identifier."
        case .differentApp: return "This backup was made by a different app bundle identifier. Restore using the original identifier so Health sync identities stay consistent."
        case .busy: return "Finish syncing before restoring a backup."
        }
    }
}

struct BackupPayload: Codable, Equatable, Sendable {
    var format = "recomp-backup"
    var version = 1
    var createdAt: Date
    var bundleID: String
    var appearance: String
    var state: AppState
    static let maximumPlainBytes = 160 * 1024 * 1024
    var isValid: Bool {
        format == "recomp-backup" && version == 1 && !bundleID.isEmpty && bundleID.count <= 250 &&
        ["system", "light", "dark"].contains(appearance) && createdAt.timeIntervalSince1970.isFinite && state.isValid
    }
    func encode() throws -> Data {
        guard isValid else { throw BackupError.invalid }
        let data = try JSONEncoder().encode(self)
        guard data.count <= Self.maximumPlainBytes else { throw BackupError.tooLarge }
        return data
    }
    static func decode(_ data: Data) throws -> BackupPayload {
        guard data.count <= maximumPlainBytes else { throw BackupError.tooLarge }
        let payload: BackupPayload
        do { payload = try JSONDecoder().decode(Self.self, from: data) }
        catch { throw BackupError.invalid }
        guard payload.isValid else { throw BackupError.invalid }
        return payload
    }
    func restoredState(over current: AppState, bundleID: String) throws -> AppState {
        guard isValid else { throw BackupError.invalid }
        guard current.canRestoreBackup else { throw BackupError.nonemptyDiary }
        guard self.bundleID == bundleID else { throw BackupError.differentApp }
        var result = state
        // Keep IDs, versions, receipts, tombstones and approved scan selections. DO NOT re-log entries.
        // A restored file must not itself read/write/delete anything in Health.
        result.healthEnabled = false; result.bodyHealthEnabled = false; result.dxaHealthEnabled = false
        result.activityPreferences.enabled = false
        result.widgetPreferences.showNumbers = false
        return result
    }
}

extension AppState {
    var canRestoreBackup: Bool {
        guard deletedRecords.values.allSatisfy(\.isEmpty), removedReviews.isEmpty else { return false }
        guard entries.isEmpty, measurements.isEmpty, dxaScans.isEmpty, dayReviews.isEmpty else { return false }
        guard deletions.isEmpty, bodyDeletions.isEmpty, dxaHealthLinks.isEmpty, contextEvents.isEmpty else { return false }
        guard targetRevisions.isEmpty, maintenanceHistory.isEmpty, healthBodyScaleAssignments.isEmpty else { return false }
        guard ignoredHealthBodyIDs.isEmpty, activityPreferences.hiddenWorkoutIDs.isEmpty else { return false }
        guard targets == .startingTargets, adaptive == AdaptiveSettings() else { return false }
        guard scaleLocations == ScaleLocation.starters, lastScaleLocationID == nil, maintenanceScaleLocationID == nil else { return false }
        let defaults = FoodTemplate.starters
        guard templates.count == defaults.count else { return false }
        for (a, b) in zip(templates, defaults) {
            guard a.name == b.name, a.nutrition == b.nutrition, a.isEstimate == b.isEstimate, a.note == b.note else { return false }
        }
        return true
    }
}
