/// Opaque identifiers. Each encodes as a plain JSON string and can key a
/// dictionary that encodes as a JSON object (via `CodingKeyRepresentable`).

public struct PlayerID: RawRepresentable, Hashable, Comparable, Codable, CodingKeyRepresentable,
    ExpressibleByStringLiteral, CustomStringConvertible, Sendable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(_ rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { self.rawValue = value }
    public static func < (lhs: PlayerID, rhs: PlayerID) -> Bool { lhs.rawValue < rhs.rawValue }
    public var description: String { rawValue }
}

public struct GameID: RawRepresentable, Hashable, Comparable, Codable, CodingKeyRepresentable,
    ExpressibleByStringLiteral, CustomStringConvertible, Sendable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(_ rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { self.rawValue = value }
    public static func < (lhs: GameID, rhs: GameID) -> Bool { lhs.rawValue < rhs.rawValue }
    public var description: String { rawValue }
}

public struct CalloutID: RawRepresentable, Hashable, Comparable, Codable, CodingKeyRepresentable,
    ExpressibleByStringLiteral, CustomStringConvertible, Sendable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(_ rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { self.rawValue = value }
    public static func < (lhs: CalloutID, rhs: CalloutID) -> Bool { lhs.rawValue < rhs.rawValue }
    public var description: String { rawValue }
}

/// A coding key made from any string. Used to flatten format-specific detail
/// into the same JSON object as a `GameResult`'s common fields.
struct AnyCodingKey: CodingKey {
    let stringValue: String
    let intValue: Int?
    init(_ string: String) { stringValue = string; intValue = nil }
    init?(stringValue: String) { self.stringValue = stringValue; intValue = nil }
    init?(intValue: Int) { stringValue = String(intValue); self.intValue = intValue }
}
