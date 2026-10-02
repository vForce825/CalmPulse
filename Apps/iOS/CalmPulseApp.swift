import SwiftUI
import WellnessCore
import WellnessServices
@main struct CalmPulseApp: App {
    @State private var runtime = AppRuntime()
    @Environment(\.scenePhase) private var scenePhase
    var body: some Scene {
        WindowGroup {
            Group {
                #if DEBUG
                if runtime.testing && ProcessInfo.processInfo.environment["CALMPULSE_WIDGET_GALLERY"] == "1" {
                    WidgetVerificationGallery()
                } else { PhoneRootView(runtime: runtime) }
                #else
                PhoneRootView(runtime: runtime)
                #endif
            }
                .task { await runtime.start() }
                .onChange(of: scenePhase) { _, phase in if phase == .active { Task { await runtime.foreground() } } }
        }
    }
}
