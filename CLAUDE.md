# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

`fuel-ios` is a native SwiftUI port of `fuel-android`, one of five sibling repos under the parent
`fueltracker/` directory: `fuel-android`, `fuel-api` (backend), `fuel-admin`, `fuel-web`, `fuel-ios`.
When implementing or fixing a feature here, check the Android Kotlin source directly
(`../fuel-android`) rather than assuming — it's the source of truth for intended behavior, and this
codebase is full of comments citing exact Android file/line parity. Backend contract questions
(endpoint shapes, auth flow) are answered by reading `../fuel-api` directly, not by guessing.

## Build, test, run

No `xcodegen`/CocoaPods workflow — `FuelTracker.xcodeproj/project.pbxproj` is the tracked, live
project file, edited directly (including by Xcode itself when adding file references). A
`project.yml` exists from the initial scaffold but isn't regenerated as part of normal work; don't
assume it's authoritative if it looks out of sync with the `.xcodeproj`.

```bash
# Build for a simulator
xcodebuild -project FuelTracker.xcodeproj -scheme FuelTracker -destination 'id=<SIMULATOR_UDID>' build

# Run the full test suite
xcodebuild -project FuelTracker.xcodeproj -scheme FuelTracker -destination 'id=<SIMULATOR_UDID>' test

# Run a single test
xcodebuild -project FuelTracker.xcodeproj -scheme FuelTracker -destination 'id=<SIMULATOR_UDID>' test \
  -only-testing:FuelTrackerTests/DTODecodingTests/decodesStationWithArrayAmenities

# List available simulators / connected physical devices
xcrun simctl list devices available
xcrun xctrace list devices

# Build + install + launch on a connected physical device (requires a provisioning profile/team)
xcodebuild -project FuelTracker.xcodeproj -scheme FuelTracker -destination 'id=<DEVICE_UDID>' -configuration Debug build
xcrun devicectl device install app --device <DEVICE_UDID> <path-to>/FuelTracker.app
xcrun devicectl device process launch --device <DEVICE_UDID> --terminate-existing uk.fueltracker.app
```

Tests use **Swift Testing** (`import Testing`, `@Test`, `#expect`), not XCTest.

## Local secrets setup

Real secrets are gitignored and must be supplied locally before Google Sign-In, Maps, push, or
Unleash flags will do anything:

- Copy `Config/Secrets.xcconfig.example` → `Config/Secrets.xcconfig` and fill in real values.
  `Config/Debug.xcconfig`/`Release.xcconfig` are committed and non-secret; they `#include?
  "Secrets.xcconfig"` so a fresh checkout without it still builds.
- `FuelTracker/Resources/GoogleService-Info.plist` (also gitignored) is required for Firebase
  (push notifications, analytics).
