import Foundation
import XCTest
@testable import XIXScoring

/// A generic JSON tree used to compare a fixture's `expected` block against the
/// encoded `RoundResult` one field at a time.
enum JSONValue: Equatable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])
}

extension JSONValue: Decodable {
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let b = try? c.decode(Bool.self) { self = .bool(b) }
        else if let d = try? c.decode(Double.self) { self = .number(d) }
        else if let s = try? c.decode(String.self) { self = .string(s) }
        else if let a = try? c.decode([JSONValue].self) { self = .array(a) }
        else if let o = try? c.decode([String: JSONValue].self) { self = .object(o) }
        else {
            throw DecodingError.dataCorruptedError(in: c, debugDescription: "unsupported JSON value")
        }
    }

    /// Encodes any `Encodable` and re-reads it as a JSON tree.
    init<T: Encodable>(encoding value: T) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(value)
        self = try JSONDecoder().decode(JSONValue.self, from: data)
    }

    var rendered: String {
        switch self {
        case .null: return "null"
        case .bool(let b): return b ? "true" : "false"
        case .number(let d): return d == d.rounded() && abs(d) < 1e15 ? String(Int(d)) : String(d)
        case .string(let s): return "\"\(s)\""
        case .array(let a):
            let inner = a.map(\.rendered).joined(separator: ", ")
            return "[\(inner)]"
        case .object(let o):
            let inner = o.keys.sorted().map { "\($0): \(o[$0]!.rendered)" }.joined(separator: ", ")
            return "{\(inner)}"
        }
    }

    var shortRendered: String {
        let r = rendered
        return r.count > 80 ? String(r.prefix(77)) + "…" : r
    }
}

struct Mismatch {
    let path: String
    let expected: String
    let actual: String
}

/// Walks `expected` and reports every leaf that differs from `actual`.
///
/// Rules:
/// - Only keys present in `expected` are checked; the result may carry extra fields.
/// - Keys starting with `_` and the keys `note`, `notes`, `description` are annotations and skipped.
/// - An expected `null` matches an absent field.
/// - An expected object compared with an actual array of objects is matched by id
///   (`gameID`, `calloutID`, `id`, `player`, `profile`), so fixtures may key games and
///   callouts by id while the contract carries arrays.
/// - Numbers under `rivalPoints` tolerate ±1 (B.9: rounding tolerance only there).
enum JSONDiff {
    static let annotationKeys: Set<String> = ["note", "notes", "description"]
    static let idKeys = ["gameID", "calloutID", "id", "player", "profile"]

    static func diff(expected: JSONValue, actual: JSONValue?, path: String, into out: inout [Mismatch]) {
        switch (expected, actual) {
        case (.null, nil), (.null, .some(.null)):
            return
        case (_, nil), (_, .some(.null)) where expected != .null:
            leaves(of: expected, path: path) { leafPath, leaf in
                out.append(Mismatch(path: leafPath, expected: leaf.shortRendered, actual: "<missing>"))
            }
        case (.object(let e), .some(.object(let a))):
            for key in e.keys.sorted() where !isAnnotation(key) {
                diff(expected: e[key]!, actual: a[key], path: join(path, key), into: &out)
            }
        case (.object(let e), .some(.array(let a))):
            let indexed = index(a)
            for key in e.keys.sorted() where !isAnnotation(key) {
                diff(expected: e[key]!, actual: indexed[key], path: join(path, key), into: &out)
            }
        case (.array(let e), .some(.array(let a))):
            if e.count != a.count {
                out.append(Mismatch(path: "\(path).count", expected: String(e.count), actual: String(a.count)))
            }
            for i in e.indices {
                diff(expected: e[i], actual: i < a.count ? a[i] : nil, path: "\(path)[\(i)]", into: &out)
            }
        case (.number(let e), .some(.number(let a))):
            let tolerance = path.hasPrefix("rivalPoints") ? 1.0 : 0.0
            if abs(e - a) > tolerance + 1e-9 {
                out.append(Mismatch(path: path, expected: expected.rendered, actual: actual!.rendered))
            }
        default:
            if expected != actual {
                out.append(Mismatch(path: path, expected: expected.shortRendered, actual: actual!.shortRendered))
            }
        }
    }

    private static func isAnnotation(_ key: String) -> Bool {
        key.hasPrefix("_") || annotationKeys.contains(key)
    }

    private static func join(_ path: String, _ key: String) -> String {
        path.isEmpty ? key : "\(path).\(key)"
    }

    /// Indexes an array of objects by the first id-like key each carries.
    private static func index(_ array: [JSONValue]) -> [String: JSONValue] {
        var out: [String: JSONValue] = [:]
        for item in array {
            guard case .object(let o) = item else { continue }
            for key in idKeys {
                if case .string(let id)? = o[key] {
                    if out[id] == nil { out[id] = item }
                    break
                }
            }
        }
        return out
    }

    private static func leaves(of value: JSONValue, path: String, _ visit: (String, JSONValue) -> Void) {
        switch value {
        case .object(let o):
            for key in o.keys.sorted() where !isAnnotation(key) { leaves(of: o[key]!, path: join(path, key), visit) }
        case .array(let a):
            if a.isEmpty { visit(path, value) }
            for (i, v) in a.enumerated() { leaves(of: v, path: "\(path)[\(i)]", visit) }
        default:
            visit(path, value)
        }
    }
}

struct Fixture: Decodable {
    let fixture: String
    let description: String?
    let engineVersion: Int
    let input: RoundInput
    let expected: JSONValue
}

enum FixtureLoader {
    static func url(_ name: String) throws -> URL {
        guard let url = Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures") else {
            throw NSError(domain: "XIXScoringTests", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "fixture \(name).json not found in Tests/XIXScoringTests/Fixtures"])
        }
        return url
    }

    static func data(_ name: String) throws -> Data {
        try Data(contentsOf: try url(name))
    }

    static func load(_ name: String) throws -> Fixture {
        try JSONDecoder().decode(Fixture.self, from: try data(name))
    }
}

enum FixtureRunner {
    /// Runs the engine on a fixture and fails with a per-field report if any expected field differs.
    @discardableResult
    static func run(_ name: String, file: StaticString = #filePath, line: UInt = #line) throws -> RoundResult {
        let fixture = try FixtureLoader.load(name)
        let result = ScoringEngine.score(fixture.input)
        XCTAssertEqual(result.engineVersion, fixture.engineVersion, "\(name): engineVersion", file: file, line: line)

        let actual = try JSONValue(encoding: result)
        var mismatches: [Mismatch] = []
        JSONDiff.diff(expected: fixture.expected, actual: actual, path: "", into: &mismatches)
        if !mismatches.isEmpty {
            XCTFail(report(name, mismatches), file: file, line: line)
        }
        return result
    }

    static func report(_ name: String, _ mismatches: [Mismatch]) -> String {
        let width = min(60, mismatches.map(\.path.count).max() ?? 0)
        var lines = ["\(name): \(mismatches.count) field(s) differ from expected"]
        for m in mismatches {
            let pad = String(repeating: " ", count: max(1, width - m.path.count + 2))
            lines.append("  \(m.path)\(pad)expected \(m.expected) · actual \(m.actual)")
        }
        return lines.joined(separator: "\n")
    }
}
