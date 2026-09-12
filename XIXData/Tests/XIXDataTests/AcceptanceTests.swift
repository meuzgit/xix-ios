// D.5 item 3: the Fraserview round entered by hand through the session (the same path the hole card's
// Save takes), the games and callouts set up as the round was played, the round ended, the engine run
// on the server — and the server's results.payload must equal the device's local RoundResult and the
// fixture's expected block. Needs `supabase functions serve` running; set XIX_ACCEPTANCE=1 to enable.
import Foundation
import Supabase
import XCTest
@testable import XIXData
@testable import XIXModels
import XIXScoring

final class AcceptanceTests: XCTestCase {
    struct Envelope: Decodable { let input: RoundInput; let expected: JSONValue }

    func testFraserviewEnteredByHandMatchesServerAndFixture() async throws {
        guard ProcessInfo.processInfo.environment["XIX_ACCEPTANCE"] != nil else {
            throw XCTSkip("set XIX_ACCEPTANCE=1 with `supabase functions serve` running (make acceptance)")
        }
        let fixtureURL = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("fraserview_2026-09-09.json")
        let fixture = try JSONDecoder().decode(Envelope.self, from: Data(contentsOf: fixtureURL))
        let input = fixture.input
        let names = ["ray": "Ray", "dave": "Dave", "mo": "Mo", "tess": "Tess"]

        // Ray sets the round up: Fraserview with par and stroke index, three guests, the three games.
        // Against a hosted project the two people are throwaway users, removed with the round at the end.
        var rayID = LocalSupabase.ray, daveID = LocalSupabase.dave
        var rayEmail = "ray@privaterelay.appleid.com", daveEmail = "dave@privaterelay.appleid.com"
        if LocalSupabase.isRemote {
            let tag = UUID().uuidString.prefix(8).lowercased()
            rayEmail = "xix-acceptance-ray-\(tag)@privaterelay.appleid.com"
            daveEmail = "xix-acceptance-dave-\(tag)@privaterelay.appleid.com"
            rayID = try await LocalSupabase.service.auth.admin.createUser(attributes: AdminUserAttributes(email: rayEmail, emailConfirm: true, userMetadata: ["display_name": .string("Ray")])).id
            daveID = try await LocalSupabase.service.auth.admin.createUser(attributes: AdminUserAttributes(email: daveEmail, emailConfirm: true, userMetadata: ["display_name": .string("Dave")])).id
            print("[acceptance] throwaway users \(rayID) \(daveID)")
        }
        let throwawayUsers: [UUID] = LocalSupabase.isRemote ? [rayID, daveID] : []
        let ray = try await LocalSupabase.client(as: rayID, email: rayEmail, label: "acc-ray")
        let dave = try await LocalSupabase.client(as: daveID, email: daveEmail, label: "acc-dave")
        let repo = RoundRepository(client: ray)
        var bundle = try await repo.createRound(
            course: CourseDraft(name: "Fraserview", region: "Vancouver", par: input.par, strokeIndex: input.strokeIndex),
            holes: input.holes, ownerName: "Ray", guestNames: ["Dave", "Mo", "Tess"])
        let roundID = bundle.round.id, courseID = bundle.round.courseId
        print("[acceptance] throwaway round \(roundID) course \(courseID?.uuidString ?? "-")")
        addTeardownBlock {
            // Remove everything this run created: the round (cascades to players, scores, games, callouts,
            // stickers, results, queue rows, medals), its course, and on a hosted project the two users.
            let db = LocalSupabase.service.schema("xix")
            try? await db.from("rounds").delete().eq("id", value: roundID).execute()
            if let courseID { try? await db.from("courses").delete().eq("id", value: courseID).execute() }
            for id in throwawayUsers { try? await LocalSupabase.service.auth.admin.deleteUser(id: id) }
            struct Count: Decodable { let count: Int }
            for (table, column, value) in [("rounds", "id", roundID.uuidString), ("players", "round_id", roundID.uuidString),
                                           ("scores", "round_id", roundID.uuidString), ("results", "round_id", roundID.uuidString),
                                           ("medals", "round_id", roundID.uuidString), ("engine_queue", "round_id", roundID.uuidString)] {
                let raw = try? await db.from(table).select("*", head: false, count: .exact).eq(column, value: value).execute()
                print("[acceptance] cleanup \(table): \(raw?.count ?? -1) rows left")
            }
            if let courseID {
                let raw = try? await db.from("courses").select("*", head: false, count: .exact).eq("id", value: courseID).execute()
                print("[acceptance] cleanup courses: \(raw?.count ?? -1) rows left")
            }
        }
        let rowOf = Dictionary(uniqueKeysWithValues: bundle.players.map { ($0.displayName, $0.id) })
        let daveRow = try XCTUnwrap(rowOf["Dave"])
        try await RoundRepository(client: dave).claimRow(roundID: bundle.round.id, playerID: daveRow)
        let games = try input.games.map { g -> GameDraft in
            let options = try JSONDecoder().decode([String: AnyJSON].self, from: JSONEncoder().encode(g.options))
            return GameDraft(format: g.format.rawValue, options: options, players: g.players.map { rowOf[names[$0.rawValue]!]! })
        }
        try await repo.setGames(roundID: bundle.round.id, games: games)
        bundle = try await repo.fetchBundle(roundID: bundle.round.id)

        // Play it: every score through the session, callouts raised and answered before their holes.
        let session = RoundSession(client: ray, roundID: bundle.round.id, connectivity: Connectivity(startMonitoring: false))
        try await session.start()
        let daveSession = RoundSession(client: dave, roundID: bundle.round.id, connectivity: Connectivity(startMonitoring: false))
        try await daveSession.start()
        try await Task.sleep(for: .milliseconds(500))
        let entered = Date()
        for hole in 1...input.holes {
            for callout in input.callouts where callout.hole == hole {
                let targets = callout.targets.map { rowOf[names[$0.rawValue]!]! }
                let created = try await PlayRepository(client: ray).createCallout(roundID: bundle.round.id, hole: hole, kind: callout.kind.rawValue,
                                                                                   targets: targets, params: ["goal": .string("par")])
                for (target, response) in callout.responses where names[target.rawValue] == "Dave" {
                    try await PlayRepository(client: dave).respondCallout(calloutID: created.id, action: response == .signed ? .signed : .ducked)
                }
            }
            for (i, p) in input.players.enumerated() {
                guard let score = input.scores[i][hole - 1] else { continue }
                let row = rowOf[names[p.id.rawValue]!]!
                switch score {
                case .strokes(let n): await session.enterScore(playerID: row, hole: hole, strokes: n, pickedUp: false)
                case .pickedUp: await session.enterScore(playerID: row, hole: hole, strokes: nil, pickedUp: true)
                }
            }
        }
        await LocalSupabase.waitUntil(30, "all 72 scores acknowledged") { await session.pendingWrites() == 0 }
        await session.resync()
        let recomputed = await session.recompute()
        let local = try XCTUnwrap(recomputed)
        XCTAssertEqual(local.status, .complete)
        print("[acceptance] 72 scores entered and acknowledged in \(String(format: "%.1f", Date().timeIntervalSince(entered)))s")

        // End the round and run the authoritative engine. Locally the test calls the function; on a hosted
        // project the Database Webhook on engine_queue does, and the test waits for the result to appear.
        let ended = Date()
        try await repo.endRound(roundID: bundle.round.id)
        if LocalSupabase.isRemote {
            await LocalSupabase.waitUntil(120, "the webhook to produce results.payload") {
                let raw = try? await LocalSupabase.service.schema("xix").from("results").select("round_id").eq("round_id", value: bundle.round.id).execute()
                return raw.map { $0.data.count > 4 } ?? false
            }
            print("[acceptance] webhook produced the result \(String(format: "%.1f", Date().timeIntervalSince(ended)))s after end_round")
        } else {
            var request = URLRequest(url: LocalSupabase.url.appendingPathComponent("functions/v1/xix-engine"))
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: ["round_id": bundle.round.id.uuidString.lowercased()])
            let (body, response) = try await URLSession.shared.data(for: request)
            XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200, String(decoding: body, as: UTF8.self))
        }

        // The server's payload equals the device's local result, field for field.
        struct PayloadOnly: Decodable { let payload: JSONValue }
        let rows: [PayloadOnly]
        do {
            // Raw bytes, decoded with a plain JSONDecoder: the client's decoder is tuned for row types, not free-form JSON.
            let raw = try await LocalSupabase.service.schema("xix").from("results").select("payload").eq("round_id", value: bundle.round.id).execute().data
            rows = try JSONDecoder().decode([PayloadOnly].self, from: raw)
        } catch { XCTFail("results select: \(error)"); throw error }
        let payloadTree = try XCTUnwrap(rows.first).payload
        let payloadData = try JSONEncoder().encode(payloadTree)
        let server = try JSONDecoder().decode(RoundResult.self, from: payloadData)
        XCTAssertEqual(server, local, "server results.payload ≠ local RoundResult")
        XCTAssertEqual(server.engineVersion, 1)

        // And the fixture's expected block, with this round's ids mapped back to the fixture's.
        bundle = try await repo.fetchBundle(roundID: bundle.round.id)   // now includes the callouts raised during play
        var back: [String: String] = [:]
        for (name, id) in rowOf { back[id.uuidString.lowercased()] = names.first { $0.value == name }!.key }
        for g in bundle.games { back[g.id.uuidString.lowercased()] = ["nassau": "g_nassau", "skins": "g_skins", "stableford": "g_stab"][g.format]! }
        for c in bundle.callouts { back[c.id.uuidString.lowercased()] = "c\(c.hole)" }
        let actual = JSONValue.unmap(payloadTree, back)
        var mismatches: [String] = []
        JSONValue.diff(expected: fixture.expected, actual: actual, path: "", into: &mismatches)
        XCTAssertTrue(mismatches.isEmpty, "payload differs from the fixture:\n" + mismatches.joined(separator: "\n"))
        struct MedalKeyOnly: Decodable { let key: String }
        let medals: [MedalKeyOnly]
        do {
            let raw = try await LocalSupabase.service.schema("xix").from("medals").select("key").eq("round_id", value: bundle.round.id).execute().data
            medals = try JSONDecoder().decode([MedalKeyOnly].self, from: raw)
        } catch { XCTFail("medals select: \(error)"); throw error }
        print("[acceptance] medals awarded on the server: \(medals.count) (\(medals.map(\.key).sorted().joined(separator: ", ")))")
        // Only claimed players hold medals on the server; Mo and Tess are guests until they sign in and claim.
        let claimed = Set([rowOf["Ray"]!, rowOf["Dave"]!].map { $0.uuidString.lowercased() })
        let expectedKeys = Set(local.medals.filter { claimed.contains($0.profile.rawValue) }.map(\.key.rawValue))
        XCTAssertEqual(Set(medals.map(\.key)), expectedKeys, "server medals = the local medals of claimed players")
        await session.stop()
        await daveSession.stop()
    }
}

