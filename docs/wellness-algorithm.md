# Local wellness algorithm, version wellness-sdnn-v1

This original, deterministic scale describes the current SDNN measurement's position relative to the same source's earlier measurements. It does not measure psychological stress, clinical risk, or an uninterrupted duration. SDNN is measured in milliseconds and is not RMSSD. Resting heart rate is separate context and is not an input to the scale.

For a current SDNN sample, use the preceding 28 complete civil days in the supplied Calendar and time zone. The current sample's civil day is excluded. A source change creates a separate baseline. UUIDs are deduplicated. Only finite, positive SDNN values with valid chronological intervals qualify. Samples overlapping a workout or its inclusive 30-minute post-workout tail are excluded from both the baseline and current scoring.

For each day d with eligible values, calculate `P_d = (count(lower than current) + 0.5 * count(equal to current)) / count(day values)`. Average `P_d` across days with equal weight, then calculate `round(100 * (1 - mean(P_d)))`, clamped to 0...100. Missing days contribute no fabricated values. At least seven populated days and 20 eligible baseline samples are required. Seven through thirteen days are labelled limited; fourteen or more established. These labels describe data coverage, not accuracy.

Bands are 0...24 low, 25...49 moderate, 50...74 high, and 75...100 highest. The score is a relative product scale, never a stress percentage. Result records retain source/sample identity, observation time, version, baseline window and counts. After strictly more than three hours, a result is historical. Future samples and current samples affected by exercise cannot score.

## Notification qualification

Notifications are disabled by default. The explicitly selected owner alone evaluates delivery. Watch is the default owner; iPhone mode must be chosen explicitly, with no automatic failover. The policy checks the newest two unique readings in the previous inclusive six hours. Both must be in the highest band and share source and algorithm version. The latest must be at most three hours old and marked fresh. Cooldown is at least two hours, and the newest sample must have been observed after the previous delivery to prevent replay. Default quiet hours are local 22:00 inclusive through 08:00 exclusive, using Calendar for DST boundaries.

Qualification does not guarantee a background wake, notification presentation, or minute-level delivery. The platform must call this policy on a new-data event and must persist the successful delivery time. No workout sessions are created to keep the app awake. Missing workout records cannot prove that exercise influence was excluded; the platform must disclose this data limitation.

## Verification

Tests use fixed synthetic values only. Portable tests cover known midrank values, boundary counts, equal civil-day weighting, source separation, UUID deduplication, invalid values, inclusive workout exclusion, 28-day windows, spring/fall DST, historical readings, notification quiet-hour/cooldown boundaries, ownership and replay suppression. Apple platform, authorization, background delivery and real-device behavior require separate verification.
