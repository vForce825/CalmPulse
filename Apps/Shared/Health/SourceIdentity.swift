import Foundation
import WellnessCore
public enum SourceIdentity {
    /// A missing device identifier cannot safely share a baseline with another record.
    public static func key(for kind: MetricKind = .sdnn, bundle: String, localDeviceID: String?, sampleID: UUID, isAppleWatch: Bool = false, hardware: String? = nil) -> String {
        if let localDeviceID, !localDeviceID.isEmpty { return bundle + "|" + localDeviceID }
        if kind == .sdnn {
            if let native = nativeWatchSource(bundle: bundle, isAppleWatch: isAppleWatch, hardware: hardware) { return native }
            return bundle + "|unidentified|" + sampleID.uuidString
        }
        return bundle + "|unidentified-producer"
    }
    /// Compatibility heuristic for the observed native Watch source format, not an Apple-guaranteed hardware ID.
    public static func nativeWatchSource(bundle: String, isAppleWatch: Bool, hardware: String?) -> String? {
        let prefix = "com.apple.health."
        guard isAppleWatch, bundle.hasPrefix(prefix), let uuid = UUID(uuidString: String(bundle.dropFirst(prefix.count))) else { return nil }
        return prefix + uuid.uuidString + "|native-watch-source|" + (hardware ?? "unknown-hardware")
    }
}
