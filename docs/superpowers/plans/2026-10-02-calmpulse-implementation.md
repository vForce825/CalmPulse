# CalmPulse Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deliver a public-source, local-first personal iOS 27/watchOS 27 wellness app implementing the approved SDNN and habit feature set.

**Architecture:** Native SwiftUI clients, a portable pure-Swift domain package, HealthKit adapters, protected on-device stores, and explicit WatchConnectivity synchronization. WidgetKit reads minimal protected summaries. No server or health-data telemetry.

**Tech Stack:** Swift, SwiftUI, Swift Charts, HealthKit, WidgetKit, WatchConnectivity, UserNotifications, XCTest; standard GitHub-hosted macOS CI. XcodeGen only if needed to maintain multi-target project reproducibly; pin its official release and retain generated project.

**Spec:** `docs/superpowers/specs/2026-10-02-calmpulse-design.md` version 1.2.

## Global Constraints

- Minimum deployment targets iOS 27 and watchOS 27. Verify corresponding SDKs and simulator runtimes; never lower silently.
- User approved public repository under vForce825. Name CalmPulse is provisional. MIT is proposed for independently authored code only and included in this plan's review; no proprietary StressWatch or Thump code/assets.
- No product implementation or repository creation before this plan is reviewed and execution method chosen.
- Preserve account's $0 Actions budget; only standard public macOS runners. Stop before any paid runner, membership, service or signing integration.
- No user-computer access, real health records in CI, credentials in source/history/artifacts, cloud AI, analytics SDK, account/paywall, or background-workout workaround.
- Chinese primary interface. SDNN must never be labeled RMSSD; no diagnostic, emotional-state, biological-age or clinical-accuracy claims.
- Notifications off by default; default owner Watch when installed. Explicit iPhone-only mode, no automatic failover.
- All workflow permissions read-only unless a narrowly scoped publishing step is separately authorized; external PR tests receive no signing secrets.

## Review Focus

1. A watch replacement/source change must not combine unrelated baselines: Task 2 source-isolation assertion.
2. DST travel and midnight boundaries must not double-count daily baselines: Task 2 civil-day assertion.
3. HealthKit read refusal looks like empty results: Task 3 exact neutral empty-state assertion.
4. Replayed offline delete must not resurrect habit entries: Task 4 tombstone assertion.
5. Stale widget cache and locked-device storage must not masquerade as fresh live data: Tasks 4 and 7 freshness/locked assertions.

## File Map and Shared Interfaces

- `Packages/WellnessCore/Sources/WellnessCore/Models.swift`: `HealthSample(id: UUID, kind: MetricKind, sourceID: String, start: Date, end: Date, value: Double)`; `MetricKind` covers SDNN, RHR, HR, steps, energy, exercise minutes, daylight, sleep and mindfulness. `WorkoutWindow(start:end:)` defines exclusions.
- `WellnessEngine.swift`: `assess(current: HealthSample, history: [HealthSample], workouts: [WorkoutWindow], calendar: Calendar, now: Date) -> WellnessAssessment`. Assessment contains optional integer score, band, baseline-day/sample counts, version, sourceID, sampleID, observedAt and freshness.
- `NotificationPolicy.swift`: `decision(recent: [WellnessAssessment], settings: NotificationSettings, lastSentAt: Date?, now: Date, calendar: Calendar) -> NotificationDecision`.
- `HabitModels.swift`: `HabitEntry(id: UUID, kind: HabitKind, timestamp: Date, value: Double?, note: String?, revision: UInt64, origin: String, deleted: Bool)` with mood, waterML, caffeineMG and breathingSeconds kinds.
- `TrendService.swift`: `summarize(samples: [HealthSample], assessments: [WellnessAssessment], habits: [HabitEntry], range: DateInterval, calendar: Calendar) -> TrendReport`.
- `Apps/Shared/Health/HealthRepository.swift`: protocol `requestReadAccess(for: Set<MetricKind>) async throws`; `changes(for: MetricKind, anchor: Data?) async throws -> HealthChanges` (inserted/deletedIDs/newAnchor).
- `Apps/Shared/Storage/HistoryStore.swift`: actor exposing `apply(_ changes: HealthChanges) async throws`, `upsertHabit(_ entry: HabitEntry) async throws`, `snapshot() async throws -> StoredSnapshot`, `clearLocalData() async throws`.
- `Apps/Shared/Connectivity/SyncCoordinator.swift`: `merge(_ envelope: SyncEnvelope) async throws -> MergeResult`; Codable envelope contains schema version, settings revision, optional summary and habit changes. Settings authority iPhone; habit merge orders `(revision, origin)` lexicographically; tombstones win equal revisions.
- `Apps/iOS/`, `Apps/Watch/`, `Apps/iOSWidgets/`, `Apps/WatchWidgets/`: separate platform targets consuming the shared package/adapters. Tests live beside the responsible package or under `Tests/Integration/` and `Tests/UI/`.
- `.github/workflows/ci.yml`, `project.yml`, `scripts/verify-platform.sh`, `scripts/verify-release.sh`: reproducible project/build checks. `docs/device-checklist.md` separates simulator evidence from real hardware evidence.

