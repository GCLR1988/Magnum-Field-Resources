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
        VStack(alignment: .leading, spacing: 16) {
            Text("MAGNUM • FIELD RESOURCES")
                .font(.caption.weight(.bold))
                .tracking(2)
                .foregroundStyle(.white.opacity(0.8))
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
            // Keep every phrase in layout so wrapping never shifts the cards below.
            ZStack {
                ForEach(phrases.indices, id: \.self) { index in
                    Text(phrases[index])
                        .fixedSize(horizontal: false, vertical: true)
                        .opacity(phraseIndex == index ? 1 : 0)
                        .accessibilityHidden(phraseIndex != index)
                }
            }
            .frame(maxWidth: .infinity)
            .multilineTextAlignment(.center)
            .font(.largeTitle.weight(.bold))
            .foregroundStyle(.white)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.5), value: phraseIndex)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [Color(red: 0.24, green: 0.10, blue: 0.14), Color(red: 0.12, green: 0.13, blue: 0.17)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 24)
        )
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
            .shadow(color: .black.opacity(0.035), radius: 8, x: 0, y: 3)
    }
}
