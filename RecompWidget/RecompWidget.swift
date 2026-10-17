import Foundation
import SwiftUI
import WidgetKit

struct RecompTimelineEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
}

struct RecompTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> RecompTimelineEntry {
        RecompTimelineEntry(date: Date(), snapshot: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (RecompTimelineEntry) -> Void) {
        completion(RecompTimelineEntry(date: Date(), snapshot: context.isPreview ? nil : read()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<RecompTimelineEntry>) -> Void) {
        let now = Date()
        let midnight = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: now)) ?? now.addingTimeInterval(3600)
        let entries = [
            RecompTimelineEntry(date: now, snapshot: read()),
            RecompTimelineEntry(date: midnight, snapshot: nil)
        ]
        completion(Timeline(entries: entries, policy: .after(min(now.addingTimeInterval(900), midnight))))
    }

    private func read() -> WidgetSnapshot? {
        guard let group = Bundle.main.object(forInfoDictionaryKey: "RecompAppGroup") as? String,
              let directory = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group) else { return nil }
        let url = directory.appendingPathComponent(WidgetSnapshot.filename)
        guard let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size]) as? NSNumber,
              size.intValue <= 16_384,
              let data = try? Data(contentsOf: url),
              let snapshot = try? JSONDecoder().decode(WidgetSnapshot.self, from: data),
              snapshot.isCurrent(now: Date()),
              snapshot.entriesCount >= 0,
              snapshot.caloriesRemaining?.isFinite != false,
              snapshot.proteinRemaining?.isFinite != false else { return nil }
        return snapshot
    }
}

// MARK: - Four Concentric Intake Rings
/// Calories (outer), Protein, Carbs, Fat (inner)
struct WidgetRings: View {
    var calFraction: Double = 0
    var proFraction: Double = 0
    var carbFraction: Double = 0
    var fatFraction: Double = 0
    let side: CGFloat
    var strokeWidth: CGFloat? = nil
    var gap: CGFloat? = nil

    var body: some View {
        let w = strokeWidth ?? max(3.5, side * 0.065)
        let g = gap ?? max(1.8, side * 0.024)
        ZStack {
            ring(fraction: calFraction, color: Color("RingCalories"), index: 0, width: w, gap: g)
            ring(fraction: proFraction, color: Color("RingProtein"), index: 1, width: w, gap: g)
            ring(fraction: carbFraction, color: Color("RingCarbs"), index: 2, width: w, gap: g)
            ring(fraction: fatFraction, color: Color("RingFat"), index: 3, width: w, gap: g)
        }
        .frame(width: side, height: side)
    }

