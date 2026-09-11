import SwiftUI

/// Full-screen splash shown while the very first Dropbox sync is in flight, so a
/// foreman sees the Magnum logo instead of a flash of "No Programs Yet" in the
/// moment between the app appearing and that first `syncAll()` populating the
/// program list. ContentView fades this OUT once that first sync completes.
///
/// Renders at full opacity immediately -- no fade-in of its own. It matches the
/// native launch screen's WarmBackground/LogoMark exactly (see the target's
/// Info.plist build settings), so the two hand off with nothing showing through
/// in between. A self fade-in would briefly blend this view with whatever sits
/// behind it in ContentView's ZStack (i.e. "No Programs Yet" before the first
/// sync populates the list), which is exactly the flash this view exists to hide.
struct SplashView: View {
    var body: some View {
        Color("WarmBackground")
            .ignoresSafeArea()
            .overlay {
                Image("LogoMark")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 220, height: 220)
            }
    }
}

#Preview {
    SplashView()
}