## Task 1: Reproducible Public Build and Platform Gate

**Files:** Create `Package.swift` in WellnessCore package, `project.yml`, minimal app/widget target entry files, scripts and workflow above, README, LICENSE, `.gitignore`, synthetic fixtures and `Tests/BuildConfigurationTests.swift`.
**Interfaces:** Produces schemes `CalmPulse-iOS`, `CalmPulse-Watch`, `CalmPulse-iOSWidgets`, `CalmPulse-WatchWidgets`; shared module `WellnessCore`. No health data/signing needed.
- [ ] Write failing configuration tests: `XCTAssertEqual(config.iOSMinimum,"27.0")`; `XCTAssertEqual(config.watchOSMinimum,"27.0")`; `XCTAssertFalse(config.workflowUsesSecrets)`.
- [ ] Run configuration test harness and confirm missing configuration fails before creating product scaffold.
- [ ] After plan approval create public repo, verify owner/name/visibility, add reviewed spec/plan, original-source MIT notice and minimal compilable targets; use a confirmed standard macOS label, not a larger runner. Verify `xcodebuild -version`, `xcodebuild -showsdks`, `xcrun simctl list runtimes` report usable iOS/watchOS 27 support. If not, stop and report exact missing SDK/runtime; no silent fallback.
- [ ] Run `scripts/verify-platform.sh`, `xcodebuild -list` and unsigned simulator builds for both app schemes. Expected exit 0 and `BUILD SUCCEEDED`. Capture exact destinations to reuse; never assume device names. Configure one workflow per commit, concurrency cancellation, 30-minute timeout and short artifact retention; no signing or distribution.
- [ ] Commit buildable baseline and evidence; private runtime credentials, personal metadata, health records and scratch research never enter public history.

## Task 2: SDNN Engine and Notification Decisions

**Files:** Create core Models, WellnessEngine, NotificationPolicy and `Tests/WellnessCoreTests/{WellnessEngineTests,NotificationPolicyTests}.swift`.
**Interfaces:** Produces exact assess/decision signatures in File Map.
- [ ] Write failing fixtures: 7 prior days each `[10,20,30]`, current 20 => `XCTAssertEqual(result.score,50)`; current 40 => score 0; current 5 => score 100. Six days or 19 samples => nil score. Source B samples do not change source A result. Today excluded; adding ten duplicate low samples to one day must not increase that day's weight versus other days. Zero/NaN/infinity invalid. DST local days retain unique civil dates.
- [ ] `swift test --package-path Packages/WellnessCore --filter WellnessEngineTests` must fail on absent implementation.
- [ ] Implement equal-day mean midrank percentile over previous 28 complete civil days, score `round(100*(1-P))`, clamp 0...100; same source; unique UUID; exclude workouts through 30 minutes after end. Baseline min 7 days/20 samples; 7...13 days limited, 14+ established. Freshness at age >3h becomes historical. Bands 0...24 /25...49 /50...74 /75...100; version `wellness-sdnn-v1`. RHR never silently mixed into score.
- [ ] Write/run failing policy tests then implement: enabled plus two highest-band assessments within 6h, latest <=3h, cooldown >=2h, quiet interval [22:00,08:00), explicit owner. Assert disabled/stale/one-sample/duplicate IDs never send; assert exact 08:00 allowed and 22:00 blocked. Local DST times use Calendar.
- [ ] Run `swift test --package-path Packages/WellnessCore`; all tests pass, then commit engine and policy together with formula documentation.

