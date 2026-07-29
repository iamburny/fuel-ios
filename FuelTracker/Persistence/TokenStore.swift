import Foundation
import Security

/// JWT + signed-in email persistence via Keychain — the secret-adjacent iOS equivalent of
/// Android's DataStore-backed `TokenStore`. Hand-rolled rather than pulling in a wrapper
/// dependency: only two keys, ~40 lines covers it.
final class TokenStore: @unchecked Sendable {
    private let service = "uk.co.fuelprices.auth"
    private let tokenAccount = "jwt_token"
    private let emailAccount = "user_email"
    private let lock = NSLock()

    var token: String? {
        get { lock.withLock { read(account: tokenAccount) } }
        set { lock.withLock { write(newValue, account: tokenAccount) } }
    }

    var email: String? {
        get { lock.withLock { read(account: emailAccount) } }
        set { lock.withLock { write(newValue, account: emailAccount) } }
    }

    var isSignedIn: Bool { token != nil }

    func clear() {
        lock.withLock {
            write(nil, account: tokenAccount)
            write(nil, account: emailAccount)
        }
    }

    private func read(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func write(_ value: String?, account: String) {
        let baseQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        guard let value, let data = value.data(using: .utf8) else {
            SecItemDelete(baseQuery as CFDictionary)
            return
        }
        var attributes = baseQuery
        attributes[kSecValueData as String] = data
        let status = SecItemAdd(attributes as CFDictionary, nil)
        if status == errSecDuplicateItem {
            SecItemUpdate(baseQuery as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        }
    }
}

private extension NSLock {
    func withLock<T>(_ body: () -> T) -> T {
        lock()
        defer { unlock() }
        return body()
    }
}
