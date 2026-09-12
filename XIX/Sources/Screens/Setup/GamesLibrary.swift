// The games picker's library (PRD 8.5, Pass 6 6b): one line of plain rule per format, whether par is
// needed, players required, and the FULL tag. Free rounds run two games (client-side here; the server
// enforces it in step 9). Reference only: no pricing, no promotion.
import Foundation
import XIXScoring

struct GameEntry: Hashable, Identifiable {
    let format: Format
    let name: String
    let rule: String
    let needsPar: Bool
    let full: Bool
    let minPlayers: Int
    /// Two-side formats need each player on side 0 or 1.
    let sided: Bool
    var id: String { format.rawValue }
}

enum GamesLibrary {
    static let classic: [GameEntry] = [
        GameEntry(format: .skins, name: "Skins", rule: "Lowest score on a hole takes it; ties carry over", needsPar: false, full: false, minPlayers: 2, sided: false),
        GameEntry(format: .nassau, name: "Nassau", rule: "Three matches: front nine, back nine, the 18", needsPar: false, full: false, minPlayers: 2, sided: true),
        GameEntry(format: .matchPlay, name: "Match Play", rule: "Hole by hole, head to head", needsPar: false, full: false, minPlayers: 2, sided: true),
        GameEntry(format: .stableford, name: "Stableford", rule: "Points per hole against par", needsPar: true, full: false, minPlayers: 1, sided: false),
        GameEntry(format: .strokePlay, name: "Stroke Play", rule: "Fewest strokes over the round", needsPar: false, full: false, minPlayers: 1, sided: false),
        GameEntry(format: .bestBall, name: "Best Ball", rule: "Two sides, each takes its lower score", needsPar: false, full: true, minPlayers: 4, sided: true),
        GameEntry(format: .scramble, name: "Scramble", rule: "Two sides, one ball each side", needsPar: false, full: true, minPlayers: 4, sided: true),
        GameEntry(format: .shamble, name: "Shamble", rule: "Best drive, then play your own", needsPar: false, full: true, minPlayers: 4, sided: true),
        GameEntry(format: .alternateShot, name: "Alternate Shot", rule: "Two sides, taking turns on one ball", needsPar: false, full: true, minPlayers: 4, sided: true),
        GameEntry(format: .chapman, name: "Chapman", rule: "Both drive, swap, then alternate", needsPar: false, full: true, minPlayers: 4, sided: true),
    ]
    static let group: [GameEntry] = [
        GameEntry(format: .vegas, name: "Vegas", rule: "Pair scores make a two-digit number", needsPar: false, full: true, minPlayers: 4, sided: true),
        GameEntry(format: .nines, name: "Nines", rule: "Nine points shared out on every hole", needsPar: false, full: true, minPlayers: 3, sided: false),
        GameEntry(format: .sixes, name: "Sixes", rule: "Partners rotate every six holes", needsPar: false, full: true, minPlayers: 4, sided: false),
        GameEntry(format: .quota, name: "Quota", rule: "Points against your own number", needsPar: true, full: true, minPlayers: 2, sided: false),
        GameEntry(format: .rabbit, name: "Rabbit", rule: "Hold the rabbit until someone takes it off you", needsPar: false, full: true, minPlayers: 2, sided: false),
        GameEntry(format: .defender, name: "Defender", rule: "One against the rest, hole by hole", needsPar: false, full: true, minPlayers: 3, sided: false),
    ]
    static let casual: [GameEntry] = [
        GameEntry(format: .fewestBlowUps, name: "Fewest Blow-Ups", rule: "Count the holes that got away", needsPar: true, full: true, minPlayers: 1, sided: false),
        GameEntry(format: .beatYourAverage, name: "Beat Your Average", rule: "Beat your own last three rounds", needsPar: false, full: true, minPlayers: 1, sided: false),
        GameEntry(format: .bogeyGolf, name: "Bogey Golf", rule: "Bogey is your par", needsPar: true, full: true, minPlayers: 1, sided: false),
        GameEntry(format: .mostPars, name: "Most Pars", rule: "Simply the most pars in the round", needsPar: true, full: true, minPlayers: 1, sided: false),
        GameEntry(format: .firstToFive, name: "First to Five", rule: "First to five holes at par or better", needsPar: true, full: true, minPlayers: 2, sided: false),
        GameEntry(format: .worstHole, name: "Worst Hole", rule: "The round's single worst hole", needsPar: true, full: true, minPlayers: 2, sided: false),
    ]
    static let groups: [(label: String, games: [GameEntry])] = [("Classic", classic), ("Group", group), ("Casual-first", casual)]
    static var all: [GameEntry] { classic + group + casual }

    static let freeLimit = 2

    static func entry(format raw: String) -> GameEntry? {
        guard let f = Format(rawValue: raw) else { return nil }
        return all.first { $0.format == f }
    }
    static func name(for raw: String) -> String { entry(format: raw)?.name ?? raw.replacingOccurrences(of: "_", with: " ").capitalized }
}
