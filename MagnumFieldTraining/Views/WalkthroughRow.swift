import SwiftUI
import UIKit

/// A single row representing a walkthrough (PDF or video). Shows an
/// optional subtitle (e.g. the parent program's name, used when listed
/// under Pinned), a tappable pin icon to pin/unpin, a cloud icon when it's
/// Dropbox-backed and not yet downloaded, and a swipe action as a shortcut
/// to the same pin toggle.
struct WalkthroughRow: View {
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
    /// Small grey "PDF"/"Video" caption under the title. Off by default so the
    /// Pinned section's look is unchanged; ProgramDetailView turns it on.
    var showsTypeLabel: Bool = false

    private var isNew: Bool {
        seenStore.isNew(resource.persistenceKey)
    }

    private var isPinned: Bool {
        pinnedStore.isPinned(resource.persistenceKey)
    }

    var body: some View {
        HStack(spacing: 12) {
            rowIcon

            VStack(alignment: .center, spacing: 2) {
                HStack(spacing: 6) {
                    Text(resource.title)
                        .multilineTextAlignment(.center)
                    if isNew {
                        Text("NEW")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color("AccentColor"), in: Capsule())
                    }
                }
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                if showsTypeLabel {
                    Text(typeLabelText)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity)

            Button {
                pinnedStore.toggle(resource.persistenceKey)
            } label: {
                Image(systemName: isPinned ? "pin.fill" : "pin")
                    .font(.caption)
                    .foregroundStyle(isPinned ? Color("AccentColor") : .secondary)
                    .frame(width: 24, height: 24)
                    .symbolEffect(.bounce, value: isPinned)
            }
            .buttonStyle(.borderless)
        }
        .contentShape(Rectangle())
        .swipeActions(edge: .leading) {
            Button {
                pinnedStore.toggle(resource.persistenceKey)
            } label: {
                Label(
                    isPinned ? "Unpin" : "Pin",
                    systemImage: isPinned ? "pin.slash" : "pin"
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
        case .pdf:
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
                .background(Color("WarmBackground"), in: Circle())
        } else {
            Image(systemName: iconName)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(iconColor)
                .frame(width: 32, height: 32)
                .background(iconColor.opacity(0.15), in: Circle())
        }
    }

    private func cachedLogoImage(_ file: DropboxFileMetadata) -> Image? {
        guard MediaCache.shared.isCached(file),
              let uiImage = UIImage(contentsOfFile: MediaCache.shared.localURL(for: file).path) else {
            return nil
        }
        return Image(uiImage: uiImage)
    }

    private var typeLabelText: String {
        switch resource.kind {
        case .pdf:
            return "PDF"
        case .video:
            return "Video"
        }
    }
}
