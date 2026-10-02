# Verification and device handoff

Minimum supported deployment: iOS 27 / watchOS 27. Required SDK/runtime gate is enforced without fallback.

## Simulator and automated gates
- Portable domain tests: synthetic SDNN source/date/baseline, workout exclusions, notification rules, sleep overlap, activity, conservative associations
- Service tests: protected/unavailable store semantics, UUID upserts and deletion, anchors, tombstones, settings authority, peer isolation, widget age and hidden values, durable notification idempotence, local habit actions
- Unsigned iOS/watchOS applications and both WidgetKit extensions
- iPhone UI: no-data onboarding, destructive-clear cancellation, local habit create/edit/delete, ranges and navigation
- Shared production widget-content galleries and Watch simulator home launched and were visually inspected; this does not verify live WidgetKit delivery

The completed run and exact results are in [verification.md](verification.md).

## Required real-device checks (not yet performed)
- HealthKit read authorization, partial/empty data and source identity across watch replacement
- First-unlock protection/backup exclusion on iPhone and Watch; app-group availability
- Incremental background delivery and observer completion under lock, low power and suspended apps
- Paired WatchConnectivity offline/replay/deletion sync and interrupted transfer retries
- Explicit notification ownership switching, authorization/Focus/quiet hours and duplicate suppression
- Widget/complication/Smart Stack system refresh and privacy rendering on lock screens
- Breathing haptics, accessibility, long text and battery/thermal behavior during normal wear

Unsigned simulator builds are not installable device releases. Real installation requires the owner's Apple signing team and provisioning. No Apple membership, certificates, tokens, distribution or signing service is purchased or created by this project. Personal Team and supported entitlements must be checked on the actual hardware/toolchain before promising installation. TestFlight/distribution requires separate authorization.

The final implementation report must identify exact tested commit and public CI run; a build pass is not evidence of real-device behavior.
