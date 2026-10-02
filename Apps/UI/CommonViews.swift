import SwiftUI
import WellnessCore
import WellnessServices

extension HabitKind {
    var title: String { switch self { case .mood: "情绪"; case .waterML: "饮水"; case .caffeineMG: "咖啡因"; case .breathingSeconds: "呼吸" } }
    var symbol: String { switch self { case .mood: "face.smiling"; case .waterML: "drop"; case .caffeineMG: "cup.and.saucer"; case .breathingSeconds: "wind" } }
    var unit: String { switch self { case .mood: "1–5"; case .waterML: "mL"; case .caffeineMG: "mg"; case .breathingSeconds: "秒" } }
    var initialValue: Double { switch self { case .mood: 3; case .waterML: 250; case .caffeineMG: 80; case .breathingSeconds: 60 } }
}
extension WellnessBand {
    var title: String { switch self { case .low: "相对较低"; case .moderate: "中等"; case .high: "相对较高"; case .highest: "明显偏高" } }
}
struct PulseCard<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 12) { Text(title).font(.headline); content }
            .frame(maxWidth: .infinity, alignment: .leading).padding()
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22))
    }
}
struct ReadingView: View {
    let model: AppController
    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            VStack(alignment: .leading, spacing: 14) {
                HStack { Image(systemName: "waveform.path.ecg"); Text("个人趋势指标").font(.headline); Spacer() }
                if let summary = model.summary {
                    HStack(alignment: .firstTextBaseline) {
                        Text(summary.assessment.score.map(String.init) ?? "—")
                            .font(.system(.largeTitle, design: .rounded, weight: .bold)).monospacedDigit()
                        Text(summary.assessment.band?.title ?? "正在建立基线").font(.subheadline)
                    }.accessibilityElement(children: .combine)
                    Text("SDNN  \(summary.sdnn.formatted(.number.precision(.fractionLength(1)))) ms").font(.title3).monospacedDigit()
                    Label(context.date.timeIntervalSince(summary.assessment.observedAt) > 10_800 ? "历史读数" : "最近读数", systemImage: "clock")
                        .font(.caption).foregroundStyle(.secondary)
                    Text(summary.assessment.observedAt, format: .dateTime.month().day().hour().minute()).font(.caption)
                    Text("\(summary.assessment.baselineDayCount) 个基线日 · \(summary.assessment.baselineSampleCount) 条样本")
                        .font(.caption).foregroundStyle(.secondary)
                    Text(summary.assessment.confidence == .established ? "基线已建立" : summary.assessment.confidence == .limited ? "基线有限" : "至少需要 7 个历史日、20 条有效样本")
                        .font(.caption)
                    if let source = model.samples.first(where: { $0.id == summary.assessment.sampleID }) {
                        Text("来源：\(source.sourceName ?? "所选健康数据来源")").font(.caption).foregroundStyle(.secondary)
                    }
                } else {
                    Text("SDNN").font(.title3)
                    Text(model.dataStatus.message).font(.title2.bold())
                    Text("有记录时显示毫秒值；基线充足后再计算个人相对趋势。")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                Text("这不是压力百分比，也不是医学判断").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

struct HabitEditor: View {
    let model: AppController
    let kind: HabitKind
    let entry: HabitEntry?
    @Environment(\.dismiss) private var dismiss
    @State private var value = ""
    @State private var note = ""
    @State private var deleting = false
    @State private var saving = false
    init(model: AppController, kind: HabitKind, entry: HabitEntry? = nil) { self.model = model; self.kind = kind; self.entry = entry }
    var body: some View {
        NavigationStack {
            Form {
                Section("\(kind.title) · \(kind.unit)") {
                    TextField("数值", text: $value).accessibilityIdentifier("habit.value")
                        #if os(iOS)
                        .keyboardType(.decimalPad)
                        #endif
                    TextField("备注（可选）", text: $note).accessibilityIdentifier("habit.note")
                    if kind == .mood { Text("1 很低落 · 3 一般 · 5 很愉快").font(.caption) }
                }
                Section { Text("仅保存为本地日志，不写入 Apple Health。").font(.caption).foregroundStyle(.secondary) }
                if entry != nil {
                    Button("删除", role: .destructive) { deleting = true }.accessibilityIdentifier("habit.delete")
                }
            }
            .navigationTitle(entry == nil ? "记录\(kind.title)" : "编辑\(kind.title)")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        saving = true
                        Task {
                            model.errorMessage = nil
                            await model.saveHabit(kind: kind, value: Double(value), note: note.isEmpty ? nil : note, editing: entry)
                            saving = false
                            if model.errorMessage == nil { dismiss() }
                        }
                    }.disabled(saving).accessibilityIdentifier("habit.save")
                }
            }
            .confirmationDialog("删除这条本地记录？", isPresented: $deleting, titleVisibility: .visible) {
                Button("删除记录", role: .destructive) { Task { if let entry { await model.deleteHabit(entry) }; dismiss() } }
                Button("取消", role: .cancel) {}
            }
            .onAppear { value = (entry?.value ?? kind.initialValue).formatted(.number.grouping(.never)); note = entry?.note ?? "" }
        }
    }
}

