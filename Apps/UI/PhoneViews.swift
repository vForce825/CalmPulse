#if os(iOS)
import SwiftUI
import WellnessCore
import WellnessServices
struct PhoneRootView: View {
    let runtime: AppRuntime
    @Environment(\.dynamicTypeSize) private var systemTypeSize
    private var model: AppController { runtime.model }
    private var tint: Color { switch model.settings.theme { case "forest": .green; case "dusk": .indigo; default: .teal } }
    var body: some View {
        TabView {
            NavigationStack { TodayView(model: model, testing: runtime.testing) }.tabItem { Label("今日", systemImage: "sun.horizon") }
            NavigationStack { TrendsView(model: model) }.tabItem { Label("趋势", systemImage: "chart.xyaxis.line") }
            NavigationStack { HabitsView(model: model) }.tabItem { Label("习惯", systemImage: "leaf") }
            NavigationStack { SettingsView(runtime: runtime) }.tabItem { Label("设置", systemImage: "slider.horizontal.3") }
        }.tint(tint)
        .preferredColorScheme(runtime.testing && ProcessInfo.processInfo.environment["CALMPULSE_DARK"] == "1" ? .dark : nil)
        .environment(\.dynamicTypeSize, runtime.testing && ProcessInfo.processInfo.environment["CALMPULSE_LARGE"] == "1" ? .accessibility5 : systemTypeSize)
        .alert("提示", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button("好") { model.errorMessage = nil }
        } message: { Text(model.errorMessage ?? "") }
    }
}
struct TodayView: View {
    let model: AppController
    let testing: Bool
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(Date(), format: .dateTime.month().day().weekday()).font(.subheadline).foregroundStyle(.secondary)
                    Text("关注变化，\n也留一点空间").font(.largeTitle.bold())
                }.padding(.vertical, 8)
                if testing { Label("合成演示测试 · 无真实健康数据", systemImage: "testtube.2").font(.caption).foregroundStyle(.secondary) }
                PulseCard(title: "你的节奏") { ReadingView(model: model) }
                if model.summary == nil {
                    PulseCard(title: "从已有记录开始") {
                        Text("CalmPulse 在你的设备上读取 SDNN 和静息心率。无需账户，不上传健康数据。")
                        Button("读取核心健康记录") { Task { await model.request([.sdnn, .restingHeartRate]) } }
                            .buttonStyle(.borderedProminent).accessibilityIdentifier("onboarding.readCore")
                        Text("暂未读到记录可能来自尚无测量、同步延迟或读取不可用；无法判断你是否拒绝了读取权限。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                if let heart = model.samples.filter({ $0.kind == .restingHeartRate }).max(by: { $0.start < $1.start }) {
                    PulseCard(title: "静息心率 · 独立参考") {
                        Text("\(heart.value.formatted(.number.precision(.fractionLength(0)))) 次/分").font(.title2.bold())
                        Text(heart.start, format: .dateTime.month().day().hour().minute()).font(.caption).foregroundStyle(.secondary)
                        Text("不混入 SDNN 趋势指标").font(.caption)
                    }
                }
                NavigationLink { BreathingView(model: model) } label: {
                    Label("做一次轻松呼吸", systemImage: "wind").frame(maxWidth: .infinity).padding()
                }.buttonStyle(.bordered).accessibilityIdentifier("today.breathing")
                Text(model.samples.contains(where: { $0.kind == .workout }) ? "已按可见运动记录排除运动期间及结束后 30 分钟的影响。" : "未排除运动影响：可在习惯里的健康概览读取运动记录。")
                    .font(.caption).foregroundStyle(.secondary)
                Text("采样时刻、佩戴和睡眠会影响比较。系统决定采样与刷新时间；超过 3 小时的值只作为历史读数。")
                    .font(.caption).foregroundStyle(.secondary)
            }.padding()
        }.background(Color.teal.opacity(0.04)).navigationTitle("CalmPulse").navigationBarTitleDisplayMode(.inline)
            .toolbar { Button { Task { await model.refreshHealth() } } label: { Image(systemName: "arrow.clockwise") }.disabled(model.isRefreshing).accessibilityLabel("刷新健康记录") }
            .refreshable { await model.refreshHealth() }
    }
}
private struct HabitDraft: Identifiable { let id = UUID(); let kind: HabitKind; var entry: HabitEntry? }
struct HabitsView: View {
    let model: AppController
    @State private var draft: HabitDraft?
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("把日常的小事记下来").font(.title2.bold())
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    ForEach(HabitKind.allCases, id: \.self) { kind in
                        Button { draft = HabitDraft(kind: kind) } label: {
                            VStack(spacing: 8) { Image(systemName: kind.symbol).font(.title2); Text(kind.title).font(.headline) }
                                .frame(maxWidth: .infinity, minHeight: 80).background(.teal.opacity(0.08), in: RoundedRectangle(cornerRadius: 18))
                        }.accessibilityIdentifier("habit.add." + kind.rawValue)
                    }
                }
                NavigationLink { HealthOverviewView(model: model) } label: { Label("睡眠、活动与习惯关联", systemImage: "heart.text.square") }
                    .accessibilityIdentifier("health.overview")
                NavigationLink { BreathingView(model: model) } label: { Label("呼吸计时", systemImage: "wind") }
                Text("本地记录").font(.headline)
                if model.habits.isEmpty { Text("还没有记录，从一杯水开始也很好。").foregroundStyle(.secondary) }
                ForEach(model.habits) { entry in
                    Button { draft = HabitDraft(kind: entry.kind, entry: entry) } label: {
                        HStack(alignment: .top) {
                            Image(systemName: entry.kind.symbol).frame(width: 28)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("\(entry.kind.title) · \((entry.value ?? 0).formatted()) \(entry.kind.unit)").font(.headline)
                                Text(entry.timestamp, format: .dateTime.month().day().hour().minute()).font(.caption).foregroundStyle(.secondary)
                                if let note = entry.note, !note.isEmpty { Text(note).font(.subheadline).foregroundStyle(.secondary) }
                            }
                            Spacer(); Image(systemName: "chevron.right").font(.caption)
                        }.padding().frame(maxWidth: .infinity, alignment: .leading).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                    }.buttonStyle(.plain).accessibilityIdentifier("habit.entry")
                }
            }.padding()
        }.navigationTitle("习惯").sheet(item: $draft) { HabitEditor(model: model, kind: $0.kind, entry: $0.entry) }
    }
}
#endif
