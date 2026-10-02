#if DEBUG
import SwiftUI
import WidgetKit
import WellnessCore
import WellnessServices
/// Debug-only synthetic gallery renders the production content component; it is not a live WidgetKit host.
struct WidgetVerificationGallery: View {
    private let now = Date()
    private func entry(age: TimeInterval = 60, hidden: Bool = false, available: Bool = true, score: Int = 42, learning: Bool = false) -> PulseEntry {
        let assessment = WellnessAssessment(score: learning ? nil : score, baselineDayCount: learning ? 3 : 14, baselineSampleCount: learning ? 9 : 42,
            confidence: learning ? .insufficient : .established, sourceID: "synthetic-demonstration", sampleID: UUID(), observedAt: now.addingTimeInterval(-age))
        let summary = StoredSummary(assessment: assessment, sdnn: 36.4, sourceDevice: "demonstration", hideValues: hidden)
        return PulseEntry(date: now, state: WidgetState(summary: summary, now: now, protectedDataAvailable: available))
    }
    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                Text("合成组件样式验证").font(.headline).accessibilityIdentifier("widget.gallery")
                Text("布局验证，不代表系统刷新或真实健康数据").font(.caption2).foregroundStyle(.secondary)
                #if os(iOS)
                LazyVGrid(columns: [GridItem(.fixed(165)), GridItem(.fixed(165))], spacing: 12) {
                    item(entry(), family: .systemSmall, width: 165, height: 175)
                    item(entry(age: 14_400), family: .systemSmall, width: 165, height: 175)
                    item(entry(hidden: true), family: .systemSmall, width: 165, height: 175)
                    item(entry(available: false), family: .systemSmall, width: 165, height: 175)
                    item(entry(score: 12), family: .systemSmall, width: 165, height: 175)
                    item(entry(score: 62), family: .systemSmall, width: 165, height: 175)
                    item(entry(score: 88), family: .systemSmall, width: 165, height: 175)
                    item(entry(learning: true), family: .systemSmall, width: 165, height: 175)
                    item(entry(age: -60), family: .systemSmall, width: 165, height: 175)
                    item(PulseEntry(date: now, state: WidgetState(summary: nil, now: now, protectedDataAvailable: true)), family: .systemSmall, width: 165, height: 175)
                }
                #endif
                HStack {
                    item(entry(), family: .accessoryCircular, width: 76, height: 76)
                    #if os(iOS)
                    item(entry(age: 14_400), family: .accessoryRectangular, width: 220, height: 90)
                    #endif
                }
                #if os(watchOS)
                item(entry(age: 14_400), family: .accessoryRectangular, width: 175, height: 90)
                item(entry(hidden: true), family: .accessoryRectangular, width: 175, height: 90)
                item(entry(learning: true), family: .accessoryRectangular, width: 175, height: 90)
                #endif
            }.padding(8)
        }
    }
    private func item(_ entry: PulseEntry, family: WidgetFamily, width: CGFloat, height: CGFloat) -> some View {
        PulseWidgetContent(entry: entry, family: family)
            .padding(8).frame(width: width, height: height)
            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 18))
    }
}
#endif
