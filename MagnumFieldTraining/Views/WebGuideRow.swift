import SwiftUI

struct WebGuideRow: View {
    @Environment(\.locale) private var locale
    @EnvironmentObject private var pinnedStore: PinnedStore
    @Environment(\.openURL) private var openURL
    @State private var couldNotOpen = false
    let guide: WebGuide
    var showsDetails: Bool = true

    private var isPinned: Bool { pinnedStore.isPinned(guide.id) }

    private func localized(_ resource: LocalizedStringResource) -> LocalizedStringResource {
        var value = resource
        value.locale = locale
        return value
    }

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Button {
                openURL(guide.url) { accepted in
                    if accepted {
                        RecentStore.shared.record(guide.id)
                    } else {
                        couldNotOpen = true
                    }
                }
            } label: {
                HStack(alignment: .top, spacing: 14) {
                    Image(systemName: guide.symbol)
                        .font(.title3)
                        .foregroundStyle(Color("AccentColor"))
                        .frame(width: 32, height: 32)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(localized(guide.title))
                            .font(.headline)
                            .foregroundStyle(.primary)
                        if showsDetails {
                            Text(localized(guide.detail))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Text("\(guide.collection) · Website · Internet required")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: "arrow.up.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
                .padding(.vertical, 6)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens the guide in your browser")
            Button {
                pinnedStore.toggle(guide.id)
            } label: {
                Image(systemName: isPinned ? "bookmark.fill" : "bookmark")
                    .foregroundStyle(isPinned ? Color("AccentColor") : .secondary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(isPinned ? "Remove Bookmark" : "Bookmark")
        }
        .bookmarkAction(guide.id)
        .alert("Unable to open guide", isPresented: $couldNotOpen) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Please try again. This guide opens on the publisher's website.")
        }
    }
}
