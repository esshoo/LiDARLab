import Foundation
import SceneKit
import UIKit
import simd

struct Color3DMeshExporter {
    private struct TextureFrame {
        let keyframe: AreaScanKeyframe
        let worldToCamera: simd_float4x4
        let cameraPosition: SIMD3<Float>
        let sampler: ColorSampler?
    }

    private struct ColorSampler {
        let pixels: [UInt8]
        let width: Int
        let height: Int
        let sourceWidth: Int
        let sourceHeight: Int

        func sample(x: Float, y: Float) -> SIMD3<UInt8>? {
            guard sourceWidth > 0, sourceHeight > 0 else { return nil }
            let sx = Int((x / Float(sourceWidth)) * Float(width))
            let sy = Int((y / Float(sourceHeight)) * Float(height))
            guard sx >= 0, sy >= 0, sx < width, sy < height else { return nil }
            let index = (sy * width + sx) * 4
            guard index + 2 < pixels.count else { return nil }
            return SIMD3<UInt8>(pixels[index], pixels[index + 1], pixels[index + 2])
        }
    }

    private struct FlattenedMesh {
        let vertices: [SIMD3<Float>]
        let normals: [SIMD3<Float>]
        let faces: [SIMD3<UInt32>]
    }

    static func buildTexturedMesh(
        chunks: [AreaScanMeshChunk],
        keyframes: [AreaScanKeyframe],
        maximumTextureFrames: Int,
        rejectUncertainTextures: Bool,
        depthOcclusionToleranceMeters: Float,
        maximumTextureDistanceMeters: Float,
        progress: @escaping (Double) -> Void
    ) -> AreaScanTexturedMesh {
        let flat = flatten(chunks: chunks)
        let selectedFrames = evenlySample(keyframes, limit: max(1, maximumTextureFrames))
        let textureFrames = selectedFrames.map(prepareTextureFrame)

        var vertices: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var texcoords: [SIMD2<Float>] = []
        var colors: [SIMD3<UInt8>] = []
        var faces: [SIMD3<UInt32>] = []
        var faceTextureIndices: [Int] = []

        vertices.reserveCapacity(flat.faces.count * 3)
        normals.reserveCapacity(flat.faces.count * 3)
        texcoords.reserveCapacity(flat.faces.count * 3)
        colors.reserveCapacity(flat.faces.count * 3)
        faces.reserveCapacity(flat.faces.count)
        faceTextureIndices.reserveCapacity(flat.faces.count)

        let totalFaces = max(flat.faces.count, 1)
        for (faceIndex, face) in flat.faces.enumerated() {
            let ids = [Int(face.x), Int(face.y), Int(face.z)]
            guard ids.allSatisfy({ $0 >= 0 && $0 < flat.vertices.count }) else { continue }
            let points = ids.map { flat.vertices[$0] }

            // Reject only clearly implausible transient triangles caused by unstable tracking.
            let edge01 = simd_distance(points[0], points[1])
            let edge12 = simd_distance(points[1], points[2])
            let edge20 = simd_distance(points[2], points[0])
            let maximumEdge = max(edge01, max(edge12, edge20))
            let areaVector = simd_cross(points[1] - points[0], points[2] - points[0])
            guard maximumEdge < 0.75, simd_length(areaVector) > 0.00001 else { continue }

            let sourceNormals = ids.map { $0 < flat.normals.count ? flat.normals[$0] : SIMD3<Float>(0, 1, 0) }

            let selection = bestTextureFrame(
                for: points,
                in: textureFrames,
                rejectUncertainTextures: rejectUncertainTextures,
                depthOcclusionToleranceMeters: depthOcclusionToleranceMeters,
                maximumTextureDistanceMeters: maximumTextureDistanceMeters
            )
            let base = UInt32(vertices.count)

            for localIndex in 0..<3 {
                vertices.append(points[localIndex])
                normals.append(sourceNormals[localIndex])

                if let selection,
                   let projection = project(points[localIndex], into: selection.frame) {
                    let u = projection.x / Float(selection.frame.keyframe.imageWidth)
                    let v = 1.0 - (projection.y / Float(selection.frame.keyframe.imageHeight))
                    texcoords.append(SIMD2<Float>(min(max(u, 0), 1), min(max(v, 0), 1)))
                    colors.append(selection.frame.sampler?.sample(x: projection.x, y: projection.y) ?? SIMD3<UInt8>(180, 180, 180))
                } else {
                    texcoords.append(.zero)
                    colors.append(SIMD3<UInt8>(142, 142, 142))
                }
            }

            faces.append(SIMD3<UInt32>(base, base + 1, base + 2))
            faceTextureIndices.append(selection?.index ?? -1)

            if faceIndex % 500 == 0 {
                progress(Double(faceIndex) / Double(totalFaces))
            }
        }

        progress(1)
        return AreaScanTexturedMesh(
            vertices: vertices,
            normals: normals,
            texcoords: texcoords,
            colors: colors,
            faces: faces,
            faceTextureIndices: faceTextureIndices,
            textureURLs: selectedFrames.map(\.imageURL)
        )
    }

