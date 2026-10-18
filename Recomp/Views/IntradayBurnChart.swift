import SwiftUI
import Charts

struct IntradayBurnChart: View {
    let curve: IntradayBurnCurve
    let now: Date
    var isCompact: Bool = false

    @State private var selectedTime: Date?
    @Environment(\.dynamicTypeSize) private var dynamicType

    private var selectedPoint: IntradayBurnPoint? {
        selectedTime.flatMap { curve.point(nearestTo: $0) }
    }
    private var activePoint: IntradayBurnPoint? { selectedPoint ?? curve.currentPoint }
    private var isComplete: Bool { curve.fraction >= 1 }
    private var isUpcoming: Bool { curve.points.first.map { $0.time > now } ?? false }
    private var hasForecast: Bool { !curve.projectedPoints.isEmpty }
    private var dayRange: ClosedRange<Date> {
        let start = curve.points.first?.time ?? Calendar.current.startOfDay(for: now)
        let end = curve.points.last?.time ?? start.addingTimeInterval(24 * 3600)
        return start...max(end, start.addingTimeInterval(1))
    }
    private var yMaximum: Double {
        let maximum = max(curve.dailyBurn, curve.points.last?.linearCumulative ?? 0)
        return max(500, (maximum * 1.08 / 500).rounded(.up) * 500)
    }
    private var axisTimes: [Date] {
        let calendar = Calendar.current
        let hours = dynamicType.isAccessibilitySize ? [] : [6, 12, 18]
        return [dayRange.lowerBound] + hours.compactMap {
            calendar.date(bySettingHour: $0, minute: 0, second: 0, of: dayRange.lowerBound)
        } + [dayRange.upperBound]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            headerView
            chartView.frame(height: isCompact ? 160 : 210)
            legendView
            inspectionView
            if !isCompact { modelDetailsView }
        }
        .onChange(of: curve.points.first?.time) { _, _ in selectedTime = nil }
    }

    private var headerView: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 16) {
                expenditureReadout
                Spacer(minLength: 8)
                dayReadout
            }
            VStack(alignment: .leading, spacing: 12) {
                expenditureReadout
                dayReadout
            }
        }
    }

    private var expenditureTitle: String {
        if let selectedPoint {
            return selectedPoint.isProjected ? "FORECAST AT \(timeLabel(selectedPoint.time))" : "ESTIMATE AT \(timeLabel(selectedPoint.time))"
        }
        if isComplete { return "ESTIMATED DAY TOTAL" }
        return "ESTIMATED BURN SO FAR"
    }

    private var expenditureReadout: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(expenditureTitle)
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(Theme.muted)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text((selectedPoint?.actualCumulative ?? curve.expendedSoFar).wholeNumber)
                    .font(.system(.title2, design: .monospaced).weight(.semibold))
                    .foregroundStyle(Theme.ink)
                    .accessibilityIdentifier("burn.amount")
                Text("kcal")
                    .font(.caption).foregroundStyle(Theme.muted)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
    }

    private var dayReadout: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(isComplete ? "MAINTENANCE" : "DAY FORECAST")
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(Theme.muted)
            Text("\((isComplete ? curve.points.last?.linearCumulative ?? curve.dailyBurn : curve.dailyBurn).wholeNumber) kcal")
                .font(.system(.subheadline, design: .monospaced).weight(.medium))
                .foregroundStyle(Theme.ink)
        }
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
    }

    private var chartView: some View {
        Chart {
            if let first = curve.points.first, let last = curve.points.last {
                // Neutral dotted maintenance; orange dashes are reserved for forecasts.
                ForEach([first, last]) { point in
                    LineMark(x: .value("Time", point.time), y: .value("Maintenance kcal", point.linearCumulative),
                             series: .value("Series", "Maintenance"))
                        .foregroundStyle(Theme.muted)
                        .lineStyle(StrokeStyle(lineWidth: 1.2, dash: [2, 4]))
                        .accessibilityHidden(true)
                }
            }

            ForEach(curve.estimatedPoints) { point in
                AreaMark(x: .value("Time", point.time), y: .value("Estimated kcal", point.actualCumulative))
                    .interpolationMethod(.linear)
                    .foregroundStyle(LinearGradient(colors: [Theme.accent.opacity(0.2), Theme.accent.opacity(0.02)],
                                                    startPoint: .top, endPoint: .bottom))
                    .accessibilityHidden(true)
                LineMark(x: .value("Time", point.time), y: .value("Estimated kcal", point.actualCumulative),
                         series: .value("Series", "Estimated burn"))
                    .interpolationMethod(.linear)
                    .foregroundStyle(Theme.accent)
                    .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                    .accessibilityLabel(timeLabel(point.time))
                    .accessibilityValue("\(point.actualCumulative.wholeNumber) kilocalories estimated")
            }

            ForEach(curve.projectedPoints) { point in
                LineMark(x: .value("Time", point.time), y: .value("Forecast kcal", point.actualCumulative),
                         series: .value("Series", "Forecast"))
                    .interpolationMethod(.linear)
                    .foregroundStyle(Theme.accent)
                    .lineStyle(StrokeStyle(lineWidth: 2, dash: [6, 4]))
                    .accessibilityLabel(timeLabel(point.time))
                    .accessibilityValue("\(point.actualCumulative.wholeNumber) kilocalories forecast")
            }

            ForEach(curve.workoutMarkers) { point in
                PointMark(x: .value("Time", point.time), y: .value("Estimated kcal", point.actualCumulative))
                    .symbol(.diamond).symbolSize(55)
                    .foregroundStyle(Theme.ink)
                    .accessibilityLabel("\(point.workoutTitle ?? "Workout") at \(timeLabel(point.time))")
            }

            if !isComplete, !isUpcoming, let current = curve.currentPoint {
                RuleMark(x: .value("Now", current.time))
                    .foregroundStyle(Theme.muted.opacity(0.6))
                    .lineStyle(StrokeStyle(lineWidth: 1))
                    .accessibilityHidden(true)
                PointMark(x: .value("Time", current.time), y: .value("Estimated kcal", current.actualCumulative))
                    .foregroundStyle(Theme.accent).symbolSize(65)
                    .annotation(position: .top, spacing: 8,
                                overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))) {
                        Text("NOW").font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(Theme.ink)
                    }
                    .accessibilityLabel("Current estimate")
                    .accessibilityValue("\(current.actualCumulative.wholeNumber) kilocalories")
            }

            if let selectedPoint {
                RuleMark(x: .value("Selected time", selectedPoint.time))
                    .foregroundStyle(Theme.ink.opacity(0.65))
                    .lineStyle(StrokeStyle(lineWidth: 1))
                    .accessibilityHidden(true)
                PointMark(x: .value("Time", selectedPoint.time), y: .value("Selected kcal", selectedPoint.actualCumulative))
                    .symbolSize(85).foregroundStyle(Theme.ink)
                    .accessibilityHidden(true)
            }
        }
        .chartXScale(domain: dayRange)
        .chartYScale(domain: 0...yMaximum)
        .chartXSelection(value: $selectedTime)
        #if !targetEnvironment(macCatalyst)
        .chartGesture { proxy in
            // Keep a tapped selection visible. Require a brief hold for scrubbing
            // so ordinary vertical swipes can still scroll the surrounding page.
            SpatialTapGesture()
                .onEnded { proxy.selectXValue(at: $0.location.x) }
                .simultaneously(with:
                    LongPressGesture(minimumDuration: 0.2)
                        .sequenced(before: DragGesture(minimumDistance: 0))
                        .onChanged { value in
                            if case .second(true, let drag?) = value {
                                proxy.selectXValue(at: drag.location.x)
                            }
                        }
                )
        }
        #endif
        .chartXAxis {
            AxisMarks(values: axisTimes) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(Theme.rule)
                AxisValueLabel(anchor: value.index == 0 ? .topLeading : value.index == axisTimes.count - 1 ? .topTrailing : .top,
                               collisionResolution: .disabled) {
                    if let date = value.as(Date.self) {
                        Text(date == dayRange.upperBound ? "End" : date.formatted(.dateTime.hour(.defaultDigits(amPM: .abbreviated))))
                            .font(.system(.caption2, design: .monospaced)).foregroundStyle(Theme.muted)
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 4)) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(Theme.rule)
                AxisValueLabel {
                    if let amount = value.as(Double.self) {
                        Text(dynamicType.isAccessibilitySize ? amount.formatted(.number.notation(.compactName)) : amount.wholeNumber)
                            .font(.system(.caption2, design: .monospaced)).foregroundStyle(Theme.muted)
                    }
                }
            }
        }
        .accessibilityLabel("Cumulative calorie burn")
        .accessibilityIdentifier("burn.chart")
    }

    private var legendView: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 14) { legendItems }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: dynamicType.isAccessibilitySize ? 220 : 125), alignment: .leading)],
                      alignment: .leading, spacing: 8) { legendItems }
        }
        .font(.caption2).foregroundStyle(Theme.muted)
    }

    @ViewBuilder private var legendItems: some View {
        if !curve.estimatedPoints.isEmpty { legendItem("Estimated", color: Theme.accent, dash: []) }
        if hasForecast { legendItem("Forecast", color: Theme.accent, dash: [6, 4]) }
        legendItem("Maintenance", color: Theme.muted, dash: [2, 4])
        if !curve.workoutMarkers.isEmpty {
            Label {
                Text("Workout")
            } icon: {
                Image(systemName: "diamond.fill").font(.system(size: 7)).foregroundStyle(Theme.ink)
            }
        }
    }

    private func legendItem(_ title: String, color: Color, dash: [CGFloat]) -> some View {
        HStack(spacing: 5) {
            Path { path in
                path.move(to: CGPoint(x: 0, y: 4))
                path.addLine(to: CGPoint(x: 20, y: 4))
            }
            .stroke(color, style: StrokeStyle(lineWidth: 2, dash: dash))
            .frame(width: 20, height: 8).accessibilityHidden(true)
            Text(title).fixedSize()
        }
    }

    private var inspectionView: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let point = activePoint {
                let delta = point.actualCumulative - point.linearCumulative
                Text("\(delta >= 0 ? "+" : "−")\(abs(delta).wholeNumber) kcal vs maintenance pace")
                    .font(.caption.monospacedDigit()).foregroundStyle(Theme.ink)
                if let title = point.workoutTitle {
                    Label(title, systemImage: "figure.run")
                        .font(.caption).foregroundStyle(Theme.ink)
                }
            }
            if selectedPoint != nil {
                Button { selectedTime = nil } label: {
                    Text("Reset to \(isComplete ? "day total" : "current estimate")")
                        .frame(minHeight: 44).contentShape(Rectangle())
                }
                    .font(.caption).buttonStyle(.borderless)
                    .accessibilityIdentifier("burn.reset")
            } else {
                Text(isUpcoming ? "This day has not started. All values are forecasts." :
                     isComplete ? "Full-day estimate · cumulative kcal" :
                     "Through \(timeLabel(curve.currentPoint?.time ?? now)) · cumulative kcal")
                    .font(.caption).foregroundStyle(Theme.muted)
                #if targetEnvironment(macCatalyst)
                Text("Hover over the chart to inspect a time.")
                    .font(.caption2).foregroundStyle(Theme.muted)
                #else
                Text("Tap to inspect · hold and drag to explore")
                    .font(.caption2).foregroundStyle(Theme.muted)
                #endif
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var modelDetailsView: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let energy = curve.energy {
                Text("\(energy.resting.isMeasured ? "Entered measured RMR" : "Estimated resting energy") · \(energy.resting.kcalPerDay.wholeNumber) kcal/day")
                    .font(.caption).foregroundStyle(Theme.muted)
                    .accessibilityIdentifier("burn.resting")
                Text(curve.calibrationDays > 0 ? "Trend-calibrated movement allowance" : "Movement allowance is provisional")
                    .font(.caption).foregroundStyle(Theme.muted)
                if !curve.hasActivityEstimate {
                    Text("No movement records · everyday activity may be missing")
                        .font(.caption).foregroundStyle(Theme.muted)
                }
            } else if !curve.hasActivityEstimate {
                Text("No activity data · using maintenance pace")
                    .font(.caption).foregroundStyle(Theme.muted)
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) { activityLabels }
                    VStack(alignment: .leading, spacing: 6) { activityLabels }
                }
                .font(.caption).foregroundStyle(Theme.muted)
                Text(curve.modelNote)
                    .font(.caption).foregroundStyle(Theme.muted)
            }
            DisclosureGroup("How this is estimated") {
                VStack(alignment: .leading, spacing: 8) {
                    if let energy = curve.energy {
                        Text(isComplete ? "Estimated day breakdown" : "Estimated burn so far").fontWeight(.medium)
                        InstrumentDatum(title: "Resting · RMR", value: "\(energy.restingSoFar.wholeNumber) kcal")
                        InstrumentDatum(title: "Everyday movement · NEAT", value: "\((curve.stepBurn + energy.untrackedSoFar).wholeNumber) kcal")
                        Text("Includes \(energy.untrackedSoFar.wholeNumber) kcal of untracked movement / calibration allowance.")
                        InstrumentDatum(title: "Exercise · above rest", value: "\(curve.workoutBurn.wholeNumber) kcal")
                        InstrumentDatum(title: "Digestion · TEF", value: "\(curve.tefBurn.wholeNumber) kcal")
                        Text(energy.intakeBasis)
                        if !energy.foodCoverageComplete {
                            Text("Food coverage is incomplete. Digestion includes \(energy.digestionAllowanceSoFar.wholeNumber) kcal of usual-intake allowance; missing meals are not treated as fasting.")
                        }
                        Text(curve.modelNote)
                        Text("Cunningham 1991 uses fat-free mass, or your manual resting value. Digestion uses macro estimates over a coarse 8-hour window. Resting energy and untracked movement timing are assumptions. These components have not been individually validated.")
                    } else if curve.hasActivityEstimate {
                        Text(isComplete ? "Estimated day breakdown" : "Estimated burn so far")
                            .fontWeight(.medium)
                        InstrumentDatum(title: "Background", value: "\(curve.backgroundSoFar.wholeNumber) kcal")
                        InstrumentDatum(title: "Walking outside workouts", value: "\(curve.stepBurn.wholeNumber) kcal")
                        InstrumentDatum(title: "Workouts", value: "\(curve.workoutBurn.wholeNumber) kcal")
                    }
                    if curve.energy == nil && !curve.hasActivityEstimate { Text(curve.modelNote) }
                    Text("Recomp calculates energy from the recorded inputs; no Apple calorie estimates are added. Step timing and workout intensity are approximate. Overlapping steps and workouts count once.")
                    if hasForecast {
                        Text("The dashed forecast assumes typical activity for the rest of the day. Future calories are not included in burn so far.")
                    }
                }
                .font(.caption).foregroundStyle(Theme.muted)
                .padding(.top, 8)
            }
            .font(.caption).foregroundStyle(Theme.muted)
            .accessibilityIdentifier("burn.model")
        }
    }

    @ViewBuilder private var activityLabels: some View {
        if curve.stepCount > 0 {
            Label("\(curve.stepCount.wholeNumber) steps", systemImage: "figure.walk")
        }
        if !curve.workouts.isEmpty {
            Label("\(curve.workouts.count) \(curve.workouts.count == 1 ? "workout" : "workouts")", systemImage: "diamond.fill")
        }
    }

    private func timeLabel(_ time: Date) -> String {
        if time == dayRange.upperBound { return "day end" }
        return time.formatted(date: .omitted, time: .shortened)
    }
}
