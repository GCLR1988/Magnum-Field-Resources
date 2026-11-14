import SwiftUI

/// Shared text slots keep every folder tile the same height, including tiles without a subtitle.
struct ResourceTile<Icon: View>: View {
    let title: String
    var subtitle: String? = nil
    @ViewBuilder let icon: () -> Icon
    @ScaledMetric(relativeTo: .headline) private var titleHeight: CGFloat = 66

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                icon()
                    .frame(width: 56, height: 56)
                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppStyle.accent)
                    .padding(8)
                    .background(AppStyle.accent.opacity(0.06), in: Circle())
                    .accessibilityHidden(true)
            }
            .frame(height: 56, alignment: .top)
            Text(title)
                .font(.headline)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.leading)
                .lineLimit(3)
                .frame(height: titleHeight, alignment: .topLeading)
            Rectangle()
                .fill(AppStyle.border)
                .frame(height: 1)
                .accessibilityHidden(true)
            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(AppStyle.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(AppStyle.inset)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .trainingCard()
        .contentShape(RoundedRectangle(cornerRadius: AppStyle.cornerRadius))
        .accessibilityElement(children: .combine)
    }
}

/// Compact subfolder cards keep the name and count together without reserved empty title space.
struct SubfolderTile: View {
    let name: String
    let subtitle: String
    let logo: DropboxFileMetadata?
    @Environment(\.colorScheme) private var colorScheme

    private var theme: ResourceIconTheme {
        switch name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "field":
            let palette = ResourceIconTheme.forName("Forms")
            return ResourceIconTheme(symbol: "hammer", base: palette.base, highlight: palette.highlight)
        case "office":
            let palette = ResourceIconTheme.forName("Payroll")
            return ResourceIconTheme(symbol: "building.2", base: palette.base, highlight: palette.highlight)
        default:
            return ResourceIconTheme.forName(name)
        }
    }

    var body: some View {
        let tint = colorScheme == .dark ? theme.highlight : theme.base
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)

        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .center) {
                if logo != nil {
                    FolderArtwork(name: name, logo: logo, compact: true, isSubfolder: true)
                } else {
                    Image(systemName: theme.symbol)
                        .font(.system(size: 28, weight: .regular))
                        .foregroundStyle(tint)
                        .frame(width: 36, height: 36, alignment: .leading)
                        .accessibilityHidden(true)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(tint.opacity(0.7))
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 5) {
                Text(name)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .multilineTextAlignment(.leading)
        }
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: 144, maxHeight: .infinity, alignment: .topLeading)
        .background {
            shape.fill(AppStyle.surface)
            shape.fill(theme.base.opacity(colorScheme == .dark ? 0.16 : 0.055))
        }
        .overlay {
            shape.strokeBorder(tint.opacity(colorScheme == .dark ? 0.28 : 0.15), lineWidth: 1)
        }
        .contentShape(shape)
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
        ResourceGridLayout(
            minimumTileWidth: minimumTileWidth,
            singleColumn: dynamicTypeSize.isAccessibilitySize
        ) {
            content()
        }
    }
}

/// These small grids live inside List rows. Lay out every card eagerly so nested
/// lazy containers cannot discard visible cards while the row is measured.
private struct ResourceGridLayout: Layout {
    let minimumTileWidth: CGFloat
    let singleColumn: Bool
    private let spacing: CGFloat = 12

    private func metrics(width: CGFloat?, subviews: Subviews) -> (width: CGFloat, columns: Int, tileWidth: CGFloat, rowHeight: CGFloat) {
        let availableWidth = max(0, width?.isFinite == true ? (width ?? minimumTileWidth) : minimumTileWidth)
        let columns = singleColumn ? 1 : max(1, Int((availableWidth + spacing) / (minimumTileWidth + spacing)))
        let tileWidth = max(0, (availableWidth - CGFloat(columns - 1) * spacing) / CGFloat(columns))
        let proposal = ProposedViewSize(width: tileWidth, height: nil)
        let rowHeight = subviews.map { $0.sizeThatFits(proposal).height }.max() ?? 0
        return (availableWidth, columns, tileWidth, rowHeight)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard !subviews.isEmpty else { return .zero }
        let metrics = metrics(width: proposal.width, subviews: subviews)
        let rows = (subviews.count + metrics.columns - 1) / metrics.columns
        return CGSize(width: metrics.width, height: CGFloat(rows) * metrics.rowHeight + CGFloat(rows - 1) * spacing)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let metrics = metrics(width: bounds.width, subviews: subviews)
        let tileProposal = ProposedViewSize(width: metrics.tileWidth, height: metrics.rowHeight)
        for (index, subview) in subviews.enumerated() {
            subview.place(
                at: CGPoint(
                    x: bounds.minX + CGFloat(index % metrics.columns) * (metrics.tileWidth + spacing),
                    y: bounds.minY + CGFloat(index / metrics.columns) * (metrics.rowHeight + spacing)
                ),
                anchor: .topLeading,
                proposal: tileProposal
            )
        }
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
