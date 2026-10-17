import Foundation

/// Robust common trend using ONLY pairs from the same physical scale/source.
/// Constant differences between scales cancel in the pairwise differences. The fitted
/// intercepts are nuisance parameters, NOT a calibration or a correction to stored data.
enum ScaleWeightFit {
    struct Result {
        var fit: MaintenanceEngine.Fit
        var daily: [DailyBodyPoint] // Internally aligned to one reference for residual checks.
        var referenceID: String
        var groupSlopes: [Double]
    }
    static func eligible(_ series: [BodyScaleSeries], calendar: Calendar) -> [BodyScaleSeries] {
        series.filter {
            guard $0.points.count >= 3, let first = $0.points.first, let last = $0.points.last else { return false }
            return (calendar.dateComponents([.day], from: first.date, to: last.date).day ?? 0) >= 7
        }
    }
    static func fit(_ points: [ScaleDay], calendar: Calendar) -> Result? {
        guard let origin = points.map(\.date).min() else { return nil }
        let grouped = Dictionary(grouping: points, by: \.seriesID)
        // Collapse duplicate dates even when called outside the normal chart pipeline.
        let groups = grouped.mapValues { rows in
            Dictionary(grouping: rows, by: { calendar.startOfDay(for: $0.date) }).compactMap { date, rows -> DailyBodyPoint? in
                guard let value = BodyMath.median(rows.map(\.value)) else { return nil }
                return DailyBodyPoint(date: date, value: value)
            }.sorted { $0.date < $1.date }
        }.filter { _, rows in
            guard let first = rows.first, let last = rows.last else { return false }
            return rows.count >= 3 && (calendar.dateComponents([.day], from: first.date, to: last.date).day ?? 0) >= 7
        }
        guard !groups.isEmpty else { return nil }
        func x(_ date: Date) -> Double {
            Double(calendar.dateComponents([.day], from: calendar.startOfDay(for: origin), to: date).day ?? 0)
        }
        var slopes: [Double] = []
        var groupSlopes: [Double] = []
        for key in groups.keys.sorted() {
            guard let rows = groups[key] else { continue }
            var local: [Double] = []
            for i in rows.indices {
                for j in rows.indices where j > i {
                    let gap = x(rows[j].date) - x(rows[i].date)
                    if gap >= 7 { local.append((rows[j].value - rows[i].value) / gap) }
                }
            }
            if let m = BodyMath.median(local) { groupSlopes.append(m); slopes += local }
        }
        slopes.sort()
        guard let m = BodyMath.median(slopes), m.isFinite else { return nil }
        var intercepts: [String: Double] = [:]
        for (key, rows) in groups {
            guard let med = BodyMath.median(rows.map { $0.value - m * x($0.date) }) else { return nil }
            intercepts[key] = med
        }
        // Deterministic reference: most recent scale, then most days, then stable ID.
        let referenceCandidates = groups.keys.sorted { a, b in
            let dateA = groups[a]?.last?.date ?? .distantPast
            let dateB = groups[b]?.last?.date ?? .distantPast
            if dateA != dateB { return dateA > dateB }
            let countA = groups[a]?.count ?? 0
            let countB = groups[b]?.count ?? 0
            if countA != countB { return countA > countB }
            return a < b
        }
        guard let reference = referenceCandidates.first,
              let referenceIntercept = intercepts[reference] else { return nil }
        let adjusted: [DailyBodyPoint] = groups.flatMap { key, rows in
            let intc = intercepts[key] ?? referenceIntercept
            return rows.map { DailyBodyPoint(date: $0.date, value: $0.value - intc + referenceIntercept) }
        }
        let daily = Dictionary(grouping: adjusted, by: \.date).compactMap { date, rows -> DailyBodyPoint? in
            guard let med = BodyMath.median(rows.map(\.value)) else { return nil }
            return DailyBodyPoint(date: date, value: med)
        }.sorted { $0.date < $1.date }
        guard let lastDaily = daily.last else { return nil }
        let residual = (BodyMath.median(daily.map { abs($0.value - (m * x($0.date) + referenceIntercept)) }) ?? 0) * 1.4826
        let fit = MaintenanceEngine.Fit(slope: m, lowerSlope: slopes[Int(Double(slopes.count - 1) * 0.25)],
            upperSlope: slopes[Int(Double(slopes.count - 1) * 0.75)], residualSpread: residual,
            lastPrediction: m * x(lastDaily.date) + referenceIntercept)
        return Result(fit: fit, daily: daily, referenceID: reference, groupSlopes: groupSlopes)
    }
}

