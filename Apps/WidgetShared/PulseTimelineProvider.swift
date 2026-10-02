import Foundation
import WidgetKit
import WellnessServices

/// A timeline contains only the values allowed by the protected, same-device cache.
struct PulseEntry: TimelineEntry {
    let date: Date
    let state: WidgetState
}

struct PulseTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> PulseEntry {
        // The gallery must never invent a health reading or expose a cached value.
        PulseEntry(date: .now, state: WidgetState(summary: nil, now: .now, protectedDataAvailable: true))
    }

    func getSnapshot(in context: Context, completion: @escaping (PulseEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : read(at: .now))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<PulseEntry>) -> Void) {
        let current = read(at: .now)
        var entries = [current]
        if let transition = current.state.nextTransition, transition > current.date {
            // Precompute the conservative three-hour transition. System scheduling can delay it.
            // Relative-age text continues to update without querying HealthKit or reloading the app.
            entries.append(read(at: transition))
        }
        completion(Timeline(entries: entries, policy: .never))
    }

    private func read(at date: Date) -> PulseEntry {
        guard let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: WidgetCacheFile.groupID
        ) else {
            return PulseEntry(date: date, state: WidgetState(summary: nil, now: date, protectedDataAvailable: false))
        }
        let file = container.appendingPathComponent("summary.json")
        return PulseEntry(date: date, state: WidgetCacheFile.read(from: file, now: date))
    }
}
