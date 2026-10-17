import SwiftUI

@MainActor
struct WidgetSettingsScreen: View {
    @EnvironmentObject private var diary: DiaryStore
    @State private var writeOK = true
    var body: some View {
        Form {
            Section {
                Toggle("Show calories & protein", isOn: Binding(get: { diary.state.widgetPreferences.showNumbers }, set: {
                    diary.setWidgetNumbers($0); writeOK = WidgetPublisher.publish(diary.state)
                }))
                Text("Numbers are hidden by default. The widget uses only today's local food diary, not additional Apple Health nutrition. It is labelled LOCAL DIARY and may differ from Today when Health nutrition is included.")
                    .font(.footnote).foregroundStyle(.secondary)
            } header: { Text("Home Screen readout") }
            Section("Add the widget") {
                Text("Touch and hold the iPhone Home Screen, choose Edit → Add Widget, search for Recomp, then add the small or medium widget. The medium widget opens Log, Check or Weigh without saving anything.")
                Text("Updates are requested after local changes and when Recomp opens. iOS controls refresh timing; numbers are not guaranteed live. At midnight a scheduled entry hides yesterday's totals until the app publishes today.")
                Text("The widget marks its numbers as private and requests complete Data Protection. Native lock-screen redaction and device behaviour need testing. No photos, scan reports, weights, scale names or server credentials are put in the shared widget file.")
            }.font(.footnote)
            Section("Developer setup") {
                Text("Enable the same App Group for the Recomp and RecompWidget targets in Xcode. The group identifier must match the RECOMP_APP_GROUP build setting. See the 1.7 guide. The diary works without a configured group; the widget cannot read a snapshot until it is configured.")
                if WidgetPublisher.container == nil || !writeOK {
                    Label("Shared widget container unavailable. Check App Group signing, or unlock and reopen the app.", systemImage: "info.circle")
                }
                Button("Refresh widget snapshot") { writeOK = WidgetPublisher.publish(diary.state) }
            }.font(.footnote)
        }.instrumentForm().navigationTitle("Widget").navigationBarTitleDisplayMode(.inline)
    }
}
