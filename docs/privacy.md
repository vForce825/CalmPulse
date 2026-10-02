# Privacy and interpretation

CalmPulse is a general wellness reference, not diagnosis or a measure of emotions. SDNN is shown in milliseconds, never as RMSSD. The 0–100 scale is an intentionally defined personal historical rank, not a stress percentage, health probability, or continuous exposure duration. Low values do not prove good health. Sampling, sleep, wearing patterns and workouts affect comparability.

All health processing, caches and habit logs stay on your iPhone and paired Apple Watch. No account, server, analytics, ads, cloud AI, CloudKit or subscription is included. The system's Apple Health/iCloud behavior remains controlled by your device settings. Original Apple Health records are read-only.

Core permissions request SDNN and resting heart rate. Optional screens separately explain and request sleep, workouts/heart rate, activity, daylight and mindfulness. An empty response is labeled “暂未读到记录”; apps cannot discover whether read permission was refused. Foreground reconciliation replaces locally cached records with records currently visible from HealthKit. Observer/anchored queries handle incremental additions and deletions in the background.

Cache files and local logs use complete-until-first-user-authentication protection and are excluded from device cloud backups. Before first unlock, unavailable protected data is not rendered as zero. Clearing local data never deletes Apple Health records; available health records may be read again on next refresh. Deletion metadata (UUID, habit kind, original timestamp, revision and origin), deleted-health UUIDs, evaluated/delivered notification UUIDs and the notification cooldown timestamp remain to prevent offline log resurrection and repeat alerts. Measurement values and habit notes are removed; settings remain unchanged. This is not an erase-all-identifiers operation.

WatchConnectivity shares versioned settings, minimal peer summaries and local habit logs only with the paired device. Device-local HealthKit source identifiers are not portable settings. Peer summaries remain separate from local assessments, widgets and notification decisions. Out-of-order/replayed log changes are merged deterministically, with deletion winning equal revisions.

Widgets default to hidden values, use privacy-sensitive rendering, and distinguish historical readings older than three hours. Widget refresh and HealthKit background delivery are system-controlled; no update frequency is guaranteed. Notifications default off, require explicit opt-in and system permission, respect quiet hours and Focus, and have one explicit owner. No workout is started to keep the app alive.

Development and CI use synthetic fixtures only. No real health exports, habit records or signing credentials belong in this public repository or its logs.
