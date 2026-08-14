import SwiftUI

/// The Info tab: a link to Settings, a short "what this is", and honest notes on
/// the v1 limitations (LAN-only, widget refresh budget) so they read as known
/// rather than broken.
struct InfoView: View {
    private var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
        return "\(v) (\(b))"
    }

    var body: some View {
        List {
            Section {
                NavigationLink(value: Route.settings) {
                    Label("Settings", systemImage: "gearshape")
                }
            }

            Section("About") {
                Text("Porto Bus shows what you can catch on foot from where you are, using live STCP arrivals and the official GTFS schedule.")
                    .font(.callout)
            }

            Section("Good to know") {
                Label {
                    Text("Works on your local network for now. Away from home it needs the API hosted online.")
                } icon: {
                    Image(systemName: "wifi")
                }
                Label {
                    Text("Live times refresh about every 20 seconds while the app is open.")
                } icon: {
                    Image(systemName: "clock.arrow.circlepath")
                }
            }
            .font(.footnote)

            Section {
                LabeledContent("Version", value: appVersion)
            }
        }
        .floatingBarInset()
        .navigationTitle("Info")
        .navigationDestination(for: Route.self) { $0.destination }
    }
}

#Preview {
    NavigationStack { InfoView() }
        .environment(AppServices.preview())
}
