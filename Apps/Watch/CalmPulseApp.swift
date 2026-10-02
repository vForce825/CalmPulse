import SwiftUI
import Charts
import WatchKit
import WellnessCore
import WellnessServices

@main @MainActor struct CalmPulseApp: App {
    @State private var runtime = AppRuntime()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            Group {
                #if DEBUG
                if runtime.testing && ProcessInfo.processInfo.environment["CALMPULSE_WIDGET_GALLERY"] == "1" {
                    WidgetVerificationGallery()
                } else { WatchHomeView(runtime: runtime) }
                #else
                WatchHomeView(runtime: runtime)
                #endif
            }
                .task { await runtime.start() }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { Task { await runtime.foreground() } }
                }
        }
    }
}

private struct WatchHomeView: View {
    let runtime: AppRuntime
    @State private var selectedLog: WatchLogKind?
    @Environment(\.colorScheme) private var colorScheme
    private var model: AppController { runtime.model }
    private var accent: Color { colorScheme == .dark ? .cyan : .teal }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    if runtime.testing {
                        Label("演示测试 · 无真实健康数据", systemImage: "testtube.2")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    if model.dataStatus == .protected {
                        WatchMessageCard(title: "解锁后查看", message: "受保护数据暂不可读取，解锁后再试。", symbol: "lock.shield")
                    } else if let summary = model.summary {
                        WatchReadingCard(model: model, summary: summary)
                    } else {
                        WatchMessageCard(title: "暂未读到记录", message: "SDNN来自Apple Health。不同设备收到记录的时间可能不同。", symbol: "waveform.path")
                    }
                    if !model.settings.requestedMetrics.contains(.sdnn) {
                        VStack(alignment: .leading, spacing: 7) {
                            Text("先连接核心记录").font(.headline)
                            Text("只读取SDNN与静息心率。不写入健康数据。")
                                .font(.caption).foregroundStyle(.secondary)
                            Button {
                                Task { await model.request([.sdnn, .restingHeartRate]) }
                            } label: {
                                Label("读取健康记录", systemImage: "heart.text.clipboard")
                            }
                            .accessibilityIdentifier("watch.readCore")
                            .disabled(model.isRefreshing)
                        }
                        .watchCard()
                    }
                    restingHeartRate
                    briefTrend
                    VStack(alignment: .leading, spacing: 8) {
                        Text("快速记录").font(.headline)
                        ForEach(WatchLogKind.allCases) { kind in
                            Button { selectedLog = kind } label: {
                                Label(kind.title, systemImage: kind.symbol)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .accessibilityIdentifier("watch.quickLog." + kind.rawValue)
                            .accessibilityHint("仅记录到应用；系统允许时与配对iPhone同步")
                        }
                    }
                    NavigationLink {
                        BreathingView(model: model)
                    } label: {
                        Label("呼吸练习", systemImage: "wind")
                    }
                    .accessibilityIdentifier("watch.breathing")
                    NavigationLink {
                        HealthOverviewView(model: model)
                    } label: {
                        Label("睡眠与活动", systemImage: "figure.walk")
                    }
                    NavigationLink {
                        WatchLogHistoryView(model: model)
                    } label: {
                        Label("习惯记录", systemImage: "list.bullet.clipboard")
                    }
                    NavigationLink {
                        WatchInformationView(model: model)
                    } label: {
                        Label("说明与同步", systemImage: "info.circle")
                    }
                    Button {
                        Task { await model.refreshHealth() }
                    } label: {
                        Label(model.isRefreshing ? "刷新中" : "刷新本机记录", systemImage: "arrow.clockwise")
                    }
                    .disabled(model.isRefreshing)
                    .accessibilityIdentifier("watch.refresh")
                    if let error = model.errorMessage {
                        Text(error).font(.caption).foregroundStyle(.secondary)
                            .accessibilityIdentifier("watch.error")
                    }
                    Text("一般健康参考，不用于医疗诊断。打开应用补查记录，后台刷新由系统安排。")
                        .font(.caption2).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 4)
            }
            .navigationTitle("CalmPulse")
            .tint(accent)
            .sheet(item: $selectedLog) { kind in
                WatchQuickLogView(model: model, kind: kind)
            }
        }
    }

    @ViewBuilder private var restingHeartRate: some View {
        if let latest = model.samples.filter({ $0.kind == .restingHeartRate && $0.value.isFinite && $0.value > 0 })
            .max(by: { $0.start < $1.start }) {
            VStack(alignment: .leading, spacing: 5) {
                Label("静息心率", systemImage: "heart").font(.headline)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(latest.value, format: .number.precision(.fractionLength(0)))
                        .font(.title3).monospacedDigit()
                    Text("次/分").font(.caption)
                }
                Text(latest.start, format: .dateTime.month().day().hour().minute())
                    .font(.caption2).foregroundStyle(.secondary)
                Text("来源：" + (latest.sourceName ?? latest.sourceID))
                    .font(.caption2).foregroundStyle(.secondary)
                Text("单独展示，不混入趋势分值").font(.caption2).foregroundStyle(.secondary)
            }
            .watchCard()
        }
    }

    private var trendSamples: [HealthSample] {
        let lower = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        let source = model.summary?.assessment.sourceID ?? model.settings.selectedSourceID
        guard let source else { return [] }
        return model.samples.filter {
            $0.kind == .sdnn && $0.sourceID == source && $0.start >= lower && $0.start <= Date() && $0.value.isFinite && $0.value > 0
        }.sorted { $0.start < $1.start }
    }

    private var briefTrend: some View {
        VStack(alignment: .leading, spacing: 7) {
            NavigationLink {
                TrendsView(model: model)
            } label: {
                HStack {
                    Text("近7天 · SDNN").font(.headline)
                    Spacer(minLength: 3)
                    Image(systemName: "chevron.right").font(.caption2)
                }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("watch.trends")
            if trendSamples.isEmpty {
                Text("暂未读到记录").font(.caption).foregroundStyle(.secondary)
            } else {
                Chart(trendSamples) { sample in
                    PointMark(x: .value("采集时间", sample.start), y: .value("SDNN（毫秒）", sample.value))
                        .foregroundStyle(accent)
                        .accessibilityLabel(Text(sample.start, format: .dateTime.month().day().hour().minute()))
                        .accessibilityValue(Text("SDNN \(sample.value.formatted(.number.precision(.fractionLength(1)))) 毫秒"))
                }
                .chartXAxis { AxisMarks(values: .automatic(desiredCount: 2)) }
                .chartYAxis(.hidden)
                .frame(height: 65)
                .accessibilityLabel("近七天的SDNN实测样本，未连接缺失时段")
                Text("\(trendSamples.count)条实测 · 缺口保留").font(.caption2).foregroundStyle(.secondary)
            }
        }
        .watchCard()
    }
}

