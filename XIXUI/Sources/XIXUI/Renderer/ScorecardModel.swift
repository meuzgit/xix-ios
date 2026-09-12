// What the renderer draws. Built by the app from RoundSession state and RoundResult; the renderer
// itself knows nothing about the engine or the network (Build Doc 2 D.2).
import Foundation

public struct ScorecardModel: Equatable, Sendable {
    public enum NameStyle: String, Sendable { case names, initials }

    public struct Player: Equatable, Sendable, Identifiable {
        public var id: UUID
        public var name: String
        public var initials: String
        public init(id: UUID, name: String, initials: String? = nil) {
            self.id = id
            self.name = name
            self.initials = initials ?? ScorecardModel.initials(for: name)
        }
    }

    /// Printed-card marks (PRD 7): circle = birdie or better, square = bogey, filled = double or worse, x = picked up.
    public enum Mark: String, Equatable, Sendable { case none, circle, square, filled, x }

    public struct StickerPin: Equatable, Sendable {
        public var key: String
        public var senderInitials: String
        /// Stack depth for the "×n" tab; 1 for a single sticker.
        public var count: Int
        public init(key: String, senderInitials: String, count: Int = 1) {
            self.key = key; self.senderInitials = senderInitials; self.count = count
        }
    }

    public struct Cell: Equatable, Sendable {
        public var text: String              // "4", "X", or "" when not entered
        public var mark: Mark
        public var sticker: StickerPin?      // the top sticker on the cell
        public init(text: String, mark: Mark = .none, sticker: StickerPin? = nil) {
            self.text = text; self.mark = mark; self.sticker = sticker
        }
        public static let empty = Cell(text: "")
    }

    public var courseName: String
    public var dateLabel: String
    public var holes: Int                    // 9 or 18
    public var par: [Int?]                   // per hole
    public var players: [Player]
    public var cells: [[Cell]]               // [player][hole]
    public var totals: [Int?]                // gross per player (nil until a hole is entered)
    public var liveCalloutHole: Int?         // ink mark on that hole's column header
    public var nameStyle: NameStyle
    /// One line under the header, e.g. the active game's standing ("Skins · Ray 2 · Tess 2"). Optional.
    public var strapline: String?
    /// The join link printed in the corner of an export (PRD 8.12).
    public var joinLink: String?

    public init(courseName: String, dateLabel: String, holes: Int, par: [Int?], players: [Player], cells: [[Cell]],
                totals: [Int?], liveCalloutHole: Int? = nil, nameStyle: NameStyle = .names, strapline: String? = nil, joinLink: String? = nil) {
        self.courseName = courseName
        self.dateLabel = dateLabel
        self.holes = holes
        self.par = par
        self.players = players
        self.cells = cells
        self.totals = totals
        self.liveCalloutHole = liveCalloutHole
        self.nameStyle = nameStyle
        self.strapline = strapline
        self.joinLink = joinLink
    }

    public static func initials(for name: String) -> String {
        let parts = name.split(separator: " ").filter { !$0.isEmpty }
        let letters = parts.prefix(2).compactMap { $0.first }.map { String($0).uppercased() }
        return letters.isEmpty ? "?" : letters.joined()
    }

    /// Sum of entered cells' numeric values over a hole range; nil when none entered.
    func blockTotal(player: Int, holes range: Range<Int>) -> Int? {
        var sum = 0; var any = false
        for h in range where h < cells[player].count {
            if let v = Int(cells[player][h].text) { sum += v; any = true }
            else if cells[player][h].mark == .x, let p = par[h] { sum += 2 * p; any = true }
        }
        return any ? sum : nil
    }

    func parTotal(_ range: Range<Int>) -> Int? {
        let values = range.compactMap { $0 < par.count ? par[$0] : nil }
        return values.count == range.count ? values.reduce(0, +) : nil
    }
}
