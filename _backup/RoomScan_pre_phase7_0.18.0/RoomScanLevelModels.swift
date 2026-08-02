import Foundation
import RoomPlan
import simd

/// App-owned floor and ceiling information. RoomPlan remains the immutable source scan.
struct RoomLevelProfileRecord: Codable, Identifiable, Equatable {
    let id: UUID
    let roomIndex: Int
    let roomIdentifier: UUID
    var story: Int
    let roomPlanFloorElevationMeters: Double
    var floorElevationMeters: Double
    var structuralCeilingHeightMeters: Double
    var finishedCeilingHeightMeters: Double
    let createdAt: Date
    var updatedAt: Date
}

enum CeilingZoneKind: String, Codable, CaseIterable, Identifiable {
    case falseCeiling
    case soffit
    case beam
    case raisedCeiling
    case custom

    var id: String { rawValue }

    var arabicTitle: String {
        switch self {
        case .falseCeiling: return "سقف مستعار"
        case .soffit: return "ساقط جبس"
        case .beam: return "كمرة"
        case .raisedCeiling: return "منطقة مرتفعة"
        case .custom: return "منطقة مخصصة"
        }
    }

    var systemImage: String {
        switch self {
        case .falseCeiling: return "rectangle.inset.filled"
        case .soffit: return "rectangle.bottomhalf.inset.filled"
        case .beam: return "rectangle.compress.vertical"
        case .raisedCeiling: return "arrow.up.to.line"
        case .custom: return "square.dashed"
        }
    }
}

/// Rectangular app-owned ceiling region expressed in the shared building coordinate space.
struct CeilingZoneRecord: Codable, Identifiable, Equatable {
    let id: UUID
    let roomIndex: Int
    var name: String
    var kind: CeilingZoneKind
    var centerX: Double
    var centerZ: Double
    var widthMeters: Double
    var depthMeters: Double
    var rotationDegrees: Double
    var heightAboveFloorMeters: Double
    let createdAt: Date
    var updatedAt: Date
}

struct RoomLevelDocument: Codable, Equatable {
    let schemaVersion: Int
    let updatedAt: Date
    let profiles: [RoomLevelProfileRecord]
    let ceilingZones: [CeilingZoneRecord]
}

/// Lightweight geometry seed derived from Apple RoomPlan floor surfaces where available.
struct RoomLevelGeometrySeed: Equatable {
    let floorElevationMeters: Double
    let structuralCeilingHeightMeters: Double
    let centerX: Double
    let centerZ: Double
    let widthMeters: Double
    let depthMeters: Double
    let rotationDegrees: Double

