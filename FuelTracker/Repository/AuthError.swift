import Foundation

/// Typed auth failure reasons — direct port of fuel-android's `AuthException.kt`, so the Auth
/// screen can distinguish "wrong password" from "email taken" from "network broke" the same way
/// Android does, instead of sniffing HTTP status codes ad hoc at the call site.
struct AuthError: Error, LocalizedError, Sendable {
    enum Reason: Sendable {
        case invalidCredentials
        case emailTaken
        /// Constructed directly by the Auth ViewModel on a Google/Apple SDK-level failure (not an
        /// HTTP response) — mirrors `Reason.GOOGLE_SIGNIN_FAILED`, generalized to cover Apple too.
        case signInFailed
        case other
    }

    let reason: Reason
    let message: String

    var errorDescription: String? { message }

    /// Maps an `APIError.http` status code the same way `AuthException.from(HttpException)` does.
    static func from(_ error: APIError) -> AuthError {
        guard case .http(let status, _) = error else {
            return AuthError(reason: .other, message: "Couldn't connect. Check your connection and try again.")
        }
        switch status {
        case 401: return AuthError(reason: .invalidCredentials, message: "Invalid email or password")
        case 409: return AuthError(reason: .emailTaken, message: "That email is already registered")
        default: return AuthError(reason: .other, message: "Something went wrong. Please try again.")
        }
    }
}
