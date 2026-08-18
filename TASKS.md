# TASKS

Feature-parity source of truth: `../fuel-android`. Per `CLAUDE.md`, this repo is a deliberate
SwiftUI port of it — check the Android Kotlin source directly before assuming intended behaviour.

Reviewed 2026-08-04 against `fuel-android/FEATURES.md` + a full pass of both codebases. Result:
**every phone-app feature is at parity** (forgot-password, heatmap, Unleash flags, Google/Apple
sign-in, coffee-support prompt, "also on the web" link, GA4 analytics, FCM push, 6 fuel types,
national trends, drive-cost/net-savings math, offline caching with the same per-endpoint rules,
vs-national-average deltas). The gov.uk source-link App Store compliance gap that used to be
Milestone 0 here is now **fixed** (`FuelTracker/Components/DataAttributionNotice.swift`,
commit `026c386`). The one remaining real gap is the car experience — see below.

---

## Milestone 1 — CarPlay feasibility spike (research only, no code)

Android's car experience (`fuel-android/FEATURES.md` §"Car app") runs on the Car App Library's
**POI category** — `FuelCarAppService` is explicitly registered under `POI`
(`core/src/main/AndroidManifest.xml`), which Google grants to any developer with no special
approval. Apple's CarPlay has **no equivalent general-purpose POI category** — third-party CarPlay
apps are restricted to a fixed list (Audio, Communication, Navigation, Parking, EV Charging, Quick
Food Ordering, Driving Task, Fitness), each requiring its own entitlement request and Apple review,
and a live fuel-price finder doesn't obviously map to any of them (it isn't a turn-by-turn
Navigation app, doesn't handle Parking session state, etc.).

This means CarPlay parity may not be a "port the Android car app" task at all — it may be
infeasible under Apple's current program, or require reframing the app as a different CarPlay
category than what it actually is. Confirm this **before** committing engineering time.

- [ ] Review Apple's current CarPlay app category list and entitlement request process
      (developer.apple.com/carplay) and determine which category, if any, a fuel-price-finder app
      could plausibly qualify for.
- [ ] If no category fits: document that CarPlay parity is a non-goal for the foreseeable future
      (mirroring how `fuel-android/CLAUDE.md` documents deliberate non-goals like the car's
      non-interactive map) and close this out as "not applicable, platform limitation" rather than
      leaving it open indefinitely.
- [ ] If a category does fit: submit the entitlement request early — Apple's review/approval lead
      time can be weeks and blocks all of Milestone 2.

---

## Milestone 2 — CarPlay build-out (blocked on Milestone 1 approval)

Do not start until Milestone 1 confirms Apple will grant an applicable entitlement. Scope mirrors
`fuel-android/FEATURES.md` §"Car app" (Nearby Stations → Station Detail / Preferences → Fuel Type
Picker), adjusted for whatever CarPlay template category was approved.

- [ ] Car-local preferences store (no phone pairing, same as Android's rationale — the standalone
      car surface has no access to the phone's on-device storage): usual fuel type + long-name
      toggle editable in-car; MPG/tank capacity **read-only in car**, only settable on the phone.
- [ ] Nearby Stations list template: stations within a fixed radius (match Android's 15 miles
      unless the approved CarPlay category dictates otherwise), adaptive sort — by distance when
      MPG/tank aren't set, by estimated net savings when they are. `FuelCostCalculator
      .estimateNetSavingsPounds` (`FuelTracker/Domain/FuelCostCalculator.swift:34-51`) is already
      ported and correct but currently has no call site — this is exactly what it's for.
- [ ] Station Detail template: address, per-fuel prices (cheapest first), signed vs-national-average
      delta, a required data-source attribution row (reuse `DataAttributionNotice`'s URLs), and a
      Navigate action.
- [ ] Document deliberate CarPlay limitations (e.g. no in-car web links, any template-imposed
      constraints on map interactivity or list length) once the approved category's real
      constraints are known — mirror Android FEATURES.md's "Deliberate car limitations" section.
