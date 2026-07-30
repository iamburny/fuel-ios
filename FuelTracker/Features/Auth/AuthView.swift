import SwiftUI
import SwiftData
import AuthenticationServices
import GoogleSignIn

/// Direct port of fuel-android's `AuthScreen.kt`. Presented as a sheet (Android pushes it as a
/// destination reached from Preferences' Account card or Favourites' logged-out prompt).
struct AuthView: View {
    let onAuthed: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(FuelRepository.self) private var repository
    @State private var viewModel: AuthViewModel?
    /// Email/password is a secondary path behind a text link — Apple/Google are the primary,
    /// one-tap CTAs. Once revealed there's no need to hide it again.
    @State private var showEmailForm = false

    /// Shared visual language for every full-width auth CTA (email submit, Apple, Google) so
    /// they read as one consistent button group rather than three different shapes.
    private static let buttonHeight: CGFloat = 50

    var body: some View {
        NavigationStack {
            Group {
                if let viewModel {
                    content(viewModel)
                } else {
                    ProgressView()
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        // `.onAppear` runs synchronously before the first frame is presented, unlike `.task`
        // (which schedules onto the cooperative thread pool and guarantees a one-frame flash of
        // the loading `ProgressView()` even for this synchronous, non-`await` initializer).
        .onAppear {
            if viewModel == nil {
                viewModel = AuthViewModel(repository: repository, pushTokenProvider: PushNotificationManager.shared)
            }
        }
    }

    private var title: String {
        guard let viewModel else { return "" }
        if viewModel.isReset { return "Reset password" }
        return viewModel.isRegister ? "Sign up" : "Log in"
    }

    @ViewBuilder
    private func content(_ viewModel: AuthViewModel) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if viewModel.isReset {
                    resetForm(viewModel)
                } else {
                    loginForm(viewModel)
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func resetForm(_ viewModel: AuthViewModel) -> some View {
        Text("Reset your password").font(.title2.bold())
        Text("Enter your email and we'll send you a link to reset your password.")
            .font(.subheadline)
            .foregroundStyle(.secondary)

        TextField("Email", text: Binding(
            get: { viewModel.email },
            set: { viewModel.setEmail($0) }
        ))
        .textFieldStyle(.roundedBorder)
        .textContentType(.emailAddress)
        .keyboardType(.emailAddress)
        .autocapitalization(.none)
        .disabled(viewModel.resetSent)

        if let error = viewModel.errorMessage {
            Text(error).font(.footnote).foregroundStyle(.red)
        }

        if viewModel.resetSent {
            Text("If that address has an account, we've sent a reset link. Check your inbox (and spam folder) — the link expires in 1 hour.")
                .font(.subheadline)
        } else {
            Button {
                Task { await viewModel.sendPasswordReset() }
            } label: {
                Group {
                    if viewModel.loading {
                        ProgressView()
                    } else {
                        Text("Send reset link")
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: Self.buttonHeight)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .disabled(viewModel.loading)
        }

        Button("Back to log in") { viewModel.backFromReset() }
            .frame(maxWidth: .infinity, alignment: .center)
    }

    @ViewBuilder
    private func loginForm(_ viewModel: AuthViewModel) -> some View {
        Text(viewModel.isRegister ? "Create an account" : "Welcome back").font(.title2.bold())
        Text("Get notified of fuel price drops in your area.")
            .font(.subheadline)
            .foregroundStyle(.secondary)

        SignInWithAppleButton(.signIn) { request in
            // Mirrors Android's `signInWithGoogle` clearing `error`/setting `loading` before the
            // native picker launches, so a stale error banner doesn't linger under the sheet.
            viewModel.errorMessage = nil
            viewModel.loading = true
            request.requestedScopes = [.fullName, .email]
        } onCompletion: { result in
            handleAppleSignInResult(result, viewModel: viewModel)
        }
        .signInWithAppleButtonStyle(.black)
        .frame(height: Self.buttonHeight)
        .cornerRadius(Self.buttonHeight / 2)
        .disabled(viewModel.loading)

        Button {
            handleGoogleSignIn(viewModel: viewModel)
        } label: {
            HStack(spacing: 10) {
                Image.googleLogo
                    .resizable()
                    .scaledToFit()
                    .frame(width: 20, height: 20)
                Text("Continue with Google")
                    .font(.headline)
                    .foregroundStyle(.primary)
            }
            .frame(maxWidth: .infinity)
            .frame(height: Self.buttonHeight)
            .background(Capsule().fill(Color(.secondarySystemBackground)))
            .overlay(Capsule().strokeBorder(Color(.separator), lineWidth: 1))
            // Unlike the native Apple button/.borderedProminent, this button has no built-in
            // disabled-state dimming — apply it explicitly so it doesn't look tappable mid-loading.
            .opacity(viewModel.loading ? 0.5 : 1)
        }
        .disabled(viewModel.loading)

        if let error = viewModel.errorMessage {
            Text(error).font(.footnote).foregroundStyle(.red)
        }

        if showEmailForm {
            HStack {
                VStack { Divider() }
                Text("or").font(.footnote).foregroundStyle(.secondary)
                VStack { Divider() }
            }

            TextField("Email", text: Binding(
                get: { viewModel.email },
                set: { viewModel.setEmail($0) }
            ))
            .textFieldStyle(.roundedBorder)
            .textContentType(.emailAddress)
            .keyboardType(.emailAddress)
            .autocapitalization(.none)

            SecureField("Password", text: Binding(
                get: { viewModel.password },
                set: { viewModel.setPassword($0) }
            ))
            .textFieldStyle(.roundedBorder)
            .textContentType(viewModel.isRegister ? .newPassword : .password)

            Button {
                Task {
                    if await viewModel.submit() { onAuthed() }
                }
            } label: {
                Group {
                    if viewModel.loading {
                        ProgressView()
                    } else {
                        Text(viewModel.isRegister ? "Sign up" : "Log in")
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: Self.buttonHeight)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .disabled(viewModel.loading)

            if !viewModel.isRegister {
                Button("Forgot password?") { viewModel.showResetPassword() }
                    .frame(maxWidth: .infinity, alignment: .center)
            }

            Button(viewModel.isRegister ? "Already have an account? Log in" : "New here? Create an account") {
                viewModel.toggleMode()
            }
            .frame(maxWidth: .infinity, alignment: .center)
        } else {
            Button("Sign in with email") {
                withAnimation { showEmailForm = true }
            }
            .font(.subheadline)
            .frame(maxWidth: .infinity, alignment: .center)
            .disabled(viewModel.loading)
        }
    }

    private func handleAppleSignInResult(_ result: Result<ASAuthorization, Error>, viewModel: AuthViewModel) {
        switch result {
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let tokenData = credential.identityToken,
                  let idToken = String(data: tokenData, encoding: .utf8) else {
                viewModel.loading = false
                viewModel.errorMessage = "Apple sign-in failed. Please try again."
                return
            }
            let name = credential.fullName.flatMap { components -> String? in
                let formatted = PersonNameComponentsFormatter().string(from: components)
                return formatted.isEmpty ? nil : formatted
            }
            Task {
                if await viewModel.signInWithApple(idToken: idToken, email: credential.email, name: name) {
                    onAuthed()
                }
            }
        case .failure(let error):
            if let authError = error as? ASAuthorizationError, authError.code == .canceled {
                // User dismissed the Apple ID prompt — not an error worth surfacing, matches
                // Android's silent handling of GetCredentialCancellationException.
                viewModel.cancelSignIn()
            } else {
                viewModel.loading = false
                viewModel.errorMessage = "Apple sign-in failed. Please try again."
            }
        }
    }

    /// Mirrors Android's `signInWithGoogle`: guard on the client ID being configured (matches
    /// `serverClientId.isBlank()`), launch the native account picker, exchange the resulting
    /// Google ID token for the app JWT.
    private func handleGoogleSignIn(viewModel: AuthViewModel) {
        guard AppConfig.googleClientID != nil else {
            viewModel.errorMessage = "Google sign-in isn't configured yet."
            return
        }
        guard let presenting = topViewController() else {
            viewModel.errorMessage = "Google sign-in failed. Please try again."
            return
        }
        viewModel.errorMessage = nil
        viewModel.loading = true
        Task {
            do {
                let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: presenting)
                guard let idToken = result.user.idToken?.tokenString else {
                    viewModel.loading = false
                    viewModel.errorMessage = "Unexpected sign-in response. Please try again."
                    return
                }
                if await viewModel.signInWithGoogle(idToken: idToken, email: result.user.profile?.email ?? "") {
                    onAuthed()
                }
            } catch let error as GIDSignInError where error.code == .canceled {
                // User dismissed the account picker — not an error worth surfacing, matches
                // Android's silent handling of GetCredentialCancellationException.
                viewModel.cancelSignIn()
            } catch {
                viewModel.loading = false
                viewModel.errorMessage = "Google sign-in failed. Please try again."
            }
        }
    }

    /// The Google Sign-In SDK needs a `UIViewController` to present its account-picker sheet from
    /// — there's no SwiftUI-native equivalent of Android's Activity-scoped Credential Manager call.
    private func topViewController() -> UIViewController? {
        guard let scene = UIApplication.shared.connectedScenes.first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene,
              let window = scene.windows.first(where: \.isKeyWindow) ?? scene.windows.first,
              var top = window.rootViewController else { return nil }
        while let presented = top.presentedViewController { top = presented }
        return top
    }
}

/// Loads Google's own multicolor "G" mark straight out of the `GoogleSignIn` SPM package's
/// bundled resources (`GoogleSignIn_GoogleSignIn.bundle/google.png`) — the same asset
/// `GoogleSignInSwift`'s own `GoogleSignInButton` draws, just without pulling in that whole
/// opinionated component (which hardcodes a 2pt corner radius, so it can't match this screen's
/// capsule-shaped buttons). Reusing Google's official asset keeps this on-brand rather than
/// hand-drawing a logo mark ourselves.
private extension Image {
    static var googleLogo: Image {
        guard let bundlePath = Bundle(for: GIDSignIn.self).path(forResource: "GoogleSignIn_GoogleSignIn", ofType: "bundle"),
              let url = Bundle(path: bundlePath)?.url(forResource: "google", withExtension: "png"),
              let uiImage = UIImage(contentsOfFile: url.path) else {
            // This resource path/name is an undocumented internal detail of the GoogleSignIn-iOS
            // SPM package, not a public API — a future major version bump or a switch to CocoaPods
            // integration could silently move it. Fail loudly in dev/debug builds rather than
            // shipping a silently-degraded SF Symbol placeholder unnoticed.
            assertionFailure("GoogleSignIn's bundled \"google\" logo image not found — falling back to a placeholder icon")
            return Image(systemName: "g.circle.fill")
        }
        return Image(uiImage: uiImage)
    }
}

#Preview {
    AuthView(onAuthed: {})
        .environment(FuelRepository(api: FuelPricesAPIClient(client: APIClient(baseURL: AppConfig.apiBaseURL, tokenStore: TokenStore())), modelContext: try! ModelContainer(for: CachedStation.self, CachedFuelPrice.self).mainContext, tokenStore: TokenStore()))
}
