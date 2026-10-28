import SwiftUI
import UIKit

/// A single row representing a walkthrough (PDF or video). Shows an
/// optional subtitle (e.g. the parent program's name, used when listed
/// under Pinned), a tappable pin icon to pin/unpin, a cloud icon when it's
/// Dropbox-backed and not yet downloaded, and a swipe action as a shortcut
/// to the same pin toggle.
struct WalkthroughRow: View {
    @Environment(\.locale) private var locale
    @EnvironmentObject private var catalogStore: CatalogStore
    @EnvironmentObject private var pinnedStore: PinnedStore
    @EnvironmentObject private var seenStore: SeenStore
    let resource: WalkthroughResource
    var subtitle: String? = nil
    /// The parent program's logo, if it has one -- shown in place of the generic
    /// PDF/video icon (unless this file itself still needs downloading, which
    /// takes priority) so rows read as branded to their program. Only
    /// ProgramDetailView passes this; the Pinned section on the home screen spans
    /// multiple programs and keeps the plain type icon.
    var logo: DropboxFileMetadata? = nil
    /// Identifies the document format and whether a download is needed.
    var showsTypeLabel: Bool = true

    private var isNew: Bool {
        seenStore.isNew(resource.persistenceKey)
    }

    private var isPinned: Bool {
        pinnedStore.isPinned(resource.persistenceKey)
    }

    var body: some View {
        let _ = catalogStore.cacheVersion
        HStack(spacing: 12) {
            rowIcon

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(resource.title)
                        .font(AppStyle.rowTitle)
                        .multilineTextAlignment(.leading)
                    if isNew {
                        Text("New")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.primary.opacity(0.06), in: Capsule())
                            .fixedSize()
                    }
                }
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }
                if showsTypeLabel {
                    Text("\(typeLabelText) · \(needsDownloadIcon ? AppLanguage.string("Download required", locale: locale) : AppLanguage.string("Available offline", locale: locale))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                pinnedStore.toggle(resource.persistenceKey)
            } label: {
                Image(systemName: isPinned ? "bookmark.fill" : "bookmark")
                    .font(.caption)
                    .foregroundStyle(isPinned ? Color("AccentColor") : .secondary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
                    .symbolEffect(.bounce, value: isPinned)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(isPinned ? "Remove Bookmark" : "Bookmark")
        }
        .contentShape(Rectangle())
        .bookmarkAction(resource.persistenceKey)
        .sensoryFeedback(.selection, trigger: isPinned)
        .swipeActions(edge: .leading) {
            Button {
                pinnedStore.toggle(resource.persistenceKey)
            } label: {
                Label(
                    isPinned ? "Remove Bookmark" : "Bookmark",
                    systemImage: isPinned ? "bookmark.slash" : "bookmark"
                )
            }
            .tint(Color("AccentColor"))
        }
    }

    private var iconName: String {
        if case .dropbox(let file) = resource.location, !MediaCache.shared.isCached(file) {
            return "icloud.and.arrow.down"
        }
        switch resource.kind {
        case .pdf:
            return "doc.text.fill"
        case .video:
            return "play.rectangle.fill"
        case .document:
            return "doc.fill"
        }
    }

    /// PDFs use the app's primary maroon accent; videos get a distinct warm
    /// rust tone so file type is readable from the icon color alone, not
    /// just its shape. A file still downloading keeps the primary accent,
    /// since the cloud icon itself already communicates its own state.
    private var iconColor: Color {
        if case .dropbox(let file) = resource.location, !MediaCache.shared.isCached(file) {
            return Color("AccentColor")
        }
        switch resource.kind {
        case .pdf, .document:
            return Color("AccentColor")
        case .video:
            return Color("VideoAccent")
        }
    }

    /// True when this specific file still needs downloading -- takes priority
    /// over showing the program's logo, since that status matters more here
    /// than branding.
    private var needsDownloadIcon: Bool {
        if case .dropbox(let file) = resource.location, !MediaCache.shared.isCached(file) {
            return true
        }
        return false
    }

    @ViewBuilder
    private var rowIcon: some View {
        if !needsDownloadIcon, let logo, let image = cachedLogoImage(logo) {
            image
                .resizable()
                .scaledToFit()
                .frame(width: 20, height: 20)
                .frame(width: 32, height: 32)
                .background(Color("WarmBackground"), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        } else {
            Image(systemName: iconName)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(iconColor)
                .frame(width: 32, height: 32)
                .background(iconColor.opacity(0.15), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }

    private func cachedLogoImage(_ file: DropboxFileMetadata) -> Image? {
        guard let uiImage = LogoImageCache.shared.image(for: file) else {
            return nil
        }
        return Image(uiImage: uiImage)
    }

    private var typeLabelText: String {
        switch resource.kind {
        case .pdf:
            return "PDF"
        case .video:
            return AppLanguage.string("Video", locale: locale)
        case .document:
            return AppLanguage.string("Document", locale: locale)
        }
    }
}
