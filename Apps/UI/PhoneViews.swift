#if os(iOS)
import SwiftUI
import WellnessCore
import WellnessServices
struct PhoneRootView: View {
    let runtime: AppRuntime
    @Environment(\.dynamicTypeSize) private var systemTypeSize
    @Environment(\.colorScheme) private var colorScheme
    private var model: AppController { runtime.model }
    private var tint: Color {
        if colorScheme == .dark { return model.settings.theme == "forest" ? .mint : model.settings.theme == "dusk" ? .purple : .cyan }
        switch model.settings.theme { case "forest": return Color(red: 0.12, green: 0.4, blue: 0.22); case "dusk": return .indigo; default: return Color(red: 0, green: 0.4, blue: 0.43) }
    }
    var body: some View {
        TabView {
            NavigationStack { TodayView(model: model, testing: runtime.testing) }.tabItem { Label("今日", systemImage: "sun.horizon") }
            NavigationStack { TrendsView(model: model) }.tabItem { Label("趋势", systemImage: "chart.xyaxis.line") }
            NavigationStack { HabitsView(model: model) }.tabItem { Label("习惯", systemImage: "leaf") }
            NavigationStack { SettingsView(runtime: runtime) }.tabItem { Label("设置", systemImage: "slider.horizontal.3") }
        }.id(model.clearEpoch).tint(tint)
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
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if !typeSize.isAccessibilitySize { HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("留一点时间给自己").font(.title3.weight(.semibold))
                        Text(Date(), format: .dateTime.month().day().weekday().locale(Locale(identifier: "zh_Hans_CN"))).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "leaf").font(.title2).foregroundStyle(StressStyle.forest)
                }.padding(.horizontal, 4) }
                if testing { Text("合成演示 · 非真实健康数据").font(.caption2).foregroundStyle(.secondary) }
                StressHero(model: model)
                TodayStressTimeline(model: model)
                Text("身体信号提供参考，请结合自己的感受。")
                    .font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity)
            }.padding(18)
        }
        .background(scheme == .dark ? Color(red: 0.06, green: 0.09, blue: 0.09) : Color(red: 0.95, green: 0.96, blue: 0.92))
        .navigationTitle("CalmPulse").navigationBarTitleDisplayMode(.inline)
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
