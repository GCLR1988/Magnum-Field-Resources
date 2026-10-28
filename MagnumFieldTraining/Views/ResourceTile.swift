import SwiftUI

/// Shared text slots keep every folder tile the same height, including tiles without a subtitle.
struct ResourceTile<Icon: View>: View {
    let title: String
    var subtitle: String? = nil
    @ViewBuilder let icon: () -> Icon
    @ScaledMetric(relativeTo: .headline) private var titleHeight: CGFloat = 66
    @ScaledMetric(relativeTo: .caption) private var subtitleHeight: CGFloat = 34

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                icon()
                    .frame(width: 56, height: 56)
                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .frame(height: 56, alignment: .top)
            Text(title)
                .font(.headline)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.leading)
                .lineLimit(3)
                .frame(height: titleHeight, alignment: .topLeading)
            Text(subtitle ?? "")
                .font(AppStyle.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.leading)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: subtitleHeight, alignment: .topLeading)
                .accessibilityHidden(subtitle?.isEmpty != false)
        }
        .padding(AppStyle.inset)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .trainingCard()
        .contentShape(RoundedRectangle(cornerRadius: AppStyle.cornerRadius))
        .accessibilityElement(children: .combine)
    }
}

/// Responds to the actual content width, including rotation and split-screen resizing.
/// An incomplete final row keeps the same column widths as the rows above it.
struct ResourceTileGrid<Content: View>: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .headline) private var minimumTileWidth: CGFloat = 150
    @ViewBuilder let content: () -> Content

    var body: some View {
        LazyVGrid(
            columns: dynamicTypeSize.isAccessibilitySize
                ? [GridItem(.flexible(), spacing: 12)]
                : [GridItem(.adaptive(minimum: minimumTileWidth), spacing: 12)],
            alignment: .leading,
            spacing: 12,
            content: content
        )
    }
}

/// Prefer the folder's supplied artwork everywhere it appears.
struct FolderArtwork: View {
    @EnvironmentObject private var catalogStore: CatalogStore
    let name: String
    let logo: DropboxFileMetadata?
    var compact = false
    var isSubfolder = false

    var body: some View {
        let _ = catalogStore.cacheVersion
        Group {
            if let logo, let image = LogoImageCache.shared.image(for: logo) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: compact ? 28 : 44, height: compact ? 28 : 44)
                    .scaleEffect(name.caseInsensitiveCompare("Procore") == .orderedSame ? 1.65 : 1)
                    .frame(width: compact ? 32 : 56, height: compact ? 32 : 56)
                    .clipped()
                    .background {
                        let theme = ResourceIconTheme.forName(name)
                        RoundedRectangle(cornerRadius: compact ? 9 : 16)
                            .fill(LinearGradient(
                                colors: [theme.highlight.opacity(0.12), theme.base.opacity(0.06)],
                                startPoint: .topLeading, endPoint: .bottomTrailing
                            ))
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: compact ? 9 : 16)
                            .strokeBorder(ResourceIconTheme.forName(name).base.opacity(0.15), lineWidth: 0.75)
                    }
            } else {
                ResourceFolderIcon(name: name, compact: compact, isSubfolder: isSubfolder)
            }
        }
        .accessibilityHidden(true)
    }
}

extension View {
    func resourceGridRow() -> some View {
        self
            .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 8, trailing: 0))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
    }
}
