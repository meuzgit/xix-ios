// Home at the root, every other screen pushed. The sign-in sheet rises over whatever asked for identity.
import SwiftUI
import XIXUI

struct RootView: View {
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        @Bindable var router = env.router
        NavigationStack(path: $router.path) {
            HomeScreen()
                .navigationDestination(for: Route.self) { route in
                    switch route {
                    case .setup(let mode): SetupFlow(mode: mode)
                    case .round(let id): RoundScreen(roundID: id)
                    case .results(let id): ResultsHost(roundID: id)
                    case .join(let code): JoinScreen(code: code)
                    }
                }
        }
        .toolbar(.hidden, for: .navigationBar)
        .sheet(item: Binding(get: { env.signInRequest }, set: { if $0 == nil { env.finishSignIn(success: false) } })) { request in
            SignInSheet(reason: request.reason)
                .presentationDetents([.medium, .large])
                .interactiveDismissDisabled(false)
        }
        .environment(\.colorScheme, .light)
    }
}
