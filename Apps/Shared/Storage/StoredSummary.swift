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
    private enum CodingKeys: String, CodingKey { case assessment, sdnn, sourceDevice, hideValues, generatedAt }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        assessment = try c.decode(WellnessAssessment.self, forKey: .assessment)
        sdnn = try c.decode(Double.self, forKey: .sdnn)
        sourceDevice = try c.decode(String.self, forKey: .sourceDevice)
        hideValues = try c.decode(Bool.self, forKey: .hideValues)
        generatedAt = try c.decodeIfPresent(Date.self, forKey: .generatedAt) ?? assessment.observedAt
    }

}
