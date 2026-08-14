import SwiftUI

/// Renders a ViewModel's `LoadState` uniformly across screens: a spinner on the
/// first load, an error card with Retry on failure, and the caller's content
/// once loaded. A refresh over existing content stays in `.loaded`, so content
/// never flashes back to a spinner mid-refresh.
struct LoadStateView<Value, Content: View>: View {
    let state: LoadState<Value>
    var retry: (() -> Void)?
    @ViewBuilder var content: (Value) -> Content

    var body: some View {
        switch state {
        case .idle, .loading:
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .loaded(let value):
            content(value)
        case .failed(let error):
            ErrorView(error: error, retry: retry)
        }
    }
}

/// The shared failure state. Uses the API's rider-facing `errorDescription`.
struct ErrorView: View {
    let error: Error
    var retry: (() -> Void)?

    var body: some View {
        ContentUnavailableView {
            Label("Something went wrong", systemImage: "exclamationmark.triangle")
        } description: {
            Text(error.localizedDescription)
        } actions: {
            if let retry {
                Button("Try Again", action: retry)
                    .buttonStyle(.borderedProminent)
            }
        }
    }
}
