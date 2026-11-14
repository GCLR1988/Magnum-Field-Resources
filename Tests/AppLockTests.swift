import Testing
import LocalAuthentication
@testable import AppLock

@MainActor
private final class AuthenticationProbe {
    var attempts = 0
    var pending: CheckedContinuation<Bool, Error>?

    func evaluate(_ context: LAContext) async throws -> Bool {
        attempts += 1
        return try await withCheckedThrowingContinuation { pending = $0 }
    }

    func finish(_ result: Result<Bool, Error>) {
        let continuation = pending
        pending = nil
        continuation?.resume(with: result)
    }

    func waitForAttempt() async {
        for _ in 0..<1_000 where pending == nil { await Task.yield() }
        #expect(pending != nil)
    }
}

@Test @MainActor
func lockedUntilSuccessfulAuthenticationAndRelockedAfterBackground() async {
    let lock = AppLockSession(evaluate: { _ in true })
    #expect(lock.needsCover && !lock.hasOpened)
    await lock.authenticate()
    #expect(!lock.isUnlocked) // Inactive scenes cannot authenticate.
    lock.becameActive()
    await lock.authenticate()
    #expect(lock.isUnlocked && lock.hasOpened && !lock.needsCover)
    lock.becameInactive()
    #expect(lock.needsCover)
    lock.becameActive()
    #expect(!lock.needsCover) // A temporary interruption preserves authentication.
    lock.enteredBackground()
    #expect(lock.needsCover && !lock.isUnlocked && lock.hasOpened)
    lock.becameActive()
    await lock.authenticate()
    #expect(lock.isUnlocked)
}

@Test @MainActor
func cancellationAndFailureStayLockedAndAllowExplicitRetry() async {
    var attempts = 0
    let lock = AppLockSession { _ in
        attempts += 1
        if attempts == 1 { throw LAError(.userCancel) }
        if attempts == 2 { return false }
        return true
    }
    lock.becameActive()
    await lock.authenticate()
    #expect(!lock.isUnlocked && !lock.hasOpened && lock.message != nil)
    await Task.yield() // The queued activation must not prompt again after cancel.
    #expect(attempts == 1)
    await lock.authenticate()
    #expect(!lock.isUnlocked && !lock.isAuthenticating)
    await lock.authenticate()
    #expect(lock.isUnlocked && lock.message == nil)
}

@Test @MainActor
func missingDevicePasscodeShowsSetupMessage() async {
    let lock = AppLockSession { _ in throw LAError(.passcodeNotSet) }
    lock.becameActive()
    await lock.authenticate()
    #expect(!lock.isUnlocked && lock.needsCover)
    #expect(lock.message == AppLanguage.string("Set a device passcode in Settings before using this app."))
}

@Test @MainActor
func duplicateRequestsAreSuppressedAndInactiveSuccessRemainsCovered() async {
    let probe = AuthenticationProbe()
    let lock = AppLockSession(evaluate: probe.evaluate)
    lock.becameActive()
    await probe.waitForAttempt()
    await lock.authenticate()
    #expect(probe.attempts == 1)
    lock.becameInactive()
    probe.finish(.success(true))
    for _ in 0..<1_000 where lock.isAuthenticating { await Task.yield() }
    #expect(lock.isUnlocked && lock.needsCover)
    lock.becameActive()
    #expect(!lock.needsCover && probe.attempts == 1)
}

@Test @MainActor
func backgroundInvalidatesLateSuccessAndAllowsFreshAuthentication() async {
    let probe = AuthenticationProbe()
    let lock = AppLockSession(evaluate: probe.evaluate)
    lock.becameActive()
    await probe.waitForAttempt()
    lock.enteredBackground()
    probe.finish(.success(true))
    for _ in 0..<20 { await Task.yield() }
    #expect(!lock.isUnlocked && !lock.hasOpened && lock.needsCover)
    lock.becameActive()
    await probe.waitForAttempt()
    #expect(probe.attempts == 2)
    probe.finish(.success(true))
    for _ in 0..<1_000 where lock.isAuthenticating { await Task.yield() }
    #expect(lock.isUnlocked && !lock.needsCover)
}

@Test @MainActor
func staleCompletionCannotClearANewerAuthenticationAttempt() async {
    let probe = AuthenticationProbe()
    let lock = AppLockSession(evaluate: probe.evaluate)
    lock.becameActive()
    await probe.waitForAttempt()
    let oldAttempt = probe.pending
    probe.pending = nil
    lock.enteredBackground()
    lock.becameActive()
    await probe.waitForAttempt()
    oldAttempt?.resume(returning: true)
    for _ in 0..<20 { await Task.yield() }
    #expect(!lock.isUnlocked && lock.isAuthenticating && lock.needsCover)
    probe.finish(.success(true))
    for _ in 0..<1_000 where lock.isAuthenticating { await Task.yield() }
    #expect(lock.isUnlocked && !lock.isAuthenticating)
}