    private func ring(fraction: Double, color: Color, index: Int, width: CGFloat, gap: CGFloat) -> some View {
        let inset = width / 2 + CGFloat(index) * (width + gap)
        let progress = min(1.0, max(0.0, fraction))
        return ZStack {
            Circle()
                .stroke(color.opacity(0.20), lineWidth: width)
            if progress > 0 {
                Circle()
                    .trim(from: 0, to: CGFloat(progress))
                    .stroke(color, style: StrokeStyle(lineWidth: width, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .shadow(color: color.opacity(0.35), radius: 2, x: 0, y: 0)
            }
        }
        .padding(inset)
    }
}

// MARK: - Root Widget View
struct RecompWidgetView: View {
    let entry: RecompTimelineEntry
    @Environment(\.widgetFamily) private var family

    private var snapshot: WidgetSnapshot? {
        guard let s = entry.snapshot, s.isCurrent(now: Date()) else { return nil }
        return s
    }

    private var visible: WidgetSnapshot? {
        guard let s = snapshot, s.showsNumbers else { return nil }
        return s
    }

    private func dayHeader(_ date: Date, wide: Bool = false) -> String {
        let cal = Calendar.current
        let isToday = cal.isDateInToday(date)
        let dayPart = wide
            ? date.formatted(.dateTime.weekday(.wide).day().month(.abbreviated)).uppercased()
            : date.formatted(.dateTime.weekday(.abbreviated).day()).uppercased()
        return isToday ? "TODAY · \(dayPart)" : dayPart
    }

    var body: some View {
        Group {
            if family == .systemMedium {
                mediumBody
            } else {
                smallBody
            }
        }
        .environment(\.colorScheme, .dark)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .containerBackground(for: .widget) {
            ZStack {
                Color(red: 0.06, green: 0.07, blue: 0.09)
                RadialGradient(
                    colors: [Color.white.opacity(0.04), Color.clear],
                    center: .topLeading,
                    startRadius: 0,
                    endRadius: 180
                )
            }
        }
        .widgetURL(URL(string: "recomp://today"))
    }

    // MARK: - Small Widget (Circles + Numbers, Day, Log Button)
    @ViewBuilder
    private var smallBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header Row: Day & Date on Left, + Log Button on Right
            HStack(alignment: .center) {
                Text(dayHeader(entry.date))
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .tracking(0.7)
                    .foregroundStyle(Color.white.opacity(0.65))
                    .lineLimit(1)

                Spacer(minLength: 4)

                Link(destination: URL(string: "recomp://log") ?? URL(fileURLWithPath: "/")) {
                    HStack(spacing: 3) {
                        Image(systemName: "plus")
                            .font(.system(size: 9, weight: .bold))
                        Text("Log")
                            .font(.system(size: 10.5, weight: .bold, design: .rounded))
                    }
                    .padding(.horizontal, 8)
                    .frame(height: 22)
                    .background(Color.white.opacity(0.12))
                    .overlay(Capsule().stroke(Color.white.opacity(0.16), lineWidth: 0.5))
                    .foregroundStyle(Color.white)
                    .clipShape(Capsule())
                }
            }
            .padding(.bottom, 6)

            Spacer(minLength: 0)

            // Main Row: 76pt Rings (Left) + Detailed Numbers (Right)
            HStack(spacing: 11) {
                // Left: Concentric 4 Rings with center flame indicator
                ZStack {
                    WidgetRings(
                        calFraction: snapshot?.calorieFraction ?? 0,
                        proFraction: snapshot?.proteinFraction ?? 0,
                        carbFraction: snapshot?.carbsFraction ?? 0,
                        fatFraction: snapshot?.fatFraction ?? 0,
                        side: 76,
                        strokeWidth: 4.6,
                        gap: 2.2
                    )

                    Image(systemName: "flame.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color("RingCalories"))
                        .shadow(color: Color("RingCalories").opacity(0.4), radius: 3)
                }

                // Right: Calorie Balance + 3 Macro Rows
                VStack(alignment: .leading, spacing: 3) {
                    if let s = visible, let kcal = s.caloriesRemaining {
                        // Calorie Readout
                        VStack(alignment: .leading, spacing: 0) {
                            Text(abs(kcal), format: .number.precision(.fractionLength(0)))
                                .font(.system(size: 22, weight: .bold, design: .rounded))
                                .foregroundStyle(Color.white)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                            Text(kcal < 0 ? "kcal over" : "kcal left")
                                .font(.system(size: 8.5, weight: .semibold, design: .rounded))
                                .foregroundStyle(kcal < 0 ? Color("Signal") : Color.white.opacity(0.55))
                        }

                        // Macro Breakdown
                        VStack(alignment: .leading, spacing: 2) {
                            if let p = s.proteinRemaining {
                                macroLine(
                                    color: Color("RingProtein"),
                                    value: "\(abs(p).formatted(.number.precision(.fractionLength(0))))g",
                                    label: "P",
                                    isOver: p < 0
                                )
                            }
                            if let cf = s.carbsFraction {
                                macroLine(
                                    color: Color("RingCarbs"),
                                    value: "\(Int(round(cf * 100)))%",
                                    label: "C",
                                    isOver: cf > 1.0
                                )
                            }
                            if let ff = s.fatFraction {
                                macroLine(
                                    color: Color("RingFat"),
                                    value: "\(Int(round(ff * 100)))%",
                                    label: "F",
                                    isOver: ff > 1.0
                                )
                            }
                        }
                        .padding(.top, 1)
                    } else {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Log food")
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .foregroundStyle(Color.white)
                            Text("to fill rings")
                                .font(.system(size: 10, weight: .medium, design: .rounded))
                                .foregroundStyle(Color.white.opacity(0.55))
                        }
                    }
                }
                .privacySensitive()
            }

            Spacer(minLength: 0)
        }
    }

