# Health data read and cache coverage

This adapter policy reduces lifetime raw-record volume without truncating the iPhone's SDNN/trend or daily activity history. All queries read only records currently visible in the device's local HealthKit store. Empty results cannot distinguish absent data from declined read permission.

## iPhone

- SDNN, resting heart rate, sleep, mindfulness sessions, and raw workout metadata retain complete visible history. Foreground reconciliation and anchored changes preserve original UUIDs and SDNN/device source identities. No local habit logs are subject to a health read cutoff
- Steps, active energy, Apple exercise time, and daylight use HealthKit cumulative statistics, partitioned into local civil-day buckets and separated by HKSource. The earliest visible date is found by a limit-1 sample query; lifetime raw quantities are never loaded. Every refresh (including an observer wake) returns the complete daily-statistics result for that metric
- Raw heart rate used by the recent overview has a rolling 90-calendar-day cache: Calendar.current subtracts 90 days from the read time, rather than assuming every day is 86,400 seconds. The predicate retains records overlapping the cutoff as well as records starting after it; incremental reads also expire records ending before the cutoff. Workout metadata remains complete
- Historical workout detail may explicitly fetch heart-rate samples only for that workout's start-inclusive/end-exclusive range after HR was opted in. These transient records do not update the routine cache or anchors. No HR samples means unavailable mean/min/max/zones; no values or durations are invented

## Watch

Watch keeps a brief local health history. SDNN, RHR, heart rate, sleep, and mindfulness reads/cache use the same rolling 90-calendar-day cutoff. Workout reads retain an additional 30-minute boundary lookback because scoring excludes exercise and the following 30 minutes. Daily activity statistics begin at the midnight containing the 90-day cutoff, preserving the entire edge-day bucket; their maximum coverage is therefore 90 calendar days plus the elapsed portion of that boundary day. This is device-local coverage, not a claim that Watch contains complete iPhone history. User-created local habit logs remain untruncated.

The oldest Watch SDNN samples may lack the earlier 28-day baseline and appropriately show insufficient information; a shortened cache never substitutes a fabricated baseline.

## Aggregate semantics and deletion

Each daily aggregate has a deterministic synthetic UUID keyed by metric, source identity, and the bucket's absolute start. Changing a total keeps its ID; different sources/kinds/days remain distinct. ActivitySummary keeps one deterministic primary source per metric; with source-level daily totals this selection uses covered-day count then source key, without guessing a Watch-device preference. Source-level identity is derived only from the HKSource bundle identifier for these four cumulative kinds. HKStatistics does not expose per-record HKDevice identity. This path never handles SDNN and cannot merge SDNN baselines.

A daily total is normalized as a point at the civil-day bucket start. It represents a daily total, not a measurement at midnight or a uniform intraday distribution. In particular, today's partial-day sum is not prorated a second time by ActivitySummary. These aggregates support day-based views; they do not promise intraday activity detail.

A complete aggregate response atomically replaces all cached samples of that metric and removes its obsolete raw-query anchor. Empty buckets are omitted rather than reported as measured zero. An empty complete response removes all old totals; source removal or HealthKit deletion cannot leave stale source/day aggregates. Other metrics and local habit logs are unaffected. A query error does not provide a replacement result. Unexpected noncumulative types and missing statistics results are explicit errors rather than a guessed fallback.

Timezone/calendar changes are reconciled by the next complete statistics refresh; the old daily buckets are replaced. Calendar-day boundaries and DST must still be verified against HealthKit on real iPhone/Watch hardware. Portable synthetic tests validate policy, deterministic IDs, source separation, point totals, complete/empty replacement, bounded-cache expiry, and inclusive/exclusive detail-range edges. They do not validate HealthKit delivery, permission, source, or statistics behavior.

## Apple API references

- [Statistics collection query](https://developer.apple.com/documentation/healthkit/hkstatisticscollectionquery) and [collection query example and interval/anchor semantics](https://developer.apple.com/documentation/healthkit/executing-statistics-collection-queries)
- [Statistics options](https://developer.apple.com/documentation/healthkit/hkstatisticsoptions), [separateBySource](https://developer.apple.com/documentation/healthkit/hkstatisticsoptions/separatebysource), and [per-source sum](https://developer.apple.com/documentation/healthkit/hkstatistics/sumquantity(for:))
- Cumulative types: [steps](https://developer.apple.com/documentation/healthkit/hkquantitytypeidentifier/stepcount), [active energy](https://developer.apple.com/documentation/healthkit/hkquantitytypeidentifier/activeenergyburned), [exercise time](https://developer.apple.com/documentation/healthkit/hkquantitytypeidentifier/appleexercisetime), and [daylight](https://developer.apple.com/documentation/healthkit/hkquantitytypeidentifier/timeindaylight)
- [Sample query](https://developer.apple.com/documentation/healthkit/hksamplequery) and [sample date predicate](https://developer.apple.com/documentation/healthkit/hkquery/predicateforsamples(withstart:end:options:))