/// A generic JSON tree with the fixture harness's diff rules (only expected keys, annotations skipped,
/// object-vs-array matched by id, ±1 on rivalPoints).
indirect enum JSONValue: Equatable, Codable {
    case null, bool(Bool), number(Double), string(String), array([JSONValue]), object([String: JSONValue])

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let b = try? c.decode(Bool.self) { self = .bool(b) }
        else if let d = try? c.decode(Double.self) { self = .number(d) }
        else if let s = try? c.decode(String.self) { self = .string(s) }
        else if let a = try? c.decode([JSONValue].self) { self = .array(a) }
        else { self = .object(try c.decode([String: JSONValue].self)) }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case .bool(let b): try c.encode(b)
        case .number(let d): if d == d.rounded(), abs(d) < 1e15 { try c.encode(Int(d)) } else { try c.encode(d) }
        case .string(let s): try c.encode(s)
        case .array(let a): try c.encode(a)
        case .object(let o): try c.encode(o)
        }
    }

    static func unmap(_ v: JSONValue, _ back: [String: String]) -> JSONValue {
        switch v {
        case .object(let o): return .object(Dictionary(uniqueKeysWithValues: o.map { (back[$0.key] ?? $0.key, unmap($0.value, back)) }))
        case .array(let a): return .array(a.map { unmap($0, back) })
        case .string(var s):
            if let m = back[s] { return .string(m) }
            for (uuid, id) in back { s = s.replacingOccurrences(of: uuid, with: id) }
            return .string(s)
        default: return v
        }
    }

    static func diff(expected: JSONValue, actual: JSONValue?, path: String, into out: inout [String]) {
        let skip: Set<String> = ["note", "notes", "description"]
        switch (expected, actual) {
        case (.null, nil), (.null, .some(.null)): return
        case (_, nil), (_, .some(.null)): out.append("\(path): expected \(expected), missing")
        case (.object(let e), .some(.object(let a))):
            for (k, v) in e where !k.hasPrefix("_") && !skip.contains(k) { diff(expected: v, actual: a[k], path: path.isEmpty ? k : "\(path).\(k)", into: &out) }
        case (.object(let e), .some(.array(let a))):
            var index: [String: JSONValue] = [:]
            for item in a { if case .object(let o) = item { for key in ["gameID", "calloutID", "id", "player", "profile"] { if case .string(let s)? = o[key] { index[s] = index[s] ?? item; break } } } }
            for (k, v) in e where !k.hasPrefix("_") && !skip.contains(k) { diff(expected: v, actual: index[k], path: path.isEmpty ? k : "\(path).\(k)", into: &out) }
        case (.array(let e), .some(.array(let a))):
            if e.count != a.count { out.append("\(path).count: \(e.count) vs \(a.count)") }
            for (i, v) in e.enumerated() { diff(expected: v, actual: i < a.count ? a[i] : nil, path: "\(path)[\(i)]", into: &out) }
        case (.number(let e), .some(.number(let a))):
            if abs(e - a) > (path.hasPrefix("rivalPoints") ? 1 : 0) + 1e-9 { out.append("\(path): \(e) vs \(a)") }
        default:
            if expected != actual { out.append("\(path): \(expected) vs \(String(describing: actual))") }
        }
    }
}
