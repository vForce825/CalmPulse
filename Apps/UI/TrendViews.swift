import Foundation
import SwiftUI
import Charts
import HealthKit
import WellnessCore
import WellnessServices

/// Both screens consume local, source-isolated data. No health values leave the device.
@MainActor struct TrendsView: View {
    let model: AppController
    @State private var anchor = Date.now
    @State private var chartMetric: CPTrendChartMetric = .relative
    @State private var choosingDate = false

    private var selectedRange: CPTrendRange {
        CPTrendRange(rawValue: model.settings.selectedRange) ?? .week
    }

    var body: some View {
        let calendar = Calendar.current
        let interval = selectedRange.interval(containing: anchor, calendar: calendar)
        let inputs = CPTrendInputs(model: model)
        let report = TrendService().summarize(samples: inputs.samples, assessments: inputs.assessments,
            habits: model.habits, range: interval, calendar: calendar)
        let rawSamples = inputs.sdnn(in: interval)
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                CPTrendRangeControls(range: Binding(get: { selectedRange }, set: { range in
                    Task { await model.selectRange(range.rawValue) }
                }), anchor: $anchor, choosingDate: $choosingDate, calendar: calendar)
                CPTrendCard {
                    Label("压力参考的变化", systemImage: "leaf")
                        .font(.headline)
                    Text("回看身体的节奏，也听听自己的感受").font(.subheadline).foregroundStyle(.secondary)
                    if report.points.isEmpty {
                        CPTrendEmpty(title: "暂未读到记录", detail: "这个区间还没有可用记录。可以换个日期看看。", symbol: "chart.xyaxis.line")
                            .accessibilityIdentifier("trend.empty")
                    } else {
                        if chartMetric == .sdnn { CPTrendStatistics(report: report) }
                        Picker("图表指标", selection: $chartMetric) {
                            ForEach(CPTrendChartMetric.allCases, id: \.self) { metric in
                                Text(metric.title).tag(metric)
                            }
                        }
                        #if os(iOS)
                        .pickerStyle(.segmented)
                        #endif
                        CPTrendScatterChart(report: report, metric: chartMetric)
                        Text("每个点是一条测量。没有测量的时间保留空白；点与点之间不连接。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                DisclosureGroup("查看原始记录与比较依据") {
                CPTrendCard {
                    CPTrendSectionTitle(title: "记录覆盖", symbol: "calendar.badge.checkmark")
                    CPTrendCoverageView(coverage: report.coverage)
                    Text("覆盖率按这个区间内已有测量的本地日计算，不代表全天连续监测。当前区间只统计已经过的日期。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                CPTrendCard {
                    CPTrendSectionTitle(title: "各区间的样本比例", symbol: "chart.bar.xaxis")
                    CPTrendBandDistribution(shares: report.bandDistribution, scoredCount: report.scoredSampleCount, unscoredCount: report.unscoredSampleCount)
                }
                CPTrendCard {
                    CPTrendSectionTitle(title: "逐条记录", symbol: "list.bullet.rectangle")
                    if rawSamples.isEmpty {
                        Text("暂未读到记录").foregroundStyle(.secondary)
                    } else {
                        ForEach(Array(rawSamples.prefix(5))) { sample in
                            NavigationLink {
                                CPTrendSampleDetail(sample: sample, assessment: inputs.assessment(for: sample), workoutRecordsAvailable: model.samples.contains { $0.kind == .workout })
                            } label: {
                                CPTrendSampleRow(sample: sample, assessment: inputs.assessment(for: sample))
                            }.buttonStyle(.plain).accessibilityIdentifier("trend.sample")
                            if sample.id != rawSamples.prefix(5).last?.id { Divider() }
                        }
                        NavigationLink {
                            CPTrendSampleList(samples: rawSamples, inputs: inputs, workoutRecordsAvailable: model.samples.contains { $0.kind == .workout })
                        } label: {
                            Label("查看全部 \(rawSamples.count) 条原始记录", systemImage: "arrow.right.circle")
                                .font(.subheadline.weight(.semibold))
                        }.accessibilityIdentifier("trend.allSamples")
                    }
                }
                CPTrendCard {
                    CPTrendSectionTitle(title: "周报", symbol: "doc.text.image")
                    if report.weeklyReports.isEmpty {
                        Text("这个区间暂无周报").foregroundStyle(.secondary)
                    } else {
                        ForEach(Array(report.weeklyReports.reversed().prefix(4).enumerated()), id: \.offset) { _, week in
                            NavigationLink {
                                CPTrendWeeklyDetail(report: week)
                            } label: { CPTrendWeeklyRow(report: week) }.buttonStyle(.plain)
                        }
                        if report.weeklyReports.count > 4 {
                            NavigationLink("查看全部 \(report.weeklyReports.count) 份周报") {
                                List {
                                    ForEach(Array(report.weeklyReports.reversed().enumerated()), id: \.offset) { _, week in
                                        NavigationLink { CPTrendWeeklyDetail(report: week) } label: { CPTrendWeeklyRow(report: week) }
                                    }
                                }.navigationTitle("区间周报")
                            }
                        }
                    }
                }
                CPTrendCard {
                    CPTrendSectionTitle(title: "如何理解这些数字", symbol: "info.circle")
                    Text("SDNN 以毫秒显示。个人趋势指标将每条有效样本与此前 28 个完整本地日的同来源记录比较，各个有数据的日等权。高分表示这次 SDNN 相对个人历史偏低。")
                    Text("指标是自定义的相对刻度，不是压力百分比或医学阈值。采样时间、佩戴方式、睡眠和运动会影响可比性；低分也不能保证健康状况。")
                    Text("数值需要至少 7 个有记录的历史日和 20 条有效基线样本；14 日起标为“基线已建立”。这些标签表示数据充足度。")
                    Text("算法版本：\(WellnessEngine.version)")
                        .font(.caption.monospaced()).foregroundStyle(.secondary)
                    if !model.samples.contains { $0.kind == .workout } {
                        Label("未排除运动影响", systemImage: "figure.run")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }.font(.subheadline)
                }
            }.padding()
        }
        .background(CPTrendPalette.canvas)
        .navigationTitle("趋势")
        .sheet(isPresented: $choosingDate) { CPTrendDateSheet(anchor: $anchor) }
        .refreshable { await model.refreshHealth() }
    }
}

@MainActor struct HealthOverviewView: View {
    let model: AppController
    @State private var range: CPTrendRange = .month
    @State private var anchor = Date.now
    @State private var choosingDate = false

    var body: some View {
        let calendar = Calendar.current
        let interval = range.interval(containing: anchor, calendar: calendar)
        let inputs = CPTrendInputs(model: model)
        let sleep = SleepAggregator().summarize(samples: inputs.samples, range: interval, calendar: calendar)
        let activities = ActivitySummary().summarize(samples: inputs.samples, range: interval, calendar: calendar,
            zones: HeartRateZoneConfiguration(boundaries: model.settings.heartRateZoneBoundaries))
        let insights = HabitInsights()
        let totals = insights.dailyTotals(habits: model.habits, range: interval, calendar: calendar)
        let comparisons = HabitKind.allCases.map {
            insights.compare(kind: $0, samples: inputs.samples, habits: model.habits, range: interval, calendar: calendar)
        }
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                CPTrendRangeControls(range: $range, anchor: $anchor, choosingDate: $choosingDate, calendar: calendar)
                Text("把日常记录放在一起看")
                    .font(.title2.bold()).accessibilityAddTraits(.isHeader)
                Text("按所选日期汇总，只解释已有记录。可选健康类型会在你点选后申请读取，拒绝其中一项不影响其他功能。日累计活动以每日总量呈现；心率常规缓存为近90天，打开旧运动详情时按需读取该时段。")
                    .font(.subheadline).foregroundStyle(.secondary)
                sleepCard(sleep)
                activityCard(activities, inputs: inputs)
                daylightCard(activities, inputs: inputs)
                workoutCard(activities, inputs: inputs)
                CPTrendCard {
                    CPTrendSectionTitle(title: "本地习惯记录", symbol: "square.and.pencil")
                    Text("情绪、饮水、咖啡因和呼吸练习只保存在应用中，不读取或写入 Apple 健康。")
                        .font(.caption).foregroundStyle(.secondary)
                    ForEach(HabitKind.allCases, id: \.self) { kind in
                        let days = totals.filter { $0.kind == kind }
                        CPTrendLabeledValue(title: CPTrendFormat.habitName(kind),
                            value: CPTrendFormat.habitSummary(kind, totals: days),
                            detail: "\(days.count) 个记录日 · \(days.reduce(0) { $0 + $1.entryCount }) 条记录")
                    }
                }
                CPTrendCard {
                    CPTrendSectionTitle(title: "习惯与 SDNN 的关联", symbol: "arrow.triangle.branch")
                    Text(inputs.sourceLabel).font(.caption).foregroundStyle(.secondary)
                    Text("比较同一天的习惯记录与 SDNN 日中位数。至少需要 14 个配对日，且较低、较高记录组各有 5 日；缺少记录的日不会按零补齐。")
                        .font(.caption).foregroundStyle(.secondary)
                    ForEach(comparisons, id: \.kind) { comparison in
                        CPTrendHabitComparison(comparison: comparison)
                        if comparison.kind != comparisons.last?.kind { Divider() }
                    }
                    Text("相关不代表因果。睡眠、采样时间、运动和其他未记录因素都可能影响结果；这些比较不能证明改变某个习惯就会改变 SDNN。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Label("仅供一般健康参考，不用于疾病诊断", systemImage: "info.circle")
                    .font(.caption).foregroundStyle(.secondary)
            }.padding()
        }
        .background(CPTrendPalette.canvas)
        .navigationTitle("健康概览")
        .sheet(isPresented: $choosingDate) { CPTrendDateSheet(anchor: $anchor) }
        .refreshable { await model.refreshHealth() }
    }

    private func sleepCard(_ sleep: SleepSummary) -> some View {
        CPTrendCard {
            CPTrendSectionTitle(title: "睡眠", symbol: "moon.zzz.fill")
            CPTrendPermissionPrompt(model: model, kinds: [.sleep], identifier: "sleep",
                explanation: "读取 Apple 健康中的睡眠时段。已有睡眠阶段时显示阶段，无阶段时显示可得时长；不会诊断睡眠疾病。",
                buttonTitle: "读取睡眠记录")
            if sleep.availability == .unavailable {
                CPTrendEmpty(title: "暂未读到记录", detail: "这个日期区间没有可用睡眠记录。可检查 Apple 健康中的记录和系统读取设置。", symbol: "moon")
                    .accessibilityIdentifier("health.sleep.empty")
            } else {
                CPTrendLabeledValue(title: "已记录睡眠", value: CPTrendFormat.minutes(sleep.asleepMinutes), detail: "\(sleep.days.count) 个有记录的日 · 区间合计")
                if sleep.inBedMinutes > 0 {
                    CPTrendLabeledValue(title: "已记录卧床", value: CPTrendFormat.minutes(sleep.inBedMinutes))
                }
                if sleep.stages.contains(where: { [.core, .deep, .rem].contains($0.stage) }) {
                    Text("已记录的睡眠阶段").font(.subheadline.weight(.semibold))
                    ForEach(sleep.stages, id: \.stage) { stage in
                        CPTrendLabeledValue(title: CPTrendFormat.sleepStage(stage.stage), value: CPTrendFormat.minutes(stage.minutes))
                    }
                } else {
                    Text("暂未读到细分睡眠阶段，仅展示可得时长").font(.caption).foregroundStyle(.secondary)
                }
                NavigationLink("逐日睡眠记录") {
                    List(sleep.days, id: \.day) { day in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(day.day.formatted(date: .abbreviated, time: .omitted)).font(.headline)
                            Text("睡眠 \(CPTrendFormat.minutes(day.asleepMinutes))")
                            ForEach(day.stages, id: \.stage) { stage in
                                Text("\(CPTrendFormat.sleepStage(stage.stage))：\(CPTrendFormat.minutes(stage.minutes))").font(.caption)
                            }
                        }.accessibilityElement(children: .combine)
                    }.navigationTitle("逐日睡眠")
                }
                Text("跨午夜记录按本地日分段；重叠睡眠记录不重复累计。合计只包含所选区间内的时段。")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func activityCard(_ report: ActivityReport, inputs: CPTrendInputs) -> some View {
        CPTrendCard {
            CPTrendSectionTitle(title: "日常活动", symbol: "figure.walk")
            CPTrendPermissionPrompt(model: model, kinds: [.steps, .activeEnergy, .exerciseMinutes], identifier: "activity",
                explanation: "读取步数、活动能量和运动分钟，展示这个日期区间内已有记录的合计。不会写入或补造活动记录。", buttonTitle: "读取活动记录")
            CPTrendActivityMetric(title: "步数", unit: "步", values: report.daily.compactMap(\.steps), source: report.sourceIDs[.steps].map(inputs.sourceName))
            CPTrendActivityMetric(title: "活动能量", unit: "千卡", values: report.daily.compactMap(\.activeEnergyKCAL), source: report.sourceIDs[.activeEnergy].map(inputs.sourceName))
            CPTrendActivityMetric(title: "运动时间", unit: "分钟", values: report.daily.compactMap(\.exerciseMinutes), source: report.sourceIDs[.exerciseMinutes].map(inputs.sourceName))
            if !report.daily.isEmpty {
                NavigationLink("逐日活动记录") { CPTrendDailyActivityList(days: report.daily) }
            }
            Text("各类型选择一个记录来源进行汇总。没有记录的日保留缺失，不按零计入。")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func daylightCard(_ report: ActivityReport, inputs: CPTrendInputs) -> some View {
        CPTrendCard {
            CPTrendSectionTitle(title: "日照与正念", symbol: "sun.max.fill")
            CPTrendPermissionPrompt(model: model, kinds: [.daylightMinutes, .mindfulnessMinutes], identifier: "daylight",
                explanation: "在系统支持时读取日照时间与正念时段。这里展示 Apple 健康已有记录；应用内呼吸计时另外记录。", buttonTitle: "读取日照与正念记录")
            CPTrendActivityMetric(title: "日照时间", unit: "分钟", values: report.daily.compactMap(\.daylightMinutes), source: report.sourceIDs[.daylightMinutes].map(inputs.sourceName))
            CPTrendActivityMetric(title: "正念时间", unit: "分钟", values: report.daily.compactMap(\.mindfulnessMinutes), source: report.sourceIDs[.mindfulnessMinutes].map(inputs.sourceName))
        }
    }

    private func workoutCard(_ report: ActivityReport, inputs: CPTrendInputs) -> some View {
        CPTrendCard {
            CPTrendSectionTitle(title: "运动与心率", symbol: "heart.text.square")
            CPTrendPermissionPrompt(model: model, kinds: [.workout, .heartRate], identifier: "workout",
                explanation: "读取运动记录和运动期间的心率，用于摘要、用户设置的心率区间统计，以及排除运动期间和结束后 30 分钟的 SDNN 评分影响。", buttonTitle: "读取运动与心率记录")
            if model.settings.heartRateZoneBoundaries.isEmpty {
                Text("尚未设置心率区间。仍可查看运动时长与原始心率摘要；区间边界可在设置中输入。")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Text("使用自设边界：\(model.settings.heartRateZoneBoundaries.map { CPTrendFormat.number($0) }.joined(separator: " / ")) 次/分")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if report.workouts.isEmpty {
                CPTrendEmpty(title: "暂未读到记录", detail: "这个区间暂无运动摘要。没有运动记录不等于没有运动。", symbol: "figure.run")
            } else {
                Text("\(report.workouts.count) 次运动 · 已记录 \(CPTrendFormat.minutes(report.workouts.reduce(0) { $0 + $1.durationMinutes }))")
                    .font(.headline)
                ForEach(report.workouts.sorted { $0.start > $1.start }) { workout in
                    NavigationLink {
                        CPTrendWorkoutDetailLoader(model: model, workout: workout, sourceLabel: inputs.sourceName(workout.sourceID))
                    } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(CPTrendFormat.workoutName(workout.activityType)).font(.subheadline.weight(.semibold))
                            Text(workout.start.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary)
                            Text("\(CPTrendFormat.minutes(workout.durationMinutes)) · 心率 \(workout.heartRateSampleCount) 条").font(.caption)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }.buttonStyle(.plain)
                }
            }
        }
    }
}

// MARK: - Source isolation and civil-date navigation

private struct CPTrendInputs {
    let samples: [HealthSample]
    let assessments: [WellnessAssessment]
    let sourceID: String?
    let sourceLabel: String

    @MainActor init(model: AppController) {
        // Settings win during a source change, before the asynchronous recalculation finishes.
        let selected = model.settings.selectedSourceID ?? model.summary?.assessment.sourceID ??
            model.samples.filter { $0.kind == .sdnn && $0.isAppleWatch && $0.value.isFinite && $0.value > 0 }
                .max(by: { $0.start < $1.start })?.sourceID
        sourceID = selected
        samples = model.samples.filter { $0.kind != .sdnn || $0.sourceID == selected }
        assessments = model.assessments.filter { $0.sourceID == selected }
        let name = model.samples.first { $0.kind == .sdnn && $0.sourceID == selected }?.sourceName ?? selected
        sourceLabel = name.map { "SDNN 来源：\($0)" } ?? "SDNN 来源：暂未读到 Apple Watch 记录"
    }
    func sdnn(in range: DateInterval) -> [HealthSample] {
        var seen = Set<UUID>()
        return samples.filter { $0.kind == .sdnn && $0.start >= range.start && $0.start < range.end }
            .sorted { $0.start > $1.start }.filter { seen.insert($0.id).inserted }
    }
    func assessment(for sample: HealthSample) -> WellnessAssessment? {
        assessments.filter { $0.sampleID == sample.id && $0.sourceID == sample.sourceID && $0.observedAt == sample.start }
            .sorted { ($0.score ?? -1) < ($1.score ?? -1) }.first
    }
    func sourceName(_ id: String) -> String { samples.first { $0.sourceID == id }?.sourceName ?? id }
}

private enum CPTrendRange: String, CaseIterable, Sendable {
    case day, week, month, year
    var title: String {
        switch self { case .day: "日"; case .week: "周"; case .month: "月"; case .year: "年" }
    }
    var component: Calendar.Component {
        switch self { case .day: .day; case .week: .weekOfYear; case .month: .month; case .year: .year }
    }
    func fullInterval(containing date: Date, calendar: Calendar) -> DateInterval {
        calendar.dateInterval(of: component, for: date) ?? DateInterval(start: calendar.startOfDay(for: date), duration: 86400)
    }
    func interval(containing date: Date, calendar: Calendar, now: Date = .now) -> DateInterval {
        let full = fullInterval(containing: date, calendar: calendar)
        return DateInterval(start: full.start, end: max(full.start, min(full.end, now)))
    }
}

private struct CPTrendRangeControls: View {
    @Binding var range: CPTrendRange
    @Binding var anchor: Date
    @Binding var choosingDate: Bool
    let calendar: Calendar
    var body: some View {
        VStack(spacing: 14) {
            Picker("日期区间", selection: $range) {
                ForEach(CPTrendRange.allCases, id: \.self) { option in Text(option.title).tag(option) }
            }
            #if os(iOS)
            .pickerStyle(.segmented)
            #endif
            .accessibilityIdentifier("trend.rangePicker")
            HStack(spacing: 12) {
                Button { move(-1) } label: { Image(systemName: "chevron.left").frame(minWidth: 36, minHeight: 36) }
                    .accessibilityLabel("上一个\(range.title)").accessibilityIdentifier("trend.previous")
                Button { choosingDate = true } label: {
                    VStack(spacing: 3) {
                        Text(CPTrendFormat.range(range.fullInterval(containing: anchor, calendar: calendar))).font(.subheadline.weight(.semibold))
                        Text("点选日期查看历史").font(.caption2).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity)
                }.buttonStyle(.plain).accessibilityIdentifier("trend.chooseDate")
                Button { move(1) } label: { Image(systemName: "chevron.right").frame(minWidth: 36, minHeight: 36) }
                    .disabled(range.fullInterval(containing: anchor, calendar: calendar).end > .now)
                    .accessibilityLabel("下一个\(range.title)").accessibilityIdentifier("trend.next")
            }
            if !range.fullInterval(containing: anchor, calendar: calendar).contains(.now) {
                Button("回到当前\(range.title)") { anchor = .now }.font(.caption)
            }
        }
    }
    private func move(_ amount: Int) {
        let period = range.fullInterval(containing: anchor, calendar: calendar)
        // Move from the period start, avoiding month-end clamping drift.
        if let date = calendar.date(byAdding: range.component, value: amount, to: period.start) { anchor = min(date, .now) }
    }
}

private struct CPTrendDateSheet: View {
    @Binding var anchor: Date
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("选择任意历史日期，查看所在的日、周、月或年。所有已读取历史都可按日期访问。")
                        .font(.subheadline).foregroundStyle(.secondary)
                    DatePicker("历史日期", selection: $anchor, in: ...Date.now, displayedComponents: .date)
                        #if os(iOS)
                        .datePickerStyle(.graphical)
                        #endif
                        .accessibilityIdentifier("trend.datePicker")
                }.padding()
            }.navigationTitle("选择日期")
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
        }
    }
}

// MARK: - Charts, coverage and sample shares

private enum CPTrendChartMetric: String, CaseIterable {
    case relative, sdnn
    var title: String { self == .sdnn ? "原始 HRV" : "压力参考" }
}
private struct CPTrendScatterChart: View {
    let report: TrendReport
    let metric: CPTrendChartMetric
    private var points: [TrendPoint] { metric == .sdnn ? report.points : report.points.filter { StressPresentation.bandIndex(for: $0.score) != nil } }
    var body: some View {
        if points.isEmpty {
            CPTrendEmpty(title: "信息不足", detail: "记录还不够了解你的日常节奏；原始记录仍可查看。", symbol: "chart.dots.scatter")
        } else {
            Chart(points) { point in
                PointMark(x: .value("测量时间", point.observedAt),
                    y: .value(metric.title, metric == .sdnn ? point.value : Double((StressPresentation.bandIndex(for: point.score) ?? 0))))
                    .foregroundStyle(metric == .sdnn ? CPTrendPalette.accent : StressStyle.color((StressPresentation.bandIndex(for: point.score) ?? 0)))
                    .symbolSize(42)
                    .accessibilityLabel(Text(point.observedAt.formatted(date: .abbreviated, time: .shortened)))
                    .accessibilityValue(Text(metric == .sdnn ? "SDNN \(CPTrendFormat.number(point.value)) 毫秒" : StressPresentation.titles[(StressPresentation.bandIndex(for: point.score) ?? 0)]))
            }
            .chartXScale(domain: report.range.start...max(report.range.end, report.range.start.addingTimeInterval(1)))
            .chartYScale(domain: (metric == .relative ? -0.4 : 0)...upperBound)
            .chartXAxis { AxisMarks(values: .automatic(desiredCount: 4)) }
            .chartYAxis {
                if metric == .relative {
                    AxisMarks(position: .leading, values: [0, 1, 2, 3]) { value in
                        AxisGridLine().foregroundStyle(.secondary.opacity(0.12))
                        AxisValueLabel { if let i = value.as(Int.self) { Text(StressPresentation.titles[i]).font(.caption2) } }
                    }
                } else { AxisMarks(position: .leading) }
            }
            .frame(height: 210)
            .accessibilityLabel(metric.title + "散点图")
            .accessibilityIdentifier("trend.scatterChart")
        }
    }
    private var upperBound: Double {
        if metric == .relative { return 3.4 }
        let maximum = points.map(\.value).max() ?? 10
        return max(10, maximum <= Double.greatestFiniteMagnitude / 1.15 ? maximum * 1.15 : maximum)
    }
}
private struct CPTrendStatistics: View {
    let report: TrendReport
    var body: some View {
        let values = report.points.map(\.value).sorted()
        let middle = values.count / 2
        let median = values.isEmpty ? nil : (values.count.isMultiple(of: 2) ? values[middle - 1] + (values[middle] - values[middle - 1]) / 2 : values[middle])
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 24) { statistics(median: median) }
            VStack(alignment: .leading, spacing: 14) { statistics(median: median) }
        }
    }
    @ViewBuilder private func statistics(median: Double?) -> some View {
        CPTrendLabeledValue(title: "SDNN 中位数", value: median.map { "\(CPTrendFormat.number($0)) 毫秒" } ?? "—")
        CPTrendLabeledValue(title: "有效测量", value: "\(report.coverage.sampleCount) 条", detail: "\(report.coverage.coveredCivilDays) 个有记录的日")
    }
}
private struct CPTrendCoverageView: View {
    let coverage: TrendCoverage
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("\(coverage.coveredCivilDays) / \(coverage.totalCivilDays) 日有记录")
                .font(.title3.bold()).monospacedDigit()
            ProgressView(value: coverage.fraction).tint(CPTrendPalette.accent)
                .accessibilityLabel("测量日覆盖率").accessibilityValue(CPTrendFormat.percent(coverage.fraction))
            Text("日覆盖率 \(CPTrendFormat.percent(coverage.fraction)) · \(coverage.sampleCount) 条有效样本")
                .font(.subheadline).foregroundStyle(.secondary)
        }.accessibilityElement(children: .combine)
    }
}
private struct CPTrendBandDistribution: View {
    let shares: [BandShare]
    let scoredCount: Int
    let unscoredCount: Int
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("以 \(scoredCount) 条有指标的样本为分母；\(unscoredCount) 条暂无指标")
                .font(.caption).foregroundStyle(.secondary)
            ForEach(WellnessBand.allCases, id: \.self) { band in
                let share = shares.first { $0.band == band }
                let count = share?.sampleCount ?? 0
                let fraction = share?.fraction ?? 0
                VStack(alignment: .leading, spacing: 5) {
                    ViewThatFits(in: .horizontal) {
                        HStack { Text(CPTrendFormat.band(band)); Spacer(); Text("\(count) 条 · \(CPTrendFormat.percent(fraction))").monospacedDigit() }
                        VStack(alignment: .leading) { Text(CPTrendFormat.band(band)); Text("\(count) 条 · \(CPTrendFormat.percent(fraction))").monospacedDigit() }
                    }.font(.subheadline)
                    ProgressView(value: fraction).tint(CPTrendPalette.bandColor(band))
                }.accessibilityElement(children: .combine)
            }
            Text("这些是样本比例，不是处于某状态的时间比例。不能据此推断连续压力时长。")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

// MARK: - Drill-down screens

private struct CPTrendSampleRow: View {
    let sample: HealthSample
    let assessment: WellnessAssessment?
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(sample.start.formatted(date: .abbreviated, time: .shortened)).font(.subheadline.weight(.semibold))
                Text(assessment?.band.map(CPTrendFormat.band) ?? "暂无个人趋势指标").font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 4) {
                Text(CPTrendFormat.sdnn(sample.value)).font(.subheadline.weight(.semibold)).monospacedDigit()
                if let score = assessment?.score { Text("指标 \(score)").font(.caption).monospacedDigit() }
                Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.secondary).accessibilityHidden(true)
            }
        }.accessibilityElement(children: .combine)
    }
}
private struct CPTrendSampleList: View {
    let samples: [HealthSample]
    let inputs: CPTrendInputs
    let workoutRecordsAvailable: Bool
    var body: some View {
        List(samples) { sample in
            NavigationLink {
                CPTrendSampleDetail(sample: sample, assessment: inputs.assessment(for: sample), workoutRecordsAvailable: workoutRecordsAvailable)
            } label: { CPTrendSampleRow(sample: sample, assessment: inputs.assessment(for: sample)) }
        }.navigationTitle("逐条 SDNN")
    }
}
private struct CPTrendSampleDetail: View {
    let sample: HealthSample
    let assessment: WellnessAssessment?
    let workoutRecordsAvailable: Bool
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                CPTrendCard {
                    Text("SDNN").font(.headline)
                    Text(CPTrendFormat.sdnn(sample.value)).font(.largeTitle.bold()).monospacedDigit()
                    Text(Date.now.timeIntervalSince(sample.start) > 3 * 3600 ? "历史读数" : "最近一次测量")
                        .font(.subheadline).foregroundStyle(.secondary)
                    CPTrendLabeledValue(title: "测量开始", value: sample.start.formatted(date: .complete, time: .standard))
                    CPTrendLabeledValue(title: "测量结束", value: sample.end.formatted(date: .complete, time: .standard))
                    CPTrendLabeledValue(title: "来源", value: sample.sourceName ?? sample.sourceID)
                    Text("来源标识：\(sample.sourceID)").font(.caption).foregroundStyle(.secondary)
                        #if os(iOS)
                        .textSelection(.enabled)
                        #endif
                    Text("样本标识：\(sample.id.uuidString)").font(.caption.monospaced()).foregroundStyle(.secondary)
                        #if os(iOS)
                        .textSelection(.enabled)
                        #endif
                }
                CPTrendCard {
                    CPTrendSectionTitle(title: "个人趋势指标", symbol: "waveform.path")
                    if let assessment {
                        if let score = assessment.score {
                            Text("\(score) / 100").font(.largeTitle.bold()).monospacedDigit()
                            Text(assessment.band.map(CPTrendFormat.band) ?? "暂无区间").font(.headline)
                        } else {
                            Text("信息不足或不适用于评分").font(.headline)
                            Text("需要至少 7 个有记录的历史日和 20 条有效基线样本。无效输入、运动期间及运动结束后 30 分钟的测量也不会评分。")
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                        CPTrendLabeledValue(title: "基线进度", value: "\(assessment.baselineDayCount) 日 · \(assessment.baselineSampleCount) 条",
                            detail: CPTrendFormat.confidence(assessment.confidence))
                        if let baseline = assessment.baselineRange {
                            CPTrendLabeledValue(title: "基线区间", value: CPTrendFormat.range(baseline), detail: "此前 28 个完整本地日，不包含测量当天")
                        }
                        CPTrendLabeledValue(title: "算法版本", value: assessment.version)
                        if assessment.version != WellnessEngine.version {
                            Text("这是历史算法版本的结果，定义可能不同；不会混入当前版本的趋势比例。")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    } else {
                        Text("暂无保存的指标结果").font(.headline)
                        Text("原始测量仍可查看。刷新后仅在输入和基线符合要求时生成指标。")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    if !workoutRecordsAvailable { Label("未排除运动影响", systemImage: "figure.run").font(.caption).foregroundStyle(.secondary) }
                    Text("高分仅表示本次 SDNN 相对同来源个人历史偏低，不是压力百分比或疾病概率。超过 3 小时的测量显示为历史读数。")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }.padding()
        }.background(CPTrendPalette.canvas).navigationTitle("测量详情")
    }
}
private struct CPTrendWeeklyRow: View {
    let report: WeeklyReport
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(CPTrendFormat.range(report.range)).font(.subheadline.weight(.semibold))
            Text("\(report.sampleCount) 条样本 · \(report.coveredCivilDays)/\(report.totalCivilDays) 日有记录")
                .font(.caption).foregroundStyle(.secondary)
            Text("SDNN 中位数 \(report.medianSDNN.map(CPTrendFormat.sdnn) ?? "暂未读到记录")")
                .font(.subheadline).monospacedDigit()
        }.padding(.vertical, 6).frame(maxWidth: .infinity, alignment: .leading).accessibilityElement(children: .combine)
    }
}
private struct CPTrendWeeklyDetail: View {
    let report: WeeklyReport
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                CPTrendCard {
                    Text(CPTrendFormat.range(report.range)).font(.headline)
                    CPTrendLabeledValue(title: "SDNN 中位数", value: report.medianSDNN.map(CPTrendFormat.sdnn) ?? "暂未读到记录")
                    CPTrendCoverageView(coverage: TrendCoverage(totalCivilDays: report.totalCivilDays, coveredCivilDays: report.coveredCivilDays, sampleCount: report.sampleCount))
                    Text("周报只包含所选日期区间内的部分；首尾可能不足完整一周。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                CPTrendCard {
                    CPTrendSectionTitle(title: "样本比例", symbol: "chart.bar")
                    let scored = report.bandDistribution.reduce(0) { $0 + $1.sampleCount }
                    CPTrendBandDistribution(shares: report.bandDistribution, scoredCount: scored, unscoredCount: report.sampleCount - scored)
                }
                CPTrendCard {
                    CPTrendSectionTitle(title: "已有健康记录合计", symbol: "heart.text.square")
                    CPTrendLabeledValue(title: "睡眠", value: report.sleepMinutes.map(CPTrendFormat.minutes) ?? "暂未读到记录")
                    CPTrendLabeledValue(title: "步数", value: report.steps.map { "\(CPTrendFormat.number($0)) 步" } ?? "暂未读到记录")
                    CPTrendLabeledValue(title: "活动能量", value: report.activeEnergyKCAL.map { "\(CPTrendFormat.number($0)) 千卡" } ?? "暂未读到记录")
                    CPTrendLabeledValue(title: "运动", value: report.exerciseMinutes.map(CPTrendFormat.minutes) ?? "暂未读到记录")
                    CPTrendLabeledValue(title: "日照", value: report.daylightMinutes.map(CPTrendFormat.minutes) ?? "暂未读到记录")
                    CPTrendLabeledValue(title: "正念", value: report.mindfulnessMinutes.map(CPTrendFormat.minutes) ?? "暂未读到记录")
                }
                CPTrendCard {
                    CPTrendSectionTitle(title: "本地习惯", symbol: "square.and.pencil")
                    ForEach(HabitKind.allCases, id: \.self) { kind in
                        CPTrendLabeledValue(title: CPTrendFormat.habitName(kind), value: CPTrendFormat.habitSummary(kind, totals: report.habitTotals.filter { $0.kind == kind }))
                    }
                    Text("以上是已有记录的描述，不代表因果，也不推断连续压力时长。")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }.padding()
        }.background(CPTrendPalette.canvas).navigationTitle("周报详情")
    }
}
@MainActor private struct CPTrendWorkoutDetailLoader: View {
    let model: AppController
    let workout: WorkoutSummary
    let sourceLabel: String
    @State private var loaded: WorkoutSummary?
    @State private var unavailable = false
    @State private var error: String?
    private var requestKey: String { workout.id.uuidString + model.settings.heartRateZoneBoundaries.map { String($0) }.joined(separator: ",") }
    var body: some View {
        VStack(spacing: 0) {
            if unavailable { Text("这条记录已不在本机缓存").padding() }
            else { CPTrendWorkoutDetail(workout: loaded ?? workout, sourceLabel: sourceLabel, zonesConfigured: !model.settings.heartRateZoneBoundaries.isEmpty) }
            if let error { Text(error).font(.caption).foregroundStyle(.secondary).padding() }
        }
        .task(id: requestKey) {
            do {
                let detail = try await model.loadWorkoutDetails(workout)
                guard !Task.isCancelled else { return }
                loaded = detail; unavailable = detail == nil
            } catch { self.error = "暂未读到此运动时段的心率记录，原始运动摘要仍可查看" }
        }
    }
}
private struct CPTrendWorkoutDetail: View {
    let workout: WorkoutSummary
    let sourceLabel: String
    let zonesConfigured: Bool
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                CPTrendCard {
                    Text(CPTrendFormat.workoutName(workout.activityType)).font(.title2.bold())
                    CPTrendLabeledValue(title: "开始", value: workout.start.formatted(date: .abbreviated, time: .standard))
                    CPTrendLabeledValue(title: "结束", value: workout.end.formatted(date: .abbreviated, time: .standard))
                    CPTrendLabeledValue(title: "区间内时长", value: CPTrendFormat.minutes(workout.durationMinutes))
                    CPTrendLabeledValue(title: "来源", value: sourceLabel)
                    CPTrendLabeledValue(title: "心率样本", value: "\(workout.heartRateSampleCount) 条")
                    CPTrendLabeledValue(title: "样本平均心率", value: workout.meanHeartRate.map { "\(CPTrendFormat.number($0)) 次/分" } ?? "暂未读到记录")
                    if let min = workout.minHeartRate, let max = workout.maxHeartRate {
                        CPTrendLabeledValue(title: "样本心率范围", value: "\(CPTrendFormat.number(min))–\(CPTrendFormat.number(max)) 次/分")
                    }
                }
                CPTrendCard {
                    CPTrendSectionTitle(title: "自设心率区间", symbol: "chart.bar.xaxis")
                    if !zonesConfigured {
                        Text("尚未设置区间边界。请在设置中输入，应用不会根据年龄推断最大心率。")
                    } else if workout.zones.isEmpty {
                        Text("信息不足").font(.headline)
                        Text("心率采样过于稀疏时，不补算未测量的区间时长。")
                    } else {
                        ForEach(workout.zones, id: \.index) { zone in
                            CPTrendLabeledValue(title: "区间 \(zone.index + 1)：\(CPTrendFormat.zoneBounds(zone))", value: CPTrendFormat.minutes(zone.minutes))
                        }
                    }
                    Text("仅累计间隔不超过 5 分钟的相邻同来源心率样本，不跨越长缺口，也不补算运动尾段。区间时长可能少于运动时长。")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }.padding()
        }.background(CPTrendPalette.canvas).navigationTitle("运动详情")
    }
}
private struct CPTrendDailyActivityList: View {
    let days: [ActivityDaySummary]
    var body: some View {
        List(days.reversed(), id: \.day) { day in
            VStack(alignment: .leading, spacing: 6) {
                Text(day.day.formatted(date: .abbreviated, time: .omitted)).font(.headline)
                if let value = day.steps { Text("步数 \(CPTrendFormat.number(value)) 步") }
                if let value = day.activeEnergyKCAL { Text("活动能量 \(CPTrendFormat.number(value)) 千卡") }
                if let value = day.exerciseMinutes { Text("运动 \(CPTrendFormat.minutes(value))") }
                if let value = day.daylightMinutes { Text("日照 \(CPTrendFormat.minutes(value))") }
                if let value = day.mindfulnessMinutes { Text("正念 \(CPTrendFormat.minutes(value))") }
            }.font(.subheadline).accessibilityElement(children: .combine)
        }.navigationTitle("逐日活动")
    }
}

