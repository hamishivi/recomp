import SwiftUI
import Charts

enum TrendRange: String, CaseIterable, Identifiable {
    case oneWeek = "1W"
    case oneMonth = "1M"
    case threeMonths = "3M"
    case oneYear = "1Y"
    case allTime = "All"

    var id: String { rawValue }

    var shortTitle: String { rawValue }

    var title: String {
        switch self {
        case .oneWeek: return "1 week"
        case .oneMonth: return "1 month"
        case .threeMonths: return "3 months"
        case .oneYear: return "1 year"
        case .allTime: return "All time"
        }
    }

    func startDate(relativeTo today: Date, earliestDate: Date?) -> Date {
        let calendar = Calendar.current
        switch self {
        case .oneWeek:
            return calendar.date(byAdding: .day, value: -6, to: today) ?? today
        case .oneMonth:
            return calendar.date(byAdding: .day, value: -29, to: today) ?? today
        case .threeMonths:
            return calendar.date(byAdding: .day, value: -89, to: today) ?? today
        case .oneYear:
            return calendar.date(byAdding: .day, value: -364, to: today) ?? today
        case .allTime:
            return earliestDate ?? (calendar.date(byAdding: .day, value: -364, to: today) ?? today)
        }
    }
}

private struct LoggedDay: Identifiable {
    var date: Date
    var nutrition: Nutrition
    var entryCount: Int
    var id: Date { date }
}

@MainActor
struct ProgressScreen: View {
    @EnvironmentObject private var diary: DiaryStore
    @State private var range: TrendRange = .oneWeek
    @State private var scaleFilter: ScaleFilter = .all