- **Google Sign-In needs two distinct OAuth client IDs**, easy to mix up: `GOOGLE_IOS_CLIENT_ID`
  (an iOS-type client, used as `GIDConfiguration`'s `clientID` for the native sign-in redirect) and
  `GOOGLE_SERVER_CLIENT_ID` (a Web-type client, passed as `serverClientID` so the returned ID
  token's `aud` matches what `fuel-api` verifies against — same ID Android passes as
  `serverClientId`). Passing the Web client ID as `clientID` breaks native sign-in with "Custom
  scheme URIs are not allowed for 'WEB' client type."

Every one of these integrations is intentionally designed to **degrade gracefully, not crash**,
when its secret is absent (see `AppConfig.swift`) — e.g. "Continue with Google" shows a friendly
"not configured yet" message, Maps shows a placeholder, push/Unleash just no-op. Preserve this
pattern in any new integration; a fresh checkout with no `Secrets.xcconfig` should always build and
run.

## Architecture

Single Xcode app target (no local SwiftPM package split). Layout mirrors Android's module split:

```
FuelTracker/
  App/            AppContainer (manual DI), AppConfig, RootView (tab shell), AppDelegate, DeepLink
  Networking/     APIClient (URLSession), APIEndpoint, FuelPricesAPI, DTOs/
  Repository/     FuelRepository — single source of truth, see caching rules below
  Persistence/    TokenStore (Keychain), UserPreferencesStore (UserDefaults), CachedStation (SwiftData)
  Domain/         FuelType, FuelCostCalculator, AmenitiesFormatter
  Features/       One folder per screen: View + @Observable ViewModel
  Components/     Shared views (FuelMapView, PriceLineChart, AnnouncementBanner, ...)
  Push/           PushNotificationManager (singleton), PushTokenProvider protocol
  FeatureFlags/   Unleash Frontend API client
  Analytics/      AppAnalytics (Firebase wrapper)
  Location/       LocationManager
```

### Dependency injection

`AppContainer` (`App/AppContainer.swift`) is a manual container built once in `FuelTrackerApp`,
threaded through the view tree via SwiftUI `@Environment`. Individually-injected pieces
(`FuelRepository`, `UserPreferencesStore`, `FeatureFlags`, `AppPreferencesViewModel`) are also
exposed via a custom `\.appContainer` environment key as a whole, for ViewModels that need several
dependencies at construction time. `PushNotificationManager` is a `.shared` singleton, *not* part of
`AppContainer` — its `Messaging`/`UNUserNotificationCenter` delegates must be set from
`AppDelegate.didFinishLaunchingWithOptions`, before `AppContainer` (a SwiftUI `@State` on the `App`
struct) is guaranteed to exist.

State/UI pattern throughout: `@Observable` + `@MainActor` view models (not `ObservableObject`/Combine).

### FuelRepository's caching rules are asymmetric per endpoint — by design, not an inconsistency

This is the single most important thing to understand before touching `Repository/FuelRepository.swift`:

- `getNearbyStations`: cache-first (24h TTL); on network failure, falls back to **any** cached
  station (unscoped) — better than nothing.
- `getStationsInBounds`: cache-first; on network failure, falls back to cache **scoped to the same
  bounding box** — an unrelated station from elsewhere in the country has no business appearing on
  a dragged map viewport. Don't unify this with the rule above.
- `getStation(id:)`: network-first, cache-fallback only on failure.
- `searchStations`: network-first, in-memory substring-match fallback on failure.
- `getCheapest` / `getNationalAverages` / `getHeatmap` / `getPriceHistory` / `getNationalTrends`:
  **never cached, no fallback** — errors must propagate to the UI. This is a Fair Use Policy
  compliance requirement, not just a UX choice; don't add caching here to "improve" offline support.

`apiFailureCount` is a repository-level (not per-ViewModel) consecutive-failure counter, reset on
any success — the UI (`NearbyView`) surfaces a "can't reach the service" banner once it crosses a
threshold.

### Fuel types are exact-case wire values

`FuelType` (`Domain/FuelTypes.swift`) is a `String`-backed enum with explicit raw values (`E10`,
`B7_STANDARD`, `B7_PREMIUM`, `B10`, `HVO`, `E5`) matching the backend exactly — these values are
used as network wire values, cache keys, and UI keys. Never normalize/reformat them; when a 7th
fuel type appears server-side that isn't a known case, the `forRaw:` static helpers degrade
gracefully (fallback color/label) rather than crashing.

### Amenities decoding

The backend's `amenities` field has no fixed shape — it arrives as either an array of strings or an
object of string→bool. `StationDTO`'s `Decodable` conformance tries both shapes, and a bad value for
one object key must not blank out the other keys (see `DTODecodingTests.amenitiesObjectDecodeSkipsOnlyBadKeysNotWholeObject`).

### Push notifications

`registerForRemoteNotifications()` must be called on **every launch** once already authorized, not
just on the first-ever grant — APNs delivers the device token to `Messaging` asynchronously via
`AppDelegate.didRegisterForRemoteNotificationsWithDeviceToken`, and it isn't persisted across
launches on the `Messaging` side. `PushNotificationManager.currentToken()` polls briefly for
`Messaging.messaging().apnsToken` to become non-nil before calling `.token()`, since calling it too
early throws "No APNS token specified before fetching FCM Token."

### Feature flags

`FeatureFlags/FeatureFlags.swift` hand-rolls a client for Unleash's Frontend API
(`GET {url}/api/frontend`, `Authorization: <clientKey>` header) — there's no official Unleash Swift
SDK, unlike Android which uses Unleash's own SDK against the same Frontend API. Only ever use a
**Frontend API token** here (safe to ship in a client binary by Unleash's own design), never a
Backend token (broader-privileged, must stay server-side only).

**Critical, easy-to-get-wrong gotcha: the Frontend API only ever returns currently-*enabled*
toggles.** A flag that's deliberately turned off in the Unleash dashboard and a flag name Unleash
has never heard of are both simply *absent* from the response — there is no explicit "off" entry to
distinguish them. That means `isEnabled(name, default:)`'s fallback value is what silently wins
whenever a flag is off, not just when Unleash is unreachable or misconfigured. **Any flag meant to
be remotely toggleable off must use `default: false`** — passing `true` "to be safe" makes that flag
permanently impossible to disable remotely, since a real "off" toggle is indistinguishable from an
outage. (`AnnouncementBanner`'s flag already does this correctly; verify every other call site the
same way rather than assuming the SDK/pattern you're copying from defaults sensibly.) When
diagnosing "toggling this flag in the dashboard doesn't do anything," check the call site's default
before suspecting the flag name/project/environment.
