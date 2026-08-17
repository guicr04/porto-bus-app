import SwiftUI
import PortoBusKit

/// Shared swipe action for favoriting the station a Board row departs from. A
/// swipe action rather than a persistent heart badge, deliberately: Board is
/// scanned constantly, and a heart on every row would be clutter. The station
/// screen reached from Lines — visited less often, viewed for longer — gets a
/// persistent toolbar heart instead (see StopDetailView).
struct FavoriteSwipeButton: View {
    let stop: Stop
    @Environment(AppServices.self) private var services

    var body: some View {
        let isFavorite = services.favorites.isFavorite(stopCode: stop.stopCode)
        Button {
            services.favorites.toggle(stop)
        } label: {
            Label(isFavorite ? "Unfavorite" : "Favorite", systemImage: isFavorite ? "heart.slash" : "heart")
        }
        .tint(isFavorite ? .gray : .favorite)
    }
}
