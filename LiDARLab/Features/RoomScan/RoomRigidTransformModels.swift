import Foundation
import simd

/// App-owned rigid horizontal transform for an entire captured room.
/// It moves/rotates the room as one block without rewriting CapturedRoom geometry.
struct RoomRigidTransformRecord: Codable, Identifiable, Equatable {
    let id: UUID
    let roomIndex: Int
    let roomIdentifier: UUID
    let pivotX: Double
    let pivotZ: Double
    var translationXMeters: Double
    var translationZMeters: Double
    var rotationDegrees: Double
    var isLocked: Bool
    let createdAt: Date
    var updatedAt: Date

    var isIdentity: Bool {
        abs(translationXMeters) < 0.000_001
            && abs(translationZMeters) < 0.000_001
            && abs(rotationDegrees) < 0.000_001
    }

    func applying(to point: SIMD2<Float>) -> SIMD2<Float> {
        let pivot = SIMD2<Float>(Float(pivotX), Float(pivotZ))
        let local = point - pivot
        let radians = Float(rotationDegrees * .pi / 180)
        let cosine = cos(radians)
        let sine = sin(radians)
        let rotated = SIMD2<Float>(
            local.x * cosine - local.y * sine,
            local.x * sine + local.y * cosine
        )
        return pivot
            + rotated
            + SIMD2<Float>(Float(translationXMeters), Float(translationZMeters))
    }

    func applying(to direction: SIMD2<Float>) -> SIMD2<Float> {
        let radians = Float(rotationDegrees * .pi / 180)
        let cosine = cos(radians)
        let sine = sin(radians)
        let rotated = SIMD2<Float>(
            direction.x * cosine - direction.y * sine,
            direction.x * sine + direction.y * cosine
        )
        let length = simd_length(rotated)
        return length > 0.000_1 ? rotated / length : direction
    }

    /// Matrix suitable for a parent SceneKit node whose children remain in the
    /// original RoomPlan world coordinates.
    var sceneTransform: simd_float4x4 {
        let radians = Float(rotationDegrees * .pi / 180)
        let cosine = cos(radians)
        let sine = sin(radians)

        var rotation = matrix_identity_float4x4
        rotation.columns.0 = SIMD4<Float>(cosine, 0, sine, 0)
        rotation.columns.2 = SIMD4<Float>(-sine, 0, cosine, 0)

        var toOrigin = matrix_identity_float4x4
        toOrigin.columns.3 = SIMD4<Float>(-Float(pivotX), 0, -Float(pivotZ), 1)

        var fromOrigin = matrix_identity_float4x4
        fromOrigin.columns.3 = SIMD4<Float>(
            Float(pivotX + translationXMeters),
            0,
            Float(pivotZ + translationZMeters),
            1
        )
        return simd_mul(fromOrigin, simd_mul(rotation, toOrigin))
    }
}

struct RoomRigidTransformDocument: Codable, Equatable {
    let schemaVersion: Int
    let updatedAt: Date
    let transforms: [RoomRigidTransformRecord]
}

struct RoomAlignmentSuggestion: Equatable {
    let sourceRoomIndex: Int
    let targetRoomIndex: Int
    let buildingWallID: UUID
    let translationXCentimeters: Double
    let translationZCentimeters: Double
    let rotationDegrees: Double
    let confidence: Double?
}

/// Vertical rectangular void cut from a wall in local wall coordinates.
/// x is measured from the wall center along its tangent; y is measured from
/// the wall bottom. This is a render/export helper and does not mutate RoomPlan.
struct WallOpeningCut: Identifiable, Equatable {
    let id: UUID
    let kind: ManualOpeningKind
    let centerOffsetMeters: Float
    let bottomMeters: Float
    let widthMeters: Float
    let heightMeters: Float

    var minX: Float { centerOffsetMeters - widthMeters / 2 }
    var maxX: Float { centerOffsetMeters + widthMeters / 2 }
    var minY: Float { bottomMeters }
    var maxY: Float { bottomMeters + heightMeters }
}
