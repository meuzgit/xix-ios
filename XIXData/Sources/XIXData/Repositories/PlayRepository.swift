// In-round writes: scores, callouts, stickers (Build Doc 2 A.4). Called directly when online and by
// the offline queue when it drains.
import Foundation
import Supabase
import XIXModels

public struct PlayRepository: Sendable {
    let client: XIXClient
    public init(client: XIXClient) { self.client = client }

    @discardableResult
    public func enterScore(roundID: UUID, playerID: UUID, hole: Int, strokes: Int?, pickedUp: Bool, clientTs: Date) async throws -> ScoreRow {
        struct P: Encodable {
            let round_id: UUID; let player_id: UUID; let hole: Int; let strokes: Int?; let picked_up: Bool; let client_ts: String
            enum CodingKeys: String, CodingKey { case round_id, player_id, hole, strokes, picked_up, client_ts }
            // PostgREST matches an RPC by its named parameters, so a nil `strokes` must be sent as null, not omitted.
            func encode(to encoder: Encoder) throws {
                var c = encoder.container(keyedBy: CodingKeys.self)
                try c.encode(round_id, forKey: .round_id); try c.encode(player_id, forKey: .player_id); try c.encode(hole, forKey: .hole)
                try c.encode(strokes, forKey: .strokes); try c.encode(picked_up, forKey: .picked_up); try c.encode(client_ts, forKey: .client_ts)
            }
        }
        return try await client.supabase.rpc("enter_score", params: P(
            round_id: roundID, player_id: playerID, hole: hole, strokes: pickedUp ? nil : strokes, picked_up: pickedUp,
            client_ts: ISO8601.string(clientTs))).single().execute().value
    }

    @discardableResult
    public func createCallout(roundID: UUID, hole: Int, kind: String, targets: [UUID], params: [String: AnyJSON]) async throws -> CalloutRow {
        struct P: Encodable { let round_id: UUID; let hole: Int; let kind: String; let target_ids: [UUID]; let params: [String: AnyJSON] }
        return try await client.supabase.rpc("create_callout", params: P(
            round_id: roundID, hole: hole, kind: kind, target_ids: targets, params: params)).single().execute().value
    }

    @discardableResult
    public func respondCallout(calloutID: UUID, action: CalloutResponseAction) async throws -> CalloutResponseRow {
        struct P: Encodable { let callout_id: UUID; let action: String }
        return try await client.supabase.rpc("respond_callout", params: P(callout_id: calloutID, action: action.rawValue)).single().execute().value
    }

    @discardableResult
    public func sendSticker(roundID: UUID, hole: Int, targetPlayerID: UUID, stickerKey: String, packKey: String = "base") async throws -> StickerRow {
        struct P: Encodable { let round_id: UUID; let hole: Int; let target_player_id: UUID; let sticker_key: String; let pack_key: String }
        return try await client.supabase.rpc("send_sticker", params: P(
            round_id: roundID, hole: hole, target_player_id: targetPlayerID, sticker_key: stickerKey, pack_key: packKey)).single().execute().value
    }

    public func markStickerPlayed(stickerID: UUID) async throws {
        try await client.supabase.schema("xix").from("stickers")
            .update(["played_at": ISO8601.string(Date())]).eq("id", value: stickerID).execute()
    }
}
