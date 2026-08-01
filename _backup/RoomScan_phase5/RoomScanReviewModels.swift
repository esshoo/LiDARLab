import Foundation
import RoomPlan

struct RoomRevisionMetrics: Codable, Equatable {
  let wallCount: Int
  let doorCount: Int
  let windowCount: Int
  let openingCount: Int
  let objectCount: Int

  init(room: CapturedRoom) {
    wallCount = room.walls.count
    doorCount = room.doors.count
    windowCount = room.windows.count
    openingCount = room.openings.count
    objectCount = room.objects.count
  }
}

enum RoomRevisionDecision: String, Codable, Equatable {
  case pending
  case accepted
  case rejected

  var arabicTitle: String {
    switch self {
    case .pending:
      return "بانتظار المراجعة"
    case .accepted:
      return "معتمدة"
    case .rejected:
      return "مرفوضة"
    }
  }
}

struct RoomRevisionRecord: Codable, Identifiable, Equatable {
  let id: UUID
  let roomIndex: Int
  let revisionNumber: Int
  let createdAt: Date
  var decidedAt: Date?
  var decision: RoomRevisionDecision
  let originalRoomIdentifier: UUID
  let candidateRoomIdentifier: UUID
  let originalMetrics: RoomRevisionMetrics
  let candidateMetrics: RoomRevisionMetrics
  let originalRelativePath: String
  let candidateRelativePath: String
}

struct RoomRevisionDocument: Codable, Equatable {
  let schemaVersion: Int
  let updatedAt: Date
  let revisions: [RoomRevisionRecord]
}

/// In-memory candidate kept until the user accepts or rejects the new scan.
struct PendingRoomRevision: Identifiable {
  let record: RoomRevisionRecord
  let originalRoom: CapturedRoom
  let candidateRoom: CapturedRoom

  var id: UUID { record.id }
}

/// Lightweight room information consumed by the review UI.
struct RoomReviewSummary: Identifiable, Equatable {
  var id: Int { roomIndex }
  let roomIndex: Int
  let roomIdentifier: UUID
  let metrics: RoomRevisionMetrics
  let revisionCount: Int
  let sharedWallCount: Int
}
