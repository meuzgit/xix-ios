// Settings (Pass 6 6j, the account part for now; the rest of the list arrives in step 6): who you are
// signed in as, the sign-in methods attached, "Add another sign-in method", sign out. Debug builds
// keep the backend switch here.
import SwiftUI
import XIXData
import XIXUI

struct SettingsScreen: View {
    @Environment(AppEnvironment.self) private var env
    @State private var providers: [String] = []
    @State private var linking = false
    #if DEBUG
    @State private var lab = false
    @State private var full = XIXFull.isActive
    #endif
    @State private var quietDefault = UserDefaults.standard.bool(forKey: "xix.quietDefault")
    @State private var initials = UserDefaults.standard.bool(forKey: "xix.initialsOnExport")
    @State private var sound = UserDefaults.standard.object(forKey: "xix.sound") as? Bool ?? true

    var body: some View {
        VStack(spacing: 0) {
            GreenBar("SETTINGS", onBack: { env.router.path.removeLast() })
            ScrollView {
                VStack(spacing: 0) {
                    SectionLabel(text: "Account")
                    if env.isSignedIn {
                        ListRow(env.displayName, sub: env.auth.currentEmail ?? "Signed in")
                        ListRow("Sign-in methods", sub: providers.isEmpty ? "…" : providers.map(Self.name).joined(separator: " · "))
                        ListRow("Add another sign-in method", sub: "Attach Apple, Google or an email address to this account", action: { linking = true }) { chevron }
                        ListRow("Sign out", danger: true, action: { Task { await env.signOut() } }) { EmptyView() }
                    } else {
                        ListRow("Not signed in", sub: "Sign-in is asked for when a round needs it")
                        ListRow("Sign in now", action: { Task { _ = await env.requireSignIn(reason: "Sign in"); await reload() } }) { chevron }
                    }
                    SectionLabel(text: "Rounds")
                    ListRow("Quiet mode by default", sub: "Mutes stickers sent to you") {
                        InkToggle(on: Binding(get: { quietDefault }, set: { quietDefault = $0; UserDefaults.standard.set($0, forKey: "xix.quietDefault") }))
                    }
                    ListRow("Names on export", sub: "Off shows initials only") {
                        InkToggle(on: Binding(get: { !initials }, set: { initials = !$0; UserDefaults.standard.set(!$0, forKey: "xix.initialsOnExport") }))
                    }
                    ListRow("Sound", sub: "One cue when a sticker lands") {
                        InkToggle(on: Binding(get: { sound }, set: { sound = $0; UserDefaults.standard.set($0, forKey: "xix.sound") }))
                    }
                    #if DEBUG
                    SectionLabel(text: "Backend · debug")
                    ForEach(Backend.allCases) { b in
                        ListRow(b.title, sub: b.isConfigured ? (b.url?.absoluteString ?? "") : "Not configured (make xcconfig)", dim: !b.isConfigured,
                                action: { Task { await env.switchBackend(b) } }) {
                            if env.backend == b { Text("ON").trackedCaps(8, weight: .bold).foregroundStyle(XIXColor.green) }
                        }
                    }
                    ListRow("User id", sub: env.userID?.uuidString ?? "—")
                    ListRow("Sticker lab", sub: "Play all twelve and measure the frame rate", action: { lab = true }) { chevron }
                    ListRow("XIX Full", sub: full ? "On. Callouts are available" : "Off. The callout gate shows instead") {
                        InkToggle(on: Binding(get: { full }, set: { full = $0; XIXFull.isActive = $0 }))
                    }
                    #endif
                }
            }
        }
        .background(XIXColor.sheet)
        .toolbar(.hidden, for: .navigationBar)
        .environment(\.colorScheme, .light)
        .task { await reload() }
        .onChange(of: env.isSignedIn) { Task { await reload() } }
        .sheet(isPresented: $linking, onDismiss: { Task { await reload() } }) { LinkIdentitySheet() }
        #if DEBUG
        .sheet(isPresented: $lab) { StickerLab() }
        #endif
    }

    private var chevron: some View { Text("›").font(XIXType.body(20)).foregroundStyle(XIXColor.faint) }

    private func reload() async {
        guard env.isSignedIn else { providers = []; return }
        providers = (try? await env.auth.identityProviders()) ?? []
    }

    static func name(_ provider: String) -> String {
        switch provider {
        case "apple": return "Apple"
        case "google": return "Google"
        case "email": return "Email code"
        default: return provider.capitalized
        }
    }
}