## Task 3: Incremental HealthKit Reading

**Files:** Create HealthRepository protocol, `HealthKitRepository.swift`, `PermissionCoordinator.swift`, `SampleNormalizer.swift`, `Tests/Integration/HealthRepositoryTests.swift`.
**Interfaces:** Consumes core models; produces HealthChanges and neutral data-status states.
- [ ] Write failing mock tests: same UUID inserted twice produces one sample; deletion removes and invalidates assessment; absent read data => `XCTAssertEqual(status.message,"暂未读到记录")`; partial sleep denial leaves core SDNN functional; unsupported optional metric never requested.
- [ ] Run iOS integration test target and confirm failure before adapters.
- [ ] Implement observer+anchored query incremental retrieval, persisted per-type anchors, source metadata, deletes, completion handlers and foreground catch-up. Request SDNN/RHR first; optional HR/workouts, sleep, steps/energy/exercise, daylight/mindfulness only on feature entry. No HealthKit writes or false claims that read permission can be detected. Enable documented HealthKit/background entitlements with matching purpose strings.
- [ ] Run mock integration tests and synthetic HealthKit simulator flows; verify exact granted/requested matrix. Report background-delivery behavior as unverified until device testing.
- [ ] Commit reader and permission handling.

## Task 4: Protected Storage and Offline Synchronization

**Files:** Create HistoryStore, `FileProtection.swift`, HabitModels, SyncEnvelope/SyncCoordinator and `StorageTests.swift`, `SyncTests.swift`.
**Interfaces:** Uses File Map actors and envelopes; schema v1, UInt64 revisions, deterministic origin ordering.
- [ ] Write failing tests: duplicate envelope => unchanged snapshot; higher revision wins; equal revision tombstone wins; old insert after delete stays deleted; older observedAt summary cannot replace newer; locked-store read returns protected/unavailable state rather than zero data; iPhone settings override watch proposal; double clear is safe.
- [ ] Run targeted storage/sync tests, confirm red; implement protected files, backups excluded, atomic writes, minimal app-group summaries, queued WatchConnectivity transfers and bounded retries. Clear logs/cache only with user confirmation; leave Apple Health untouched.
- [ ] Assert secrets/values never reach diagnostic logs; inspect file protection/backup attributes and serialized envelope to ensure no whole HealthKit history transfer. Lost schema version rejects safely without deleting current records.
- [ ] Rerun storage/sync suites and core tests; commit storage and connectivity.

## Task 5: Trends Sleep Activity and Habit Analysis

**Files:** Create TrendService, `SleepAggregator.swift`, `ActivitySummary.swift`, `HabitInsights.swift`, corresponding tests.
**Interfaces:** Produces TrendReport with sparse points, coverage, sample-band distribution, sleep/activities and descriptive habit comparisons.
- [ ] Write failing tests: gap remains gap; three highest of four scored samples => 75% sample share, never six hours of stress; overlapping sleep sources do not double count; no HR zones configured => raw workout summary; empty permission returns unavailable section; water/caffeine totals respect civil day and deleted entries.
- [ ] Run targeted suites, confirm failures; implement day/week/month/year range summaries, stage-if-present sleep, exercise/daylight/mindfulness, user-entered HR-zone boundaries, habit totals and weekly report.
- [ ] Implement conservative associations only after >=14 paired civil days, with at least 5 days per compared group. Show group counts and direction of median SDNN difference; label association not causation. Constant/no-variation or insufficient samples => information insufficient. No inferred biological age, diagnoses or continuous stress durations.
- [ ] Assert these minimum counts and no-variation behaviors in HabitInsightsTests; run full package suite and commit.

## Task 6: iPhone and Watch User Flows

