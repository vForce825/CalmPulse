import SwiftUI
import WellnessCore
import WellnessServices
@main struct CalmPulseApp: App {
    @State private var runtime = AppRuntime()
    @Environment(\.scenePhase) private var scenePhase
    var body: some Scene {
        WindowGroup {
            PhoneRootView(runtime: runtime)
                .task { await runtime.start() }
                .onChange(of: scenePhase) { _, phase in if phase == .active { Task { await runtime.foreground() } } }
        }
    }
}
