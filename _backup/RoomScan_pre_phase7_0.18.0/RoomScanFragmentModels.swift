import Foundation

/// Why a RoomPlan capture fragment ended. RoomPlan doesn't expose a true pause API,
/// so the app freezes the current partial result and starts another fragment later.
enum RoomScanFragmentReason: String, Codable, Equatable {
    case manualPause
    case appInterruption
    case roomCompletion

    var arabicTitle: String {
        switch self {
        case .manualPause:
            return "توقف مؤقت"
        case .appInterruption:
            return "حفظ تلقائي عند مغادرة التطبيق"
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

/// Durable checkpoint for reopening an unfinished scan after the app process ends.
/// New optional fields keep checkpoints from Phase 3 readable.
struct RoomScanSessionCheckpoint: Codable, Equatable {
    let schemaVersion: Int
    let updatedAt: Date
    let completedRoomCount: Int
    let totalFragmentCount: Int
    let isPaused: Bool
    let activeRoomNumber: Int
    let activeRoomFragmentCount: Int
    let resumeScope: String

    let buildingDefaultWallThicknessMeters: Double?
    let activeRoomDefaultThicknessMeters: Double?
    let isBuildingFinished: Bool?
    let worldMapRelativePath: String?
    let referenceSnapshotRelativePath: String?
    let worldMapSavedAt: Date?
    let worldMappingStatus: String?
}

/// Lightweight summary shown before loading an unfinished project from disk.
struct RecoverableRoomScanProject: Identifiable, Equatable {
    var id: String { folderURL.path }
    let folderURL: URL
    let updatedAt: Date
    let completedRoomCount: Int
    let totalFragmentCount: Int
    let activeRoomNumber: Int
    let isPaused: Bool
    let hasWorldMap: Bool
    let hasReferenceSnapshot: Bool
}

enum RoomScanRelocalizationState: String, Equatable {
    case idle
    case preparing
    case relocalizing
    case localized
    case failed
}
