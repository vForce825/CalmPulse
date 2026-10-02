#if os(iOS)
import SwiftUI
import WellnessCore
import WellnessServices
struct SettingsView: View {
    let runtime: AppRuntime
    private var model: AppController { runtime.model }
    @State private var clearing = false
    @State private var zones = ""
    private var sources: [HealthSample] {
        var seen = Set<String>()
        return model.samples.filter { $0.kind == .sdnn }.sorted { $0.start > $1.start }.filter { seen.insert($0.sourceID).inserted }
    }
    var body: some View {
        Form {
            Section("本机数据来源") {
                Picker("SDNN 来源", selection: Binding(get: { model.settings.selectedSourceID ?? "" }, set: { value in Task { await model.changeSettings { $0.selectedSourceID = value.isEmpty ? nil : value } } })) {
                    Text("自动选择 Apple Watch").tag("")
                    ForEach(sources, id: \.sourceID) { source in Text(source.sourceName ?? source.sourceID).tag(source.sourceID) }
                }
                Text("不同设备来源分别建立基线。来源标识仅在本机有效，不从另一台设备照搬。")
                    .font(.caption).foregroundStyle(.secondary)
                Button("重新请求核心读取") { Task { await model.request([.sdnn, .restingHeartRate]) } }
            }
            Section("提醒 · 默认关闭") {
                Toggle("启用趋势提醒", isOn: Binding(get: { model.settings.notifications.enabled }, set: { enabled in Task { await runtime.enableNotifications(enabled) } }))
                Picker("唯一提醒设备", selection: Binding(get: { model.settings.notifications.owner }, set: { owner in
                    if owner == .iPhone && runtime.watchInstalled { model.errorMessage = "Watch 应用已安装，请由 Watch 负责提醒；不用 Watch 应用时可明确切换到 iPhone。" }
                    else { Task { await model.changeSettings { $0.notifications.owner = owner } } }
                })) {
                    Text("Apple Watch").tag(NotificationOwner.watch)
                    Text("仅 iPhone").tag(NotificationOwner.iPhone)
                }
                Picker("静音开始", selection: Binding(get: { model.settings.notifications.quietStartHour }, set: { hour in Task { await model.changeSettings { $0.notifications.quietStartHour = hour } } })) {
                    ForEach(0..<24, id: \.self) { Text(String(format: "%02d:00", $0)).tag($0) }
                }
                Picker("静音结束", selection: Binding(get: { model.settings.notifications.quietEndHour }, set: { hour in Task { await model.changeSettings { $0.notifications.quietEndHour = hour } } })) {
                    ForEach(0..<24, id: \.self) { Text(String(format: "%02d:00", $0)).tag($0) }
                }
                Text("最近 6 小时的两条最新样本均在最高区间、最新不超过 3 小时，才有资格提示；最多每 2 小时一次。起止小时相同表示不设静音。不会自动切换提醒设备，也不绕过专注模式。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("显示与隐私") {
                Toggle("小组件隐藏数值", isOn: Binding(get: { model.settings.hideWidgetValues }, set: { hidden in Task { await model.changeSettings { $0.hideWidgetValues = hidden } } }))
                Picker("主题", selection: Binding(get: { model.settings.theme }, set: { theme in Task { await model.changeSettings { $0.theme = theme } } })) {
                    Text("海风").tag("ocean"); Text("林间").tag("forest"); Text("暮色").tag("dusk")
                }
                Text("小组件仍受系统刷新与锁屏隐私设置控制，不保证固定更新频率。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("自定运动心率区间") {
                TextField("例如 100, 130, 160", text: $zones).keyboardType(.numbersAndPunctuation)
                Button("保存区间边界") {
                    let values = zones.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
                    let count = zones.split(separator: ",").count
                    guard values.count == count, values.allSatisfy({ $0.isFinite && $0 > 0 && $0 < 260 }), values == values.sorted(), Set(values).count == values.count else { model.errorMessage = "请用英文逗号分隔递增的有效心率值"; return }
                    Task { await model.changeSettings { $0.heartRateZoneBoundaries = values } }
                }
                Text("不读取生日推算最大心率。留空时仅显示原始运动摘要。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("你的数据由你掌握") {
                NavigationLink("解释与隐私") { PrivacyView() }
                Button("清除本地缓存与日志", role: .destructive) { clearing = true }.accessibilityIdentifier("settings.clear")
                Text("不会删除 Apple Health 原始记录。下一次刷新可重新读取健康记录；删除标记用于防止离线日志复活。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section { Text("CalmPulse 1.0 · 原创设计 · MIT\n仅供个人健康参考").font(.caption).foregroundStyle(.secondary) }
        }.navigationTitle("设置")
            .onAppear { zones = model.settings.heartRateZoneBoundaries.map { $0.formatted(.number.grouping(.never)) }.joined(separator: ", ") }
            .confirmationDialog("清除本机缓存和本地习惯日志？", isPresented: $clearing, titleVisibility: .visible) {
                Button("清除本地数据", role: .destructive) { Task { await model.clearLocalData() } }
                Button("取消", role: .cancel) {}
            } message: { Text("此操作不删除 Apple Health 数据。日志删除会同步到配对设备。") }
    }
}
struct PrivacyView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("看懂趋势，也看清边界").font(.title.bold())
                Text("SDNN 是心搏间期变异性的一个统计指标，以毫秒表示。它不是 RMSSD，也不直接测量你的情绪。")
                Text("个人趋势指标将本次 SDNN 与同来源此前 28 个完整本地日比较，按天等权计算中位秩分位，再取 100 × (1 − 分位)。至少 7 个历史日和 20 条有效样本才显示数值。")
                Text("高分只表示本次 SDNN 相对历史较低；低分不保证健康良好。这不是压力百分比、疾病概率或医学阈值。样本比例不等于处于某种状态的时长。")
                Text("采样时刻、佩戴、运动和睡眠影响可比性。运动期间及结束后 30 分钟排除于默认评分；未读到运动记录时会明确提示。算法版本：wellness-sdnn-v1。")
                Text("所有计算在设备上完成。无账户、广告、云 AI、服务器或订阅。只通过 WatchConnectivity 与配对设备交换必要设置、独立摘要和本地日志；不传全量健康历史。")
                Text("健康记录只读。情绪、饮水、咖啡因和呼吸均为本地日志，不写入 Apple Health。你可拒绝部分读取；空白数据只表述为‘暂未读到记录’。")
                Text("本地文件受系统保护并排除云备份。Apple Health 自身的 iCloud 同步仍由你的系统设置控制。后台交付、通知和组件均受系统调度限制。")
            }.font(.body).padding()
        }.navigationTitle("解释与隐私").navigationBarTitleDisplayMode(.inline)
    }
}
#endif
