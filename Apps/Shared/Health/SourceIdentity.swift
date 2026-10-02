import Foundation
public enum SourceIdentity {
    /// A missing device identifier cannot safely share a baseline with another record.
    public static func key(bundle: String, localDeviceID: String?, sampleID: UUID) -> String {
        if let localDeviceID, !localDeviceID.isEmpty { return bundle + "|" + localDeviceID }
        return bundle + "|unidentified|" + sampleID.uuidString
    }
}
