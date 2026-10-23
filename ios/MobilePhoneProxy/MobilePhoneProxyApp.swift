import SwiftUI

@main
struct MobilePhoneProxyApp: App {
    @StateObject private var server = ProxyServer()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(server)
                .onOpenURL { url in server.handleCallback(url) }
                .onChange(of: scenePhase) { phase in
                    if phase == .active { server.becameActive() }
                }
                .onAppear {
                    UIApplication.shared.isIdleTimerDisabled = true
                    // Auto-start a second after launch; the user can still stop it.
                    // (Also lets xcodebuild-driven simulator smoke tests run
                    // without UI automation.)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                        server.startIfNeededOnLaunch()
                    }
                }
        }
    }
}
