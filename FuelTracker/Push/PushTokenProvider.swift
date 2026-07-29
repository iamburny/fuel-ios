import Foundation

/// Abstraction over "get the current push token to register with the backend" so Auth (Phase 1)
/// doesn't need to depend on Firebase, which lands in the Push Notifications phase. `AppContainer`
/// wires the no-op default for now; Phase 6 swaps in a Firebase-Messaging-backed implementation
/// that bridges the APNs token to an FCM token.
protocol PushTokenProvider: Sendable {
    func currentToken() async -> String?
}

struct NoOpPushTokenProvider: PushTokenProvider {
    func currentToken() async -> String? { nil }
}
