import SwiftUI
import WidgetKit

@main struct CalmPulseWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "CalmPulse", provider: PulseTimelineProvider()) { entry in
            PulseWidgetView(entry: entry)
        }
        .configurationDisplayName("CalmPulse · 本机趋势")
        .description("查看SDNN与采集时间。数值默认隐藏，三小时后标记为历史读数。")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}
