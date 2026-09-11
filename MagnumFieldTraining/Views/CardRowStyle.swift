import SwiftUI

/// Styles a List row as a soft rounded card sitting on the warm background,
/// with breathing room between rows, instead of Apple's default flat,
/// edge-to-edge list-row look.
extension View {
    func cardRowStyle() -> some View {
        self
            .listRowBackground(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color("WarmCard"))
                    .padding(.vertical, 4)
            )
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
    }
}
