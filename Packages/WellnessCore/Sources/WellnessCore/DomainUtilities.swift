import Foundation

/// Internal helpers never contact a service or alter the supplied records.
enum DomainUtilities {
    static func validInterval(_ start: Date, _ end: Date) -> Bool {
        start.timeIntervalSince1970.isFinite && end.timeIntervalSince1970.isFinite && end >= start
    }
    static func uniqueSamples(_ samples: [HealthSample]) -> [HealthSample] {
        var seen = Set<UUID>()
        return samples.filter { validInterval($0.start, $0.end) && $0.value.isFinite }.sorted {
            if $0.start != $1.start { return $0.start < $1.start }
            if $0.end != $1.end { return $0.end < $1.end }
            if $0.sourceID != $1.sourceID { return $0.sourceID < $1.sourceID }
            if $0.value != $1.value { return $0.value < $1.value }
            return $0.id.uuidString < $1.id.uuidString
        }.filter { seen.insert($0.id).inserted }
    }
    static func civilDays(in range: DateInterval, calendar: Calendar) -> [Date] {
        guard validInterval(range.start, range.end), range.duration > 0 else { return [] }
        var day = calendar.startOfDay(for: range.start)
        var days: [Date] = []
        while day < range.end {
            days.append(day)
            guard let next = calendar.date(byAdding: .day, value: 1, to: day), next > day else { break }
            day = next
        }
        return days
    }
    static func slices(start: Date, end: Date, range: DateInterval, calendar: Calendar) -> [(day: Date, start: Date, end: Date)] {
        guard validInterval(start, end), end > start, range.duration > 0 else { return [] }
        var cursor = max(start, range.start)
        let limit = min(end, range.end)
        var result: [(Date, Date, Date)] = []
        while cursor < limit {
            let day = calendar.startOfDay(for: cursor)
            guard let next = calendar.date(byAdding: .day, value: 1, to: day), next > cursor else { break }
            let end = min(next, limit)
            result.append((day, cursor, end))
            cursor = end
        }
        return result
    }
    static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted(), middle = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? sorted[middle - 1] / 2 + sorted[middle] / 2 : sorted[middle]
    }
    static func primarySource(in samples: [HealthSample]) -> String? {
        let grouped = Dictionary(grouping: samples, by: \.sourceID)
        return grouped.keys.sorted { a, b in
            let left = grouped[a]!, right = grouped[b]!
            let leftWatch = left.contains(where: \.isAppleWatch), rightWatch = right.contains(where: \.isAppleWatch)
            if leftWatch != rightWatch { return leftWatch }
            if left.count != right.count { return left.count > right.count }
            return a < b
        }.first
    }
    static func canonicalHabits(_ entries: [HabitEntry]) -> [HabitEntry] {
        var selected: [UUID: HabitEntry] = [:]
        for entry in entries {
            guard let old = selected[entry.id] else { selected[entry.id] = entry; continue }
            if entry.revision > old.revision ||
               (entry.revision == old.revision && entry.deleted && !old.deleted) ||
               (entry.revision == old.revision && entry.deleted == old.deleted && entry.origin > old.origin) {
                selected[entry.id] = entry
            }
        }
        return selected.values.sorted { $0.id.uuidString < $1.id.uuidString }
    }
}
