import SwiftUI
import WidgetKit

@main struct CalmPulseWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "CalmPulse", provider: PulseTimelineProvider()) { entry in
            PulseWidgetView(entry: entry)
        }
        .configurationDisplayName("CalmPulse · 本机趋势")
        .description("表盘与Smart Stack中的本机SDNN摘要。数值默认隐藏，显示采集年龄。")
        // accessoryRectangular also serves the watchOS Smart Stack.
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}
