import Foundation

/// Ephemeral example data. Never inserted into DiaryStore and never sent to HealthKit.
enum AdaptiveDemo: String, CaseIterable, Identifiable {
    case stable, losing, gaining, incomplete, water, waist, scales
    var id: String { rawValue }
    var title: String {
        switch self {
        case .scales: return "Two scales, different baselines"
        case .stable: return "Stable weight"
        case .losing: return "Losing faster than recomp goal"
        case .gaining: return "Gaining above goal"
        case .incomplete: return "Incomplete food history"
        case .water: return "Sudden weight fluctuation"
        case .waist: return "Stable weight, smaller waist"
        }
    }
    func data(now: Date = Date(), calendar: Calendar = .current) -> (state: AppState, points: [BodyPoint]) {
        var state = AppState()
        state.adaptive.guidanceEnabled = true
        let end = calendar.startOfDay(for: now)
        let start = calendar.date(byAdding: .day, value: -28, to: end) ?? end.addingTimeInterval(-28 * 86400)
        for i in 0..<28 {
            guard let day = calendar.date(byAdding: .day, value: i, to: start) else { continue }
            if self != .incomplete || i != 18 {
                state.dayReviews.append(DayReview(dayKey: DayReview.key(day, calendar: calendar), timeZoneID: calendar.timeZone.identifier,
                    confirmedAt: now, total: .startingTargets, estimatedCalorieFraction: 0.2, includedHealth: false))
            }
        }
        var points: [BodyPoint] = []
        for i in 0...28 {
            guard let day = calendar.date(byAdding: .day, value: i, to: start) else { continue }
            var weight = 85.0
            let locationID = self == .scales ? state.scaleLocations[(i / 7) % 2].id : nil
            if self == .scales && (i / 7) % 2 == 1 { weight += 1.5 }
            if self == .losing { weight -= Double(i) * 0.065 }
            if self == .gaining { weight += Double(i) * 0.045 }
            if self == .water && i == 28 { weight += 2.5 }
            points.append(BodyPoint(id: UUID(), date: day, metric: .weight, value: weight, source: "Example",
                                    method: "example scale", isLocal: true, excludedFromTrend: false, scaleLocationID: locationID))
            if self == .waist && [0, 3, 23, 28].contains(i) {
                points.append(BodyPoint(id: UUID(), date: day, metric: .waist, value: i < 7 ? 90 : 89,
                    source: "Example", method: "example tape", isLocal: true, excludedFromTrend: false))
            }
        }
        return (state, points)
    }
}