private struct WatchReadingCard: View {
    let model: AppController
    let summary: StoredSummary
    @Environment(\.colorScheme) private var colorScheme
    private var assessment: WellnessAssessment { summary.assessment }
    private var sourceName: String {
        model.samples.first(where: { $0.id == assessment.sampleID })?.sourceName ?? assessment.sourceID
    }
    private var freshnessDates: [Date] {
        let now = Date(), boundary = assessment.observedAt.addingTimeInterval(10_801)
        return boundary > now ? [now, boundary] : [now]
    }
    private var baselineText: String {
        switch assessment.confidence {
        case .insufficient: "建立基线中"
        case .limited: "基线有限"
        case .established: "基线已建立"
        }
    }
    private var bandText: String {
        switch assessment.band {
        case .low: "相对较低"
        case .moderate: "中等"
        case .high: "相对较高"
        case .highest: "明显偏高"
        case nil: "信息不足"
        }
    }

    var body: some View {
        TimelineView(.explicit(freshnessDates)) { context in
            let historical = context.date.timeIntervalSince(assessment.observedAt) > 10_800
            VStack(alignment: .leading, spacing: 8) {
                Label(historical ? "历史读数" : "最近读数", systemImage: historical ? "clock.arrow.circlepath" : "waveform.path.ecg")
                    .font(.caption).foregroundStyle(.secondary)
                Text("SDNN").font(.headline)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(summary.sdnn, format: .number.precision(.fractionLength(1)))
                        .font(.largeTitle).fontWeight(.semibold).monospacedDigit()
                        .foregroundStyle(colorScheme == .dark ? Color.cyan : Color.teal)
                        .minimumScaleFactor(0.75)
                    Text("毫秒").font(.caption)
                }
                if let score = assessment.score {
                    Text("相对趋势 \(score) / 100").font(.headline).monospacedDigit()
                    Text(bandText).font(.caption)
                } else {
                    Text("个人趋势：信息不足").font(.caption)
                }
                HStack(spacing: 3) {
                    Text("距采集").font(.caption2)
                    Text(assessment.observedAt, style: .timer).font(.caption2).monospacedDigit()
                }
                Text(assessment.observedAt, format: .dateTime.month().day().hour().minute().second())
                    .font(.caption2).foregroundStyle(.secondary)
                Text("来源：" + sourceName).font(.caption2).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Divider()
                Text(baselineText).font(.caption).fontWeight(.medium)
                Text("过去28个完整日：\(assessment.baselineDayCount)天 · \(assessment.baselineSampleCount)条")
                    .font(.caption2).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if assessment.confidence == .insufficient {
                    Text("需至少7个历史日与20条有效样本").font(.caption2).foregroundStyle(.secondary)
                }
                if !model.settings.requestedMetrics.contains(.workout) {
                    Text("未排除运动影响").font(.caption2).foregroundStyle(.secondary)
                } else {
                    Text("仅排除已读到的运动影响").font(.caption2).foregroundStyle(.secondary)
                }
                if historical {
                    Text("超过3小时，仅供历史参考").font(.caption2).foregroundStyle(.secondary)
                }
                Text("高分仅表示SDNN相对本人历史偏低；并非压力百分比。")
                    .font(.caption2).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .watchCard()
        }
        .accessibilityIdentifier("watch.reading")
    }
}

