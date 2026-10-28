import SwiftUI

/// Shared visual values keep resource screens consistent in light and dark appearances.
enum AppStyle {
    static let accent = Color("AccentColor")
    static let background = Color("WarmBackground")
    static let surface = Color("WarmCard")
    static let border = Color.primary.opacity(0.08)
    static let cornerRadius: CGFloat = 18
    static let inset: CGFloat = 16
    static let sectionSpacing: CGFloat = 20
    static let rowTitle = Font.body.weight(.medium)
    static let caption = Font.caption
}

/// Keeps navigation native while giving custom resource buttons visible touch feedback.
struct ResourcePressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(isEnabled ? (configuration.isPressed ? 0.82 : 1) : 0.45)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: configuration.isPressed)
    }
}

struct ResourceLoadingView: View {
    let title: LocalizedStringKey

    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.large)
                .tint(AppStyle.accent)
            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(28)
        .frame(maxWidth: 320)
        .trainingCard()
        .padding(24)
        .accessibilityElement(children: .combine)
    }
}
