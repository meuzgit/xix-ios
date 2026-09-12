// Builds the engine's RoundInput from the local store, in the same shape xix.round_input produces
// on the server, so local and server results agree (Build Doc 2 B.3).
import Foundation
import GRDB
import XIXScoring

enum RoundInputBuilder {
    static func build(roundID: UUID, store: LocalStore) throws -> RoundInput? {
        try store.dbQueue.read { db in
            guard let round = try LocalRound.fetchOne(db, key: roundID) else { return nil }
            let holes = round.holes
            let courseHoles = try LocalCourseHole.filter(Column("round_id") == roundID).fetchAll(db)
            var par = [Int?](repeating: nil, count: holes)
            var si = [Int?](repeating: nil, count: holes)
            for h in courseHoles where h.hole >= 1 && h.hole <= holes { par[h.hole - 1] = h.par; si[h.hole - 1] = h.stroke_index }

            let players = try LocalPlayer.filter(Column("round_id") == roundID).order(Column("seat")).fetchAll(db)
            let scores = try LocalScore.filter(Column("round_id") == roundID).fetchAll(db)
            var rows: [[HoleScore?]] = []
            var inputs: [PlayerInput] = []
            for p in players {
                var row = [HoleScore?](repeating: nil, count: holes)
                var lastScored = 0
                for s in scores where s.player_id == p.id && s.hole >= 1 && s.hole <= holes {
                    row[s.hole - 1] = s.picked_up ? .pickedUp : s.strokes.map { .strokes($0) }
                    lastScored = max(lastScored, s.hole)
                }
                rows.append(row)
                let extras: PlayerExtras? = p.left_at != nil ? PlayerExtras(leftAfterHole: lastScored) : nil
                inputs.append(PlayerInput(id: PlayerID(p.id.uuidString.lowercased()), level: p.level_snapshot, name: p.display_name, extras: extras))
            }

            let games = try LocalGame.filter(Column("round_id") == roundID).order(Column("position"), Column("created_at"), Column("id")).fetchAll(db)
            let gamePlayers = try LocalGamePlayer.filter(Column("round_id") == roundID).fetchAll(db)
            let seatOf = Dictionary(uniqueKeysWithValues: players.map { ($0.id, $0.seat) })
            let gameInputs: [GameInput] = try games.map { g in
                let members = gamePlayers.filter { $0.game_id == g.id }.sorted { (seatOf[$0.player_id] ?? 0) < (seatOf[$1.player_id] ?? 0) }
                let options = try JSONDecoder().decode(Options.self, from: Data(g.options.utf8))
                var sides: [PlayerID: Int]? = nil
                if members.contains(where: { $0.side != nil }) {
                    sides = Dictionary(uniqueKeysWithValues: members.compactMap { m in m.side.map { (PlayerID(m.player_id.uuidString.lowercased()), $0) } })
                }
                return GameInput(id: GameID(g.id.uuidString.lowercased()), format: Format(lenient: g.format) ?? .strokePlay,
                                 options: options, players: members.map { PlayerID($0.player_id.uuidString.lowercased()) }, sides: sides)
            }

            let callouts = try LocalCallout.filter(Column("round_id") == roundID).order(Column("created_at"), Column("id")).fetchAll(db)
            let responses = try LocalCalloutResponse.fetchAll(db)
            let calloutInputs: [CalloutInput] = try callouts.map { c in
                let targets = (try? JSONDecoder().decode([UUID].self, from: Data(c.target_ids.utf8))) ?? []
                let params = try JSONDecoder().decode(CalloutParams.self, from: Data(c.params.utf8))
                var resp: [PlayerID: CalloutResponse] = [:]
                for r in responses where r.callout_id == c.id {
                    if let a = CalloutResponse(rawValue: r.action) { resp[PlayerID(r.player_id.uuidString.lowercased())] = a }
                }
                return CalloutInput(id: CalloutID(c.id.uuidString.lowercased()), hole: c.hole, kind: CalloutKind(rawValue: c.kind) ?? .target,
                                    caller: PlayerID(c.caller_id.uuidString.lowercased()), targets: targets.map { PlayerID($0.uuidString.lowercased()) },
                                    params: params, responses: resp)
            }

            return RoundInput(holes: holes, par: par, strokeIndex: si, players: inputs, scores: rows, games: gameInputs, callouts: calloutInputs)
        }
    }
}
