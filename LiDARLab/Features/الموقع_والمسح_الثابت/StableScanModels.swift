import CoreGraphics
import Foundation
import simd

// The stable core intentionally supports only the priorities agreed for v0.5.0.
enum StableScanMode: String, CaseIterable, Identifiable, Codable, Sendable {
    case locationOnly
    case scan2D

    var id: String { rawValue }

    var title: String {
        switch self {
        case .locationOnly: "تحديد الموقع"
        case .scan2D: "مسح 2D"
        }
    }

    var subtitle: String {
        switch self {
        case .locationOnly: "Pose والمسار فقط بأعلى أولوية"
        case .scan2D: "Pose كاملة مع Depth مرتبطة بنفس Frame"
        }
    }

    var protocolName: String {
        switch self {
        case .locationOnly: "pose_only"
        case .scan2D: "scan2d"
        }
    }
}

enum StableSessionState: String, Codable, Sendable {
    case preparing
    case ready
    case recording
    case paused
    case finalizing
    case finished
    case processing
    case resultReady
    case failed

    var title: String {
        switch self {
        case .preparing: "تهيئة التتبع"
        case .ready: "جاهز"
        case .recording: "تسجيل"
        case .paused: "متوقف مؤقتًا"
        case .finalizing: "حفظ الجلسة"
        case .finished: "انتهت الجلسة"
        case .processing: "معالجة"
        case .resultReady: "النتيجة جاهزة"
        case .failed: "خطأ"
        }
    }
}

struct StableQuaternion: Codable, Sendable, Equatable {
    var x: Float
    var y: Float
    var z: Float
    var w: Float

    init(_ value: simd_quatf) {
        x = value.vector.x
        y = value.vector.y
        z = value.vector.z
        w = value.vector.w
    }

    var simdValue: simd_quatf {
        simd_quatf(ix: x, iy: y, iz: z, r: w)
    }
}

struct StablePoseSample: Sendable {
    let frameID: UInt64
    let timestampSeconds: TimeInterval
    let timestampNanoseconds: UInt64
    let px: Float
    let py: Float
    let pz: Float
    let quaternion: StableQuaternion
    let trackingState: UInt8
    let trackingReason: UInt8
    let worldMappingStatus: UInt8
    let thermalState: UInt8

    var position: SIMD3<Float> { SIMD3(px, py, pz) }
}

struct StablePathPoint: Codable, Hashable, Sendable {
    let x: Float
    let z: Float
    let timestampNanoseconds: UInt64
}

struct StablePathSegment: Codable, Identifiable, Sendable {
    let id: Int
    var points: [StablePathPoint]
}

struct StableBreakPoint: Codable, Identifiable, Sendable {
    let id: Int
    let x: Float
    let z: Float
    let reason: String
}

struct StableCoverageCell: Codable, Hashable, Identifiable, Sendable {
    let ix: Int
    let iz: Int

    var id: String { "\(ix):\(iz)" }
}


struct StableCameraCoverageSample: Hashable, Sendable {
    let u: Float
    let v: Float
    let confidence: UInt8
    let depthMeters: Float
}

struct StablePreviewSnapshot: Sendable {
    let pathSegments: [StablePathSegment]
    let breakPoints: [StableBreakPoint]
    let coverageCells: [StableCoverageCell]
    let currentPose: StablePoseSample?
    let trackingText: String
    let poseCount: UInt64
    let depthCount: UInt64
    let recordedPackets: UInt64
    let recordedBytes: UInt64
    let networkQueuedPackets: Int
    let networkQueuedBytes: UInt64
    let cameraCoverageSamples: [StableCameraCoverageSample]
    let cameraImageWidth: Int
    let cameraImageHeight: Int
    let ambientIntensity: CGFloat?
}

struct StableCaptureSettings: Sendable {
    var mode: StableScanMode
    var depthFPS: Int
    var samplingStride: Int
    var includeConfidence: Bool
    var previewFPS: Int
    var previewCellSize: Float
    var previewHorizontalRays: Int
    var previewMinimumConfidence: Int
    var previewMinimumDepth: Float
    var previewMaximumDepth: Float
}

struct StableProcessedCell: Codable, Hashable, Identifiable, Sendable {
    let ix: Int
    let iz: Int
    let hits: Int
    let frameCount: Int
    let minimumY: Float
    let maximumY: Float
    let averageConfidence: Float

    var id: String { "\(ix):\(iz)" }
}

struct StableProcessingSummary: Codable, Sendable {
    let mode: String
    let posePackets: Int
    let scanPackets: Int
    let matchedScans: Int
    let unmatchedScans: Int
    let acceptedPoints: Int
    let rawEvidenceCells: Int
    let structuralCells: Int
    let pathSegments: Int
    let trackingBreaks: Int
    let processingDurationMilliseconds: Double
    let axisConvention: String
}

struct StableProcessingResult: Sendable {
    let runDirectory: URL
    let summary: StableProcessingSummary
    let cells: [StableProcessedCell]
    let pathSegments: [StablePathSegment]
    let breakPoints: [StableBreakPoint]
}
