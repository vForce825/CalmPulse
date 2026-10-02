import SwiftUI
import WidgetKit
struct PulseEntry: TimelineEntry { let date: Date }
struct PulseProvider: TimelineProvider {
    func placeholder(in context: Context) -> PulseEntry { PulseEntry(date: .now) }
    func getSnapshot(in context: Context, completion: @escaping (PulseEntry) -> Void) { completion(PulseEntry(date: .now)) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<PulseEntry>) -> Void) { completion(Timeline(entries: [PulseEntry(date: .now)], policy: .never)) }
}
@main struct CalmPulseWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "CalmPulse", provider: PulseProvider()) { _ in
            Text("暂未读到记录").privacySensitive().containerBackground(.fill.tertiary, for: .widget)
        }.configurationDisplayName("CalmPulse").description("本地健康趋势与数据年龄")
    }
}
