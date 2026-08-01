import Foundation

/// The source that currently controls a wall group's thickness.
enum WallThicknessSource: String, Codable, CaseIterable {
    case buildingDefault
    case roomDefault
    case inheritedSharedWall
    case userConfirmed

    var arabicTitle: String {
        switch self {
        case .buildingDefault:
            return "افتراضي المبنى"
        case .roomDefault:
            return "افتراضي الغرفة"
        case .inheritedSharedWall:
            return "موروث من حائط مشترك"
        case .userConfirmed:
            return "مؤكد يدويًا"
        }
    }
}

/// A single physical wall in the app's building model. Multiple RoomPlan wall faces
/// can point to the same record when they belong to two adjacent rooms.
struct BuildingWallRecord: Codable, Identifiable, Equatable {
    let id: UUID
    var thicknessMeters: Double
    var source: WallThicknessSource
    let createdAt: Date
    var updatedAt: Date
}

/// Geometry snapshot used only for matching wall faces between separately captured rooms.
/// RoomPlan's original CapturedRoom JSON remains untouched.
struct RoomWallGeometrySnapshot: Codable, Equatable {
    let centerX: Float
    let centerY: Float
    let centerZ: Float
    let tangentX: Float
    let tangentZ: Float
    let normalX: Float
    let normalZ: Float
    let widthMeters: Float
    let heightMeters: Float
}

/// Links one RoomPlan wall face to one physical building wall record.
struct RoomWallAssignment: Codable, Identifiable, Equatable {
    let id: UUID
    let roomIndex: Int
    let roomIdentifier: UUID
    let wallIdentifier: UUID
    let wallNumber: Int
    let buildingWallID: UUID
    let geometry: RoomWallGeometrySnapshot
    let assignmentSource: WallThicknessSource
    let matchedPreviousWallIdentifier: UUID?
    let matchConfidence: Double?
    let faceSeparationMeters: Double?
}

struct RoomWallConfiguration: Codable, Identifiable, Equatable {
    var id: Int { roomIndex }
    let roomIndex: Int
    let roomIdentifier: UUID
    let defaultThicknessMeters: Double
    let confirmedAt: Date
}

struct BuildingWallMetadataDocument: Codable {
    let schemaVersion: Int
    let updatedAt: Date
    let buildingDefaultThicknessMeters: Double
    let roomConfigurations: [RoomWallConfiguration]
    let wallRecords: [BuildingWallRecord]
    let assignments: [RoomWallAssignment]
}

/// Lightweight value consumed by SwiftUI. It intentionally contains no RoomPlan types.
struct RoomWallDisplayItem: Identifiable, Equatable {
    let id: UUID
    let roomIndex: Int
    let wallNumber: Int
    let wallIdentifier: UUID
    let buildingWallID: UUID
    let thicknessCentimeters: Double
    let source: WallThicknessSource
    let isShared: Bool
    let matchConfidence: Double?
    let faceSeparationCentimeters: Double?
}
