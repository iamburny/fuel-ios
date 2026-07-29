import Foundation

// `/login` is sent form-urlencoded (OAuth2-password-form compat), not as a JSON body — see
// `APIClient.login`. This struct exists only to carry the two fields through, not to be encoded
// via the generic Codable-body path.
struct LoginRequest: Sendable {
    let username: String
    let password: String
}

struct RegisterRequest: Encodable, Sendable {
    let email: String
    let password: String
}

struct GoogleLoginRequest: Encodable, Sendable {
    let idToken: String

    enum CodingKeys: String, CodingKey {
        case idToken = "id_token"
    }
}

/// New in this port — backend addition tracked alongside this: `POST /api/auth/apple`.
/// Apple only sends `email`/`name` on the user's very first authorization; capture and forward
/// them once, `nil` on subsequent sign-ins.
struct AppleLoginRequest: Encodable, Sendable {
    let idToken: String
    let email: String?
    let name: String?

    enum CodingKeys: String, CodingKey {
        case idToken = "id_token"
        case email, name
    }
}

struct ForgotPasswordRequest: Encodable, Sendable {
    let email: String
}

struct TokenResponse: Decodable, Sendable {
    let accessToken: String
    let tokenType: String
    /// The backend returns this (see fuel-api's login/register/google/apple handlers); not
    /// consumed anywhere yet, kept for a future admin-gated feature.
    let role: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case tokenType = "token_type"
        case role
    }
}

struct UserResponse: Decodable, Sendable {
    let id: Int
    let email: String
}
