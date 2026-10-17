import SwiftUI

@MainActor
struct DayCompletionCard: View {
    @EnvironmentObject private var diary: DiaryStore
    @State private var reviewing = false
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeading(title: "Day review", detail: diary.selectedDayReview == nil ? "Not confirmed" : "Confirmed")
            if let review = diary.selectedDayReview {
                Text("\(review.total.calories.wholeNumber) kcal · \(review.excludedFromAnalysis ? "excluded" : "confirmed")")
                    .font(.system(.subheadline, design: .monospaced)).foregroundStyle(Theme.muted)
                if Nutrient.allCases.contains(where: { abs(review.total[$0] - diary.total[$0]) > 0.1 }) {
                    Notice(text: "Totals changed. Review this day again.", symbol: "exclamationmark.triangle")
                }
                ViewThatFits(in: .horizontal) {
                    HStack { Button("Review again") { reviewing = true }; Spacer(); Button("Mark incomplete") { diary.unconfirmSelectedDay() } }
                    VStack(alignment: .leading, spacing: 10) { Button("Review again") { reviewing = true }; Button("Mark incomplete") { diary.unconfirmSelectedDay() } }
                }.font(.subheadline)
            } else {
                Text("Logged everything? Confirm the day for maintenance analysis.")
                    .font(.subheadline).foregroundStyle(Theme.muted)
                Button("Review day") { reviewing = true }.disabled(!diary.canConfirmDay)
                if !diary.canConfirmDay && diary.state.healthEnabled && diary.state.includeOtherSources {
                    Text("Refresh Health, or turn off additional Health nutrition in Settings.").font(.caption).foregroundStyle(.secondary)
                }
            }
            Divider().overlay(Theme.rule)
            NavigationLink { TravelCoverageScreen() } label: {
                Label("Travel & food coverage", systemImage: "airplane").font(.subheadline)
            }
        }.frame(maxWidth: .infinity, alignment: .leading).surface()
        .sheet(isPresented: $reviewing) { DayCompletionView(review: diary.selectedDayReview) }
    }
}

@MainActor
struct DayCompletionView: View {
    @EnvironmentObject private var diary: DiaryStore
    @Environment(\.dismiss) private var dismiss
    @State private var excluded: Bool
    @State private var note: String
    @State private var allFood = false
    init(review: DayReview?) {
        _excluded = State(initialValue: review?.excludedFromAnalysis ?? false)
        _note = State(initialValue: review?.note ?? "")
    }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(diary.selectedDay, format: .dateTime.weekday(.wide).month().day())
                    ForEach(Nutrient.allCases) { nutrient in
                        LabeledContent(nutrient.title, value: "\(diary.total[nutrient].displayNumber) \(nutrient.unit)")
                    }
                    Toggle("All food and drinks are included", isOn: $allFood)
                } footer: {
                    Text("Include drinks, oils, sauces and snacks. This day counts after its local midnight. Blank days are not fasting.")
                }
                Section("Conditions") {
                    Toggle("Exclude this day from analysis", isOn: $excluded)
                    TextField("Notes: travel, illness, creatine, unusual training…", text: $note, axis: .vertical).lineLimit(2...5)
                    Text("Exclude unreliable periods. Exclusions break the analysis window; exercise and fluid changes are not corrected automatically.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section {
                    Text("Check Health imports for missing or duplicate food. Editing a meal requires reconfirmation. Changes in other apps need a fresh review.")
                    Text("Original day timezone: \(diary.normalReviewZone). Maintenance combines confirmed real-time intervals across timezones, without treating missing hours as fasting.")
                }.font(.caption).foregroundStyle(.secondary)
            }
            .instrumentForm()
            .onChange(of: diary.total) { _, _ in allFood = false }
            .onChange(of: diary.selectedDay) { _, _ in allFood = false }
            .onChange(of: diary.state.includeOtherSources) { _, _ in allFood = false }
            .navigationTitle("Confirm complete day").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Confirm") { if diary.confirmSelectedDay(excluded: excluded, note: note) { dismiss() } }
                        .disabled(!allFood || !diary.canConfirmDay || note.count > 1000)
                }
            }
        }
    }
}
