import Foundation
import WellnessCore

/// A plain-language presentation of the existing relative scale, not a new stress model.
/// All surfaces use the same freshness/privacy gate before presenting a current tendency.
public struct StressPresentation: Sendable {
    public enum State: String, Sendable { case reading, missing, learning, historical, unavailable, invalid, hidden, locked, failed }
    public let state: State
    public let title: String
    public let explanation: String
    public let bandIndex: Int?
    public let observedAt: Date?
    public let isInitial: Bool
    public static let titles = ["较放松", "平稳", "有些紧绷", "压力偏高"]
    public static let freshnessLimit: TimeInterval = 10_800
    public static func bandIndex(for score: Int?) -> Int? {
        guard let score, (0...100).contains(score) else { return nil }
        return min(3, score / 25)
    }
    public var compactExplanation: String {
        guard let bandIndex else { return explanation }
        return ["留意自己的感受就好", "按自己的节奏来", "给自己留一点空隙", "先缓一缓，也可以"][bandIndex]
    }
    public static func ageText(observedAt: Date, now: Date) -> String {
        let age = now.timeIntervalSince(observedAt)
        guard age.isFinite, age >= 0, age < Double(Int.max) else { return "时间待核对" }
        if age < 60 { return "刚刚记录" }
        if age < 3600 { return "\(Int(age / 60)) 分钟前记录" }
        if age < 86400 { return "\(Int(age / 3600)) 小时前记录" }
        return "\(Int(age / 86400)) 天前记录"
    }
    public init(summary: StoredSummary?, now: Date, status: HealthDataStatus = .available, respectPrivacy: Bool = false) {
        var state: State = .missing
        var band: Int?
        var time: Date?
        var initial = false
        if status == .protected { state = .locked }
        else if status == .failed { state = .failed }
        else if let summary {
            let assessment = summary.assessment
            if respectPrivacy && summary.hideValues { state = .hidden }
            else if !now.timeIntervalSince1970.isFinite || !assessment.observedAt.timeIntervalSince1970.isFinite || assessment.observedAt > now || !summary.sdnn.isFinite || summary.sdnn <= 0 {
                state = .invalid
            } else {
                time = assessment.observedAt
                if now.timeIntervalSince(assessment.observedAt) > Self.freshnessLimit { state = .historical }
                else if assessment.confidence == .insufficient { state = .learning }
                else if let index = Self.bandIndex(for: assessment.score) {
                    state = .reading; band = index
                    initial = assessment.confidence == .limited
                } else { state = .unavailable }
            }
        }
        self.state = state; bandIndex = band; observedAt = time; isInitial = initial
        if let band {
            title = Self.titles[band]
            explanation = ["这次身体信号偏向放松，留意自己的感受就好。", "这次身体信号比较平稳，按自己的节奏来。", "这次身体信号偏向紧绷，给自己留一点空隙。", "这次身体信号的紧绷倾向较明显，先缓一缓也可以。"][band]
        } else {
            switch state {
            case .missing: title = "还没有可用记录"; explanation = "可能还在等待手表记录或同步，有记录后再来看看。"
            case .learning: title = "正在了解你"; explanation = "继续日常佩戴，有足够记录后再给你压力参考。"
            case .historical: title = "等一条新记录"; explanation = "上次记录已经有些久，先不判断现在的状态。"
            case .unavailable: title = "这次暂不判断"; explanation = "这条记录暂不适合比较，等下一次可用记录。"
            case .invalid: title = "记录需要核对"; explanation = "这条记录的时间或数值不可用，暂不提供判断。"
            case .hidden: title = "状态已隐藏"; explanation = "打开应用，私下看看自己的节奏。"
            case .locked: title = "解锁后查看"; explanation = "解锁设备后，再来看看自己的节奏。"
            case .failed: title = "暂时读不到记录"; explanation = "稍后再试，先按自己的节奏来。"
            case .reading: title = "压力参考"; explanation = "结合自己的感受，了解身体的节奏。"
            }
        }
    }
}
