// What the grid screen shows (Build Doc 2 D.3): the leaderboard strip with its mode pills, the
// scorecard model with marks and stickers, the current hole, and any notice. Built from plain values
// so the app builds it from RoundSession state and the tests build it from a fixture.
import Foundation
import XIXScoring

public struct GridScreenModel: Equatable, Sendable {
    /// One pill on the strip. The active games come first (default), Gross last.
    public struct Pill: Equatable, Sendable, Identifiable {
        public var id: String
        public var label: String                     // "SKINS", "NASSAU", "GROSS"
        public var rows: [Row]
        public init(id: String, label: String, rows: [Row]) { self.id = id; self.label = label; self.rows = rows }
    }
    public struct Row: Equatable, Sendable, Identifiable {
        public var id: UUID
        public var name: String
        public var value: String                     // "11", "3 up front · …", "+6"
        public var rank: Int?
        public init(id: UUID, name: String, value: String, rank: Int?) { self.id = id; self.name = name; self.value = value; self.rank = rank }
    }

    public struct ScoreInput: Equatable, Sendable {
        public var playerID: UUID; public var hole: Int; public var strokes: Int?; public var pickedUp: Bool
        public init(playerID: UUID, hole: Int, strokes: Int?, pickedUp: Bool) { self.playerID = playerID; self.hole = hole; self.strokes = strokes; self.pickedUp = pickedUp }
    }
    public struct StickerInput: Equatable, Sendable {
        public var targetPlayerID: UUID; public var senderPlayerID: UUID; public var hole: Int; public var key: String; public var createdAt: Double
        public init(targetPlayerID: UUID, senderPlayerID: UUID, hole: Int, key: String, createdAt: Double) {
            self.targetPlayerID = targetPlayerID; self.senderPlayerID = senderPlayerID; self.hole = hole; self.key = key; self.createdAt = createdAt
        }
    }

    public var scorecard: ScorecardModel
    public var pills: [Pill]
    public var selectedPill: String?
    /// First hole with any empty score; nil when every cell is filled.
    public var currentHole: Int?
    public var notice: String?

    public var selected: Pill? { pills.first { $0.id == selectedPill } ?? pills.first }

    public init(scorecard: ScorecardModel, pills: [Pill], selectedPill: String?, currentHole: Int?, notice: String? = nil) {
        self.scorecard = scorecard; self.pills = pills; self.selectedPill = selectedPill; self.currentHole = currentHole; self.notice = notice
    }

    // MARK: Building

