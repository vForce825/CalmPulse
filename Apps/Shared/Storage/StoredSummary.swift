import Foundation
import WellnessCore
public struct AppSettings: Codable, Equatable, Sendable {
    public var revision: UInt64 = 0
    public var notifications = NotificationSettings()
    public var hideWidgetValues = true
    public var selectedSourceID: String?
    public var selectedRange = "week"
    public var theme = "ocean"
    public var heartRateZoneBoundaries: [Double] = []
    public var requestedMetrics: Set<MetricKind> = []
    public init() {}
}
public struct StoredSummary: Codable, Equatable, Sendable {
    public var assessment: WellnessAssessment
    public var sdnn: Double
    public var sourceDevice: String
    public var generatedAt: Date
    public var hideValues: Bool
    public init(assessment: WellnessAssessment, sdnn: Double, sourceDevice: String, hideValues: Bool = true, generatedAt: Date = .now) {
        self.assessment = assessment; self.sdnn = sdnn; self.sourceDevice = sourceDevice; self.hideValues = hideValues; self.generatedAt = generatedAt
    }
}
