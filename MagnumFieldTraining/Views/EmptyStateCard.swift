import SwiftUI

/// Wraps an empty/error state (typically a ContentUnavailableView) in a
/// soft rounded card with a subtle shadow, so these states read as an
/// intentional part of the design rather than a bare fallback screen.
struct EmptyStateCard<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(24)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color("WarmCard"))
                    .shadow(color: .black.opacity(0.08), radius: 12, y: 4)
            )
            .padding(.horizontal, 32)
    }
}
