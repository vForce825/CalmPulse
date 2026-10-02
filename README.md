# CalmPulse

A Chinese-first, local-first **iOS 27 / watchOS 27** wellness app with an explainable personal SDNN scale. Original code is MIT licensed; this is independent of StressWatch and does not reproduce its proprietary algorithm or assets.

**Automated simulator verification passed.** [Verified implementation 59690d1](https://github.com/vForce825/CalmPulse/actions/runs/37006610791) passed the Xcode 27 platform/build/test gates. See the [verification report](docs/verification.md) for counts and scope. Unsigned simulator builds are not installable device releases; [hardware checks](docs/device-checklist.md) remain.

## Included

- iPhone Today, Trends, Habits and Settings; Watch latest reading, short history, quick logs, editable history and breathing with optional haptics
- SDNN milliseconds, source/time/data age, source-isolated 28-complete-day baseline, confidence/coverage and historical labels
- Day/week/month/year sparse charts, sample details, sample-band shares and weekly reports
- Sleep/stages, daily activity, daylight, mindfulness, workouts and user-defined heart-rate zones
- Local mood/water/caffeine/breathing logs and conservative associations requiring sufficient paired days
- Protected on-device files, read-only staged HealthKit permissions, deletion handling, offline paired-device sync and conflict tombstones
- Opt-in notifications with explicit ownership, quiet hours, cooldown, new-input and durable duplicate guards. An asynchronous submission invalidated by deletion, clear or settings changes is retracted from pending/delivered requests after completion; the OS may already have shown an alert, so retraction cannot guarantee it was never presented.
- iPhone home/lock-screen widgets and Watch complications/Smart Stack, hidden values by default

The trend scale is **not a stress percentage, diagnosis or measurement of emotion**. A lower score does not prove good health. Read the [formula](docs/wellness-algorithm.md) and [privacy/limitations](docs/privacy.md).

## Data coverage

The iPhone keeps complete available SDNN, resting-heart-rate, sleep, mindfulness and workout history. Cumulative activity is source-separated daily totals instead of lifetime raw samples. Routine raw heart-rate cache covers 90 calendar days; opening an older workout reads its heart-rate interval transiently after opt-in. Watch keeps a recent 90-day health cache for its short-history views. Original Apple Health records and local habit logs are not trimmed by these cache policies. See [exact coverage rules](docs/health-data-coverage.md).

## Build and test

Use Xcode 27 with iOS 27 and watchOS 27 SDKs and simulator runtimes. No fallback to an older SDK is performed.

```sh
export DEVELOPER_DIR=/Applications/Xcode_27.app/Contents/Developer
bash scripts/verify-release.sh
```

For only portable logic checks:

```sh
swift test --package-path Packages/WellnessCore
swift test
python3 -m unittest discover -s Tests -p 'test_*.py'
```

The generated `CalmPulse.xcodeproj` is retained. `project.yml` is the source of project configuration; regenerate with `bash scripts/generate-project.sh` (official pinned XcodeGen 2.44.1, build-only MIT dependency).

CI uses a standard public GitHub-hosted `xcode-27` runner, unsigned simulator builds, read-only repository permissions and no retained artifacts or cache uploads. Screenshots printed by UI tests are explicitly synthetic demonstration screens. Shared-widget gallery screenshots validate production content layout, not live WidgetKit refresh behavior.

## Installation boundary

Real installation needs the owner's Apple signing team, matching HealthKit/App Group capabilities and provisioning. No signing keys, Apple membership, paid runners or distribution service are configured or purchased. Real HealthKit authorization/background delivery, paired sync, notification presentation, Watch haptics and energy use require the [manual device checks](docs/device-checklist.md).

No real health records, private habit logs, credentials, analytics, servers, CloudKit, ads, accounts or purchase system belong in this repository.
