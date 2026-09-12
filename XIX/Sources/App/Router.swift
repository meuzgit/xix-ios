// Navigation: one path from Home. Links (xix://r/CODE and https://xix.golf/r/CODE) land on the join screen.
import Foundation
import Observation

enum Route: Hashable {
    case setup(SetupMode)
    case round(UUID)
    case results(UUID)
    case join(code: String)
    case settings
}

enum SetupMode: Hashable { case group, solo }

@Observable @MainActor
final class Router {
    var path: [Route] = []

    func open(_ url: URL) {
        if let code = Router.joinCode(in: url) {
            path = [.join(code: code)]
        }
    }

    /// "xix.golf/r/8K2M", "https://xix.golf/r/8K2M", "xix://r/8K2M" → "8K2M".
    static func joinCode(in url: URL) -> String? {
        let parts = url.pathComponents.filter { $0 != "/" }
        if let i = parts.firstIndex(of: "r"), i + 1 < parts.count { return parts[i + 1].uppercased() }
        if url.scheme == "xix", url.host == "r", let last = parts.last { return last.uppercased() }
        return nil
    }

    func home() { path.removeAll() }
    func replaceTop(with route: Route) {
        if path.isEmpty { path = [route] } else { path[path.count - 1] = route }
    }
}