private enum WatchLogKind: String, CaseIterable, Identifiable {
    case mood, waterML, caffeineMG
    var id: String { rawValue }
    var habitKind: HabitKind {
        switch self { case .mood: .mood; case .waterML: .waterML; case .caffeineMG: .caffeineMG }
    }
    var title: String {
        switch self { case .mood: "记录情绪"; case .waterML: "记录饮水"; case .caffeineMG: "记录咖啡因" }
    }
    var symbol: String {
        switch self { case .mood: "face.smiling"; case .waterML: "drop"; case .caffeineMG: "cup.and.saucer" }
    }
    var unit: String {
        switch self { case .mood: ""; case .waterML: "毫升"; case .caffeineMG: "毫克" }
    }
    var options: [Int] {
        switch self {
        case .mood: [1, 2, 3, 4, 5]
        case .waterML: [50, 100, 150, 200, 250, 300, 500, 750, 1000]
        case .caffeineMG: [0, 25, 50, 75, 100, 150, 200, 250, 300]
        }
    }
    var initialValue: Int {
        switch self { case .mood: 3; case .waterML: 250; case .caffeineMG: 100 }
    }
    func valueLabel(_ value: Int) -> String {
        if self == .mood {
            return ["很低落", "低落", "一般", "不错", "很好"][min(4, max(0, value - 1))]
        }
        return "\(value)\(unit)"
    }
}

private struct WatchQuickLogView: View {
    let model: AppController
    let kind: WatchLogKind
    @State private var value: Int
    @State private var note = ""
    @State private var saving = false
    @Environment(\.dismiss) private var dismiss

    init(model: AppController, kind: WatchLogKind) {
        self.model = model; self.kind = kind
        _value = State(initialValue: kind.initialValue)
    }