extension ScaleWeightFit {
    /// Fixed UTC date buckets prevent changing the phone's zone from changing
    /// measurement weighting. Slopes use each bucket's median ACTUAL timestamp.
    static func elapsedSeries(_ points: [BodyPoint], locations: [ScaleLocation]) -> [BodyScaleSeries] {
        Dictionary(grouping: points.filter { $0.metric == .weight && $0.metric.accepts($0.value) && $0.date.timeIntervalSince1970.isFinite }, by: ScaleMath.seriesID)
            .compactMap { key, rows in
                let buckets = Dictionary(grouping: rows, by: { EntryClock.utc.startOfDay(for: $0.date) })
                let daily = buckets.values.compactMap { rows -> DailyBodyPoint? in
                    let local = rows.filter(\.isLocal)
                    let chosen = (local.isEmpty ? rows : local).filter { !$0.excludedFromTrend }
                    guard let value = BodyMath.median(chosen.map(\.value)),
                          let time = BodyMath.median(chosen.map { $0.date.timeIntervalSince1970 }) else { return nil }
                    return DailyBodyPoint(date: Date(timeIntervalSince1970: time), value: value)
                }.sorted { $0.date < $1.date }
                guard daily.count >= 3, let a = daily.first, let b = daily.last,
                      b.date.timeIntervalSince(a.date) >= 7 * CoverageMath.day,
                      let firstRow = rows.first else { return nil }
                return BodyScaleSeries(id: key, label: ScaleMath.seriesLabel(firstRow, locations: locations), points: daily)
            }.sorted { $0.id < $1.id }
    }
    static func fitElapsed(_ points: [ScaleDay]) -> Result? {
        guard let origin = points.map(\.date).min() else { return nil }
        let groups = Dictionary(grouping: points, by: \.seriesID).mapValues { $0.sorted { $0.date < $1.date } }
            .filter { _, rows in
                guard let first = rows.first, let last = rows.last else { return false }
                return rows.count >= 3 && last.date.timeIntervalSince(first.date) >= 7 * CoverageMath.day
            }
        guard !groups.isEmpty else { return nil }
        func x(_ d: Date) -> Double { d.timeIntervalSince(origin) / CoverageMath.day }
        var slopes: [Double] = [], groupSlopes: [Double] = []
        for key in groups.keys.sorted() {
            guard let rows = groups[key] else { continue }
            var local: [Double] = []
            for i in rows.indices {
                for j in rows.indices where j > i {
                    let elapsed = rows[j].date.timeIntervalSince(rows[i].date) / CoverageMath.day
                    if elapsed >= 7 { local.append((rows[j].value - rows[i].value) / elapsed) }
                }
            }
            if let slope = BodyMath.median(local) { groupSlopes.append(slope); slopes += local }
        }
        slopes.sort()
        guard let m = BodyMath.median(slopes), m.isFinite else { return nil }
        var intercepts: [String: Double] = [:]
        for (key, rows) in groups {
            guard let med = BodyMath.median(rows.map { $0.value - m * x($0.date) }) else { return nil }
            intercepts[key] = med
        }
        let referenceCandidates = groups.keys.sorted { a, b in
            let dateA = groups[a]?.last?.date ?? .distantPast
            let dateB = groups[b]?.last?.date ?? .distantPast
            if dateA != dateB { return dateA > dateB }
            let countA = groups[a]?.count ?? 0
            let countB = groups[b]?.count ?? 0
            if countA != countB { return countA > countB }
            return a < b
        }
        guard let reference = referenceCandidates.first,
              let base = intercepts[reference] else { return nil }
        let adjusted: [DailyBodyPoint] = groups.flatMap { key, rows in
            let intc = intercepts[key] ?? base
            return rows.map { DailyBodyPoint(date: $0.date, value: $0.value - intc + base) }
        }
        let daily = Dictionary(grouping: adjusted, by: { EntryClock.utc.startOfDay(for: $0.date) }).values.compactMap { rows -> DailyBodyPoint? in
            guard let time = BodyMath.median(rows.map { $0.date.timeIntervalSince1970 }),
                  let val = BodyMath.median(rows.map(\.value)) else { return nil }
            return DailyBodyPoint(date: Date(timeIntervalSince1970: time), value: val)
        }.sorted { $0.date < $1.date }
        guard let lastDaily = daily.last else { return nil }
        let residual = (BodyMath.median(daily.map { abs($0.value - (m * x($0.date) + base)) }) ?? 0) * 1.4826
        return Result(fit: MaintenanceEngine.Fit(slope: m,
            lowerSlope: slopes[Int(Double(slopes.count - 1) * 0.25)], upperSlope: slopes[Int(Double(slopes.count - 1) * 0.75)],
            residualSpread: residual, lastPrediction: m * x(lastDaily.date) + base),
            daily: daily, referenceID: reference, groupSlopes: groupSlopes)
    }
}
