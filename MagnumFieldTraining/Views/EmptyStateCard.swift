import SwiftUI

/// Keeps empty states readable without an oversized card or decorative shadow.
struct EmptyStateCard<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(24)
            .frame(maxWidth: 380)
            .trainingCard()
            .padding(.horizontal, 24)
    }
}

struct EmptyStateMessage: View {
    let title: LocalizedStringKey
    let systemImage: String
    let message: Text

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 32, weight: .regular))
                .foregroundStyle(AppStyle.accent)
                .frame(width: 64, height: 64)
                .background(AppStyle.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: AppStyle.cornerRadius))
                .accessibilityHidden(true)
            Text(title)
                .font(.headline)
            message
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .multilineTextAlignment(.center)
    }
}

struct StatusNotice: View {
    let message: Text
    let systemImage: String
    var isError = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: systemImage)
                .foregroundStyle(isError ? Color.red : Color.secondary)
                .frame(width: 20)
                .accessibilityHidden(true)
            message
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .font(.footnote)
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .frame(maxWidth: 720)
        .frame(maxWidth: .infinity)
        .background(Color("WarmCard"))
        .overlay(alignment: .top) {
            Divider().opacity(0.5)
        }
    }
}
