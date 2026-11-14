import SwiftUI

struct TrainingIntroduction: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phraseIndex = 0

    private let phrases: [LocalizedStringKey] = [
        "All One Safe Team",
        "We Tell It Straight",
        "Zero Punch",
        "We Set the Standard",
        "Passionate for What We Do"
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 16) {
                Image("LogoMark")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 100, height: 64)
                    .foregroundStyle(.white)
                    .accessibilityHidden(true)
                Rectangle()
                    .fill(.white.opacity(0.25))
                    .frame(width: 1, height: 32)
                Text("MAGNUM • FIELD RESOURCES")
                    .font(.caption.weight(.semibold))
                    .tracking(1.4)
                    .foregroundStyle(.white.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
            }
            // All phrases participate in measurement, keeping the resources below steady.
            ZStack(alignment: .leading) {
                ForEach(phrases.indices, id: \.self) { index in
                    Text(phrases[index])
                        .fixedSize(horizontal: false, vertical: true)
                        .opacity(phraseIndex == index ? 1 : 0)
                        .accessibilityHidden(phraseIndex != index)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .multilineTextAlignment(.leading)
            .font(.largeTitle.weight(.bold))
            .foregroundStyle(.white)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.5), value: phraseIndex)
            Rectangle()
                .fill(.white.opacity(0.65))
                .frame(width: 42, height: 3)
                .accessibilityHidden(true)
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            LinearGradient(colors: [AppStyle.brand, AppStyle.charcoal],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        }
        .clipShape(RoundedRectangle(cornerRadius: AppStyle.cornerRadius))
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(4))
                } catch {
                    return
                }
                guard !Task.isCancelled else { return }
                phraseIndex = (phraseIndex + 1) % phrases.count
            }
        }
    }
}

extension View {
    func trainingCard() -> some View {
        self
            .background(AppStyle.surface, in: RoundedRectangle(cornerRadius: AppStyle.cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: AppStyle.cornerRadius, style: .continuous)
                    .strokeBorder(AppStyle.border, lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.04), radius: 5, x: 0, y: 2)
    }
}
