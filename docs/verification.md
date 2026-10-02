# Verified stress-first redesign

Implementation commit: [`27c00312e0cda7a1c9fbd5042adbc8833f7ec36e`](https://github.com/vForce825/CalmPulse/commit/27c00312e0cda7a1c9fbd5042adbc8833f7ec36e).

[GitHub Actions run 37021307483](https://github.com/vForce825/CalmPulse/actions/runs/37021307483) completed successfully on 2026-10-02 using the standard public `xcode-27` runner. Subsequent verification-document changes do not change the tested implementation.

## Actual results

- Xcode 27, iOS 27 and watchOS 27 SDK/runtime gate passed without fallback.
- Source privacy audit and 20 Python configuration/presentation checks passed.
- 46 pure Swift domain tests passed.
- 76 service tests passed on macOS and again in the iPhone simulator. The portable Linux service suite has 75 tests because an Apple-only file-protection case is conditional.
- 9 iPhone UI tests passed. The iPhone result bundle reports 85 tests, 85 passed, zero failed.
- Unsigned iPhone application, Watch application and both WidgetKit extensions built successfully.
- Watch simulator installation, five state launches and the synthetic widget-content gallery completed successfully.

## Product and visual coverage

The shared presentation gates cover four plain-language bands, insufficient history, limited history, stale observations, invalid values/timestamps, currently unscorable observations, locked storage and private widget content. Tests reject malformed scores and preserve the strict greater-than-three-hours historical boundary. Privacy hides both widget values and its observation timestamp. No change was made to the underlying relative SDNN algorithm.

The Today screen presents status, observation age, a short explanation and a breathing entry before advanced metrics. Sparse daily history does not join observations or invent a continuous state. Raw SDNN, source, calculation details and resting heart rate remain accessible in details. The trends screen defaults to the reference bands. Phone, Watch and widgets share the same validated status mapping.

Nineteen screenshots were emitted from the simulator run using synthetic fixtures only. Visual review covered the phone's four fresh bands, learning and stale states, normal and largest dark text, Watch status with a fully visible breathing button, and the widget gallery including hidden/locked states. The phone's date and observation age render in Chinese even under an English simulator locale. At accessibility sizes, decorative content is omitted and the remaining content stays scrollable.

Phone UI tests exercise the details/back/breathing flow, all synthetic states, a hittable primary breathing entry, Chinese date copy, the clear-data cancellation, local habit editing, trend-range persistence and optional health-read navigation. The Watch captures establish launch and first-screen layout; they do not establish every offscreen control or automated Watch touch interaction. Widget galleries render the production content component inside a debug-only host, not a live WidgetKit installation.

## Interpretation and remaining checks

The app presents an original, documented SDNN-relative wellness scale as a pressure reference. It does not reproduce a proprietary StressWatch algorithm or claim to measure actual emotion or medical risk. Tests validate the stated calculation and software behavior, not clinical effectiveness.

All test records are synthetic. No real health records, signing credentials or paid services were required. The private reference screenshot and its personal information remain outside the repository; no third-party character artwork was published. The landscape is original SwiftUI vector artwork. Real-device HealthKit authorization/source identity, protected-storage behavior, background delivery, paired offline synchronization, notification presentation, live widgets/complications, haptics and battery use remain unverified. See the [device checklist](device-checklist.md). Signed installation or distribution is not included in this simulator-verification result.