    static func make(room: CapturedRoom) -> RoomLevelGeometrySeed {
        let floorElevations = room.floors.map { Double($0.transform.columns.3.y) }
        let wallBottoms = room.walls.map {
            Double($0.transform.columns.3.y - $0.dimensions.y / 2)
        }
        let floorElevation = median(floorElevations)
            ?? median(wallBottoms)
            ?? 0

        let wallTops = room.walls.map {
            Double($0.transform.columns.3.y + $0.dimensions.y / 2)
        }
        let structuralHeight = max((wallTops.max() ?? floorElevation + 2.7) - floorElevation, 0.20)

        if let floor = room.floors.max(by: { floorArea($0) < floorArea($1) }) {
            let axis = normalized(SIMD2<Float>(floor.transform.columns.0.x, floor.transform.columns.0.z))
            let rotation = atan2(Double(axis.y), Double(axis.x)) * 180 / .pi
            let footprint = floorFootprint(surface: floor)
            if !footprint.isEmpty {
                let bounds = orientedBounds(points: footprint, axis: axis)
                return RoomLevelGeometrySeed(
                    floorElevationMeters: floorElevation,
                    structuralCeilingHeightMeters: structuralHeight,
                    centerX: Double(bounds.center.x),
                    centerZ: Double(bounds.center.y),
                    widthMeters: max(Double(bounds.width), 0.20),
                    depthMeters: max(Double(bounds.depth), 0.20),
                    rotationDegrees: rotation
                )
            }
            return RoomLevelGeometrySeed(
                floorElevationMeters: floorElevation,
                structuralCeilingHeightMeters: structuralHeight,
                centerX: Double(floor.transform.columns.3.x),
                centerZ: Double(floor.transform.columns.3.z),
                widthMeters: max(Double(floor.dimensions.x), 0.20),
                depthMeters: max(Double(floor.dimensions.y), 0.20),
                rotationDegrees: rotation
            )
        }

        let wallPoints = room.walls.flatMap { wall -> [SIMD2<Float>] in
            let center = SIMD2<Float>(wall.transform.columns.3.x, wall.transform.columns.3.z)
            let tangent = normalized(SIMD2<Float>(wall.transform.columns.0.x, wall.transform.columns.0.z))
            let half = max(wall.dimensions.x, 0.05) / 2
            return [center - tangent * half, center + tangent * half]
        }
        if let first = wallPoints.first {
            var minX = first.x
            var maxX = first.x
            var minZ = first.y
            var maxZ = first.y
            for point in wallPoints.dropFirst() {
                minX = min(minX, point.x)
                maxX = max(maxX, point.x)
                minZ = min(minZ, point.y)
                maxZ = max(maxZ, point.y)
            }
            return RoomLevelGeometrySeed(
                floorElevationMeters: floorElevation,
                structuralCeilingHeightMeters: structuralHeight,
                centerX: Double((minX + maxX) / 2),
                centerZ: Double((minZ + maxZ) / 2),
                widthMeters: max(Double(maxX - minX), 0.20),
                depthMeters: max(Double(maxZ - minZ), 0.20),
                rotationDegrees: 0
            )
        }

        return RoomLevelGeometrySeed(
            floorElevationMeters: floorElevation,
            structuralCeilingHeightMeters: structuralHeight,
            centerX: 0,
            centerZ: 0,
            widthMeters: 1,
            depthMeters: 1,
            rotationDegrees: 0
        )
    }

    static func floorFootprint(surface: CapturedRoom.Surface) -> [SIMD2<Float>] {
        if !surface.polygonCorners.isEmpty {
            return surface.polygonCorners.map { corner in
                let world = surface.transform * SIMD4<Float>(corner.x, corner.y, corner.z, 1)
                return SIMD2<Float>(world.x, world.z)
            }
        }

        let center = SIMD2<Float>(surface.transform.columns.3.x, surface.transform.columns.3.z)
        let axisX = normalized(SIMD2<Float>(surface.transform.columns.0.x, surface.transform.columns.0.z))
        var axisZ = normalized(SIMD2<Float>(surface.transform.columns.1.x, surface.transform.columns.1.z))
        if simd_length(axisZ) < 0.001 || abs(simd_dot(axisX, axisZ)) > 0.98 {
            axisZ = SIMD2<Float>(-axisX.y, axisX.x)
        }
        let halfWidth = max(surface.dimensions.x, 0.05) / 2
        let halfDepth = max(surface.dimensions.y, 0.05) / 2
        return [
            center - axisX * halfWidth - axisZ * halfDepth,
            center + axisX * halfWidth - axisZ * halfDepth,
            center + axisX * halfWidth + axisZ * halfDepth,
            center - axisX * halfWidth + axisZ * halfDepth
        ]
    }

    private static func floorArea(_ surface: CapturedRoom.Surface) -> Float {
        max(surface.dimensions.x, 0.01) * max(surface.dimensions.y, 0.01)
    }

    private static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[middle - 1] + sorted[middle]) / 2
        }
        return sorted[middle]
    }

    private static func normalized(_ value: SIMD2<Float>) -> SIMD2<Float> {
        let length = simd_length(value)
        return length > 0.0001 ? value / length : SIMD2<Float>(1, 0)
    }

    private static func orientedBounds(
        points: [SIMD2<Float>],
        axis: SIMD2<Float>
    ) -> (center: SIMD2<Float>, width: Float, depth: Float) {
        let normal = SIMD2<Float>(-axis.y, axis.x)
        let projectedX = points.map { simd_dot($0, axis) }
        let projectedZ = points.map { simd_dot($0, normal) }
        let minX = projectedX.min() ?? 0
        let maxX = projectedX.max() ?? 1
        let minZ = projectedZ.min() ?? 0
        let maxZ = projectedZ.max() ?? 1
        let center = axis * ((minX + maxX) / 2) + normal * ((minZ + maxZ) / 2)
        return (center, maxX - minX, maxZ - minZ)
    }
}