    private func macroLine(color: Color, value: String, label: String, isOver: Bool) -> some View {
        HStack(spacing: 5) {
            Circle()
                .fill(color)
                .frame(width: 5.5, height: 5.5)
            Text(value)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(isOver ? Color("Signal") : Color.white)
                .lineLimit(1)
            Text(label)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.55))
        }
    }

    // MARK: - Medium Widget (Hero Concentric Rings + Structured Macro Cards + Actions)
    @ViewBuilder
    private var mediumBody: some View {
        HStack(spacing: 14) {
            // Left: Concentric Hero Ring with center calorie readout
            ZStack {
                WidgetRings(
                    calFraction: snapshot?.calorieFraction ?? 0,
                    proFraction: snapshot?.proteinFraction ?? 0,
                    carbFraction: snapshot?.carbsFraction ?? 0,
                    fatFraction: snapshot?.fatFraction ?? 0,
                    side: 104,
                    strokeWidth: 4.4,
                    gap: 2.2
                )
                if let s = visible, let kcal = s.caloriesRemaining {
                    VStack(spacing: 0) {
                        Text(abs(kcal), format: .number.precision(.fractionLength(0)))
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                            .foregroundStyle(Color.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.65)
                        Text(kcal < 0 ? "over" : "kcal left")
                            .font(.system(size: 8.5, weight: .semibold, design: .rounded))
                            .foregroundStyle(kcal < 0 ? Color("Signal") : Color.white.opacity(0.6))
                    }
                    .frame(maxWidth: 52)
                    .privacySensitive()
                }
            }

            // Right side: Header, Macro pills, Action buttons
            VStack(alignment: .leading, spacing: 7) {
                // 1. Day Header
                HStack(alignment: .firstTextBaseline) {
                    Text(dayHeader(entry.date, wide: true))
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .tracking(0.7)
                        .foregroundStyle(Color.white.opacity(0.65))
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Text("RECOMP")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .tracking(1.0)
                        .foregroundStyle(Color.white.opacity(0.25))
                }

                // 2. Macro Cards
                if let s = visible {
                    HStack(spacing: 5) {
                        macroCard(
                            color: Color("RingProtein"),
                            label: "Protein",
                            value: s.proteinRemaining.map { "\(abs($0).formatted(.number.precision(.fractionLength(0))))g" } ?? "--",
                            suffix: (s.proteinRemaining ?? 0) < 0 ? "over" : "left",
                            fraction: s.proteinFraction
                        )
                        macroCard(
                            color: Color("RingCarbs"),
                            label: "Carbs",
                            value: s.carbsFraction.map { "\(Int(round($0 * 100)))%" } ?? "--",
                            suffix: "of goal",
                            fraction: s.carbsFraction
                        )
                        macroCard(
                            color: Color("RingFat"),
                            label: "Fat",
                            value: s.fatFraction.map { "\(Int(round($0 * 100)))%" } ?? "--",
                            suffix: "of goal",
                            fraction: s.fatFraction
                        )
                    }
                    .privacySensitive()
                } else {
                    Text("Open Recomp for daily summary")
                        .font(.system(size: 11, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.55))
                }

                // 3. Action Buttons
                HStack(spacing: 6) {
                    Link(destination: URL(string: "recomp://log") ?? URL(fileURLWithPath: "/")) {
                        HStack(spacing: 4) {
                            Image(systemName: "plus")
                                .font(.system(size: 9.5, weight: .bold))
                            Text("Log")
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 31)
                        .background(Color("RingCalories").opacity(0.32))
                        .overlay(Capsule().stroke(Color("RingCalories").opacity(0.48), lineWidth: 0.5))
                        .foregroundStyle(Color.white)
                        .clipShape(Capsule())
                    }

                    Link(destination: URL(string: "recomp://check") ?? URL(fileURLWithPath: "/")) {
                        HStack(spacing: 4) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 9, weight: .semibold))
                            Text("Check")
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 31)
                        .background(Color.white.opacity(0.09))
                        .overlay(Capsule().stroke(Color.white.opacity(0.14), lineWidth: 0.5))
                        .foregroundStyle(Color.white.opacity(0.95))
                        .clipShape(Capsule())
                    }

                    Link(destination: URL(string: "recomp://weigh") ?? URL(fileURLWithPath: "/")) {
                        HStack(spacing: 4) {
                            Image(systemName: "scalemass")
                                .font(.system(size: 9, weight: .semibold))
                            Text("Weigh")
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 31)
                        .background(Color.white.opacity(0.09))
                        .overlay(Capsule().stroke(Color.white.opacity(0.14), lineWidth: 0.5))
                        .foregroundStyle(Color.white.opacity(0.95))
                        .clipShape(Capsule())
                    }
                }
            }
        }
    }

    private func macroCard(color: Color, label: String, value: String, suffix: String, fraction: Double? = nil) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Circle().fill(color).frame(width: 5, height: 5)
                Text(label)
                    .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.65))
            }
            Text(value)
                .font(.system(size: 15.5, weight: .bold, design: .rounded))
                .foregroundStyle(Color.white)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(suffix)
                .font(.system(size: 8, weight: .medium, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.5))

            if let f = fraction {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.white.opacity(0.12))
                        Capsule()
                            .fill(color)
                            .frame(width: max(2, min(geo.size.width, geo.size.width * CGFloat(min(1.0, max(0.0, f))))))
                    }
                }
                .frame(height: 3)
                .padding(.top, 2)
            }
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.07))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.10), lineWidth: 0.5))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

@main
struct RecompWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetSnapshot.kind, provider: RecompTimelineProvider()) { entry in
            RecompWidgetView(entry: entry)
        }
        .configurationDisplayName("Recomp / Daily readout")
        .description("Intake rings and numbers remaining with quick logging and day display.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