// MARK: - Optional permission prompts and conservative associations

@MainActor private struct CPTrendPermissionPrompt: View {
    let model: AppController
    let kinds: Set<MetricKind>
    let identifier: String
    let explanation: String
    let buttonTitle: String
    @State private var requesting = false
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(explanation).font(.caption).foregroundStyle(.secondary)
                .accessibilityIdentifier("health.\(identifier).explanation")
            if !kinds.isSubset(of: model.settings.requestedMetrics) {
                Button {
                    requesting = true
                    Task { await model.request(kinds); requesting = false }
                } label: {
                    Label(requesting ? "正在读取…" : buttonTitle, systemImage: "heart.circle")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }.buttonStyle(.bordered).disabled(requesting || model.isRefreshing)
                    .accessibilityIdentifier("health.request.\(identifier)")
            }
        }
    }
}
private struct CPTrendActivityMetric: View {
    let title: String
    let unit: String
    let values: [Double]
    let source: String?
    var body: some View {
        CPTrendLabeledValue(title: title,
            value: values.isEmpty ? "暂未读到记录" : "\(CPTrendFormat.number(values.reduce(0, +))) \(unit)",
            detail: values.isEmpty ? nil : "\(values.count) 个有记录的日 · 区间合计" + (source.map { "\n来源：\($0)" } ?? ""))
    }
}
private struct CPTrendHabitComparison: View {
    let comparison: HabitComparison
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(CPTrendFormat.habitName(comparison.kind)).font(.headline)
            if comparison.status == .association, comparison.pairedDayCount >= 14,
               comparison.lowGroupCount >= 5, comparison.highGroupCount >= 5,
               let low = comparison.lowMedianSDNN, let high = comparison.highMedianSDNN {
                Text(directionLabel).font(.subheadline.weight(.semibold))
                CPTrendLabeledValue(title: "较低记录组", value: "SDNN \(CPTrendFormat.number(low)) 毫秒", detail: "\(comparison.lowGroupCount) 日 · 日中位数的中位数")
                CPTrendLabeledValue(title: "较高记录组", value: "SDNN \(CPTrendFormat.number(high)) 毫秒", detail: "\(comparison.highGroupCount) 日 · 日中位数的中位数")
                if let difference = comparison.difference {
                    Text("两组差值：\(difference > 0 ? "+" : "")\(CPTrendFormat.number(difference)) 毫秒（较高记录组 − 较低记录组）")
                        .font(.caption).monospacedDigit()
                }
                Text("\(comparison.pairedDayCount) 个配对日 · \(comparison.caveat)")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Text("信息不足").font(.subheadline.weight(.semibold))
                Text("\(comparison.pairedDayCount)/14 个配对日 · 较低组 \(comparison.lowGroupCount)/5 日 · 较高组 \(comparison.highGroupCount)/5 日")
                    .font(.caption).monospacedDigit().foregroundStyle(.secondary)
                Text("需有足够配对记录，且习惯与 SDNN 都有变化后才展示描述性关联。")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }.padding(.vertical, 4).accessibilityElement(children: .combine)
    }
    private var directionLabel: String {
        switch comparison.direction {
        case .higherSDNN: "较高记录组的 SDNN 中位数较高"
        case .lowerSDNN: "较高记录组的 SDNN 中位数较低"
        case .noDifference: "两组 SDNN 中位数相同"
        case nil: "暂无比较方向"
        }
    }
}

