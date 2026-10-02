# CalmPulse

Independent, local-first iOS 27 / watchOS 27 wellness app. Chinese-first interface.

Implementation in progress; the approved specification and plan are under `docs/superpowers/`.
No real health records, credentials, analytics, servers or signing in this repository.
This is a general wellness reference, not a medical diagnosis or measurement of psychological stress.

## Build

Use Xcode 27 with iOS 27 and watchOS 27 SDKs and simulator runtimes.
Run `bash scripts/verify-platform.sh`, `bash scripts/generate-project.sh`, then open `CalmPulse.xcodeproj`.
Run portable domain tests with `swift test --package-path Packages/WellnessCore`.
CI uses only standard public GitHub-hosted macOS runners, no paid services or retained artifacts.
Simulator CI does not verify real HealthKit background delivery, device sync, energy use or signing.

Original code is MIT licensed. No StressWatch or Thump code, artwork, trademarks or closed algorithm is included.
XcodeGen 2.44.1 is an MIT-licensed build tool downloaded from its official release; it is not bundled with the app.
