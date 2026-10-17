import Foundation

// Synthetic code-path benchmarks, NOT iOS time-to-first-frame measurements.
@main
struct StartupBenchmark {
    static func main() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("recomp-bench-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = StateFile(url: root.appendingPathComponent("diary.json"))
        let now = Date(timeIntervalSince1970: 1_789_732_800)
        let cal = EntryClock.calendar(in: TimeZone(identifier: "America/Los_Angeles")!)
        var state = AppState()
        for i in 0..<2190 {
            let date = now.addingTimeInterval(-Double(i) * 14_400)
            state.entries.append(FoodEntry(name: "Synthetic meal", date: date, meal: .lunch,
                nutrition: Nutrition(calories: 400, protein: 25, carbs: 45, fat: 13),
                clock: EntryClock(date: date, timeZoneID: "America/Los_Angeles")))
        }
        var sink = 0.0
        func measure(_ name: String, repeats: Int, _ block: () throws -> Void) rethrows {
            var ms: [Double] = []
            for _ in 0..<repeats {
                let start = DispatchTime.now().uptimeNanoseconds
                try block()
                ms.append(Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000)
            }
            ms.sort()
            print("\(name): median \(String(format: "%.3f", ms[ms.count / 2])) ms (\(repeats) runs)")
        }
        try measure("Empty / no file load", repeats: 9) { sink += Double(try file.load().entries.count) }
        try file.save(state)
        try measure("2190 food entries / file load", repeats: 7) { sink += Double(try file.load().entries.count) }
        measure("2190 food entries / one day total", repeats: 21) {
            sink += DiaryMath.localTotal(entries: state.entries, day: now, calendar: cal).calories
        }
        let pixels = Data([0xff, 0xd8]) + Data(repeating: 0x41, count: 1_048_572) + Data([0xff, 0xd9])
        for i in 0..<24 { state.entries[i].photos = [MealPhoto(jpeg: pixels)] }
        try file.save(state)
        let bytes = try FileManager.default.attributesOfItem(atPath: file.url.path)[.size] as! NSNumber
        print("Attachment fixture: \(bytes.intValue) JSON bytes, 24 MiB synthetic framed-byte attachments (not native JPEG decoding)")
        try measure("2190 entries + 24 MiB attachments / file load", repeats: 5) {
            sink += Double(try file.load().entries.count)
        }
        print("Checksum \(sink) (prevents dead-code elimination)")
    }
}
