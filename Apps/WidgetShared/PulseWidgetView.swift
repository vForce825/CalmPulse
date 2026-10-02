import SwiftUI
import WidgetKit
import WellnessServices

struct PulseWidgetView: View {
    let entry: PulseEntry
    @Environment(\.widgetFamily) private var family
    @Environment(\.widgetRenderingMode) private var renderingMode
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced
    var body: some View {
        PulseWidgetContent(entry: entry, family: family)
            .privacySensitive()
            .containerBackground(for: .widget) {
                if renderingMode == .fullColor && !isLuminanceReduced,
                   let band = entry.state.presentation.bandIndex {
                    LinearGradient(colors: [WidgetStressStyle.color(band).opacity(0.18), Color.primary.opacity(0.02)],
                        startPoint: .topLeading, endPoint: .bottomTrailing)
                } else { Color.clear }
            }
    }
}

/// The extension shares the same presentation gate as the app, with no raw health values in its UI.
struct PulseWidgetContent: View {
    let entry: PulseEntry
    let family: WidgetFamily
    @Environment(\.widgetRenderingMode) private var renderingMode
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced
    private var presentation: StressPresentation { entry.state.presentation }
    private var accent: Color {
        guard let band = presentation.bandIndex else { return .secondary }
        return renderingMode == .fullColor && !isLuminanceReduced ? WidgetStressStyle.color(band) : .primary
    }
    private var symbol: String {
        switch presentation.state {
        case .hidden, .locked: "lock.fill"
        case .historical: "clock.arrow.circlepath"
        case .learning: "leaf"
        case .reading: "leaf.fill"
        case .missing: "sparkle"
        case .invalid, .unavailable, .failed: "minus.circle"
        }
    }
    var body: some View {
        Group {
            switch family {
            case .accessoryCircular: circular
            case .accessoryInline: inline
            case .accessoryRectangular: rectangular
            default: home
            }
        }
        .privacySensitive()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("CalmPulse，压力参考，" + accessibilitySummary)
    }
    private var circular: some View {
        ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: 2) {
                Image(systemName: symbol).font(.caption).foregroundStyle(accent).widgetAccentable()
                Text(presentation.title).font(.caption2.weight(.semibold))
                    .multilineTextAlignment(.center).lineLimit(2)
                if let observedAt = presentation.observedAt {
                    Text(observedAt, format: .dateTime.hour().minute().locale(Locale(identifier: "zh_Hans_CN"))).font(.system(size: 10)).monospacedDigit()
                }
            }.padding(4).minimumScaleFactor(0.8)
        }
    }
    private var inline: some View {
        Label { inlineText } icon: { Image(systemName: symbol) }
    }
    private var inlineText: Text {
        let title = Text(presentation.title)
        if let observedAt = presentation.observedAt {
            return title + Text(" · ") + Text(observedAt, format: .dateTime.hour().minute().locale(Locale(identifier: "zh_Hans_CN"))) + Text("记录")
        }
        return title
    }
    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Image(systemName: symbol).foregroundStyle(accent).widgetAccentable()
                Text(presentation.isInitial ? "初步压力参考" : "压力参考").font(.caption2)
            }.foregroundStyle(.secondary)
            Text(presentation.title).font(.headline).lineLimit(1).minimumScaleFactor(0.8)
            if let observedAt = presentation.observedAt {
                ageLine(observedAt).font(.caption2)
            } else {
                Text("打开应用查看").font(.caption2).foregroundStyle(.secondary)
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private var home: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: symbol).foregroundStyle(accent).widgetAccentable()
                Text(presentation.isInitial ? "压力参考 · 初步了解" : "CalmPulse · 压力参考")
                    .font(.caption2.weight(.medium)).foregroundStyle(.secondary)
            }.lineLimit(1).minimumScaleFactor(0.8)
            Text(presentation.title).font(.system(.title2, design: .rounded, weight: .bold))
                .lineLimit(2).minimumScaleFactor(0.85)
            if presentation.bandIndex != nil {
                HStack(spacing: 4) {
                    ForEach(0..<4) { index in
                        Capsule().fill(index == presentation.bandIndex ? accent : Color.secondary.opacity(0.18))
                            .frame(height: 5)
                    }
                }.accessibilityHidden(true)
            }
            Text(presentation.explanation).font(.caption2).foregroundStyle(.secondary).lineLimit(3)
            Spacer(minLength: 0)
            if let observedAt = presentation.observedAt {
                ageLine(observedAt).font(.caption2)
            }
            #if os(iOS)
            if family == .systemMedium {
                Text("身体信号参考 · 不能判断真实情绪").font(.caption2).foregroundStyle(.secondary)
            }
            #endif
        }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
    private func ageLine(_ date: Date) -> some View {
        HStack(spacing: 2) {
            Text(date, format: .dateTime.hour().minute().locale(Locale(identifier: "zh_Hans_CN"))).monospacedDigit()
            Text("记录")
        }.foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.8)
    }
    private var accessibilitySummary: String {
        var parts = [presentation.title, presentation.explanation]
        if presentation.isInitial { parts.append("初步了解") }
        if let observedAt = presentation.observedAt {
            parts.append("记录于 " + observedAt.formatted(.dateTime.year().month().day().hour().minute()))
        }
        return parts.joined(separator: "，")
    }
}

private enum WidgetStressStyle {
    static func color(_ band: Int) -> Color {
        [Color(red: 0.35, green: 0.61, blue: 0.47), Color(red: 0.49, green: 0.56, blue: 0.76),
         Color(red: 0.76, green: 0.53, blue: 0.30), Color(red: 0.69, green: 0.39, blue: 0.39)][min(3, max(0, band))]
    }
}
