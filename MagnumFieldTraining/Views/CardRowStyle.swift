import SwiftUI

/// One coordinated color family per resource category, shared by tiles and sidebar icons.
struct ResourceIconTheme {
    let symbol: String
    let base: Color
    let highlight: Color

    static func forName(_ name: String) -> ResourceIconTheme {
        let title = name.lowercased()
        if title.contains("directory") || title.contains("contact") || title.contains("employee") || title.contains("team") {
            return theme("person.crop.rectangle.fill", 0x125C73, 0x268F9C)
        }
        if title.contains("form") {
            return theme("doc.text.fill", 0x59379A, 0x9371D2)
        }
        if title.contains("safety") || title.contains("inspection") {
            return theme("checkmark.shield.fill", 0xA44D19, 0xE38A36)
        }
        if title.contains("link") {
            return theme("link", 0x086A62, 0x2B9B85)
        }
        if title.contains("training") || title.contains("guide") || title.contains("start") || title.contains("basic") {
            return theme("books.vertical.fill", 0x23499A, 0x5889D6)
        }
        if title.contains("iphone") || title.contains("ipad") || title.contains("device") {
            return theme(title.contains("ipad") ? "ipad" : "iphone", 0x3B526D, 0x7097B2)
        }
        if title.contains("time") || title.contains("payroll") {
            return theme("clock.badge.checkmark.fill", 0x975520, 0xCE9754)
        }
        if title.contains("schedule") || title.contains("calendar") {
            return theme("calendar", 0xA23852, 0xDA7289)
        }
        if title.contains("plan") || title.contains("drawing") || title.contains("blueprint") {
            return theme("ruler.fill", 0x205F9A, 0x47A2C4)
        }
        if title.contains("tool") || title.contains("equipment") {
            return theme("wrench.and.screwdriver.fill", 0x92512A, 0xCF8B55)
        }
        if title.contains("photo") || title.contains("image") {
            return theme("photo.on.rectangle.angled", 0x76509C, 0xAF88CA)
        }
        if title.contains("video") {
            return theme("play.rectangle.fill", 0x9B3F72, 0xD77DA4)
        }
        if title.contains("report") || title.contains("daily") {
            return theme("chart.bar.doc.horizontal.fill", 0x126B7F, 0x4CA0B1)
        }
        if title.contains("estimate") || title.contains("budget") || title.contains("cost") {
            return theme("chart.pie.fill", 0x2F7251, 0x70AD7C)
        }
        if title.contains("request") || title.contains("rfi") {
            return theme("bubble.left.and.bubble.right.fill", 0x4267A0, 0x8BADD5)
        }
        if title.contains("checklist") || title.contains("policy") || title.contains("policies") {
            return theme("checklist", 0x357151, 0x79A989)
        }
        if title.contains("newsletter") || title.contains("news") {
            return theme("newspaper.fill", 0x6F4586, 0xAF80BC)
        }
        // Unclassified folders use the Magnum burgundy family.
        return theme("folder.fill", 0x70263B, 0xB5677B)
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

/// Layered vector artwork stays crisp at both tile and sidebar sizes.
struct ResourceFolderIcon: View {
    let name: String
    var compact = false
    var isSubfolder = false

    var body: some View {
        let theme = ResourceIconTheme.forName(name)
        let side: CGFloat = compact ? 32 : 56
        let shape = RoundedRectangle(cornerRadius: compact ? 9 : 16, style: .continuous)
        ZStack {
            shape.fill(LinearGradient(colors: [theme.highlight, theme.base],
                                      startPoint: .topLeading, endPoint: .bottomTrailing))
            Circle()
                .fill(.white.opacity(0.12))
                .frame(width: side * 0.95, height: side * 0.95)
                .offset(x: -side * 0.3, y: -side * 0.35)
            Circle()
                .strokeBorder(.white.opacity(0.10), lineWidth: compact ? 3 : 5)
                .frame(width: side * 0.85, height: side * 0.85)
                .offset(x: side * 0.4, y: side * 0.4)
            Image(systemName: theme.symbol)
                .symbolRenderingMode(.hierarchical)
                .font(.system(size: compact ? 16 : 27, weight: .medium))
                .foregroundStyle(.white)
                .shadow(color: theme.base.opacity(0.35), radius: 1, x: 0, y: 1)
        }
        .frame(width: side, height: side)
        .clipShape(shape)
        .overlay {
            shape.strokeBorder(
                LinearGradient(colors: [.white.opacity(0.45), .white.opacity(0.05)],
                               startPoint: .topLeading, endPoint: .bottomTrailing),
                lineWidth: 0.75
            )
        }
        .shadow(color: theme.base.opacity(compact ? 0.12 : 0.22),
                radius: compact ? 2 : 4, x: 0, y: compact ? 1 : 3)
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
