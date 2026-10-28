import SwiftUI
import LocalAuthentication
import Security
import Observation

struct AppLockView: View {
    @State private var lock = AppLockSession()

    var body: some View {
        ZStack {
            Color("WarmBackground").ignoresSafeArea()
            // Once created, this subtree stays alive behind the separate lock window.
            if lock.hasOpened {
                ContentView()
            }
        }
        .background(AppLockWindowBridge(lock: lock, needsCover: lock.needsCover))
    }
}

@MainActor
@Observable
final class AppLockSession {
    private(set) var hasOpened = false
    private(set) var isUnlocked = false
    private(set) var isAuthenticating = false
    private(set) var isSceneActive = false
    private(set) var message: String?
    private var shouldPrompt = true
    @ObservationIgnored private var context: LAContext?
    @ObservationIgnored private var requestID = UUID()
    @ObservationIgnored private let evaluate: @MainActor (LAContext) async throws -> Bool

    init(evaluate: @escaping @MainActor (LAContext) async throws -> Bool = AppLockSession.evaluateDevicePasscode) {
        self.evaluate = evaluate
    }

    var needsCover: Bool { !isUnlocked || !isSceneActive }

    func becameInactive() {
        isSceneActive = false
    }

    func enteredBackground() {
        isSceneActive = false
        requestID = UUID()
        context?.invalidate()
        context = nil
        isAuthenticating = false
        isUnlocked = false
        shouldPrompt = true
        message = nil
    }

    func becameActive() {
        isSceneActive = true
        if shouldPrompt {
            Task { await authenticate() }
        }
    }

    func authenticate() async {
        guard isSceneActive, !isUnlocked, !isAuthenticating else { return }
        shouldPrompt = false
        isAuthenticating = true
        message = nil
        let id = UUID()
        requestID = id
        let newContext = LAContext()
        newContext.localizedCancelTitle = AppLanguage.string("Cancel")
        context = newContext
        defer {
            if requestID == id {
                isAuthenticating = false
                context = nil
            }
            newContext.invalidate()
        }

        do {
            let success = try await evaluate(newContext)
            // Backgrounding changes the request ID; late authentication cannot unlock the app.
            guard requestID == id else { return }
            isUnlocked = success
            if success { hasOpened = true }
            else { message = AppLanguage.string("The app is locked. Tap Unlock to try again.") }
        } catch {
            guard requestID == id else { return }
            let code = (error as NSError).code
            message = code == LAError.passcodeNotSet.rawValue
                ? AppLanguage.string("Set a device passcode in Settings before using this app.")
                : AppLanguage.string("The app is locked. Tap Unlock to try again.")
        }
    }

    private static func evaluateDevicePasscode(_ context: LAContext) async throws -> Bool {
        var policyError: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &policyError) else {
            throw policyError ?? LAError(.authenticationFailed)
        }
        var accessError: Unmanaged<CFError>?
        guard let access = SecAccessControlCreateWithFlags(
            nil, kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly, .devicePasscode, &accessError
        ) else {
            throw LAError(.invalidContext)
        }
        return try await context.evaluateAccessControl(
            access, operation: .useItem,
            localizedReason: AppLanguage.string("Enter your device passcode to unlock Magnum Field Resources.")
        )
    }
}

private struct AppLockScreen: View {
    let lock: AppLockSession

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "lock.shield")
                .font(.system(size: 48))
                .foregroundStyle(Color.accentColor)
            Text("Magnum Field Resources").font(.title2.bold())
            if !lock.isUnlocked {
                Text(lock.message ?? AppLanguage.string("Enter your device passcode to open the app."))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button("Unlock") { Task { await lock.authenticate() } }
                    .buttonStyle(.borderedProminent)
                    .disabled(lock.isAuthenticating || !lock.isSceneActive)
                if lock.isAuthenticating { ProgressView() }
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color("WarmBackground").ignoresSafeArea())
    }
}

/// A separate scene-local window covers the entire hierarchy, including existing modal sheets.
private struct AppLockWindowBridge: UIViewRepresentable {
    let lock: AppLockSession
    let needsCover: Bool

    func makeUIView(context: Context) -> AppLockAnchor {
        AppLockAnchor(lock: lock)
    }

    func updateUIView(_ uiView: AppLockAnchor, context: Context) {
        let _ = lock.needsCover
        uiView.updateCover()
    }

    static func dismantleUIView(_ uiView: AppLockAnchor, coordinator: ()) {
        uiView.tearDown()
    }
}

private final class AppLockAnchor: UIView {
    private let lock: AppLockSession
    private var coverWindow: UIWindow?
    private weak var contentWindow: UIWindow?

    init(lock: AppLockSession) {
        self.lock = lock
        super.init(frame: .zero)
        NotificationCenter.default.addObserver(self, selector: #selector(deactivate(_:)),
                                               name: UIScene.willDeactivateNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(background(_:)),
                                               name: UIScene.didEnterBackgroundNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(activate(_:)),
                                               name: UIScene.didActivateNotification, object: nil)
    }

    required init?(coder: NSCoder) { return nil }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard coverWindow == nil, let window, let scene = window.windowScene else { return }
        contentWindow = window
        let cover = UIWindow(windowScene: scene)
        cover.windowLevel = .alert + 1
        cover.rootViewController = UIHostingController(rootView: AppLockScreen(lock: lock).modifier(AppLanguageModifier()))
        coverWindow = cover
        // Conceal immediately; defer observable state changes outside the representable update.
        cover.isHidden = false
        Task { @MainActor [weak self] in
            guard let self else { return }
            if scene.activationState == .foregroundActive { self.lock.becameActive() }
            self.updateCover()
        }
    }

    private func belongsToScene(_ notification: Notification) -> Bool {
        guard let scene = notification.object as? UIScene else { return false }
        return scene === contentWindow?.windowScene
    }

    @objc private func deactivate(_ notification: Notification) {
        guard belongsToScene(notification) else { return }
        lock.becameInactive()
        updateCover()
    }

    @objc private func background(_ notification: Notification) {
        guard belongsToScene(notification) else { return }
        lock.enteredBackground()
        updateCover()
    }

    @objc private func activate(_ notification: Notification) {
        guard belongsToScene(notification) else { return }
        lock.becameActive()
        updateCover()
    }

    func updateCover() {
        guard let coverWindow else { return }
        if lock.needsCover {
            contentWindow?.endEditing(true)
            coverWindow.isHidden = false
            if lock.isSceneActive && !coverWindow.isKeyWindow {
                coverWindow.makeKey()
            }
        } else {
            let restoreKey = coverWindow.isKeyWindow
            coverWindow.isHidden = true
            if restoreKey { contentWindow?.makeKey() }
        }
    }

    func tearDown() {
        coverWindow?.isHidden = true
        coverWindow = nil
        NotificationCenter.default.removeObserver(self)
    }

    deinit { NotificationCenter.default.removeObserver(self) }
}