// MARK: - Self-contained visual components

private enum CPTrendPalette {
    static let accent = Color(red: 0.10, green: 0.47, blue: 0.52)
    static let canvas = Color.primary.opacity(0.035)
    static func bandColor(_ band: WellnessBand) -> Color {
        switch band {
        case .low: Color(red: 0.22, green: 0.55, blue: 0.48)
        case .moderate: Color(red: 0.34, green: 0.49, blue: 0.67)
        case .high: Color(red: 0.70, green: 0.46, blue: 0.20)
        case .highest: Color(red: 0.65, green: 0.32, blue: 0.38)
        }
    }
}
private struct CPTrendCard<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 14) { content }
            .frame(maxWidth: .infinity, alignment: .leading).padding(18)
            .background(.background, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 22).strokeBorder(Color.primary.opacity(0.065), lineWidth: 1) }
    }
}
private struct CPTrendSectionTitle: View {
    let title: String
    let symbol: String
    var body: some View {
        Label(title, systemImage: symbol).font(.headline).accessibilityAddTraits(.isHeader)
    }
}
private struct CPTrendLabeledValue: View {
    let title: String
    let value: String
    var detail: String? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.body.weight(.semibold)).monospacedDigit().fixedSize(horizontal: false, vertical: true)
            if let detail { Text(detail).font(.caption).foregroundStyle(.secondary) }
        }.frame(maxWidth: .infinity, alignment: .leading).accessibilityElement(children: .combine)
    }
}
private struct CPTrendEmpty: View {
    let title: String
    let detail: String
    let symbol: String
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: symbol).font(.title2).foregroundStyle(CPTrendPalette.accent).accessibilityHidden(true)
            Text(title).font(.headline)
            Text(detail).font(.subheadline).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 10)
    }
}
private enum CPTrendFormat {
    static func number(_ value: Double) -> String {
        value.isFinite ? value.formatted(.number.precision(.fractionLength(0...1))) : "—"
    }
    static func sdnn(_ value: Double) -> String { value.isFinite && value > 0 ? "\(number(value)) 毫秒" : "无效数值（原始记录保留）" }
    static func percent(_ value: Double) -> String { value.formatted(.percent.precision(.fractionLength(0))) }
    static func minutes(_ value: Double) -> String {
        guard value.isFinite, value >= 0, value < Double(Int.max / 60) else { return "—" }
        let minutes = Int(value.rounded())
        return minutes >= 60 ? "\(minutes / 60) 小时 \(minutes % 60) 分钟" : "\(minutes) 分钟"
    }
    static func range(_ interval: DateInterval) -> String {
        let last = interval.end > interval.start ? interval.end.addingTimeInterval(-1) : interval.start
        let firstString = interval.start.formatted(date: .abbreviated, time: .omitted)
        return Calendar.current.isDate(interval.start, inSameDayAs: last) ? firstString : "\(firstString) – \(last.formatted(date: .abbreviated, time: .omitted))"
    }
    static func band(_ band: WellnessBand) -> String {
        switch band { case .low: "较放松"; case .moderate: "平稳"; case .high: "有些紧绷"; case .highest: "压力偏高" }
    }
    static func confidence(_ confidence: BaselineConfidence) -> String {
        switch confidence { case .insufficient: "信息不足"; case .limited: "基线有限"; case .established: "基线已建立" }
    }
    static func sleepStage(_ stage: SleepStage) -> String {
        switch stage { case .inBed: "卧床"; case .awake: "清醒"; case .asleepUnspecified: "睡眠（未细分）"; case .core: "核心睡眠"; case .deep: "深度睡眠"; case .rem: "快速眼动睡眠" }
    }
    static func habitName(_ kind: HabitKind) -> String {
        switch kind { case .mood: "情绪"; case .waterML: "饮水"; case .caffeineMG: "咖啡因"; case .breathingSeconds: "呼吸练习" }
    }
    static func habitSummary(_ kind: HabitKind, totals: [DailyHabitTotal]) -> String {
        guard !totals.isEmpty else { return "暂无本地记录" }
        let sum = totals.reduce(0) { $0 + $1.total }
        switch kind {
        case .mood:
            let values = totals.map(\.total).sorted(), middle = values.count / 2
            let median = values.count.isMultiple(of: 2) ? values[middle - 1] + (values[middle] - values[middle - 1]) / 2 : values[middle]
            return "日中位数的中位数 \(number(median)) / 5"
        case .waterML: return "\(number(sum)) 毫升"
        case .caffeineMG: return "\(number(sum)) 毫克"
        case .breathingSeconds: return minutes(sum / 60)
        }
    }
    static func zoneBounds(_ zone: HeartRateZoneDuration) -> String {
        if let low = zone.lowerBound, let high = zone.upperBound { return "\(number(low))–小于 \(number(high)) 次/分" }
        if let low = zone.lowerBound { return "至少 \(number(low)) 次/分" }
        if let high = zone.upperBound { return "低于 \(number(high)) 次/分" }
        return "未设置边界"
    }
    static func workoutName(_ type: String?) -> String {
        guard let type else { return "运动" }
        guard let rawValue = UInt(type), let activity = HKWorkoutActivityType(rawValue: rawValue) else {
            return "运动（类型 \(type)）"
        }
        switch activity {
        case .cycling: return "骑行"
        case .running: return "跑步"
        case .swimming: return "游泳"
        case .walking: return "步行"
        case .yoga: return "瑜伽"
        case .traditionalStrengthTraining: return "力量训练"
        case .hiking: return "徒步"
        case .highIntensityIntervalTraining: return "高强度间歇训练"
        case .other: return "运动"
        default: return "运动（类型 \(type)）"
        }
    }
}
