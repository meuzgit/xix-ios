// A queued write. Each carries what makes its RPC idempotent: the primary key plus client_ts for
// scores, a client-generated id for stickers and callouts (Build Doc 2 C.3).
import Foundation
import Supabase
import XIXModels

public enum Mutation: Codable, Sendable, Equatable {
    case enterScore(roundID: UUID, playerID: UUID, hole: Int, strokes: Int?, pickedUp: Bool, clientTs: Date)
    case sendSticker(id: UUID, roundID: UUID, hole: Int, targetPlayerID: UUID, stickerKey: String, packKey: String)
    case createCallout(id: UUID, roundID: UUID, hole: Int, kind: String, targets: [UUID], params: [String: AnyJSON])
    case respondCallout(roundID: UUID, calloutID: UUID, action: CalloutResponseAction)
    case markStickerPlayed(roundID: UUID, stickerID: UUID)

    public var roundID: UUID {
        switch self {
        case .enterScore(let r, _, _, _, _, _), .sendSticker(_, let r, _, _, _, _), .createCallout(_, let r, _, _, _, _),
             .respondCallout(let r, _, _), .markStickerPlayed(let r, _):
            return r
        }
    }
}

/// One line for the card when the server keeps a different value (Build Doc 2 C.2).
public struct MergeNotice: Sendable, Equatable {
    public var playerID: UUID
    public var hole: Int
    public var previous: String
    public var current: String
    public var text: String
}
