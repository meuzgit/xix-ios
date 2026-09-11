// Hand-wrapped names over the generated row types (Build Doc 2 C.1).
import Foundation
import Supabase

public typealias ProfileRow = XixSchema.ProfilesSelect
public typealias CourseRow = XixSchema.CoursesSelect
public typealias CourseHoleRow = XixSchema.CourseHolesSelect
public typealias RoundRow = XixSchema.RoundsSelect
public typealias PlayerRow = XixSchema.PlayersSelect
public typealias ScoreRow = XixSchema.ScoresSelect
public typealias GameRow = XixSchema.GamesSelect
public typealias GamePlayerRow = XixSchema.GamePlayersSelect
public typealias CalloutRow = XixSchema.CalloutsSelect
public typealias CalloutResponseRow = XixSchema.CalloutResponsesSelect
public typealias StickerRow = XixSchema.StickersSelect
public typealias ResultRow = XixSchema.ResultsSelect
public typealias MedalRow = XixSchema.MedalsSelect
public typealias ConfirmationRow = XixSchema.ConfirmationsSelect

public enum RoundStatus: String, Codable, Sendable { case setup, live, ended }
public enum CalloutState: String, Codable, Sendable { case open, live, expired, resolved }
public enum CalloutResponseAction: String, Codable, Sendable { case signed, ducked }
public enum ConfirmationAction: String, Codable, Sendable { case confirm, object }

/// Timestamps arrive as ISO 8601 strings from PostgREST and Realtime, with or without fractional seconds.
public enum ISO8601 {
    private static let withFraction: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return f
    }()
    private static let plain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime]; return f
    }()

    public static func date(_ string: String?) -> Date? {
        guard let string else { return nil }
        return withFraction.date(from: string) ?? plain.date(from: string) ?? withFraction.date(from: string.replacingOccurrences(of: " ", with: "T"))
    }

    public static func string(_ date: Date) -> String { withFraction.string(from: date) }
}

extension RoundRow {
    public var roundStatus: RoundStatus { RoundStatus(rawValue: status) ?? .setup }
}

extension ScoreRow {
    public var clientDate: Date? { ISO8601.date(clientTs) }
    public var updatedDate: Date? { ISO8601.date(updatedAt) }
}
