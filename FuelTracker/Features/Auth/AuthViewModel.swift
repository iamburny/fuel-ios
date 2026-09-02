import Foundation
import Observation

/// Direct port of fuel-android's `AuthViewModel.kt` state machine. `isRegister`/`isReset` are
/// orthogonal flags exactly as in the Kotlin source — `isReset` swaps the whole form to the
/// email-only "send reset link" view; there is deliberately no in-app "enter new password" screen
/// (the reset completes on a web page the email links to).
@Observable
@MainActor
final class AuthViewModel {
    var email = ""
    var password = ""
    var isRegister = false
    var isReset = false
    var resetSent = false
    var loading = false
    var errorMessage: String?

    private let repository: FuelRepository
    private let pushTokenProvider: PushTokenProvider
    private let preferencesStore: UserPreferencesStore

    init(repository: FuelRepository, pushTokenProvider: PushTokenProvider, preferencesStore: UserPreferencesStore) {
        self.repository = repository
        self.pushTokenProvider = pushTokenProvider
        self.preferencesStore = preferencesStore
    }

    func setEmail(_ value: String) { email = value; errorMessage = nil }
    func setPassword(_ value: String) { password = value; errorMessage = nil }
    func toggleMode() { isRegister.toggle(); errorMessage = nil }

    func showResetPassword() { isReset = true; resetSent = false; errorMessage = nil }
    func backFromReset() { isReset = false; resetSent = false; errorMessage = nil }

    /// Request a password-reset email. The reset itself completes on the web page it links to.
    func sendPasswordReset() async {
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedEmail.isEmpty else {
            errorMessage = "Enter your email address"
            return
        }
        loading = true
        errorMessage = nil
        do {
            try await repository.forgotPassword(email: trimmedEmail)
            loading = false
            resetSent = true
        } catch {
            loading = false
            errorMessage = friendlyError(error)
        }
    }

    /// Login or register-then-login, matching Android's `submit()` exactly: on register mode this
    /// calls `register` immediately followed by `login` (registration alone does not return a
    /// session token — logging in right after is what makes sign-up feel like auto-login).
    /// Returns `true` on success.
    @discardableResult
    func submit() async -> Bool {
        // Matches Android's `isBlank()` guard — whitespace-only input is rejected too, not just
        // zero-length strings.
        guard !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !password.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = "Email and password are required"
            return false
        }
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        loading = true
        errorMessage = nil
        do {
            if isRegister {
                _ = try await repository.register(email: trimmedEmail, password: password)
            }
            _ = try await repository.login(email: trimmedEmail, password: password)
            await registerFcmTokenBestEffort()
            await syncPreferencesBestEffort()
            loading = false
            return true
        } catch {
            loading = false
            errorMessage = friendlyError(error)
            return false
        }
    }

    /// Exchange a Google ID token for the app JWT. `email` is the Google account's email, used
    /// only for local display (the backend response carries just the token).
    @discardableResult
    func signInWithGoogle(idToken: String, email: String) async -> Bool {
        loading = true
        errorMessage = nil
        do {
            _ = try await repository.loginWithGoogle(idToken: idToken, email: email)
            await registerFcmTokenBestEffort()
            await syncPreferencesBestEffort()
            loading = false
            return true
        } catch {
            loading = false
            errorMessage = friendlyError(error)
            return false
        }
    }

    /// Exchange an Apple identity token for the app JWT. `email`/`name` are only non-nil on the
    /// user's very first authorization — Apple never resends them on subsequent sign-ins.
    @discardableResult
    func signInWithApple(idToken: String, email: String?, name: String?) async -> Bool {
        loading = true
        errorMessage = nil
        do {
            _ = try await repository.loginWithApple(idToken: idToken, email: email, name: name)
            await registerFcmTokenBestEffort()
            await syncPreferencesBestEffort()
            loading = false
            return true
        } catch {
            loading = false
            errorMessage = friendlyError(error)
            return false
        }
    }

    /// Called when the user dismisses a native sign-in sheet (Google account picker / Apple ID
    /// prompt) without completing it — not an error worth surfacing, matches Android's silent
    /// handling of `GetCredentialCancellationException`.
    func cancelSignIn() {
        loading = false
    }

    // Best-effort: push the device token so the just-logged-in account can receive alerts. A
    // failure here must not block sign-in, so it's swallowed. Returns instantly (no-op) until
    // Phase 6 wires a real `PushTokenProvider`.
    private func registerFcmTokenBestEffort() async {
        guard let token = await pushTokenProvider.currentToken() else { return }
        try? await repository.registerFcmToken(token)
    }

    /// Reconciles this device's local preferences with the account's stored ones right after
    /// login: a field the account has already set wins over the local value; a field the account
    /// has never set (nil) adopts this device's local value instead, seeding the account on first
    /// login. Best-effort — a failure here must not block sign-in, matching
    /// `registerFcmTokenBestEffort()` above.
    private func syncPreferencesBestEffort() async {
        do {
            let remote = try await repository.getPreferences()
            let local = preferencesStore.preferences
            let merged = UserPreferences(
                fuelType: remote.fuelType ?? local.fuelType,
                mpg: remote.mpg ?? local.mpg,
                tankCapacityLitres: remote.tankCapacityLitres ?? local.tankCapacityLitres,
                useLongFuelNames: remote.useLongFuelNames ?? local.useLongFuelNames,
                themeMode: remote.themeMode.flatMap(ThemeMode.init(rawValue:)) ?? local.themeMode
            )
            preferencesStore.save(
                fuelType: merged.fuelType,
                mpg: merged.mpg,
                tankCapacityLitres: merged.tankCapacityLitres,
                useLongFuelNames: merged.useLongFuelNames,
                themeMode: merged.themeMode
            )
            // Pushes the reconciled set back — the part of this account's fields that were nil
            // (adopted from local just above) now get persisted server-side too.
            _ = try? await repository.updatePreferences(PreferencesDTO(
                fuelType: merged.fuelType,
                mpg: merged.mpg,
                tankCapacityLitres: merged.tankCapacityLitres,
                useLongFuelNames: merged.useLongFuelNames,
                themeMode: merged.themeMode.rawValue
            ))
        } catch {
            // Best-effort — account preferences fetch failing must not block sign-in.
        }
    }

    private func friendlyError(_ error: Error) -> String {
        if let authError = error as? AuthError { return authError.message }
        return "Couldn't connect. Check your connection and try again."
    }
}
