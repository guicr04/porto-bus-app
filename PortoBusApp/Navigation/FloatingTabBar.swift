import SwiftUI

/// The floating pill tab bar adopted from the Lisbon Metro reference (DESIGN.md
/// §5): the selected tab expands to show its label, the others stay icon-only,
/// and the centre item is emphasised. Rendered over the content, not as system
/// chrome.
struct FloatingTabBar: View {
    @Binding var selection: AppTab

    var body: some View {
        HStack(spacing: 4) {
            ForEach(AppTab.allCases) { tab in
                item(for: tab)
            }
        }
        .padding(6)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(.separator.opacity(0.4)))
        .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity)
        // A soft fade of the window background behind the bar, so list rows that
        // scroll under it dissolve out rather than peeking through the gutter
        // beside the capsule (DESIGN.md §5 — content scrolls under the bar).
        .background(
            LinearGradient(
                colors: [Color(.systemBackground).opacity(0), Color(.systemBackground)],
                startPoint: .top,
                endPoint: .bottom
            )
            .padding(.top, -24)
            .allowsHitTesting(false)
        )
    }

    @ViewBuilder
    private func item(for tab: AppTab) -> some View {
        let isSelected = tab == selection

        Button {
            withAnimation(.snappy(duration: 0.25)) { selection = tab }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: tab.systemImage)
                    .font(tab.isEmphasized ? .title3.weight(.semibold) : .body.weight(.medium))
                    .frame(width: tab.isEmphasized ? 28 : 22, height: 22)

                // Only the selected tab reveals its label — keeps five items legible.
                if isSelected {
                    Text(tab.title)
                        .font(.subheadline.weight(.semibold))
                        .fixedSize()
                        .transition(.opacity.combined(with: .move(edge: .trailing)))
                }
            }
            .padding(.vertical, 10)
            .padding(.horizontal, isSelected ? 14 : 12)
            .foregroundStyle(foreground(isSelected: isSelected, emphasized: tab.isEmphasized))
            .background(background(isSelected: isSelected, emphasized: tab.isEmphasized))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tab.title)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private func foreground(isSelected: Bool, emphasized: Bool) -> Color {
        if isSelected { return .white }
        return emphasized ? .primary : .secondary
    }

    @ViewBuilder
    private func background(isSelected: Bool, emphasized: Bool) -> some View {
        if isSelected {
            Capsule().fill(Color.accentColor)
        } else if emphasized {
            // The centre item stays visually present even when unselected.
            Capsule().fill(Color.primary.opacity(0.08))
        } else {
            Capsule().fill(.clear)
        }
    }
}

#Preview {
    struct Harness: View {
        @State var selection: AppTab = .board
        var body: some View {
            ZStack(alignment: .bottom) {
                Color(.systemGroupedBackground).ignoresSafeArea()
                FloatingTabBar(selection: $selection)
            }
        }
    }
    return Harness()
}
