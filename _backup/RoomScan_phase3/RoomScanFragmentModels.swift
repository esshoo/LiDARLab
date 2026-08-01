import Foundation

/// Why a RoomPlan capture fragment ended. RoomPlan doesn't expose a true pause API,
/// so the app freezes the current partial result and starts another fragment later.
enum RoomScanFragmentReason: String, Codable, Equatable {
    case manualPause
    case roomCompletion

    var arabicTitle: String {
        switch self {
        case .manualPause:
            return "توقف مؤقت"
        case .roomCompletion:
            return "إنهاء الغرفة"
        }
    }
}

/// Durable metadata for one partial RoomPlan result that belongs to a logical room.
/// The actual CapturedRoom is stored in the JSON path recorded here.
struct RoomScanFragmentMetadata: Codable, Identifiable, Equatable {
    let id: UUID
    let roomIndex: Int
    let fragmentIndex: Int
    let capturedRoomIdentifier: UUID
    let reason: RoomScanFragmentReason
    let createdAt: Date
    let wallCount: Int
    let doorCount: Int
    let windowCount: Int
    let openingCount: Int
    let objectCount: Int
    let relativeJSONPath: String
}

struct RoomFragmentsDocument: Codable, Equatable {
    let schemaVersion: Int
    let updatedAt: Date
    let roomIndex: Int
    let isRoomFinalized: Bool
    let fragments: [RoomScanFragmentMetadata]
}

/// Phase 3 writes this checkpoint to prepare for Phase 4 persistence. In this phase,
/// resuming is supported only while the same app process and shared ARSession remain alive.
struct RoomScanSessionCheckpoint: Codable, Equatable {
    let schemaVersion: Int
    let updatedAt: Date
    let completedRoomCount: Int
    let totalFragmentCount: Int
    let isPaused: Bool
    let activeRoomNumber: Int
    let activeRoomFragmentCount: Int
    let resumeScope: String
}
