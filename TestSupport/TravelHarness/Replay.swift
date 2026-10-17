import Foundation
@main struct ClockReplay {
    static func main() throws {
        let args=CommandLine.arguments
        let url=URL(fileURLWithPath:args[2]),when=ISO8601DateFormatter().date(from:"2026-09-18T03:00:00Z")!
        if args[1] == "create" {
            var state=AppState();state.entries=[FoodEntry(name:"Synthetic legacy dinner",date:when,meal:.dinner,nutrition:Nutrition(calories:500))]
            var raw=try JSONSerialization.jsonObject(with:JSONEncoder().encode(state)) as! [String:Any];raw["schemaVersion"]=6
            try JSONSerialization.data(withJSONObject:raw).write(to:url)
        }
        let state=try StateFile(url:url).load(),clock=state.entries[0].clock!
        guard clock.timeZoneID == "America/Los_Angeles", clock.dayKey == "2026-09-17", clock.needsReview else { fatalError("Migration rebucketed legacy dinner") }
        let viewer=EntryClock.displayDate("2026-09-17")!
        guard DiaryMath.localTotal(entries:state.entries,day:viewer).calories == 500 else { fatalError("Dinner moved between days") }
        print("PASS: restart in \(TimeZone.current.identifier) retains assumed \(clock.timeZoneID) / \(clock.dayKey), 500 kcal")
    }
}
