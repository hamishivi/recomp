import Foundation

enum StateFileError: LocalizedError {
    case invalidData
    var errorDescription: String? { "The saved diary is invalid or uses a newer format. The original file has not been overwritten." }
}

struct StateFile {
    let url: URL

    var lastModified: Date? {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate]) as? Date
    }

    static var localURL: URL {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        return root.appendingPathComponent("Recomp", isDirectory: true).appendingPathComponent("diary.json")
    }

    static var iCloudDriveURL: URL? {
        let home = URL(fileURLWithPath: NSHomeDirectory())
        let cloudDocs = home.appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs/Recomp", isDirectory: true)
        if FileManager.default.fileExists(atPath: cloudDocs.deletingLastPathComponent().path) {
            return cloudDocs.appendingPathComponent("diary.json")
        }
        if let ubiquity = FileManager.default.url(forUbiquityContainerIdentifier: nil) {
            return ubiquity.appendingPathComponent("Documents/Recomp", isDirectory: true).appendingPathComponent("diary.json")
        }
        return nil
    }

    static func defaultURL() -> URL {
        chooseDefaultURL(preference: UserDefaults.standard.string(forKey: "recomp_storage_mode"),
            local: localURL, cloud: iCloudDriveURL,
            exists: { FileManager.default.fileExists(atPath: $0.path) })
    }
    static func chooseDefaultURL(preference: String?, local: URL, cloud: URL?, exists: (URL) -> Bool) -> URL {
        if preference == "local" { return local }
        if preference == "icloud", let cloud { return cloud }
        // A newly available cloud folder must not hide an existing local diary.
        if exists(local) { return local }
        if let cloud, exists(cloud) { return cloud }
        return local
    }

    func load() throws -> AppState {
        guard FileManager.default.fileExists(atPath: url.path) else { return AppState() }
        let data = try Data(contentsOf: url)
        // Decode the version and state from ONE JSONDecoder parse. Building a
        // second Foundation dictionary duplicated parsing of every base64 photo/PDF.
        let loaded = try JSONDecoder().decode(LoadedDiary.self, from: data)
        let decoded = loaded.state
        guard decoded.isValid else { throw StateFileError.invalidData }
        if loaded.originalVersion < decoded.schemaVersion {
            try save(decoded) // Atomic; failure preserves the original and does not expose an unstable migration.
        }
        return decoded
    }
    private struct LoadedDiary: Decodable {
        let originalVersion: Int
        let state: AppState
        private enum CodingKeys: String, CodingKey { case schemaVersion }
        init(from decoder: Decoder) throws {
            originalVersion = try decoder.container(keyedBy: CodingKeys.self)
                .decode(Int.self, forKey: .schemaVersion)
            state = try AppState(from: decoder)
        }
    }
    func save(_ state: AppState) throws {
        guard state.isValid else { throw StateFileError.invalidData }
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(state)
        #if os(iOS) && !targetEnvironment(macCatalyst)
        if !url.path.contains("Mobile Documents") && !url.path.contains("ubiquity") {
            var dir = directory
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try? dir.setResourceValues(values)
        }
        try data.write(to: url, options: [.atomic, .completeFileProtection])
        #else
        try data.write(to: url, options: [.atomic])
        #endif
    }
}
