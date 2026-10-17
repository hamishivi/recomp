import Foundation

extension AppState {
    func widgetSnapshot(now: Date = Date(), calendar: Calendar = .current) -> WidgetSnapshot {
        let food = DiaryMath.entries(on: now, in: entries, calendar: calendar).filter { $0.date <= now }
        let total = food.reduce(Nutrition.zero) { $0 + $1.nutrition }
        let calProgress = IntakeRingProgress(value: total.calories, target: targets.calories)
        let proProgress = IntakeRingProgress(value: total.protein, target: targets.protein)
        let carbProgress = IntakeRingProgress(value: total.carbs, target: targets.carbs)
        let fatProgress = IntakeRingProgress(value: total.fat, target: targets.fat)
        return WidgetSnapshot(date: now, timeZoneID: calendar.timeZone.identifier,
            caloriesRemaining: widgetPreferences.showNumbers ? targets.calories - total.calories : nil,
            proteinRemaining: widgetPreferences.showNumbers ? targets.protein - total.protein : nil,
            entriesCount: food.count, showsNumbers: widgetPreferences.showNumbers,
            calorieFraction: calProgress.fraction,
            proteinFraction: proProgress.fraction,
            carbsFraction: carbProgress.fraction,
            fatFraction: fatProgress.fraction)
    }
}
