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
    }

    // **Superseded: there was a gradient behind the bar.** It faded the window
    // background in beneath the capsule so list rows scrolling under would
    // dissolve rather than peek through the gutters either side of it.
    //
    // It was wrong in three ways at once, and the map made all three obvious:
    // it painted *opaque* `systemBackground`, so it hid whatever was behind it
    // rather than softening it; it spanned the full width, well past the
    // capsule it was meant to sit behind; and it ended at the bar's own bottom
    // edge instead of the screen's, leaving a hard horizontal seam with content
    // visible below it. On a white list it was invisible and seemed fine. Over
    // the map it read as a band across the screen.
    //
    // The bar is a floating pill over the content — that is the whole idea
    // (DESIGN.md §5) — so it should draw nothing outside its own capsule. The
    // capsule's own `.regularMaterial` is what separates it from what's behind.

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
