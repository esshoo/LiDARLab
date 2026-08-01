import Foundation
import RoomPlan
import simd

// MARK: - Partial correction scans

enum RoomCorrectionDecision: String, Codable, Equatable {
    case pending
    case accepted
    case rejected

    var arabicTitle: String {
        switch self {
        case .pending: return "بانتظار المراجعة"
        case .accepted: return "مقبول"
        case .rejected: return "مرفوض"
        }
    }
}

struct RoomCorrectionRecord: Codable, Identifiable, Equatable {
    let id: UUID
    let roomIndex: Int
    let correctionNumber: Int
    let createdAt: Date
    var decidedAt: Date?
    var decision: RoomCorrectionDecision
    let capturedRoomIdentifier: UUID
    let metrics: RoomRevisionMetrics
    let candidateRelativePath: String
}

struct RoomCorrectionDocument: Codable, Equatable {
    let schemaVersion: Int
    let updatedAt: Date
    let corrections: [RoomCorrectionRecord]
}

struct PendingRoomCorrection: Identifiable {
    let record: RoomCorrectionRecord
    let candidateRoom: CapturedRoom

    var id: UUID { record.id }
}

struct AcceptedRoomCorrectionLayer: Identifiable {
    let record: RoomCorrectionRecord
    let room: CapturedRoom

    var id: UUID { record.id }
    var roomIndex: Int { record.roomIndex }
}

// MARK: - App-owned doors, openings and windows

enum ManualOpeningKind: String, Codable, CaseIterable, Identifiable {
    case door
    case opening
    case window

    var id: String { rawValue }

    var arabicTitle: String {
        switch self {
        case .door: return "باب"
        case .opening: return "فتحة"
        case .window: return "نافذة"
        }
    }

    var systemImage: String {
        switch self {
        case .door: return "door.left.hand.open"
        case .opening: return "rectangle.dashed"
        case .window: return "macwindow"
        }
    }
}

enum DetectedSurfaceKind: String, Codable, CaseIterable {
    case door
    case opening
    case window

    var arabicTitle: String {
        switch self {
        case .door: return "باب مكتشف"
        case .opening: return "فتحة مكتشفة"
        case .window: return "نافذة مكتشفة"
        }
    }
}

/// A user-confirmed architectural opening. It is deliberately stored outside
/// CapturedRoom so the original RoomPlan result remains recoverable.
struct ManualOpeningRecord: Codable, Identifiable, Equatable {
    let id: UUID
    let buildingWallID: UUID
    let sourceRoomIndex: Int
    let sourceWallIdentifier: UUID
    var kind: ManualOpeningKind
    var positionRatio: Double
    var widthMeters: Double
    var heightMeters: Double
    var sillHeightMeters: Double
    var connectsRoomIndex: Int?

    /// World-space snapshot calculated from the selected physical wall.
    var centerX: Float
    var centerY: Float
    var centerZ: Float
    var tangentX: Float
    var tangentZ: Float
    var normalX: Float
    var normalZ: Float

    let createdAt: Date
    var updatedAt: Date
}

struct SuppressedDetectedSurfaceRecord: Codable, Identifiable, Equatable {
    let id: UUID
    let roomIndex: Int
    let surfaceIdentifier: UUID
    let kind: DetectedSurfaceKind
    let createdAt: Date
}

struct ManualOpeningDocument: Codable, Equatable {
    let schemaVersion: Int
    let updatedAt: Date
    let manualOpenings: [ManualOpeningRecord]
    let suppressedDetectedSurfaces: [SuppressedDetectedSurfaceRecord]
}

struct RoomWallSelection: Identifiable, Equatable {
    var id: UUID { assignmentID }
    let assignmentID: UUID
    let roomIndex: Int
    let wallNumber: Int
    let wallIdentifier: UUID
    let buildingWallID: UUID
    let geometry: RoomWallGeometrySnapshot
}

struct DetectedOpeningDisplayItem: Identifiable, Equatable {
    var id: UUID { surfaceIdentifier }
    let roomIndex: Int
    let surfaceIdentifier: UUID
    let kind: DetectedSurfaceKind
    let parentWallIdentifier: UUID?
    let widthMeters: Float
    let heightMeters: Float
    let isSuppressed: Bool
}

struct ProjectOpeningOverlay: Identifiable, Equatable {
    let id: UUID
    let roomIndex: Int
    let buildingWallID: UUID
    let kind: ManualOpeningKind
    let start: SIMD2<Float>
    let end: SIMD2<Float>
    let centerY: Float
    let widthMeters: Float
    let heightMeters: Float
    let isManual: Bool
}
