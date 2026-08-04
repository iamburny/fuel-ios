# TASKS

## Pre-empt App Store rejection: missing source link for government data (Misleading Claims policy)

Google rejected `fuel-android`'s Play Store submission for this exact issue (see `../fuel-android`,
commit adding `DataAttributionNotice.kt`) — Apple's App Review Guideline 5.6 / accuracy requirements
are the equivalent risk here, so fix it before first submission rather than after a rejection.

**Root cause on Android (confirmed present here too):** the gov.uk data-source mention is plain,
non-tappable text — `Text("...gov.uk/government/collections/fuel-finder...")` — with only the
*discrepancy-report* button (a different URL) being an actual link. A bare domain mention isn't a
"clear and accessible URL/link to the original source," which is what the policy requires.

Confirmed the same pattern exists in `fuel-ios`:
- `FuelTracker/Features/Detail/DetailView.swift:184`
- `FuelTracker/Features/Prices/PricesView.swift:122`
- `FuelTracker/Features/Nearby/NearbyView.swift:269` (also references a "Tap ⚠ to report" affordance
  that should be checked for whether it's an actual working control)

**Fix, mirroring the Android approach:**
1. Add a real link (`Link(...)` / `.openURL` button, not inline `Text`) to
   `https://www.gov.uk/government/collections/fuel-finder` on every screen that shows government
   fuel-price data — alongside the existing "Report a price discrepancy" link, not replacing it.
   Consider one shared `DataAttributionNotice` view (SwiftUI) used by all three screens instead of
   duplicating the block three times, matching the Android-side component of the same name.
2. Also double-check the App Store Connect **app description** — if it mentions
   `gov.uk/government/collections/fuel-finder` as bare text, make sure it's not the only place the
   source is disclosed (App Store descriptions render some auto-linking, but don't rely on it).
3. Keep the existing non-affiliation disclaimer text as-is — that part already satisfies the
   "doesn't represent a government entity" requirement.

**Why this matters:** on Android this caused a full rejection under the Misleading Claims policy
requiring resubmission; better to ship it correctly on the first `fuel-ios` submission.
