// Debug builds only: switch between the local stack and the shared project, sign out, defaults.
import SwiftUI
import XIXUI

struct DebugMenu: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    @State private var quietDefault = UserDefaults.standard.bool(forKey: "xix.quietDefault")
    @State private var initials = UserDefaults.standard.bool(forKey: "xix.initialsOnExport")

    var body: some View {
        VStack(spacing: 0) {
            GreenBar("DEBUG", onBack: { dismiss() })
            ScrollView {
                VStack(spacing: 0) {
                    SectionLabel(text: "Backend")
                    ForEach(Backend.allCases) { b in
                        ListRow(b.title, sub: b.isConfigured ? (b.url?.absoluteString ?? "") : "Not configured (make xcconfig)", dim: !b.isConfigured,
                                action: { Task { await env.switchBackend(b); dismiss() } }) {
                            if env.backend == b { Text("ON").trackedCaps(8, weight: .bold).foregroundStyle(XIXColor.green) }
                        }
                    }
                    SectionLabel(text: "Account")
                    ListRow(env.isSignedIn ? env.displayName : "Signed out", sub: env.userID?.uuidString ?? "")
                    if env.isSignedIn { ListRow("Sign out", danger: true, action: { Task { await env.signOut(); dismiss() } }) { EmptyView() } }
                    SectionLabel(text: "Defaults")
                    ListRow("Quiet mode by default", sub: "Mutes stickers sent to you") {
                        InkToggle(on: Binding(get: { quietDefault }, set: { quietDefault = $0; UserDefaults.standard.set($0, forKey: "xix.quietDefault") }))
                    }
                    ListRow("Initials on export", sub: "Off shows full names") {
                        InkToggle(on: Binding(get: { initials }, set: { initials = $0; UserDefaults.standard.set($0, forKey: "xix.initialsOnExport") }))
                    }
                }
            }
        }
        .background(XIXColor.sheet)
        .environment(\.colorScheme, .light)
    }
}
