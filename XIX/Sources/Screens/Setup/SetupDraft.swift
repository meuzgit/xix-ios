// What the five setup screens collect, and the two calls that turn it into a round (createRound, then
// setGames). Seat 0 is the owner; guests follow in the order typed.
import Foundation
import Supabase
import XIXData
import XIXScoring

struct SetupDraft {
    struct Guest: Hashable, Identifiable {
        var id = UUID()
        var name: String
        var hasXIX: Bool
    }
    struct GamePick: Hashable, Identifiable {
        var entry: GameEntry
        var seats: Set<Int>              // seat indexes in this game
        var sides: [Int: Int] = [:]      // seat → side for sided formats
        var id: String { entry.id }
    }

    var courseName = ""
    var region: String? = nil
    var holes = 18
    var par: [Int] = Array(repeating: 4, count: 18)
    var strokeIndex: [Int?] = Array(repeating: nil, count: 18)
    var yards: [Int?] = Array(repeating: nil, count: 18)
    var parSkipped = false
    var guests: [Guest] = []
    var games: [GamePick] = []

    var seatCount: Int { 1 + guests.count }
    var isValid: Bool { !courseName.trimmingCharacters(in: .whitespaces).isEmpty }

    /// Games that count against the free limit: those with enough players picked.
    var activeGames: [GamePick] { games.filter { $0.seats.count >= max(1, $0.entry.minPlayers) } }

    func drafts(playerIDs seats: [UUID]) -> [GameDraft] {
        activeGames.map { pick in
            let players = pick.seats.sorted().compactMap { seats[safe: $0] }
            var sides: [UUID: Int]? = nil
            if pick.entry.sided {
                sides = Dictionary(uniqueKeysWithValues: pick.seats.sorted().compactMap { s in seats[safe: s].map { ($0, pick.sides[s] ?? (s % 2)) } })
            }
            return GameDraft(format: pick.entry.format.rawValue, options: [:], players: players, sides: sides)
        }
    }

    /// Creates the round (course with par unless skipped, owner row, guest rows) and its games. Returns the round id.
    @MainActor
    func create(env: AppEnvironment) async throws -> UUID {
        let course = CourseDraft(name: courseName.trimmingCharacters(in: .whitespaces), region: region,
                                 par: parSkipped ? nil : par.prefix(holes).map { Optional($0) },
                                 strokeIndex: parSkipped ? nil : (strokeIndex.contains { $0 != nil } ? Array(strokeIndex.prefix(holes)) : nil),
                                 yards: yards.contains { $0 != nil } ? Array(yards.prefix(holes)) : nil)
        let bundle = try await env.rounds.createRound(course: course, holes: holes, ownerName: env.displayName, guestNames: guests.map(\.name))
        let seats = bundle.players.sorted { $0.seat < $1.seat }.map(\.id)
        let gameDrafts = drafts(playerIDs: seats)
        if !gameDrafts.isEmpty { try await env.rounds.setGames(roundID: bundle.round.id, games: gameDrafts) }
        return bundle.round.id
    }
}

extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}
