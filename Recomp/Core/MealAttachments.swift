import Foundation

enum MealPhotoRole: String, CaseIterable, Codable, Identifiable, Sendable {
    case automatic, plate, nutritionLabel, packaging, menu, leftovers
    var id: String { rawValue }
    var title: String {
        switch self {
        case .automatic: return "Auto"
        case .plate: return "Food / plate"
        case .nutritionLabel: return "Nutrition label"
        case .packaging: return "Packaging"
        case .menu: return "Menu / receipt"
        case .leftovers: return "Leftovers"
        }
    }
}

/// Only re-rendered JPEGs belong here. No original filenames, EXIF, GPS or asset IDs.
struct MealPhoto: Identifiable, Codable, Equatable, Sendable {
    var id = UUID()
    var jpeg: Data
    var role: MealPhotoRole = .automatic
    var caption = ""
    static let maximumCount = 6
    static let maximumBytes = 1_500_000
    var isValid: Bool {
        !jpeg.isEmpty && jpeg.count <= Self.maximumBytes &&
        jpeg.starts(with: [0xff, 0xd8]) && jpeg.suffix(2) == Data([0xff, 0xd9]) && caption.count <= 240
    }
}

struct FoodEvidence: Codable, Equatable, Sendable {
    enum Kind: String, Codable, Sendable { case label, visual, details, assumption }
    var kind: Kind
    var photoNumber: Int? // 1-based within the submitted/reviewed photo set, never a remote URL.
    var detail: String
    var isValid: Bool {
        !detail.isEmpty && detail.count <= 400 && (photoNumber == nil || (1...MealPhoto.maximumCount).contains(photoNumber!))
    }
}

enum MealEntryMode: String, Sendable { case log, check }

/// Pure arithmetic. Calling this cannot log food, confirm a day, change targets or queue Health writes.
struct FoodCheckProjection: Equatable, Sendable {
    var current: Nutrition
    var candidate: Nutrition
    var targets: Nutrition
    var projected: Nutrition { current + candidate }
    var remaining: Nutrition { targets - projected }
}

extension AppState {
    var photoAttachmentsAreValid: Bool {
        let photos = entries.flatMap { $0.photos ?? [] }
        return photos.reduce(0) { $0 + $1.jpeg.count } <= 48 * 1024 * 1024
    }
}

/// Only the active photo-picker batch may commit or clear the loading state.
/// No image data or platform API is retained here.
struct PhotoImportSession: Equatable {
    private(set) var ticket: UUID?
    var isActive: Bool { ticket != nil }
    mutating func begin() -> UUID { let next = UUID(); ticket = next; return next }
    func accepts(_ value: UUID) -> Bool { ticket == value }
    @discardableResult mutating func finish(_ value: UUID) -> Bool {
        guard accepts(value) else { return false }; ticket = nil; return true
    }
    mutating func cancel() { ticket = nil }
}