    private var days: [LoggedDay] {
        let calendar = Calendar.current
        let today = max(calendar.startOfDay(for: Date()), diary.latestDiaryDate)
        let earliestDate = diary.state.entries.map(\.date).min()
        let start = min(today, range.startDate(relativeTo: today, earliestDate: earliestDate))
        let dayCount = max(1, (calendar.dateComponents([.day], from: start, to: today).day ?? 0) + 1)

        var totalsByKey: [String: (nutrition: Nutrition, count: Int)] = [:]
        for entry in diary.state.entries {
            let key = entry.clock?.dayKey ?? DayReview.key(entry.date, calendar: calendar)
            let current = totalsByKey[key] ?? (.zero, 0)
            totalsByKey[key] = (current.nutrition + entry.nutrition, current.count + 1)
        }

        return (0..<dayCount).reversed().compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: today) else { return nil }
            let key = DayReview.key(date, calendar: calendar)
            let pair = totalsByKey[key] ?? (.zero, 0)
            return LoggedDay(date: date, nutrition: pair.nutrition, entryCount: pair.count)
        }
    }

    private var loggedDays: [LoggedDay] { days.filter { $0.entryCount > 0 } }

    private var averageCalories: Double {
        guard !loggedDays.isEmpty else { return 0 }
        return loggedDays.reduce(0.0) { $0 + $1.nutrition.calories } / Double(loggedDays.count)
    }

    private var averageProtein: Double {
        guard !loggedDays.isEmpty else { return 0 }
        return loggedDays.reduce(0.0) { $0 + $1.nutrition.protein } / Double(loggedDays.count)
    }

    private var weightPoints: [BodyPoint] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let earliestDate = diary.bodyPoints.map(\.date).min()
        let start = min(today, range.startDate(relativeTo: today, earliestDate: earliestDate))
        return diary.bodyPoints.filter {
            $0.date <= Date() && $0.date >= start && scaleFilter.includes($0)
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    rangePicker
                    weightCard
                    localDiaryCard
                    energyBalanceCard
                    Notice(text: "A blank day means no local meals were logged—not that you ate nothing. Review complete food days in Today before using them for maintenance.")
                }.padding(18).frame(maxWidth: 640).frame(maxWidth: .infinity)
            }
            .background(Theme.background)
            .navigationTitle("Trends").navigationBarTitleDisplayMode(.inline)
            .refreshable { await diary.refreshHealth() }
        }
    }

    private var rangePicker: some View {
        Picker("Time range", selection: $range) {
            ForEach(TrendRange.allCases) { r in
                Text(r.shortTitle).tag(r)
            }
        }
        .pickerStyle(.segmented)
        .accessibilityLabel("Trends time range")
    }

    private var weightCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                SectionHeading(title: "Weight", detail: "\(range.title) · same-scale")
                Spacer()
                if let netChangeText {
                    Text(netChangeText)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(Theme.ink)
                }
            }
            ScaleFilterPicker(selection: $scaleFilter)
            ScaleTrendPlot(points: weightPoints, metric: .weight, units: diary.state.measurementUnits, locations: diary.state.scaleLocations, rolling: range != .oneWeek)
            Text("Includes local measurements and readable Health imports. Tag or edit readings in Body. Empty Health results can mean missing data or no read permission.")
                .font(.caption).foregroundStyle(.secondary)
            if !diary.weightWarning.isEmpty { Notice(text: diary.weightWarning, symbol: "exclamationmark.triangle") }
        }.frame(maxWidth: .infinity, alignment: .leading).surface()
    }

    private var netChangeText: String? {
        let sorted = ScaleMath.latestWeightSeries(weightPoints)
        guard let first = sorted.first, let last = sorted.last, first.date != last.date else { return nil }
        let unit = diary.state.measurementUnits.unit(for: .weight)
        let displayFirst = diary.state.measurementUnits.display(first.value, metric: .weight)
        let displayLast = diary.state.measurementUnits.display(last.value, metric: .weight)
        let diff = displayLast - displayFirst
        if abs(diff) < 0.05 {
            return "Net: 0 \(unit)"
        }
        let sign = diff > 0 ? "+" : "-"
        return "Net: \(sign)\(abs(diff).displayNumber) \(unit)"
    }

    private var localDiaryCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeading(title: "Intake", detail: "\(range.title) · local")

            if !loggedDays.isEmpty {
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Average intake").font(.caption).foregroundStyle(.secondary)
                        Text("\(averageCalories.wholeNumber) kcal · \(averageProtein.wholeNumber) g P")
                            .font(.subheadline.monospacedDigit()).bold()
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("Logged").font(.caption).foregroundStyle(.secondary)
                        Text("\(loggedDays.count)/\(days.count) days")
                            .font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
                    }
                }
            }

            if days.contains(where: { $0.entryCount > 0 }), let first = days.first, let last = days.last {
                Chart {
                    ForEach(days.filter { $0.entryCount > 0 }) { day in
                        BarMark(x: .value("Date", day.date, unit: .day), y: .value("Calories", day.nutrition.calories))
                            .foregroundStyle(Theme.ink).cornerRadius(1)
                    }
                    RuleMark(y: .value("Current target", diary.state.targets.calories))
                        .foregroundStyle(.secondary).lineStyle(StrokeStyle(lineWidth: 1, dash: [4]))
                }
                .chartXScale(domain: first.date...DiaryMath.dayInterval(containing: last.date).end)
                .frame(height: 180).instrumentChart()
                .accessibilityLabel("Locally logged calories for \(range.title), with your current calorie target")
            }

            if days.contains(where: { $0.entryCount > 0 }) {
                let displayDays = Array(days.suffix(7))
                if range != .oneWeek && days.count > 7 {
                    Text("Recent days").font(.caption).foregroundStyle(.secondary).padding(.top, 4)
                }
                ForEach(displayDays.reversed()) { day in
                    HStack {
                        Text(day.date, format: .dateTime.weekday(.abbreviated).month(.abbreviated).day())
                        Spacer()
                        if day.entryCount == 0 { Text("No entries").foregroundStyle(.secondary) }
                        else { Text("\(day.nutrition.calories.wholeNumber) kcal · \(day.nutrition.protein.wholeNumber) g P").monospacedDigit() }
                    }.font(.caption)
                }
            } else {
                Text("No meals logged yet for this period.")
                    .font(.subheadline).foregroundStyle(Theme.muted)
            }
            Text("This chart uses saved local diary dates for Recomp meals only. Maintenance uses reviewed complete food days. The dashed line is your current target.")
                .font(.caption).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading).surface()
    }

    private var energyBalanceCard: some View {
        let burn = diary.trendSummary.estimatedDailyBurn
        let isLearned = diary.trendSummary.isBurnLearned
        let avgCalories = averageCalories
        let hasIntake = !loggedDays.isEmpty
        let balance = hasIntake ? (avgCalories - burn) : nil
        let unit = diary.state.measurementUnits.unit(for: .weight)

        return VStack(alignment: .leading, spacing: 16) {
            SectionHeading(title: "Energy & Expenditure", detail: isLearned ? "learned model" : "baseline estimate")

            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Est. daily burn").font(.caption).foregroundStyle(.secondary)
                    Text("\(burn.wholeNumber) kcal/d")
                        .font(.title3.monospacedDigit()).bold()
                    Text(isLearned ? "Learned expenditure" : "Calibrating baseline")
                        .font(.caption2)
                        .foregroundStyle(isLearned ? Theme.accent : Theme.muted)
                }
                Spacer()
                if hasIntake, let balance = balance {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("Energy balance").font(.caption).foregroundStyle(.secondary)
                        Text(balance < 0 ? "\(abs(balance).wholeNumber) kcal/d deficit" : "\(balance.wholeNumber) kcal/d surplus")
                            .font(.subheadline.monospacedDigit()).bold()
                            .foregroundStyle(balance < -50 ? Color.green : (balance > 50 ? Color.orange : Theme.ink))

                        let kgRate = (balance * 7.0) / 7700.0
                        let displayRate = unit == "lb" ? (kgRate / 0.45359237) : kgRate
                        let sign = displayRate > 0 ? "+" : ""
                        Text(String(format: "%@%.2f %@/wk implied", sign, displayRate, unit))
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Text("Estimated daily burn combines your logged calorie intake with weight trends to model daily metabolic expenditure. When calibrating, your baseline starting maintenance is used.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .surface()
    }
}