**Files:** Create iOS four-tab views/viewmodels, Watch home/trend/log/breathing views, shared `BreathingSession.swift`, localization and `Tests/UI/OnboardingTests.swift`, `HabitFlowTests.swift`, `BreathingTests.swift`.
**Interfaces:** Consumes repository/store/report/assessment; breathing state `start(durationSeconds:)`, `pause()`, `resume()`, `stop()`, `remaining(at:)`. Uses wall-clock elapsed time, never a background tick count.
- [ ] Write failing UI tests for no-data onboarding, partial permissions, add/edit/delete each local habit, restart mid-breathing session, hidden HealthKit-write behavior and selected date range restoration.
- [ ] Run UI/logic tests red; implement Today/Trends/Habits/Settings, SDNN label/source/time/baseline/limitations, original themes, editable reminder settings, quiet hours and explicit notification-owner mode. Watch quick logs and breathing haptics do not claim to force HRV measurement.
- [ ] Run tests green; inspect Chinese, dark mode, large text and VoiceOver on both platform simulators. Fix truncation/contrast and verify destructive-clear confirmation. Commit user flows.

## Task 7: Widgets and Actual Local Notifications

**Files:** Create iOS/Watch timeline providers and widget views, `NotificationCoordinator.swift`, tests `WidgetFreshnessTests.swift`, `NotificationCoordinatorTests.swift`.
**Interfaces:** Consumes minimal StoredSummary plus NotificationPolicy decisions; persists last-delivered sample identifiers and local send time.
- [ ] Write failing assertions: stale summary => historical label; protected-store unavailable => no numeric value; repeated same decision => one notification; phone mode cannot issue while Watch owner selected; no permission => no request scheduled.
- [ ] Run red tests; implement small/lockscreen widgets, circular/rectangular Watch complications and Smart Stack. Mark sensitive content, offer hide-values, schedule stale-state transition, and request reload only after changes; no promised refresh cadence.
- [ ] Implement UserNotifications permission only after opt-in and durable idempotent scheduling. Never bypass Focus or quiet-time behavior. Use unchanged fresh inputs when app resumes.
- [ ] Run tests, inspect both widgets and exact data-age labels on simulators. Commit widgets and notifications.

## Task 8: Whole-App Verification and Install Handoff

**Files:** Create `docs/device-checklist.md`, `docs/privacy.md`, update README and verification scripts.
**Interfaces:** Produces source revision, public CI links, unsigned build evidence and explicit pass/failed/not-run matrix; no claim of signed installation unless verified.
- [ ] Add release-gate tests that fail if CI has secrets in PR jobs, prohibited SDKs are linked, purpose strings are absent, deployment targets differ from 27.0, or synthetic fixtures lack demonstration labeling.
- [ ] Run `scripts/verify-release.sh`, full core/integration/UI suites, all four target builds on discovered SDK27 destinations. Scan tracked files/history and published artifacts for credentials/health data; inspect privacy/entitlements/dependencies/license notices. Expected zero test/build failures and no secret findings.
- [ ] Independent branch review fixes require regression tests and complete rerun for affected targets. Verify remote public visibility and exact final commit's CI status; do not merge/publish signed releases beyond authorized scope.
- [ ] Report installation gates honestly: real paired iPhone/Watch authorization, background delivery, notifications, sync and energy tests remain manual until authorized devices are available. Signing certificates/persistent access and Apple membership require separate approval/secure setup. Stop without charging or requesting real health exports.
- [ ] Commit final docs, tests and evidence; present completed software scope separately from unperformed device/signing checks.

## Execution Recommendation and Approval

Recommend subagent-driven execution with a new implementer and independent reviewer per task, because notification ownership, source-based baselines and deletion propagation cross platform boundaries and mistakes affect private health interpretation. Native sequential execution with one final independent review is the lower-overhead alternative. User must review this plan and choose the method before repository creation or code implementation.

## Self-Review Result

All nine spec sections map to Tasks 1–8. Core signatures are declared in File Map; no unresolved referenced interfaces. Five review-focus conditions have explicit assertions in owning tasks. Scope includes the full approved features; exclusions, device limitations, public licensing and no-charge policy remain explicit. No implementation has been performed.
