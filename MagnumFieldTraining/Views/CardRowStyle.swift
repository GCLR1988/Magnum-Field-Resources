import SwiftUI

/// Shared brand iconography for resource tiles and sidebar rows.
struct ResourceIconTheme {
    let symbol: String
    let base: Color
    let highlight: Color

    static func forName(_ name: String) -> ResourceIconTheme {
        let title = name.lowercased()
        if title == "my forms & templates" {
            return theme("doc.on.doc", 0x256343, 0x4C9B6B)
        }
        if title.contains("weekly") && title.contains("safety") {
            return theme("checkmark.shield", 0x78232F, 0xAA4655)
        }
        if title.contains("safety") || title.contains("inspection") {
            return theme("checklist", 0x79562E, 0xAB854A)
        }
        if title.contains("payroll") || title.contains("time") {
            return theme("calendar.badge.clock", 0x2D4E6B, 0x52789A)
        }
        if title.contains("directory") || title.contains("contact") || title.contains("team") {
            return theme("person.2", 0x65506F, 0x92749F)
        }
        if title.contains("link") {
            return theme("link", 0x1D6266, 0x438B90)
        }
        if title.contains("scan") {
            return theme("viewfinder", 0x8B4336, 0xB96B55)
        }
        if title.contains("training") || title.contains("guide") || title.contains("device") {
            return theme("books.vertical", 0x3E424C, 0x6C7180)
        }
        if title.contains("iphone") || title.contains("ipad") {
            return theme(title.contains("ipad") ? "ipad" : "iphone", 0x3E424C, 0x6C7180)
        }
        if title.contains("form") {
            return theme("doc.text", 0x78232F, 0xAA4655)
        }
        if title.contains("video") {
            return theme("play.rectangle", 0x65506F, 0x92749F)
        }
        return theme("folder", 0x78232F, 0xAA4655)
    }

    private static func theme(_ symbol: String, _ base: UInt32, _ highlight: UInt32) -> ResourceIconTheme {
        ResourceIconTheme(symbol: symbol, base: color(base), highlight: color(highlight))
    }

    private static func color(_ hex: UInt32) -> Color {
        Color(red: Double((hex >> 16) & 255) / 255,
              green: Double((hex >> 8) & 255) / 255,
              blue: Double(hex & 255) / 255)
    }
}

/// Simple vector symbols on quiet tinted surfaces stay crisp at every size.
struct ResourceFolderIcon: View {
    @Environment(\.colorScheme) private var colorScheme
    let name: String
    var compact = false
    var isSubfolder = false

    var body: some View {
        let theme = ResourceIconTheme.forName(name)
        let side: CGFloat = compact ? 32 : 56
        let shape = RoundedRectangle(cornerRadius: compact ? 6 : 10, style: .continuous)
        ZStack {
            shape.fill(theme.base.opacity(0.10))
            Image(systemName: theme.symbol)
                .symbolRenderingMode(.hierarchical)
                .font(.system(size: compact ? 17 : 26, weight: .medium))
                .foregroundStyle(colorScheme == .dark ? theme.highlight : theme.base)
        }
        .frame(width: side, height: side)
        .overlay {
            shape.strokeBorder(theme.base.opacity(0.12), lineWidth: 1)
        }
        .accessibilityHidden(true)
    }
}

/// A shared surface and subtle separators let the List group related documents.
extension View {
    func documentRowStyle() -> some View {
        self
            .font(AppStyle.rowTitle)
            .listRowBackground(AppStyle.surface)
            .listRowSeparator(.visible)
            .listRowSeparatorTint(AppStyle.border)
            .listRowInsets(EdgeInsets(top: 14, leading: AppStyle.inset, bottom: 14, trailing: AppStyle.inset))
    }
}

#Preview("Resource icon colors", traits: .sizeThatFitsLayout) {
    HStack(spacing: 16) {
        ResourceFolderIcon(name: "Company Directory")
        ResourceFolderIcon(name: "Downloadable Forms")
        ResourceFolderIcon(name: "Training Resources")
        ResourceFolderIcon(name: "Safety")
        ResourceFolderIcon(name: "Useful Links")
    }
    .padding(24)
    .background(Color("WarmBackground"))
}