struct BreathingView: View {
    let model: AppController
    @AppStorage("breathingHaptics") private var haptics = true
    @State private var duration = 60
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Text("给自己片刻呼吸").font(.title2.bold()).multilineTextAlignment(.center)
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let remaining = model.breathing.remaining(at: context.date)
                    let active = model.breathing.durationSeconds > 0 && remaining > 0
                    let elapsed = model.breathing.durationSeconds - remaining
                    let inhale = elapsed % 10 < 4
                    VStack(spacing: 12) {
                        Image(systemName: "wind").font(.largeTitle)
                            .frame(width: 90, height: 90).background(.teal.opacity(0.15), in: Circle())
                            .scaleEffect(active && !model.breathing.isPaused && inhale && !reduceMotion ? 1.12 : 1)
                            .animation(reduceMotion ? nil : .easeInOut(duration: 3), value: inhale)
                            .accessibilityHidden(true)
                        Text(model.breathing.isPaused ? "已暂停" : active ? (inhale ? "轻轻吸气" : "慢慢呼气") : "按自己的节奏开始")
                            .font(.headline)
                        Text("\(remaining) 秒").font(.title.monospacedDigit()).accessibilityIdentifier("breathing.remaining")
                    }
                    .onChange(of: inhale) { _, _ in
                        #if os(watchOS)
                        if active && !model.breathing.isPaused && haptics { WKInterfaceDevice.current().play(.click) }
                        #endif
                    }
                    .onChange(of: remaining) { _, value in if value == 0 { Task { await model.finishBreathingIfNeeded(at: context.date) } } }
                }
                if model.breathing.durationSeconds > 0 {
                    Button(model.breathing.isPaused ? "继续" : "暂停") { Task { await model.updateBreathing(model.breathing.isPaused ? .resume : .pause) } }
                        .buttonStyle(.borderedProminent).accessibilityIdentifier("breathing.pauseResume")
                    Button("结束", role: .destructive) { Task { await model.updateBreathing(.stop) } }.accessibilityIdentifier("breathing.stop")
                } else {
                    Picker("练习时长", selection: $duration) { Text("1 分钟").tag(60); Text("2 分钟").tag(120); Text("5 分钟").tag(300) }
                    Button("开始呼吸") { Task { await model.updateBreathing(.start(duration)) } }
                        .buttonStyle(.borderedProminent).accessibilityIdentifier("breathing.start")
                }
                #if os(watchOS)
                Toggle("触觉引导", isOn: $haptics)
                #endif
                Text("保持自然，不必屏息；不舒服时可随时结束。练习不会强制触发 HRV 测量，也不写入健康正念记录。")
                    .font(.caption).foregroundStyle(.secondary)
            }.padding()
        }.navigationTitle("呼吸").task { await model.finishBreathingIfNeeded() }
    }
}
#if os(watchOS)
import WatchKit
#endif
