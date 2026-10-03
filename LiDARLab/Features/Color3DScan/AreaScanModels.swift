import Foundation
import simd

struct AreaScanDepthMap {
    let values: [Float]
    let width: Int
    let height: Int

    func sample(normalizedX: Float, normalizedY: Float) -> Float? {
        guard width > 0, height > 0,
              normalizedX.isFinite, normalizedY.isFinite,
              normalizedX >= 0, normalizedX <= 1,
              normalizedY >= 0, normalizedY <= 1 else { return nil }

        let centerX = min(max(Int((normalizedX * Float(width - 1)).rounded()), 0), width - 1)
        let centerY = min(max(Int((normalizedY * Float(height - 1)).rounded()), 0), height - 1)

        var samples: [Float] = []
        samples.reserveCapacity(9)
        for y in max(0, centerY - 1)...min(height - 1, centerY + 1) {
            for x in max(0, centerX - 1)...min(width - 1, centerX + 1) {
                let value = values[y * width + x]
                if value.isFinite, value > 0.05, value < 12 {
                    samples.append(value)
                }
            }
        }
        guard !samples.isEmpty else { return nil }
        samples.sort()
        return samples[samples.count / 2]
    }
}

struct AreaScanKeyframe {
    let imageURL: URL
    let cameraTransform: simd_float4x4
    let intrinsics: simd_float3x3
    let imageWidth: Int
    let imageHeight: Int
    let timestamp: TimeInterval
    let depthMap: AreaScanDepthMap?
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
