import Foundation

struct WidgetPreferences: Codable, Equatable, Sendable {
    var showNumbers = false
}

/// Shared with the extension. Never includes Health imports, photos, body data or meal names.
struct WidgetSnapshot: Codable, Equatable, Sendable {
    var schema = 1
    var date: Date
    var timeZoneID: String
    var caloriesRemaining: Double?
    var proteinRemaining: Double?
    var entriesCount: Int
    var showsNumbers: Bool
    var calorieFraction: Double? = nil
    var proteinFraction: Double? = nil
    var carbsFraction: Double? = nil
    var fatFraction: Double? = nil

    init(schema: Int = 1, date: Date, timeZoneID: String,
         caloriesRemaining: Double?, proteinRemaining: Double?,
         entriesCount: Int, showsNumbers: Bool,
         calorieFraction: Double? = nil, proteinFraction: Double? = nil,
         carbsFraction: Double? = nil, fatFraction: Double? = nil) {
        self.schema = schema
        self.date = date
        self.timeZoneID = timeZoneID
        self.caloriesRemaining = caloriesRemaining
        self.proteinRemaining = proteinRemaining
        self.entriesCount = entriesCount
        self.showsNumbers = showsNumbers
        self.calorieFraction = calorieFraction
        self.proteinFraction = proteinFraction
        self.carbsFraction = carbsFraction
        self.fatFraction = fatFraction
    }

    static let kind = "RecompReadout"
    static let filename = "recomp-widget.json"
    /// Ignore only the publish timestamp when the visible values, civil date and
    /// zone are unchanged. A stale/future/other-zone snapshot always needs a write.
    func hasSameReadout(as other: WidgetSnapshot, now: Date, calendar: Calendar = .current) -> Bool {
        isCurrent(now: now, calendar: calendar) && other.isCurrent(now: now, calendar: calendar) &&
            schema == other.schema && timeZoneID == other.timeZoneID &&
            caloriesRemaining == other.caloriesRemaining && proteinRemaining == other.proteinRemaining &&
            calorieFraction == other.calorieFraction && proteinFraction == other.proteinFraction &&
            carbsFraction == other.carbsFraction && fatFraction == other.fatFraction &&
            entriesCount == other.entriesCount && showsNumbers == other.showsNumbers
    }
    func isCurrent(now: Date, calendar: Calendar = .current) -> Bool {
        schema == 1 && timeZoneID == calendar.timeZone.identifier && calendar.isDate(date, inSameDayAs: now) && date <= now.addingTimeInterval(60)
    }
}
