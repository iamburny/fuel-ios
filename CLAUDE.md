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

## App Store submission

Archiving/uploading has to happen from Xcode on a Mac with a valid Apple Developer signing
identity — there's no `xcodebuild archive` shortcut documented here because the GUI flow is what's
actually been used. Requires real `Config/Secrets.xcconfig` + `GoogleService-Info.plist` present
(see Local secrets setup above) — a Release archive built without them still builds (by design) but
ships with Google Sign-In etc. silently disabled for reviewers.

**Archive and upload:**
1. In Xcode, target `FuelTracker` → Signing & Capabilities: confirm the right Team is selected and
   "Automatically manage signing" is checked.
2. Destination picker (top toolbar) → **Any iOS Device (arm64)** or a connected device. Archiving is
   disabled while a simulator destination is selected.
3. **Product → Archive**. Builds Release configuration.
4. Organizer opens automatically (or **Window → Organizer → Archives**). Select the new archive →
   **Distribute App → App Store Connect → Upload**, then follow the signing prompts.
5. Wait for Apple's processing email (~15 min–a few hours), then in App Store Connect, on the
   version's "Prepare for Submission" page, **Build** section → **+** → select the processed build.

**"Upload completed with warnings" about missing dSYMs (`FirebaseAnalytics`,
`GoogleAppMeasurement`, `GoogleAppMeasurementIdentitySupport`, `GoogleAdsOnDeviceConversion`) are
expected and safe to ignore.** These are precompiled binary frameworks pulled in transitively by
Firebase Analytics via SPM; Xcode doesn't bundle their dSYMs into the archive. The upload still
succeeds and the build is still submittable — the only effect is that a crash originating *inside*
one of those four specific Google frameworks won't symbolicate in App Store Connect's crash
reports. Not worth chasing before a submission.

**"Add for Review" checklist** (App Store Connect, App Information / App Privacy tabs) — items that
have tripped this up before:
- **Content Rights Information**: answer yes / confirm rights — the fuel price data comes from UK
  filling stations' government-mandated open price feeds, which exist specifically for this kind of
  reuse.
- **Privacy Policy URL**: `https://fueltracker.uk/privacy` (source: `fuel-web/app/privacy/page.tsx`
  — check it still mentions iOS/Apple Sign-In, not just Android, before pointing reviewers at it).
- **Primary category**: Utilities (Travel is a reasonable secondary).
- **Age rating questionnaire**: answer "None"/"No" throughout — no mature content, no unrestricted
  in-app web browsing (external links open in the system browser, not an embedded one), and the
  discrepancy-report feature sends free text privately to admins rather than publishing it, so it
  doesn't count as user-generated content either.
- **13-inch iPad screenshot**: required because `TARGETED_DEVICE_FAMILY = "1,2"` in
  `project.pbxproj` declares iPad support, even though the app has no iPad-specific layout (it's
  portrait-only, `UIRequiresFullScreen = true`) — it just scales up fine. To generate one without a
  fresh archive: boot an "iPad Pro 13-inch" simulator (`xcrun simctl list devices available`),
  install + launch the already-built `.app` from
  `~/Library/Developer/Xcode/DerivedData/.../Debug-iphonesimulator/FuelTracker.app` via
  `xcrun simctl install`/`launch`, then `xcrun simctl io <UDID> screenshot out.png` — this produces
  exactly the 2064×2752 resolution Apple requires. Watch out for the "Buy me a coffee" support
  prompt (`AppPreferencesViewModel.onAppOpened`) firing on cold launch #1 and every 5th launch after
  — relaunch the app once (`simctl terminate` + `launch`) to land on a launch it won't show on.

### TestFlight

Same archive/upload flow as above — there's no separate "TestFlight build"; every processed upload
becomes available for TestFlight automatically. Only what happens afterward differs:

- Go to the **TestFlight** tab in App Store Connect (not "App Store" / "Prepare for Submission" —
  that's the review-checklist tab), where the processed build appears on its own.
- Fill in **Test Information** on the build (What to Test notes, beta description, contact email) —
  required before external testers can install it.
- **Internal testing**: anyone with a role on the App Store Connect team (Admin/App Manager/
  Developer), up to 100 people. No Apple review — available within minutes of processing.
- **External testing**: testers invited by email, up to 10,000, in named groups. The first build of
  each version needs a quick **Beta App Review** (usually a few hours, well under 48h) before it
  reaches external testers; later builds of the same version can skip re-review unless the change
  is significant.

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
- `getStationsInBounds`: **always network-first** (no cache-first short-circuit) — every call comes
  from a genuine drag to a genuinely new box, and a drag's box nearly always overlaps stations
  already cached from an earlier load elsewhere, so a naive "any fresh cache hit in this box" check
  (the previous behaviour here) almost always skipped the network call and silently hid whatever
  was newly visible at the box's edges. On network failure, falls back to cache **scoped to the
  same bounding box** — an unrelated station from elsewhere in the country has no business
  appearing on a dragged map viewport. Don't unify this with the rule above.
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
