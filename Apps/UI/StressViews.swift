import SwiftUI
import Charts
import WellnessCore
import WellnessServices

enum StressStyle {
    static let ink = Color(red: 0.14, green: 0.24, blue: 0.22)
    static let forest = Color(red: 0.20, green: 0.43, blue: 0.35)
    static let bands: [Color] = [Color(red: 0.35, green: 0.61, blue: 0.47), Color(red: 0.49, green: 0.56, blue: 0.76), Color(red: 0.76, green: 0.53, blue: 0.30), Color(red: 0.69, green: 0.39, blue: 0.39)]
    static func color(_ band: Int?) -> Color { band.map { bands[min(3, max(0, $0))] } ?? .secondary }
}

/// Original vector landscape: a sun, layered hills and ripples. No third-party artwork.
struct CalmLandscape: View {
    let band: Int?
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        GeometryReader { g in
            let w = g.size.width, h = g.size.height
            ZStack {
                LinearGradient(colors: scheme == .dark ? [Color(red: 0.12, green: 0.21, blue: 0.26), Color(red: 0.20, green: 0.29, blue: 0.30)] : [Color(red: 0.81, green: 0.89, blue: 0.90), Color(red: 0.94, green: 0.93, blue: 0.83)], startPoint: .top, endPoint: .bottom)
                Circle().fill(Color(red: 0.98, green: 0.82, blue: 0.51)).frame(width: h * 0.37, height: h * 0.37).position(x: w * 0.70, y: h * 0.29)
                Ellipse().fill(.white.opacity(0.30)).frame(width: w * 0.28, height: h * 0.08).position(x: w * 0.25, y: h * 0.22)
                hill(w: w, h: h, offset: 0.51, lift: 0.28).fill(Color(red: 0.46, green: 0.64, blue: 0.60).opacity(scheme == .dark ? 0.5 : 1))
                hill(w: w, h: h, offset: 0.74, lift: -0.22).fill(Color(red: 0.29, green: 0.50, blue: 0.45).opacity(scheme == .dark ? 0.7 : 1))
                Ellipse().fill(Color(red: 0.65, green: 0.79, blue: 0.75)).frame(width: w * 1.4, height: h * 0.50).position(x: w * 0.23, y: h * 1.01)
                ForEach(0..<3) { i in
                    Capsule().fill(.white.opacity(0.35)).frame(width: w * (0.10 + Double(i) * 0.07), height: 2).position(x: w * 0.30, y: h * (0.87 + Double(i) * 0.045))
                }
                Image(systemName: band == 3 ? "leaf" : "leaf.fill").font(.system(size: h * 0.15, weight: .light)).rotationEffect(.degrees(-25)).foregroundStyle(Color(red: 0.93, green: 0.94, blue: 0.81)).position(x: w * 0.82, y: h * 0.77)
            }
        }.accessibilityHidden(true).clipped()
    }
    private func hill(w: CGFloat, h: CGFloat, offset: CGFloat, lift: CGFloat) -> Path {
        Path { p in
            p.move(to: CGPoint(x: 0, y: h * offset))
            p.addCurve(to: CGPoint(x: w, y: h * (offset + 0.10)), control1: CGPoint(x: w * 0.40, y: h * (offset - lift)), control2: CGPoint(x: w * 0.72, y: h * (offset + lift)))
            p.addLine(to: CGPoint(x: w, y: h)); p.addLine(to: CGPoint(x: 0, y: h)); p.closeSubpath()
        }
    }
}
struct StressBandScale: View {
    let selected: Int?
    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<4) { index in
                Capsule().fill(StressStyle.bands[index].opacity(selected == nil ? 0.18 : selected == index ? 1 : 0.24))
                    .frame(height: selected == index ? 10 : 6)
                    .overlay { if selected == index { Circle().fill(.white).frame(width: 5, height: 5) } }
            }
        }.frame(height: 12).accessibilityHidden(true)
    }
}
struct StressHero: View {
    let model: AppController
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let presentation = StressPresentation(summary: model.summary, now: context.date, status: model.dataStatus)
            VStack(spacing: 0) {
                if !typeSize.isAccessibilitySize { CalmLandscape(band: presentation.bandIndex).frame(height: 160) }
                VStack(spacing: 13) {
                    Text(presentation.isInitial ? "初步压力参考" : "压力参考")
                        .font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
                    Text(presentation.title).font(.system(.largeTitle, design: .rounded, weight: .bold))
                        .multilineTextAlignment(.center).accessibilityIdentifier("stress.title")
                        .fixedSize(horizontal: false, vertical: true)
                    if let time = presentation.observedAt {
                        HStack(spacing: 4) {
                            Image(systemName: "clock")
                            Text(StressPresentation.ageText(observedAt: time, now: context.date))
                        }.font(.caption).foregroundStyle(.secondary)
                    }
                    StressBandScale(selected: presentation.bandIndex).padding(.horizontal, 28)
                    Text(presentation.explanation).font(.subheadline).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                    if !model.settings.requestedMetrics.contains(.sdnn) && model.summary == nil {
                        Button("连接 Apple 健康") { Task { await model.request([.sdnn, .restingHeartRate]) } }
                            .buttonStyle(.borderedProminent).tint(StressStyle.forest).accessibilityIdentifier("onboarding.readCore")
                        Text("无需账户 · 健康记录留在设备上").font(.caption2).foregroundStyle(.secondary)
                    } else {
                        NavigationLink { BreathingView(model: model) } label: {
                            Label("做 1 分钟呼吸", systemImage: "wind").font(.headline)
                                .frame(maxWidth: .infinity).padding(.vertical, 7)
                        }.buttonStyle(.borderedProminent).tint(StressStyle.forest).accessibilityIdentifier("today.breathing")
                    }
                    NavigationLink { StressDetailsView(model: model) } label: {
                        Text(presentation.state == .missing ? "为什么还没有记录？" : "这次结果怎么看").font(.caption.weight(.medium))
                    }.accessibilityIdentifier("stress.details")
                }.padding(22)
            }
            .background(scheme == .dark ? Color(red: 0.11, green: 0.16, blue: 0.16) : Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 30))
        }
    }
}
struct TodayStressTimeline: View {
    let model: AppController
    private var points: [WellnessAssessment] {
        let now = Date(), today = Calendar.current.startOfDay(for: now)
        guard let source = model.summary?.assessment.sourceID ?? model.settings.selectedSourceID else { return [] }
        return model.assessments.filter { $0.sourceID == source && $0.observedAt >= today && $0.observedAt <= now && $0.version == WellnessEngine.version && $0.confidence != .insufficient && StressPresentation.bandIndex(for: $0.score) != nil }.sorted { $0.observedAt < $1.observedAt }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("今天的变化").font(.headline)
                    Text(points.isEmpty ? "留一点时间，认识自己的节奏" : "\(points.count) 次参考 · 只呈现有记录的时刻")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                NavigationLink { TrendsView(model: model) } label: { Image(systemName: "arrow.up.right") }
                    .accessibilityLabel("查看更多趋势")
            }
            if points.isEmpty {
                HStack(spacing: 9) { Image(systemName: "sun.horizon"); Text("有了可比较的记录，变化会出现在这里。") }
                    .font(.subheadline).foregroundStyle(.secondary).frame(minHeight: 65)
            } else {
                Chart(Array(points.enumerated()), id: \.offset) { _, item in
                    let band = (StressPresentation.bandIndex(for: item.score) ?? 0)
                    PointMark(x: .value("时间", item.observedAt), y: .value("压力参考", band))
                        .symbolSize(55).foregroundStyle(StressStyle.color(band))
                        .accessibilityLabel(Text(item.observedAt, format: .dateTime.hour().minute()))
                        .accessibilityValue(StressPresentation.titles[band])
                }
                .chartYScale(domain: -0.4...3.4)
                .chartYAxis {
                    AxisMarks(values: [0, 1, 2, 3]) { value in
                        AxisGridLine().foregroundStyle(.secondary.opacity(0.12))
                        AxisValueLabel { if let i = value.as(Int.self) { Text(StressPresentation.titles[i]).font(.caption2) } }
                    }
                }
                .chartXAxis { AxisMarks(values: .automatic(desiredCount: 3)) { _ in AxisValueLabel(format: .dateTime.hour().minute()) } }
                .frame(height: 145)
            }
        }.padding(20).background(.background, in: RoundedRectangle(cornerRadius: 26))
    }
}
struct StressDetailsView: View {
    let model: AppController
    var body: some View {
        List {
            Section("如何理解压力参考") {
                Text("它将这次心率变化与自己的历史记录比较，提供身体紧绷或放松倾向的参考。它不能直接判断你的真实情绪，也不是医学诊断。")
                Text("这些分档是产品的相对刻度，不是压力百分比，也不是医学阈值。运动、睡眠和采样时间都可能影响记录。")
            }
            Section("这次记录") { ReadingView(model: model) }
            if let heart = model.samples.filter({ $0.kind == .restingHeartRate && $0.value.isFinite && $0.value > 0 }).max(by: { $0.start < $1.start }) {
                Section("静息心率 · 独立参考") {
                    Text("\(heart.value.formatted(.number.precision(.fractionLength(0)))) 次/分").font(.title2.bold())
                    Text(heart.start, format: .dateTime.month().day().hour().minute()).font(.caption)
                    Text("来源：" + (heart.sourceName ?? "所选健康数据来源")).font(.caption).foregroundStyle(.secondary)
                    Text("单独展示，不参与压力参考的计算。").font(.caption).foregroundStyle(.secondary)
                }
            }
            Section("为什么会没有结果？") {
                Text("手表采集和同步需要时间。没有可用记录不代表你拒绝了权限；可以检查 Apple 健康中的记录与读取设置。刷新只检查已有记录，不会启动测量。")
                Text("开始比较需要至少7个有记录的历史日及20条有效记录；记录不够时继续日常佩戴即可，不保证几天后一定完成。")
                Text("超过3小时的记录只作为历史。受运动影响或不适合比较的记录，不提供当次判断。")
            }
            Section("比较依据") {
                Text(model.samples.contains { $0.kind == .workout } ? "仅排除已读到的运动时段及结束后30分钟；其他影响仍可能存在。" : "未读取到运动记录，无法排除运动影响。")
                Text("算法：" + WellnessEngine.version).font(.caption.monospaced())
            }
        }.navigationTitle("结果与记录")
    }
}