    var body: some View {
        NavigationStack {
            Form {
                Picker(kind.title, selection: $value) {
                    ForEach(kind.options, id: \.self) { option in
                        Text(kind.valueLabel(option)).tag(option)
                    }
                }
                .accessibilityIdentifier("watch.log.value")
                TextField("备注（可选）", text: $note)
                    .accessibilityIdentifier("watch.log.note")
                if kind == .caffeineMG {
                    Text("按包装或自己的估计记录毫克数，饮品大小不等于咖啡因含量。")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                Text("本地习惯日志，不读写Apple Health；离线可记录，同步由系统安排。")
                    .font(.caption2).foregroundStyle(.secondary)
                Button {
                    saving = true
                    Task { @MainActor in
                        model.errorMessage = nil
                        let previous = Set(model.habits.map(\.id))
                        await model.saveHabit(kind: kind.habitKind, value: Double(value), note: note.isEmpty ? nil : note)
                        saving = false
                        if model.habits.contains(where: { !previous.contains($0.id) }) {
                            WKInterfaceDevice.current().play(.success)
                            dismiss()
                        }
                    }
                } label: {
                    Text(saving ? "保存中" : "保存记录")
                }
                .disabled(saving)
                .accessibilityIdentifier("watch.log.save")
                if let error = model.errorMessage {
                    Text(error).font(.caption).foregroundStyle(.secondary)
                }
                Button("取消", role: .cancel) { dismiss() }.disabled(saving)
            }
            .navigationTitle(kind.title)
        }
    }
}

private struct WatchLogHistoryView: View {
    let model: AppController
    var body: some View {
        List {
            if model.habits.isEmpty {
                Text("还没有习惯记录").foregroundStyle(.secondary)
            } else {
                ForEach(model.habits) { entry in
                    NavigationLink {
                        HabitEditor(model: model, kind: entry.kind, entry: entry)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(title(for: entry)).font(.headline)
                            Text(entry.timestamp, format: .dateTime.month().day().hour().minute())
                                .font(.caption2).foregroundStyle(.secondary)
                            if let note = entry.note, !note.isEmpty {
                                Text(note).font(.caption).fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .accessibilityElement(children: .combine)
                    }
                    .accessibilityIdentifier("watch.log.entry")
                    .accessibilityHint("编辑记录；删除前会再次确认")
                }
            }
            Text("日志在本机保存，系统允许时与配对设备同步。")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .navigationTitle("习惯记录")
    }
    private func title(for entry: HabitEntry) -> String {
        let value = entry.value ?? 0
        switch entry.kind {
        case .mood:
            guard value.isFinite, (1...5).contains(value) else { return "情绪：数值不可用" }
            return "情绪：" + WatchLogKind.mood.valueLabel(Int(value))
        case .waterML: return "饮水 \(value.formatted(.number.precision(.fractionLength(0)))) 毫升"
        case .caffeineMG: return "咖啡因 \(value.formatted(.number.precision(.fractionLength(0)))) 毫克"
        case .breathingSeconds: return "呼吸练习 \(value.formatted(.number.precision(.fractionLength(0)))) 秒"
        }
    }
}

private struct WatchInformationView: View {
    let model: AppController
    @State private var notificationAuthorized = false
    @State private var notificationRequesting = false
    @State private var notificationStatus: String?
    var body: some View {
        List {
            Section("指标说明") {
                Text("SDNN以毫秒展示，是心率变异性的一种记录，不是RMSSD。")
                Text("个人趋势比较此前28个完整本地日，每个有记录日等权。当天不加入基线。")
                Text("高分只代表本次SDNN相对本人历史偏低。不是心理压力测量，也不是疾病概率。")
                Text("采样时刻、佩戴、睡眠和运动会影响可比性。样本之间不推断连续状态。")
                if let range = model.summary?.assessment.baselineRange {
                    Text("当前基线：" + range.start.formatted(.dateTime.year().month().day()) + " 至 " + range.end.formatted(.dateTime.year().month().day()))
                }
                Text("算法：" + (model.summary?.assessment.version ?? WellnessEngine.version))
            }
            Section("权限") {
                Text("首次只读取SDNN与静息心率。睡眠、活动等在对应页面另行请求。没有记录无法证明读取权限被拒绝。")
                if !model.settings.requestedMetrics.contains(.workout) {
                    Text("未排除运动影响")
                    Button("读取运动与心率") {
                        Task { await model.request([.workout, .heartRate]) }
                    }
                }
                Text("呼吸练习仅本地计时，可选触觉，不承诺触发HRV测量。")
            }
            if model.settings.notifications.enabled && model.settings.notifications.owner == .watch {
                Section("本机通知") {
                    Text("iPhone的通知许可不代表Watch已获许可。点击后请求此手表的系统通知许可，提醒设置仍由iPhone管理。")
                        .font(.caption2).foregroundStyle(.secondary)
                    Button(notificationRequesting ? "请求中" : "允许本机通知") {
                        notificationRequesting = true
                        Task { @MainActor in
                            do {
                                notificationAuthorized = try await SystemNotificationClient().requestPermission()
                                notificationStatus = notificationAuthorized ? "本机通知已允许" : "本机通知未允许，可在Watch系统设置中调整。"
                            } catch {
                                notificationStatus = "暂时无法请求本机通知，可稍后重试。"
                            }
                            notificationRequesting = false
                        }
                    }
                    .disabled(notificationRequesting || notificationAuthorized)
                    .accessibilityIdentifier("watch.notifications.request")
                    if notificationAuthorized {
                        Text("本机通知已允许").font(.caption2).foregroundStyle(.secondary)
                    } else if let notificationStatus {
                        Text(notificationStatus).font(.caption2).foregroundStyle(.secondary)
                    }
                    Text("提示仍需满足数据新鲜度、静音时段与冷却规则；系统专注模式可能延迟呈现。")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
            Section("同步与隐私") {
                Text("健康记录在此设备读取；iPhone与Watch可能看到不同记录。")
                Text("设置由iPhone管理，本机设置版本：\(model.settings.revision)")
                Text("日志离线可保存，同步由系统安排。此处版本号不代表当前连接状态。")
                Text(model.settings.hideWidgetValues ? "组件数值：已隐藏" : "组件数值：允许展示")
                Text(model.settings.notifications.enabled ? (model.settings.notifications.owner == .watch ? "提醒由Watch负责" : "提醒由iPhone负责") : "提醒：未启用")
                Text("不上传健康数据，不写入Apple Health。组件更新与后台交付不保证固定时间。")
            }
        }
        .font(.caption)
        .navigationTitle("说明与同步")
        .task { notificationAuthorized = await SystemNotificationClient().isAuthorized() }
    }
}

private struct WatchMessageCard: View {
    let title: String
    let message: String
    let symbol: String
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: symbol).font(.title2).foregroundStyle(.teal).accessibilityHidden(true)
            Text(title).font(.headline)
            Text(message).font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .watchCard()
    }
}

private extension View {
    func watchCard() -> some View {
        self.padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
