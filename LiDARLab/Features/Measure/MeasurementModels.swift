import CoreGraphics
import Foundation
import simd

struct MeasurementVector3: Codable, Hashable {
    let x: Float
    let y: Float
    let z: Float

    init(_ value: SIMD3<Float>) {
        x = value.x
        y = value.y
        z = value.z
    }

    var simdValue: SIMD3<Float> {
        SIMD3<Float>(x, y, z)
    }
}

struct MeasurementSegmentRecord: Codable, Hashable, Identifiable {
    let index: Int
    let startPointIndex: Int
    let endPointIndex: Int
    let directMeters: Double
    let horizontalMeters: Double
    let verticalMeters: Double

    var id: Int { index }
}

struct MeasurementDocument: Codable {
    let schemaVersion: Int
    let measurementId: UUID
    let name: String
    let createdAt: Date
    let updatedAt: Date
    let appVersion: String
    let isClosedPath: Bool
    let points: [MeasurementVector3]
    let segments: [MeasurementSegmentRecord]
    let totalDirectMeters: Double
    let totalHorizontalMeters: Double
    let totalVerticalMeters: Double
    let trackingStateAtSave: String
}

struct ProjectedMeasurementPoint: Equatable, Identifiable {
    let index: Int
    let screenPoint: CGPoint

    var id: Int { index }
}

struct ProjectedMeasurementSegment: Equatable, Identifiable {
    let index: Int
    let start: CGPoint
    let end: CGPoint
    let directMeters: Double
    let horizontalMeters: Double
    let verticalMeters: Double

    var id: Int { index }
    var midpoint: CGPoint {
        CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2)
    }
}

struct MeasurementProjection: Equatable {
    let points: [ProjectedMeasurementPoint]
    let segments: [ProjectedMeasurementSegment]
}
