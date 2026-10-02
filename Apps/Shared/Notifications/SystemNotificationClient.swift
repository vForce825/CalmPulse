#if canImport(UserNotifications)
@preconcurrency import UserNotifications
import Foundation
public struct SystemNotificationClient: NotificationClient {
    public init() {}
    public func isAuthorized() async -> Bool {
        let status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        return status == .authorized || status == .provisional || status == .ephemeral
    }
    public func requestPermission() async throws -> Bool {
        try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
    }
    public func schedule(sampleID: UUID) async throws {
        let content = UNMutableNotificationContent()
        content.title = "给自己片刻休息"
        content.body = "最近两次SDNN相对个人基线偏低。可查看记录，或做一次轻松呼吸。此提醒不是医疗判断。"
        content.sound = .default
        // Standard delivery respects Focus and notification settings. No critical/time-sensitive bypass.
        let request = UNNotificationRequest(identifier: "calmpulse-" + sampleID.uuidString, content: content, trigger: nil)
        try await UNUserNotificationCenter.current().add(request)
    }
}
#endif
