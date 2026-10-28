import SwiftUI

/// Keep document and guide keys unchanged so existing pins become bookmarks.
enum BookmarkKey {
    static let directory = "bookmark:directory"
    static let links = "bookmark:links"
    static let scan = "bookmark:scan"
    static func program(_ id: String) -> String { "bookmark:program:" + id }
    static func folder(_ id: String) -> String { "bookmark:folder:" + id }
    static func contact(_ id: String) -> String { "bookmark:contact:" + id }
    static func link(_ url: URL) -> String { "bookmark:link:" + url.absoluteString }
    static func device(_ id: String) -> String { "bookmark:device:" + id }
    static func microsoft(_ id: String) -> String { "bookmark:microsoft:" + id }
}

private struct BookmarkAction: ViewModifier {
    @EnvironmentObject private var pinnedStore: PinnedStore
    let key: String

    func body(content: Content) -> some View {
        let saved = pinnedStore.isPinned(key)
        content
            .contextMenu {
                Button {
                    pinnedStore.toggle(key)
                } label: {
                    Label(saved ? "Remove Bookmark" : "Bookmark",
                          systemImage: saved ? "bookmark.slash" : "bookmark")
                }
            }
            .accessibilityAction(named: Text(saved ? "Remove Bookmark" : "Bookmark")) {
                pinnedStore.toggle(key)
            }
    }
}

extension View {
    func bookmarkAction(_ key: String) -> some View {
        modifier(BookmarkAction(key: key))
    }
}
