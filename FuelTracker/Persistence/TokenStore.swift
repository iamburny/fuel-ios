import Foundation
import Security

/// JWT + signed-in email persistence via Keychain — the secret-adjacent iOS equivalent of
/// Android's DataStore-backed `TokenStore`. Hand-rolled rather than pulling in a wrapper
/// dependency.
///
/// The access and refresh tokens live together in one Keychain item, so storing a rotated pair is
/// a single write that either fully lands or leaves the previous pair intact. Items are written as
/// `AfterFirstUnlockThisDeviceOnly` so background work (push-token updates, refreshes) can still
/// read the session while the device is locked.
final class TokenStore: @unchecked Sendable {
    struct Session: Codable, Equatable, Sendable {
        let accessToken: String
        /// Optional because a login response may omit it.
        let refreshToken: String?
    }

    struct KeychainError: Error, Sendable {
        let status: OSStatus
    }

    private let service = "uk.co.fuelprices.auth"
    private let sessionAccount = "auth_session"
    /// Separate access/refresh items from the older two-item layout, folded into the session item
    /// the first time it's read.
    private let legacyTokenAccount = "jwt_token"
    private let legacyRefreshTokenAccount = "refresh_token"
    private let emailAccount = "user_email"
    private let lock = NSLock()
    /// Incremented by `setSession` each time a sign-in stores a new session (never by a refresh).
    /// Work that began under one sign-in compares it to tell whether the user has signed in again
    /// since. Guarded by `lock`.
    private var generation = 0

    /// The stored session, or `nil` when there is none or the Keychain can't be read right now.
    /// Use `loadSession()` where "unreadable" must not be mistaken for "signed out".
    var session: Session? { try? loadSession() }

    var token: String? { session?.accessToken }

    /// Long-lived opaque token used to silently mint a new `token` via `POST /api/auth/refresh`
    /// once the access token expires — see `APIClient`'s refresh-and-retry logic.
    var refreshToken: String? { session?.refreshToken }

    var email: String? {
        get {
            let data = lock.withLock { try? read(account: emailAccount) }
            return data.flatMap { String(data: $0, encoding: .utf8) }
        }
        set { lock.withLock { _ = try? write(newValue?.data(using: .utf8), account: emailAccount) } }
    }

    var isSignedIn: Bool { token != nil }

    /// Throws `KeychainError` when the Keychain can't be read (e.g. an item still locked), as
    /// distinct from returning `nil` for "no session stored".
    func loadSession() throws -> Session? {
        try lock.withLock { try loadSessionLocked() }
    }

    /// A sign-in generation paired with the session stored at that moment.
    struct Snapshot: Sendable {
        let session: Session?
        let generation: Int
    }

    struct Cleared: Sendable {
        let refreshToken: String?
    }

    /// Like `loadSession()`, plus the current sign-in generation read under the same lock.
    func loadSnapshot() throws -> Snapshot {
        try lock.withLock { Snapshot(session: try loadSessionLocked(), generation: generation) }
    }

    /// Non-throwing `loadSnapshot()`: `session` is `nil` when the Keychain can't be read.
    var snapshot: Snapshot {
        lock.withLock { Snapshot(session: try? loadSessionLocked(), generation: generation) }
    }

    /// Stores a newly signed-in session in one write and starts a new sign-in generation. Throws
    /// if the Keychain write fails, leaving the previously stored session as it was.
    func setSession(_ session: Session) throws {
        try lock.withLock {
            try writeSessionLocked(session)
            generation += 1
        }
    }

    /// Stores a rotated `session` only if no new sign-in has happened since `generation` and the
    /// stored refresh token is still `refreshToken`, so a refresh finishing after a sign-out or a
    /// new login can't overwrite it. Returns whether it wrote.
    func replaceSession(ifGeneration generation: Int, refreshToken: String, with session: Session) throws -> Bool {
        try lock.withLock { () throws -> Bool in
            guard self.generation == generation,
                  try loadSessionLocked()?.refreshToken == refreshToken else { return false }
            try writeSessionLocked(session)
            return true
        }
    }

    /// Clears everything unless a new sign-in has been stored since `generation` was read — that
    /// session must survive. Returns `nil` when it left things alone, otherwise the refresh token
    /// that was stored at the moment of clearing.
    func clear(ifGeneration generation: Int) -> Cleared? {
        lock.withLock { () -> Cleared? in
            guard self.generation == generation else { return nil }
            let refreshToken = (try? loadSessionLocked())?.refreshToken
            clearLocked()
            return Cleared(refreshToken: refreshToken)
        }
    }

    func clear() {
        lock.withLock { clearLocked() }
    }

    /// Deletes are best-effort: if one fails there's nothing further to try, and the next read
    /// simply finds whatever is left.
    private func clearLocked() {
        for account in [sessionAccount, legacyTokenAccount, legacyRefreshTokenAccount, emailAccount] {
            _ = try? write(nil, account: account)
        }
    }

    private func writeSessionLocked(_ session: Session) throws {
        guard let data = try? JSONEncoder().encode(session) else {
            throw KeychainError(status: errSecParam)
        }
        try write(data, account: sessionAccount)
    }

    /// Reads the session item, migrating the legacy two-item layout into it when only that exists.
    /// If writing the migrated item fails, the legacy items are kept and the migration runs again
    /// on the next read.
    private func loadSessionLocked() throws -> Session? {
        if let data = try read(account: sessionAccount) {
            return try? JSONDecoder().decode(Session.self, from: data)
        }
        guard let accessData = try read(account: legacyTokenAccount),
              let accessToken = String(data: accessData, encoding: .utf8) else {
            return nil
        }
        let refreshData = try read(account: legacyRefreshTokenAccount)
        let session = Session(
            accessToken: accessToken,
            refreshToken: refreshData.flatMap { String(data: $0, encoding: .utf8) }
        )
        if (try? writeSessionLocked(session)) != nil {
            _ = try? write(nil, account: legacyTokenAccount)
            _ = try? write(nil, account: legacyRefreshTokenAccount)
            // Rewriting the email item applies the current accessibility to it too.
            if let emailData = try? read(account: emailAccount) {
                _ = try? write(emailData, account: emailAccount)
            }
        }
        return session
    }

    /// `nil` when the item doesn't exist; throws for any other failure, such as the item being
    /// inaccessible while the device is locked.
    private func read(account: String) throws -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw KeychainError(status: status) }
        return result as? Data
    }

    /// Adds or updates the item, or deletes it when `data` is `nil`. Always sets the accessibility
    /// too, so an existing item created with a different one is moved onto it when rewritten.
    private func write(_ data: Data?, account: String) throws {
        let baseQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        guard let data else {
            let status = SecItemDelete(baseQuery as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else {
                throw KeychainError(status: status)
            }
            return
        }
        let updates: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        let attributes = baseQuery.merging(updates) { _, new in new }
        var status = SecItemAdd(attributes as CFDictionary, nil)
        if status == errSecDuplicateItem {
            status = SecItemUpdate(baseQuery as CFDictionary, updates as CFDictionary)
        }
        guard status == errSecSuccess else { throw KeychainError(status: status) }
    }
}
