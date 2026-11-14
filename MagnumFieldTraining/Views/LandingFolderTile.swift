import SwiftUI

/// Quiet category tints keep the landing page distinct without heavy blocks of color.
struct LandingFolderTile: View {
    let name: String
    let title: String
    var subtitle: String?
    var logo: DropboxFileMetadata?
    @Environment(\.colorScheme) private var colorScheme
    @ScaledMetric(relativeTo: .headline) private var titleHeight: CGFloat = 68

    var body: some View {
        let theme = ResourceIconTheme.forName(name)
        let iconColor = colorScheme == .dark ? theme.highlight : theme.base
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)

        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .center) {
                if logo != nil {
                    FolderArtwork(name: name, logo: logo)
                } else {
                    Image(systemName: theme.symbol)
                        .font(.system(size: 30, weight: .regular))
                        .symbolRenderingMode(.monochrome)
                        .foregroundStyle(iconColor)
                        .frame(width: 44, height: 44, alignment: .leading)
                        .accessibilityHidden(true)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(iconColor.opacity(0.75))
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(minHeight: titleHeight, alignment: .topLeading)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background {
            shape.fill(AppStyle.surface)
            shape.fill(theme.base.opacity(colorScheme == .dark ? 0.18 : 0.08))
        }
        .overlay {
            shape.strokeBorder(iconColor.opacity(colorScheme == .dark ? 0.24 : 0.12), lineWidth: 1)
        }
        .contentShape(shape)
        .accessibilityElement(children: .combine)
    }
}
