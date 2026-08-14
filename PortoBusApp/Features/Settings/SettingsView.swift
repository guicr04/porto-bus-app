import SwiftUI

/// The four-field settings form (DESIGN.md §4.4): server address, walk budget,
/// board options, and the fallback home location. Reached from the Board
/// toolbar gear and from the Info tab.
struct SettingsView: View {
    @Environment(AppServices.self) private var services

    var body: some View {
        @Bindable var settings = services.settings

        Form {
            Section {
                TextField("http://127.0.0.1:8000", text: $settings.baseURLString)
                    .keyboardType(.URL)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .font(.callout.monospaced())
            } header: {
                Text("Server")
            } footer: {
                Text("The Porto Bus API. On a real device use your Mac's LAN address, e.g. http://192.168.1.20:8000. On the simulator, 127.0.0.1 reaches your Mac.")
            }

            Section("Board") {
                Stepper("Walk budget: \(settings.walkMinutes) min",
                        value: $settings.walkMinutes, in: 1...30)
                Toggle("Sort by soonest arrival", isOn: $settings.sortByETA)
                Toggle("Show unreachable buses", isOn: $settings.showUnreachable)
            }

            Section {
                LabeledContent("Latitude") {
                    TextField("41.1496", value: $settings.homeLat, format: .number.precision(.fractionLength(0...6)))
                        .keyboardType(.numbersAndPunctuation)
                        .multilineTextAlignment(.trailing)
                }
                LabeledContent("Longitude") {
                    TextField("-8.6109", value: $settings.homeLon, format: .number.precision(.fractionLength(0...6)))
                        .keyboardType(.numbersAndPunctuation)
                        .multilineTextAlignment(.trailing)
                }
            } header: {
                Text("Home location")
            } footer: {
                Text("Used when location access is off or unavailable, so the board still has an origin.")
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack { SettingsView() }
        .environment(AppServices.preview())
}
