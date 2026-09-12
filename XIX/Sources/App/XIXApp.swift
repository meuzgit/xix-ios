// The XIX app (Build Doc 3 step 1): composes XIXScoring, XIXData and XIXUI. SwiftUI lifecycle, iOS 17+.
import SwiftUI
import XIXUI

@main
struct XIXApp: App {
    @State private var env = AppEnvironment()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(env)
                .onOpenURL { url in
                    if GoogleSignInBridge.handle(url) { return }
                    env.router.open(url)
                }
                .onAppear {
                    #if DEBUG
                    // UI tests hand a link in as a launch argument (`-xix-open xix://r/CODE`).
                    if let raw = UserDefaults.standard.string(forKey: "xix-open"), let url = URL(string: raw) { env.router.open(url) }
                    #endif
                }
                .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
                    if let url = activity.webpageURL { env.router.open(url) }
                }
                .tint(XIXColor.green)
        }
    }
}
