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
                if renderingMode == .fullColor && !isLuminanceReduced {
                    LinearGradient(colors: [Color.teal.opacity(0.13), .clear], startPoint: .topLeading, endPoint: .bottomTrailing)
                } else { Color.clear }
            }
    }
}

struct PulseWidgetContent: View {
    let entry: PulseEntry
    let family: WidgetFamily
    @Environment(\.widgetRenderingMode) private var renderingMode
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced

    private var accent: Color {
        renderingMode == .fullColor ? (colorScheme == .dark ? .cyan : .teal) : .primary
    }
    private var historical: Bool {
        guard let observedAt = entry.state.observedAt else { return false }
        return entry.date.timeIntervalSince(observedAt) > 10_800
    }
    private var hidden: Bool { entry.state.label == "已隐藏数值" }
    private var status: String {
        if hidden { return historical ? "历史 · 数值隐藏" : "已隐藏数值" }
        return historical ? "历史读数" : entry.state.label
    }
    private var symbol: String {
        if hidden { return "lock.fill" }
        if entry.state.observedAt == nil { return "waveform.path" }
        return historical ? "clock.arrow.circlepath" : "waveform.path.ecg"
    }

    var body: some View {
        Group {
            switch family {
            case .accessoryCircular:
                circular
            case .accessoryInline:
                inline
            case .accessoryRectangular:
                rectangular
            default:
                home
            }
        }
        .privacySensitive()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("CalmPulse，" + accessibilitySummary)
    }

    private var circular: some View {
        ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: 1) {
                if let sdnn = entry.state.sdnn {
                    Text(historical ? "历史SDNN" : "SDNN")
                        .font(.caption2)
                    HStack(alignment: .firstTextBaseline, spacing: 1) {
                        Text(sdnn, format: .number.precision(.fractionLength(0)))
                            .font(.headline).monospacedDigit()
                        Text("ms").font(.caption2)
                    }
                    if let observedAt = entry.state.observedAt {
                        Text(observedAt, style: .timer).font(.caption2).monospacedDigit()
                    }
                } else {
                    Image(systemName: symbol).font(.body).widgetAccentable()
                    Text(hidden ? (historical ? "历史·隐藏" : "已隐藏") : (entry.state.label == "解锁后查看" ? "待解锁" : "无记录"))
                        .font(.caption2)
                    if let observedAt = entry.state.observedAt {
                        Text(observedAt, style: .timer).font(.caption2).monospacedDigit()
                    }
                }
            }
            .minimumScaleFactor(0.75)
        }
    }

    private var inline: some View {
        Label {
            inlineText
        } icon: {
            Image(systemName: symbol)
        }
    }

    private var inlineText: Text {
        let value: Text
        if let sdnn = entry.state.sdnn {
            value = Text((historical ? "历史SDNN " : "SDNN ") + sdnn.formatted(.number.precision(.fractionLength(0))) + "ms")
        } else {
            value = Text(status)
        }
        if let observedAt = entry.state.observedAt {
            return value + Text(" · ") + Text(observedAt, style: .timer)
        }
        return value
    }

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: symbol).widgetAccentable()
                Text(status).font(.caption).fontWeight(.semibold)
            }
            if let sdnn = entry.state.sdnn {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("SDNN").font(.caption)
                    Text(sdnn, format: .number.precision(.fractionLength(1)))
                        .font(.headline).monospacedDigit()
                    Text("ms").font(.caption2)
                    if let score = entry.state.score {
                        Spacer(minLength: 2)
                        Text("相对 \(score)").font(.caption2).monospacedDigit()
                    } else {
                        Spacer(minLength: 2)
                        Text("建基线").font(.caption2)
                    }
                }
            }
            if let observedAt = entry.state.observedAt {
                ageLine(observedAt).font(.caption2)
            } else {
                Text("打开应用查看").font(.caption2).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var home: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 5) {
                Image(systemName: symbol).foregroundStyle(accent).widgetAccentable()
                Text("CalmPulse").font(.caption).fontWeight(.semibold)
            }
            Text(status).font(.caption).foregroundStyle(.secondary)
            if let sdnn = entry.state.sdnn {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(sdnn, format: .number.precision(.fractionLength(1)))
                        .font(.title).fontWeight(.semibold).monospacedDigit()
                    Text("SDNN ms").font(.caption2)
                }
                if let score = entry.state.score {
                    Text("相对趋势 \(score) / 100").font(.caption).monospacedDigit()
                } else {
                    Text("建立个人基线中").font(.caption2)
                }
            } else {
                Text(hidden ? "数值仅在应用内查看" : "打开应用查看本机记录")
                    .font(.callout).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            if let observedAt = entry.state.observedAt {
                ageLine(observedAt).font(.caption2)
                Text(observedAt, format: .dateTime.month().day().hour().minute())
                    .font(.caption2).foregroundStyle(.secondary)
            }
            #if os(iOS)
            if family == .systemMedium {
                Text("个人相对刻度 · 一般健康参考").font(.caption2).foregroundStyle(.secondary)
            }
            #endif
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .minimumScaleFactor(0.8)
    }

    private func ageLine(_ date: Date) -> some View {
        HStack(spacing: 3) {
            Text(historical ? "历史 · 距采集" : "距采集")
            Text(date, style: .timer).monospacedDigit()
        }
        .lineLimit(1)
        .minimumScaleFactor(0.75)
    }

    private var accessibilitySummary: String {
        var parts = [status]
        if historical { parts.append("超过三小时，仅供历史参考") }
        if let sdnn = entry.state.sdnn {
            parts.append("SDNN \(sdnn.formatted(.number.precision(.fractionLength(1)))) 毫秒")
            if let score = entry.state.score { parts.append("个人相对趋势 \(score)，范围零至一百") }
            else { parts.append("个人基线不足，未显示趋势分值") }
        }
        if let observedAt = entry.state.observedAt {
            let interval = entry.date.timeIntervalSince(observedAt)
            let age = interval.isFinite && interval >= 0 && interval < Double(Int.max) ? Int(interval) : 0
            parts.append("采集于 " + observedAt.formatted(.dateTime.year().month().day().hour().minute().second()))
            parts.append("此展示生成时距采集 \(age / 3600) 小时 \((age % 3600) / 60) 分 \(age % 60) 秒")
        }
        return parts.joined(separator: "，")
    }
}
