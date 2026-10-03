import Foundation
import simd

struct AreaScanKeyframe {
    let imageURL: URL
    let cameraTransform: simd_float4x4
    let intrinsics: simd_float3x3
    let imageWidth: Int
    let imageHeight: Int
    let timestamp: TimeInterval
}

struct AreaScanMeshChunk {
    let transform: simd_float4x4
    let vertices: [SIMD3<Float>]
    let normals: [SIMD3<Float>]
    let faces: [SIMD3<UInt32>]
}

struct AreaScanColoredMesh {
    let vertices: [SIMD3<Float>]
    let normals: [SIMD3<Float>]
    let colors: [SIMD3<UInt8>]
    let faces: [SIMD3<UInt32>]

    var vertexCount: Int { vertices.count }
    var faceCount: Int { faces.count }
}

struct AreaScanTexturedMesh {
    let vertices: [SIMD3<Float>]
    let normals: [SIMD3<Float>]
    let texcoords: [SIMD2<Float>]
    let colors: [SIMD3<UInt8>]
    let faces: [SIMD3<UInt32>]
    let faceTextureIndices: [Int]
    let textureURLs: [URL]

    var vertexCount: Int { vertices.count }
    var faceCount: Int { faces.count }
    var texturedFaceCount: Int { faceTextureIndices.filter { $0 >= 0 }.count }
}

struct AreaScanExportResult {
    let folderURL: URL
    let plyURL: URL?
    let objURL: URL?
    let mtlURL: URL?
    let textureFolderURL: URL?
    let usdzURL: URL?
    let manifestURL: URL
}

struct AreaScanManifest: Codable {
    struct Frame: Codable {
        let imageFile: String
        let timestamp: TimeInterval
        let imageWidth: Int
        let imageHeight: Int
        let cameraTransform: [Float]
        let intrinsics: [Float]
    }

    let schemaVersion: Int
    let createdAt: Date
    let appVersion: String
    let vertexCount: Int
    let faceCount: Int
    let keyframeCount: Int
    let textureFrameCount: Int
    let texturedFaceCount: Int
    let outputs: [String]
    let frames: [Frame]
}

extension simd_float4x4 {
    var flattenedColumnMajor: [Float] {
        [
            columns.0.x, columns.0.y, columns.0.z, columns.0.w,
            columns.1.x, columns.1.y, columns.1.z, columns.1.w,
            columns.2.x, columns.2.y, columns.2.z, columns.2.w,
            columns.3.x, columns.3.y, columns.3.z, columns.3.w
        ]
    }
}

extension simd_float3x3 {
    var flattenedColumnMajor: [Float] {
        [
            columns.0.x, columns.0.y, columns.0.z,
            columns.1.x, columns.1.y, columns.1.z,
            columns.2.x, columns.2.y, columns.2.z
        ]
    }
}
