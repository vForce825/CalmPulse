#if canImport(WatchConnectivity)
@preconcurrency import WatchConnectivity
import Foundation
/// WCSession persists accepted user-info transfers for offline delivery. No raw health history is transmitted.
public final class WatchBridge: NSObject, WCSessionDelegate, @unchecked Sendable {
    private let receive: @Sendable (SyncEnvelope) async -> Void
    private let ready: @Sendable () async -> Void
    private let transferFailed: @Sendable () async -> Void
    public init(receive: @escaping @Sendable (SyncEnvelope) async -> Void, ready: @escaping @Sendable () async -> Void, transferFailed: @escaping @Sendable () async -> Void = {}) {
        self.receive = receive; self.ready = ready; self.transferFailed = transferFailed; super.init()
    }
    public func start() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self; WCSession.default.activate()
    }
    public var watchInstalled: Bool {
        #if os(iOS)
        WCSession.isSupported() && WCSession.default.isWatchAppInstalled
        #else
        true
        #endif
    }
    @discardableResult public func queue(_ envelope: SyncEnvelope) -> Bool {
        guard WCSession.isSupported(), WCSession.default.activationState == .activated,
              let data = try? JSONEncoder().encode(envelope), data.count < 60_000 else { return false }
        let session = WCSession.default
        // Identical queued state is already durable; do not grow the offline queue on every foreground refresh.
        if session.outstandingUserInfoTransfers.contains(where: { ($0.userInfo["payload"] as? Data).map { envelope.isEquivalent(to: $0) } ?? false }) { return true }
        guard session.outstandingUserInfoTransfers.count < 64 else { return false }
        session.transferUserInfo(["payload": data, "attempt": 0])
        return true
    }
    public func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        guard error == nil, activationState == .activated else { return }
        Task { await ready() }
    }
    public func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        guard let data = userInfo["payload"] as? Data, data.count < 60_000,
              let envelope = try? JSONDecoder().decode(SyncEnvelope.self, from: data) else { return }
        Task { await receive(envelope) }
    }
    public func session(_ session: WCSession, didFinish userInfoTransfer: WCSessionUserInfoTransfer, error: Error?) {
        guard error != nil, let data = userInfoTransfer.userInfo["payload"] as? Data else { return }
        let attempt = (userInfoTransfer.userInfo["attempt"] as? Int ?? 0) + 1
        guard attempt <= 3 else { Task { await transferFailed() }; return } // Invalidate runtime dedup so next foreground can reconcile.
        DispatchQueue.global().asyncAfter(deadline: .now() + Double(1 << attempt)) {
            guard WCSession.default.activationState == .activated else { Task { await self.transferFailed() }; return }
            WCSession.default.transferUserInfo(["payload": data, "attempt": attempt])
        }
    }
    #if os(iOS)
    public func sessionDidBecomeInactive(_ session: WCSession) {}
    public func sessionDidDeactivate(_ session: WCSession) { session.activate() }
    #endif
}
#endif
