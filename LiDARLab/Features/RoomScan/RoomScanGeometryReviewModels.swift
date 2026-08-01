import Foundation
import simd

/// App-owned, non-destructive geometric correction for one RoomPlan wall face.
/// The original CapturedRoom and RoomWallAssignment remain unchanged.
struct WallGeometryOverrideRecord: Codable, Identifiable, Equatable {
    let id: UUID
    let assignmentID: UUID
    let buildingWallID: UUID
    let roomIndex: Int
    let wallIdentifier: UUID
    var centerOffsetAlongMeters: Double
    var centerOffsetNormalMeters: Double
    var rotationDegrees: Double
    var widthMeters: Double
    var heightMeters: Double
    let createdAt: Date
    var updatedAt: Date
}

struct WallGeometryOverrideDocument: Codable, Equatable {
    let schemaVersion: Int
    let updatedAt: Date
    let overrides: [WallGeometryOverrideRecord]
}

/// Geometry consumed by the app-owned 2D/3D review renderers after applying a correction.
struct EffectiveWallGeometry: Equatable {
    let centerX: Float
    let centerY: Float
    let centerZ: Float
    let tangentX: Float
    let tangentZ: Float
    let normalX: Float
    let normalZ: Float
    let widthMeters: Float
    let heightMeters: Float

    init(base: RoomWallGeometrySnapshot, adjustment: WallGeometryOverrideRecord?) {
        let baseTangent = Self.normalized(SIMD2<Float>(base.tangentX, base.tangentZ), fallback: SIMD2<Float>(1, 0))
        let baseNormal = Self.normalized(SIMD2<Float>(base.normalX, base.normalZ), fallback: SIMD2<Float>(-baseTangent.y, baseTangent.x))
        let rotation = Float((adjustment?.rotationDegrees ?? 0) * .pi / 180.0)
        let cosine = cos(rotation)
        let sine = sin(rotation)
        let rotatedTangent = Self.normalized(
            SIMD2<Float>(
                baseTangent.x * cosine - baseTangent.y * sine,
                baseTangent.x * sine + baseTangent.y * cosine
            ),
            fallback: baseTangent
        )
        let rotatedNormal = Self.normalized(
            SIMD2<Float>(
                baseNormal.x * cosine - baseNormal.y * sine,
                baseNormal.x * sine + baseNormal.y * cosine
            ),
            fallback: SIMD2<Float>(-rotatedTangent.y, rotatedTangent.x)
        )
        let center = SIMD2<Float>(base.centerX, base.centerZ)
            + baseTangent * Float(adjustment?.centerOffsetAlongMeters ?? 0)
            + baseNormal * Float(adjustment?.centerOffsetNormalMeters ?? 0)

        let effectiveHeight = max(Float(adjustment?.heightMeters ?? Double(base.heightMeters)), 0.05)
        let originalBottomY = base.centerY - base.heightMeters / 2
        centerX = center.x
        centerY = originalBottomY + effectiveHeight / 2
        centerZ = center.y
        tangentX = rotatedTangent.x
        tangentZ = rotatedTangent.y
        normalX = rotatedNormal.x
        normalZ = rotatedNormal.y
        widthMeters = max(Float(adjustment?.widthMeters ?? Double(base.widthMeters)), 0.05)
        heightMeters = effectiveHeight
    }

    var center2D: SIMD2<Float> { SIMD2<Float>(centerX, centerZ) }
    var tangent2D: SIMD2<Float> { SIMD2<Float>(tangentX, tangentZ) }
    var normal2D: SIMD2<Float> { SIMD2<Float>(normalX, normalZ) }
    var start2D: SIMD2<Float> { center2D - tangent2D * (widthMeters / 2) }
    var end2D: SIMD2<Float> { center2D + tangent2D * (widthMeters / 2) }

    var transform: simd_float4x4 {
        var value = matrix_identity_float4x4
        value.columns.0 = SIMD4<Float>(tangentX, 0, tangentZ, 0)
        value.columns.1 = SIMD4<Float>(0, 1, 0, 0)
        value.columns.2 = SIMD4<Float>(normalX, 0, normalZ, 0)
        value.columns.3 = SIMD4<Float>(centerX, centerY, centerZ, 1)
        return value
    }

    private static func normalized(_ value: SIMD2<Float>, fallback: SIMD2<Float>) -> SIMD2<Float> {
        let length = simd_length(value)
        return length > 0.0001 ? value / length : fallback
    }
}

enum ProjectReviewIssueSeverity: Int, Codable, CaseIterable, Comparable, Hashable {
    case information = 0
    case warning = 1
    case critical = 2

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }

    var arabicTitle: String {
        switch self {
        case .information: return "معلومة"
        case .warning: return "يحتاج مراجعة"
        case .critical: return "تعارض مهم"
        }
    }

    var systemImage: String {
        switch self {
        case .information: return "info.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .critical: return "xmark.octagon.fill"
        }
    }
}

enum ProjectReviewIssueKind: String, Codable {
    case disconnectedRoom
    case sharedByTooManyRooms
    case wallThicknessMismatch
    case lowSharedWallConfidence
    case duplicatedWall
    case malformedWall
    case openingOutsideWall
    case openingHeightConflict
    case invalidRoomConnection
    case orphanDetectedOpening
    case unconfirmedSharedThickness
    case extremeManualCorrection
}

struct ProjectReviewIssue: Codable, Identifiable, Equatable {
    let id: UUID
    let kind: ProjectReviewIssueKind
    let severity: ProjectReviewIssueSeverity
    let title: String
    let details: String
    let suggestedAction: String
    let roomIndex: Int?
    let assignmentID: UUID?
    let wallIdentifier: UUID?
    let buildingWallID: UUID?
}

struct ProjectReviewIssueDocument: Codable, Equatable {
    let schemaVersion: Int
    let generatedAt: Date
    let issues: [ProjectReviewIssue]
}
