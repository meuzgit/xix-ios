// Which Supabase the app talks to: the local stack in Debug, the shared project in Release, switchable
// from the debug menu. Values come from Info.plist, filled by the xcconfigs (XIX/Config).
import Foundation

enum Backend: String, CaseIterable, Identifiable {
    case local, shared
    var id: String { rawValue }

    var title: String { self == .local ? "Local stack" : "Shared project" }

    private static func plist(_ key: String) -> String? {
        let v = Bundle.main.object(forInfoDictionaryKey: key) as? String
        return (v?.isEmpty ?? true) ? nil : v
    }

    var url: URL? {
        URL(string: Backend.plist(self == .local ? "XIXLocalURL" : "XIXSharedURL") ?? "")
    }
    var anonKey: String? {
        Backend.plist(self == .local ? "XIXLocalAnonKey" : "XIXSharedAnonKey")
    }
    var isConfigured: Bool { url != nil && anonKey != nil }

    /// Debug builds default to local, Release to shared; the debug menu's choice persists per install.
    static var current: Backend {
        get {
            #if DEBUG
            if let raw = UserDefaults.standard.string(forKey: "xix.backend"), let b = Backend(rawValue: raw) { return b }
            #endif
            return Backend(rawValue: Backend.plist("XIXDefaultBackend") ?? "") ?? .local
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "xix.backend") }
    }
}
