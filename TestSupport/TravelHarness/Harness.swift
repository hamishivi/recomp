import Foundation
#if canImport(Glibc)
import Glibc
#else
import Darwin
#endif

// Production DiaryStore, real local filesystem, and an explicitly fake Health adapter.
@main struct TravelHarness {
    @MainActor static func main() async throws {
        var checks = 0, failures = 0
        func check(_ ok: @autoclosure () -> Bool, _ label: String) {
            checks += 1
            if ok() { print("PASS: \(label)") } else { failures += 1; print("FAIL: \(label)") }
        }
        let root=FileManager.default.temporaryDirectory.appendingPathComponent("recomp-travel-"+UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let h=HealthKitService(),url=root.appendingPathComponent("diary.json"),store=DiaryStore(fileURL:url,health:h)
        let base=Date().addingTimeInterval(-10*86400),end=base.addingTimeInterval(36*3600)
        var a=FoodEntry(name:"Synthetic Seattle meal",date:base.addingTimeInterval(3600),meal:.dinner,nutrition:Nutrition(calories:1000),clock:EntryClock(date:base.addingTimeInterval(3600),timeZoneID:"America/Los_Angeles"))
        let b=FoodEntry(name:"Synthetic Sydney meal",date:base.addingTimeInterval(30*3600),meal:.lunch,nutrition:Nutrition(calories:1500),clock:EntryClock(date:base.addingTimeInterval(30*3600),timeZoneID:"Australia/Sydney"))
        check(store.saveEntry(a,makeTemplate:false),"explicit departure-zone meal saves")
        check(store.saveEntry(b,makeTemplate:false),"arrival-zone meal saves")
        let captured=store.state.entries[0]
        check(captured.clock?.timeZoneID == "America/Los_Angeles","store does not replace capture timezone with current device zone")
        check(captured.clock?.healthTimeZoneID == "America/Los_Angeles","trusted clock supplies original Health timezone")
        let i=DateInterval(start:base,end:end)
        let preview=await store.previewCoverage(interval:i,includesHealth:false)
        check(preview.total.calories == 2500 && preview.localEntries.count == 2,"36-hour preview includes meals on both local dates")
        check(store.confirmCoverage(preview,timeZoneID:"Australia/Sydney",excluded:false,note:"Synthetic flight",replacingOverlaps:false),"reviewed ended flight interval is saved")
        check(store.state.dayReviews.count == 1 && store.state.dayReviews[0].intakeEvents?.count == 2,"review persists timestamped food evidence")
        check(!store.confirmCoverage(preview,timeZoneID:"America/Vancouver",excluded:false,note:"",replacingOverlaps:false),"duplicate real hours are rejected even under another zone name")
        check(store.state.dayReviews.count == 1 && store.state.entries.count == 2,"failed overlap leaves snapshots and meals unchanged")
        check(store.confirmCoverage(preview,timeZoneID:"America/Vancouver",excluded:false,note:"Replacement",replacingOverlaps:true),"explicit replacement resolves the old overlap")
        check(store.state.dayReviews.count == 1 && store.state.entries.count == 2,"replacement changes coverage only, not food or Health")
        a=store.state.entries.first { $0.id == a.id }!;a.nutrition.calories=1200
        check(store.saveEntry(a,makeTemplate:false),"editing a covered meal saves")
        check(store.state.dayReviews.isEmpty,"food edit invalidates original flight coverage in its own actual interval")
        check(!store.confirmCoverage(preview,timeZoneID:"UTC",excluded:false,note:"",replacingOverlaps:true),"stale preview cannot certify pre-edit food totals")
        let current=await store.previewCoverage(interval:i,includesHealth:false)
        check(store.confirmCoverage(current,timeZoneID:"UTC",excluded:false,note:"",replacingOverlaps:false),"refreshed preview confirms corrected totals")
        check(store.state.dayReviews[0].total.calories == 2700,"corrected snapshot contains new total")
        var moved=store.state.entries.first { $0.id == a.id }!;moved.date=end.addingTimeInterval(3600)
        check(store.saveEntry(moved,makeTemplate:false),"moving a meal recomputes its civil label using its existing clock")
        check(store.state.entries.first { $0.id == a.id }?.clock?.timeZoneID == "America/Los_Angeles","a move preserves the chosen original timezone")
        check(store.state.dayReviews.isEmpty,"move invalidates old coverage")
        let bodyDate=base.addingTimeInterval(60)
        let body=BodyMeasurement(date:bodyDate,metric:.weight,value:85,clock:EntryClock(date:bodyDate,timeZoneID:"Australia/Adelaide"))
        check(store.saveMeasurements([body]),"measurement with half-hour zone saves")
        h.writableBodyMetrics=[.weight];await store.connectBodyHealth()
        check(h.bodySaves.last?.clock?.healthTimeZoneID == "Australia/Adelaide","delayed body sync receives preserved capture timezone")
        let reload=DiaryStore(fileURL:url,health:HealthKitService())
        check(reload.state.entries == store.state.entries && reload.state.measurements == store.state.measurements,"record clocks persist through restart")
        // Explicit range reads, not the current day's cached Health totals.
        await store.connectHealth()
        h.nutritionReads=[HealthNutritionSample(id:UUID(),date:base.addingTimeInterval(31*3600),nutrient:.calories,value:200,sourceName:"Synthetic other app",sourceBundleID:"other",localEntryID:nil)]
        let withHealth=await store.previewCoverage(interval:i,includesHealth:true)
        check(h.intervalReads.last == i,"actual requested Health bounds equal the reviewed flight interval")
        check(withHealth.total.calories == 1700,"multi-day interval includes source food from its second calendar day")
        h.nutritionReadWarnings=["Synthetic partial-read error"]
        let failed=await store.previewCoverage(interval:i,includesHealth:true)
        check(!store.confirmCoverage(failed,timeZoneID:"UTC",excluded:false,note:"",replacingOverlaps:true),"partial Health read blocks completeness confirmation")
        h.nutritionReadWarnings=[]
        h.beforeNutritionRead={_ in store.pauseHealth()}
        let paused=await store.previewCoverage(interval:i,includesHealth:true)
        check(!paused.warnings.isEmpty && !store.confirmCoverage(paused,timeZoneID:"UTC",excluded:false,note:"",replacingOverlaps:true),"pausing during a range read cannot certify a late result")
        let clean=await store.previewCoverage(interval:i,includesHealth:false)
        let before=store.state
        check(!store.confirmCoverage(clean,timeZoneID:"Bad/Zone",excluded:false,note:"",replacingOverlaps:true),"invalid display timezone is rejected")
        check(store.state == before,"invalid confirmation leaves disk-backed state unchanged")
        let future=await store.previewCoverage(interval:DateInterval(start:base,end:Date().addingTimeInterval(60)),includesHealth:false)
        check(!store.confirmCoverage(future,timeZoneID:"UTC",excluded:false,note:"",replacingOverlaps:true),"unfinished or excessively long flight interval is rejected")
        let plain=FoodEntry(name:"New local meal",date:Date().addingTimeInterval(-1),meal:.lunch,nutrition:Nutrition(calories:200))
        check(store.saveEntry(plain,makeTemplate:false),"ordinary new entry still works without manually choosing a zone")
        check(store.state.entries.last?.clock?.isValid(for:plain.date) == true,"ordinary save stamps a valid original civil date")
        // Simulate timezone changes in this isolated Linux/macOS process. This
        // exercises production rollover code, not iOS notification delivery.
        let oldTZ = ProcessInfo.processInfo.environment["TZ"]
        defer { if let oldTZ { setenv("TZ", oldTZ, 1) } else { unsetenv("TZ") }; NSTimeZone.resetSystemTimeZone() }
        setenv("TZ", "America/Los_Angeles", 1); NSTimeZone.resetSystemTimeZone()
        let travelStore = DiaryStore(fileURL: root.appendingPathComponent("travel-selection.json"), health: HealthKitService())
        travelStore.selectDay(Date().addingTimeInterval(-10 * 86400))
        let selectedKey = DayReview.key(travelStore.selectedDay)
        setenv("TZ", "Australia/Sydney", 1); NSTimeZone.resetSystemTimeZone()
        travelStore.checkDayRollover()
        check(DayReview.key(travelStore.selectedDay) == selectedKey, "live zone switch preserves a deliberately selected historical civil date")
        travelStore.selectDay(Date())
        let currentFood = FoodEntry(name: "Synthetic arrival", date: Date().addingTimeInterval(-1), meal: .breakfast,
            nutrition: Nutrition(calories: 100), clock: EntryClock(date: Date().addingTimeInterval(-1), timeZoneID: "Australia/Sydney"))
        check(travelStore.saveEntry(currentFood, makeTemplate: false), "record at arrival retains Sydney date")
        let savedKey = travelStore.state.entries[0].clock!.dayKey
        setenv("TZ", "America/Los_Angeles", 1); NSTimeZone.resetSystemTimeZone()
        travelStore.checkDayRollover()
        check(Calendar.current.isDateInToday(travelStore.selectedDay), "Today follows the new local date after changing zones")
        let historical = EntryClock.displayDate(savedKey)!
        travelStore.selectDay(historical)
        check(DayReview.key(travelStore.selectedDay) == savedKey && travelStore.dayEntries.count == 1, "a date-line future civil label stays accessible without creating a future event")
        check(travelStore.defaultEntryDate() <= Date(), "backfill default never invents an event in the future")
        // No real Health API, network or personal data is involved.
        print("TRAVEL COORDINATOR: \(checks) checks, \(failures) failures. Mock Health adapter; actual store and filesystem.")
        if failures > 0 { exit(1) }
    }
}