    /// - Parameters:
    ///   - engineID: the engine's id for a player row (the app uses the lowercased uuid; fixtures use short ids).
    ///   - games: the round's games in order, each with its engine id, so the pills follow the setup order.
    public static func build(courseName: String, dateLabel: String, holes: Int, par: [Int?],
                             players: [ScorecardModel.Player], engineID: (UUID) -> PlayerID,
                             scores: [ScoreInput], stickers: [StickerInput], liveCalloutHoles: [Int],
                             result: RoundResult?, nameStyle: ScorecardModel.NameStyle, selectedPill: String?,
                             joinLink: String? = nil) -> GridScreenModel {
        // Cells: text and mark per player and hole.
        var cells: [[ScorecardModel.Cell]] = []
        for p in players {
            let summary = result?.perPlayer[engineID(p.id)]
            var row: [ScorecardModel.Cell] = []
            for h in 1...max(1, holes) {
                let s = scores.first { $0.playerID == p.id && $0.hole == h }
                let text = s.map { $0.pickedUp ? "X" : ($0.strokes.map(String.init) ?? "") } ?? ""
                let mark = summary.flatMap { $0.marks[safe: h - 1] }.flatMap { ScorecardModel.Mark(rawValue: $0.rawValue) } ?? .none
                row.append(ScorecardModel.Cell(text: text, mark: mark))
            }
            cells.append(row)
        }
        // Stickers: one per cell, the newest on top, a ×n tab for the stack. Totals never carry any.
        let initials = Dictionary(uniqueKeysWithValues: players.map { ($0.id, $0.initials) })
        let grouped = Dictionary(grouping: stickers.filter { $0.hole >= 1 && $0.hole <= holes }) { "\($0.targetPlayerID.uuidString)#\($0.hole)" }
        for (_, group) in grouped {
            guard let top = group.max(by: { $0.createdAt < $1.createdAt }),
                  let pi = players.firstIndex(where: { $0.id == top.targetPlayerID }) else { continue }
            cells[pi][top.hole - 1].sticker = ScorecardModel.StickerPin(key: top.key, senderInitials: initials[top.senderPlayerID] ?? "?", count: group.count)
        }
        let totals = players.map { p in result?.perPlayer[engineID(p.id)].map { $0.holesEntered > 0 ? $0.gross : nil } ?? nil }
        let scorecard = ScorecardModel(courseName: courseName, dateLabel: dateLabel, holes: holes, par: par, players: players, cells: cells,
                                       totals: totals, liveCalloutHole: liveCalloutHoles.sorted().first, nameStyle: nameStyle, joinLink: joinLink)

        // Pills: each active game, then Gross-to-par.
        var pills: [Pill] = []
        let names = Dictionary(uniqueKeysWithValues: players.map { (engineID($0.id), $0) })
        func row(_ id: PlayerID, _ value: String, rank: Int?) -> Row? {
            guard let p = names[id] else { return nil }
            return Row(id: p.id, name: nameStyle == .names ? p.name : p.initials, value: value, rank: rank)
        }
        for game in result?.games ?? [] {
            let label = pillLabel(game.format)
            var rows: [Row] = []
            switch game.detail {
            case .skins(let d):
                rows = game.standings.compactMap { row($0.player, "\(d.totals[$0.player] ?? 0)", rank: $0.rank) }
            case .stableford(let d):
                rows = game.standings.compactMap { row($0.player, "\(d.totals[$0.player] ?? 0)", rank: $0.rank) }
            case .matchPlay, .nassau:
                rows = game.standings.compactMap { st in
                    row(st.player, stripped(game.display[st.player] ?? st.label, prefix: pillPrefix(game.format)), rank: st.rank)
                }
            default:
                if case .unavailable(let reason)? = game.outcome {
                    rows = players.compactMap { row(engineID($0.id), reason, rank: nil) }
                } else {
                    rows = game.standings.compactMap { row($0.player, $0.label, rank: $0.rank) }
                }
            }
            pills.append(Pill(id: game.gameID.rawValue, label: label, rows: rows))
        }
        var grossRows: [Row] = []
        if let board = result?.leaderboard[.toPar] {
            grossRows = board.compactMap { row($0.player, toParText($0.value), rank: $0.rank) }
        } else if let board = result?.leaderboard[.gross] {
            grossRows = board.compactMap { row($0.player, "\($0.value)", rank: $0.rank) }
        }
        pills.append(Pill(id: "gross", label: "GROSS", rows: grossRows))

        let entered = Set(scores.filter { $0.strokes != nil || $0.pickedUp }.map { "\($0.playerID.uuidString)#\($0.hole)" })
        let current = (1...max(1, holes)).first { h in players.contains { !entered.contains("\($0.id.uuidString)#\(h)") } }
        return GridScreenModel(scorecard: scorecard, pills: pills, selectedPill: selectedPill ?? pills.first?.id, currentHole: current)
    }

    static func pillLabel(_ format: Format) -> String {
        switch format {
        case .strokePlay: return "STROKE"
        case .matchPlay: return "MATCH"
        case .bestBall: return "BEST BALL"
        case .alternateShot: return "ALT SHOT"
        case .fewestBlowUps: return "BLOW-UPS"
        case .beatYourAverage: return "BEAT AVG"
        case .bogeyGolf: return "BOGEY"
        case .mostPars: return "PARS"
        case .firstToFive: return "FIRST TO 5"
        case .worstHole: return "WORST HOLE"
        default: return format.rawValue.replacingOccurrences(of: "_", with: " ").uppercased()
        }
    }

    static func pillPrefix(_ format: Format) -> String {
        switch format {
        case .nassau: return "Nassau "
        case .matchPlay: return "Match "
        case .bestBall: return "Best Ball "
        default: return ""
        }
    }

    static func stripped(_ text: String, prefix: String) -> String {
        text.hasPrefix(prefix) ? String(text.dropFirst(prefix.count)) : text
    }

    static func toParText(_ v: Int) -> String { v == 0 ? "E" : (v > 0 ? "+\(v)" : "\(v)") }
}