    static func export(
        mesh: AreaScanTexturedMesh,
        keyframes: [AreaScanKeyframe],
        folderURL: URL,
        options: AreaScanRuntimeOptions,
        progress: @escaping (Double) -> Void
    ) throws -> AreaScanExportResult {
        let fileManager = FileManager.default
        let output = folderURL.appendingPathComponent("Model", isDirectory: true)
        try fileManager.createDirectory(at: output, withIntermediateDirectories: true)

        let plyURL = output.appendingPathComponent("room-colored.ply")
        let objURL = output.appendingPathComponent("room-textured.obj")
        let mtlURL = output.appendingPathComponent("room-textured.mtl")
        let texturesURL = output.appendingPathComponent("Textures", isDirectory: true)
        let usdzCandidate = output.appendingPathComponent("room-textured.usdz")
        let manifestURL = folderURL.appendingPathComponent("scan.json")

        var exportedPLY: URL?
        var exportedOBJ: URL?
        var exportedMTL: URL?
        var exportedTextures: URL?
        var exportedUSDZ: URL?
        var outputNames: [String] = []

        if options.exportPLY {
            progress(0.05)
            try writeBinaryPLY(mesh: mesh, to: plyURL)
            exportedPLY = plyURL
            outputNames.append("Model/\(plyURL.lastPathComponent)")
        }

        if options.exportOBJ {
            progress(0.22)
            try? fileManager.removeItem(at: texturesURL)
            try fileManager.createDirectory(at: texturesURL, withIntermediateDirectories: true)
            let textureNames = try copyTextures(mesh.textureURLs, to: texturesURL)
            try writeMTL(textureNames: textureNames, to: mtlURL)
            try writeOBJ(mesh: mesh, textureNames: textureNames, mtlName: mtlURL.lastPathComponent, to: objURL)
            exportedOBJ = objURL
            exportedMTL = mtlURL
            exportedTextures = texturesURL
            outputNames.append("Model/\(objURL.lastPathComponent)")
            outputNames.append("Model/\(mtlURL.lastPathComponent)")
            outputNames.append("Model/Textures/")
        }

        if options.exportUSDZ {
            progress(0.62)
            try? fileManager.removeItem(at: usdzCandidate)
            if writeUSDZ(mesh: mesh, to: usdzCandidate) {
                exportedUSDZ = usdzCandidate
                outputNames.append("Model/\(usdzCandidate.lastPathComponent)")
            }
        }

        progress(0.82)
        let frames = keyframes.map {
            AreaScanManifest.Frame(
                imageFile: "Images/\($0.imageURL.lastPathComponent)",
                timestamp: $0.timestamp,
                imageWidth: $0.imageWidth,
                imageHeight: $0.imageHeight,
                cameraTransform: $0.cameraTransform.flattenedColumnMajor,
                intrinsics: $0.intrinsics.flattenedColumnMajor
            )
        }
        let manifest = AreaScanManifest(
            schemaVersion: 2,
            createdAt: Date(),
            appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown",
            vertexCount: mesh.vertexCount,
            faceCount: mesh.faceCount,
            keyframeCount: keyframes.count,
            textureFrameCount: mesh.textureURLs.count,
            texturedFaceCount: mesh.texturedFaceCount,
            outputs: outputNames,
            frames: frames
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(manifest).write(to: manifestURL, options: .atomic)
        progress(1)

        return AreaScanExportResult(
            folderURL: folderURL,
            plyURL: exportedPLY,
            objURL: exportedOBJ,
            mtlURL: exportedMTL,
            textureFolderURL: exportedTextures,
            usdzURL: exportedUSDZ,
            manifestURL: manifestURL
        )
    }

    static func makeScene(mesh: AreaScanTexturedMesh) -> SCNScene {
        let scene = SCNScene()
        let geometry = makeGeometry(mesh: mesh)
        let node = SCNNode(geometry: geometry)
        node.name = "3ELiDAR-TexturedMesh"
        scene.rootNode.addChildNode(node)

        let (center, radius) = bounds(mesh.vertices)
        let camera = SCNCamera()
        camera.zNear = 0.005
        camera.zFar = max(100, Double(radius * 30))
        camera.fieldOfView = 65
        let cameraNode = SCNNode()
        cameraNode.name = "PreviewCamera"
        cameraNode.camera = camera
        cameraNode.position = SCNVector3(center.x, center.y + radius * 0.15, center.z + max(radius * 2.2, 0.8))
        let target = SCNNode()
        target.name = "PreviewTarget"
        target.position = SCNVector3(center.x, center.y, center.z)
        scene.rootNode.addChildNode(target)
        cameraNode.constraints = [SCNLookAtConstraint(target: target)]
        scene.rootNode.addChildNode(cameraNode)
        return scene
    }

    private static func flatten(chunks: [AreaScanMeshChunk]) -> FlattenedMesh {
        var vertices: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var faces: [SIMD3<UInt32>] = []

        let totalVertices = chunks.reduce(0) { $0 + $1.vertices.count }
        vertices.reserveCapacity(totalVertices)
        normals.reserveCapacity(totalVertices)

        for chunk in chunks {
            let base = UInt32(vertices.count)
            let normalTransform = simd_float3x3(
                SIMD3<Float>(chunk.transform.columns.0.x, chunk.transform.columns.0.y, chunk.transform.columns.0.z),
                SIMD3<Float>(chunk.transform.columns.1.x, chunk.transform.columns.1.y, chunk.transform.columns.1.z),
                SIMD3<Float>(chunk.transform.columns.2.x, chunk.transform.columns.2.y, chunk.transform.columns.2.z)
            )

            for index in chunk.vertices.indices {
                let local = chunk.vertices[index]
                let world4 = chunk.transform * SIMD4<Float>(local.x, local.y, local.z, 1)
                vertices.append(SIMD3<Float>(world4.x, world4.y, world4.z))

                let localNormal = index < chunk.normals.count ? chunk.normals[index] : SIMD3<Float>(0, 1, 0)
                let transformed = normalTransform * localNormal
                let length = simd_length(transformed)
                normals.append(length > 0.0001 ? transformed / length : SIMD3<Float>(0, 1, 0))
            }

            for face in chunk.faces {
                faces.append(SIMD3<UInt32>(base + face.x, base + face.y, base + face.z))
            }
        }

        return FlattenedMesh(vertices: vertices, normals: normals, faces: faces)
    }

    private static func prepareTextureFrame(_ keyframe: AreaScanKeyframe) -> TextureFrame {
        let transform = keyframe.cameraTransform
        let cameraPosition = SIMD3<Float>(transform.columns.3.x, transform.columns.3.y, transform.columns.3.z)
        return TextureFrame(
            keyframe: keyframe,
            worldToCamera: transform.inverse,
            cameraPosition: cameraPosition,
            sampler: makeColorSampler(for: keyframe)
        )
    }

    private static func bestTextureFrame(
        for points: [SIMD3<Float>],
        in frames: [TextureFrame],
        rejectUncertainTextures: Bool,
        depthOcclusionToleranceMeters: Float,
        maximumTextureDistanceMeters: Float
    ) -> (index: Int, frame: TextureFrame)? {
        guard points.count == 3, !frames.isEmpty else { return nil }
        let centroid = (points[0] + points[1] + points[2]) / 3
        let faceNormalRaw = simd_cross(points[1] - points[0], points[2] - points[0])
        let normalLength = simd_length(faceNormalRaw)
        let faceNormal = normalLength > 0.0001 ? faceNormalRaw / normalLength : SIMD3<Float>(0, 1, 0)

        var bestIndex: Int?
        var bestScore = Float.greatestFiniteMagnitude

        for (index, frame) in frames.enumerated() {
            let projected = points.compactMap { project($0, into: frame) }
            guard projected.count == 3 else { continue }

            let viewVector = frame.cameraPosition - centroid
            let distance = simd_length(viewVector)
            guard distance > 0.05, distance < maximumTextureDistanceMeters else { continue }
            let viewDirection = viewVector / max(distance, 0.0001)
            let frontal = abs(simd_dot(faceNormal, viewDirection))
            guard frontal > 0.22 else { continue }

            let cameraCentroid = frame.worldToCamera * SIMD4<Float>(centroid.x, centroid.y, centroid.z, 1)
            let expectedCentroidDepth = -cameraCentroid.z
            guard expectedCentroidDepth > 0.06 else { continue }

            var depthPenalty: Float = 0
            if rejectUncertainTextures {
                guard let depthMap = frame.keyframe.depthMap,
                      let centroidProjection = project(centroid, into: frame) else { continue }

                let normalizedX = centroidProjection.x / Float(frame.keyframe.imageWidth)
                let normalizedY = centroidProjection.y / Float(frame.keyframe.imageHeight)
                guard let measuredCentroidDepth = depthMap.sample(
                    normalizedX: normalizedX,
                    normalizedY: normalizedY
                ) else { continue }

                let centroidTolerance = max(
                    depthOcclusionToleranceMeters,
                    expectedCentroidDepth * 0.05
                )
                let centroidError = abs(measuredCentroidDepth - expectedCentroidDepth)
                guard centroidError <= centroidTolerance else { continue }

                var validVertexDepthSamples = 0
                var matchingVertexDepthSamples = 0
                var accumulatedVertexError: Float = 0

                for localIndex in 0..<3 {
                    let cameraPoint = frame.worldToCamera * SIMD4<Float>(
                        points[localIndex].x,
                        points[localIndex].y,
                        points[localIndex].z,
                        1
                    )
                    let expectedDepth = -cameraPoint.z
                    guard expectedDepth > 0.06 else { continue }

                    let projection = projected[localIndex]
                    let nx = projection.x / Float(frame.keyframe.imageWidth)
                    let ny = projection.y / Float(frame.keyframe.imageHeight)
                    guard let measuredDepth = depthMap.sample(normalizedX: nx, normalizedY: ny) else { continue }

                    validVertexDepthSamples += 1
                    let tolerance = max(depthOcclusionToleranceMeters, expectedDepth * 0.06)
                    let error = abs(measuredDepth - expectedDepth)
                    accumulatedVertexError += error
                    if error <= tolerance { matchingVertexDepthSamples += 1 }
                }

                if validVertexDepthSamples >= 2 {
                    guard matchingVertexDepthSamples >= 2 else { continue }
                    depthPenalty = accumulatedVertexError / Float(validVertexDepthSamples)
                } else {
                    depthPenalty = centroidError
                }
            }

            let depth = max(expectedCentroidDepth, 0.001)
            let offAxis = abs(cameraCentroid.x / depth) + abs(cameraCentroid.y / depth)
            let score = distance
                + offAxis * 0.55
                + (1 - frontal) * 0.95
                + depthPenalty * 2.0

            if score < bestScore {
                bestScore = score
                bestIndex = index
            }
        }

        guard let bestIndex else { return nil }
        return (bestIndex, frames[bestIndex])
    }

    private static func project(_ point: SIMD3<Float>, into frame: TextureFrame) -> SIMD2<Float>? {
        let camera4 = frame.worldToCamera * SIMD4<Float>(point.x, point.y, point.z, 1)
        let depth = -camera4.z
        guard depth > 0.06 && depth < 10 else { return nil }

        let intrinsics = frame.keyframe.intrinsics
        let fx = intrinsics.columns.0.x
        let fy = intrinsics.columns.1.y
        let cx = intrinsics.columns.2.x
        let cy = intrinsics.columns.2.y
        let u = fx * (camera4.x / depth) + cx
        let v = fy * (-camera4.y / depth) + cy

        let margin: Float = 2
        guard u >= margin,
              v >= margin,
              u < Float(frame.keyframe.imageWidth) - margin,
              v < Float(frame.keyframe.imageHeight) - margin else { return nil }
        return SIMD2<Float>(u, v)
    }

    private static func makeColorSampler(for keyframe: AreaScanKeyframe) -> ColorSampler? {
        guard let source = UIImage(contentsOfFile: keyframe.imageURL.path)?.cgImage else { return nil }
        let maxDimension = 512
        let scale = min(1.0, Double(maxDimension) / Double(max(source.width, source.height)))
        let width = max(1, Int(Double(source.width) * scale))
        let height = max(1, Int(Double(source.height) * scale))
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let ok = pixels.withUnsafeMutableBytes { raw -> Bool in
            guard let context = CGContext(
                data: raw.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.translateBy(x: 0, y: CGFloat(height))
            context.scaleBy(x: 1, y: -1)
            context.interpolationQuality = .medium
            context.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard ok else { return nil }
        return ColorSampler(
            pixels: pixels,
            width: width,
            height: height,
            sourceWidth: keyframe.imageWidth,
            sourceHeight: keyframe.imageHeight
        )
    }

    private static func evenlySample<T>(_ values: [T], limit: Int) -> [T] {
        guard values.count > limit, limit > 1 else { return values }
        let last = values.count - 1
        return (0..<limit).map { position in
            let fraction = Double(position) / Double(limit - 1)
            let index = Int((fraction * Double(last)).rounded())
            return values[min(max(index, 0), last)]
        }
    }

    private static func copyTextures(_ sourceURLs: [URL], to folder: URL) throws -> [String] {
        var names: [String] = []
        for (index, source) in sourceURLs.enumerated() {
            let name = String(format: "texture-%02d.jpg", index + 1)
            let destination = folder.appendingPathComponent(name)
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.copyItem(at: source, to: destination)
            names.append(name)
        }
        return names
    }

    private static func writeMTL(textureNames: [String], to url: URL) throws {
        var text = "# 3ELiDAR textured room materials\n"
        for (index, textureName) in textureNames.enumerated() {
            text += "newmtl texture_\(index)\n"
            text += "Ka 1.000 1.000 1.000\nKd 1.000 1.000 1.000\nKs 0.000 0.000 0.000\n"
            text += "map_Kd Textures/\(textureName)\n\n"
        }
        text += "newmtl fallback\nKa 0.55 0.55 0.55\nKd 0.55 0.55 0.55\nKs 0.0 0.0 0.0\n"
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    private static func writeOBJ(
        mesh: AreaScanTexturedMesh,
        textureNames: [String],
        mtlName: String,
        to url: URL
    ) throws {
        FileManager.default.createFile(atPath: url.path, contents: nil)
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }

        try handle.write(contentsOf: Data("# 3ELiDAR textured mesh\nmtllib \(mtlName)\n".utf8))
        var buffer = ""
        buffer.reserveCapacity(1_000_000)

        func flush() throws {
            guard !buffer.isEmpty else { return }
            try handle.write(contentsOf: Data(buffer.utf8))
            buffer.removeAll(keepingCapacity: true)
        }

        for vertex in mesh.vertices {
            buffer += String(format: "v %.6f %.6f %.6f\n", vertex.x, vertex.y, vertex.z)
            if buffer.utf8.count > 900_000 { try flush() }
        }
        for uv in mesh.texcoords {
            buffer += String(format: "vt %.6f %.6f\n", uv.x, uv.y)
            if buffer.utf8.count > 900_000 { try flush() }
        }
        for normal in mesh.normals {
            buffer += String(format: "vn %.6f %.6f %.6f\n", normal.x, normal.y, normal.z)
            if buffer.utf8.count > 900_000 { try flush() }
        }
        try flush()

        let materialIndices = Set(mesh.faceTextureIndices).sorted()
        for materialIndex in materialIndices {
            let materialName = materialIndex >= 0 && materialIndex < textureNames.count ? "texture_\(materialIndex)" : "fallback"
            buffer += "usemtl \(materialName)\n"
            for faceIndex in mesh.faces.indices where mesh.faceTextureIndices[faceIndex] == materialIndex {
                let face = mesh.faces[faceIndex]
                let a = face.x + 1
                let b = face.y + 1
                let c = face.z + 1
                buffer += "f \(a)/\(a)/\(a) \(b)/\(b)/\(b) \(c)/\(c)/\(c)\n"
                if buffer.utf8.count > 900_000 { try flush() }
            }
            try flush()
        }
    }

    private static func writeBinaryPLY(mesh: AreaScanTexturedMesh, to url: URL) throws {
        var data = Data()
        let header = """
        ply
        format binary_little_endian 1.0
        comment Generated by 3ELiDAR Color 3D Scan
        element vertex \(mesh.vertices.count)
        property float x
        property float y
        property float z
        property float nx
        property float ny
        property float nz
        property uchar red
        property uchar green
        property uchar blue
        element face \(mesh.faces.count)
        property list uchar int vertex_indices
        end_header
        """ + "\n"
        data.append(header.data(using: .utf8)!)

        for index in mesh.vertices.indices {
            let vertex = mesh.vertices[index]
            let normal = index < mesh.normals.count ? mesh.normals[index] : SIMD3<Float>(0, 1, 0)
            let color = index < mesh.colors.count ? mesh.colors[index] : SIMD3<UInt8>(142, 142, 142)
            data.appendFloat32LE(vertex.x)
            data.appendFloat32LE(vertex.y)
            data.appendFloat32LE(vertex.z)
            data.appendFloat32LE(normal.x)
            data.appendFloat32LE(normal.y)
            data.appendFloat32LE(normal.z)
            data.append(color.x)
            data.append(color.y)
            data.append(color.z)
        }
        for face in mesh.faces {
            data.append(UInt8(3))
            data.appendInt32LE(Int32(bitPattern: face.x))
            data.appendInt32LE(Int32(bitPattern: face.y))
            data.appendInt32LE(Int32(bitPattern: face.z))
        }
        try data.write(to: url, options: .atomic)
    }

    private static func writeUSDZ(mesh: AreaScanTexturedMesh, to url: URL) -> Bool {
        let scene = SCNScene()
        scene.rootNode.addChildNode(SCNNode(geometry: makeGeometry(mesh: mesh)))
        return scene.write(to: url, options: nil, delegate: nil, progressHandler: nil)
    }

    private static func makeGeometry(mesh: AreaScanTexturedMesh) -> SCNGeometry {
        var positionFloats: [Float] = []
        positionFloats.reserveCapacity(mesh.vertices.count * 3)
        for vertex in mesh.vertices { positionFloats.append(contentsOf: [vertex.x, vertex.y, vertex.z]) }

        var normalFloats: [Float] = []
        normalFloats.reserveCapacity(mesh.normals.count * 3)
        for normal in mesh.normals { normalFloats.append(contentsOf: [normal.x, normal.y, normal.z]) }

        var uvFloats: [Float] = []
        uvFloats.reserveCapacity(mesh.texcoords.count * 2)
        for uv in mesh.texcoords { uvFloats.append(contentsOf: [uv.x, uv.y]) }

        let positionData = positionFloats.withUnsafeBytes { Data($0) }
        let normalData = normalFloats.withUnsafeBytes { Data($0) }
        let uvData = uvFloats.withUnsafeBytes { Data($0) }

        let vertexSource = SCNGeometrySource(
            data: positionData,
            semantic: .vertex,
            vectorCount: mesh.vertices.count,
            usesFloatComponents: true,
            componentsPerVector: 3,
            bytesPerComponent: MemoryLayout<Float>.size,
            dataOffset: 0,
            dataStride: MemoryLayout<Float>.size * 3
        )
        let normalSource = SCNGeometrySource(
            data: normalData,
            semantic: .normal,
            vectorCount: mesh.normals.count,
            usesFloatComponents: true,
            componentsPerVector: 3,
            bytesPerComponent: MemoryLayout<Float>.size,
            dataOffset: 0,
            dataStride: MemoryLayout<Float>.size * 3
        )
        let uvSource = SCNGeometrySource(
            data: uvData,
            semantic: .texcoord,
            vectorCount: mesh.texcoords.count,
            usesFloatComponents: true,
            componentsPerVector: 2,
            bytesPerComponent: MemoryLayout<Float>.size,
            dataOffset: 0,
            dataStride: MemoryLayout<Float>.size * 2
        )

        let materialIndices = Set(mesh.faceTextureIndices).sorted()
        var elements: [SCNGeometryElement] = []
        var materials: [SCNMaterial] = []

        for materialIndex in materialIndices {
            var indices: [UInt32] = []
            for faceIndex in mesh.faces.indices where mesh.faceTextureIndices[faceIndex] == materialIndex {
                let face = mesh.faces[faceIndex]
                indices.append(contentsOf: [face.x, face.y, face.z])
            }
            guard !indices.isEmpty else { continue }
            let indexData = indices.withUnsafeBytes { Data($0) }
            let element = SCNGeometryElement(
                data: indexData,
                primitiveType: .triangles,
                primitiveCount: indices.count / 3,
                bytesPerIndex: MemoryLayout<UInt32>.size
            )
            elements.append(element)

            let material = SCNMaterial()
            material.lightingModel = .constant
            material.isDoubleSided = true
            material.diffuse.wrapS = .clamp
            material.diffuse.wrapT = .clamp
            if materialIndex >= 0,
               materialIndex < mesh.textureURLs.count,
               let image = UIImage(contentsOfFile: mesh.textureURLs[materialIndex].path) {
                material.diffuse.contents = image
            } else {
                material.diffuse.contents = UIColor(white: 0.55, alpha: 1)
            }
            materials.append(material)
        }

        let geometry = SCNGeometry(sources: [vertexSource, normalSource, uvSource], elements: elements)
        geometry.materials = materials
        return geometry
    }

    private static func bounds(_ vertices: [SIMD3<Float>]) -> (SIMD3<Float>, Float) {
        guard let first = vertices.first else { return (.zero, 1) }
        var minValue = first
        var maxValue = first
        for vertex in vertices.dropFirst() {
            minValue = simd_min(minValue, vertex)
            maxValue = simd_max(maxValue, vertex)
        }
        let center = (minValue + maxValue) * 0.5
        let radius = max(simd_length(maxValue - minValue) * 0.5, 0.5)
        return (center, radius)
    }
}

private extension Data {
    mutating func appendFloat32LE(_ value: Float) {
        var bits = value.bitPattern.littleEndian
        Swift.withUnsafeBytes(of: &bits) { append(contentsOf: $0) }
    }

    mutating func appendInt32LE(_ value: Int32) {
        var bits = UInt32(bitPattern: value).littleEndian
        Swift.withUnsafeBytes(of: &bits) { append(contentsOf: $0) }
    }
}
