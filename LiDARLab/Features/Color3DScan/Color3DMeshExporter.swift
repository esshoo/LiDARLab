import Foundation
import SceneKit
import UIKit
import simd

struct Color3DMeshExporter {
    struct PreparedImage {
        let pixels: [UInt8]
        let width: Int
        let height: Int
        let worldToCamera: simd_float4x4
        let intrinsics: simd_float3x3
        let cameraPosition: SIMD3<Float>
    }

    static func buildColoredMesh(
        chunks: [AreaScanMeshChunk],
        keyframes: [AreaScanKeyframe],
        progress: @escaping (Double) -> Void
    ) -> AreaScanColoredMesh {
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

        let prepared = keyframes.compactMap(prepareImage)
        var colors = Array(repeating: SIMD3<UInt8>(142, 142, 142), count: vertices.count)

        guard !prepared.isEmpty else {
            progress(1)
            return AreaScanColoredMesh(vertices: vertices, normals: normals, colors: colors, faces: faces)
        }

        let vertexTotal = max(vertices.count, 1)
        for index in vertices.indices {
            let vertex = vertices[index]
            var bestScore = Float.greatestFiniteMagnitude
            var bestColor: SIMD3<UInt8>?

            for image in prepared {
                let camera4 = image.worldToCamera * SIMD4<Float>(vertex.x, vertex.y, vertex.z, 1)
                let depth = -camera4.z
                guard depth > 0.08 && depth < 8.0 else { continue }

                let fx = image.intrinsics.columns.0.x
                let fy = image.intrinsics.columns.1.y
                let cx = image.intrinsics.columns.2.x
                let cy = image.intrinsics.columns.2.y

                let u = fx * (camera4.x / depth) + cx
                let v = fy * (-camera4.y / depth) + cy
                let x = Int(u.rounded())
                let y = Int(v.rounded())

                guard x >= 1, y >= 1, x < image.width - 1, y < image.height - 1 else { continue }

                let distance = simd_distance(vertex, image.cameraPosition)
                let offAxis = abs(camera4.x / depth) + abs(camera4.y / depth)
                let score = distance + offAxis * 0.35
                guard score < bestScore else { continue }

                let pixelIndex = (y * image.width + x) * 4
                guard pixelIndex + 2 < image.pixels.count else { continue }
                bestScore = score
                bestColor = SIMD3<UInt8>(
                    image.pixels[pixelIndex],
                    image.pixels[pixelIndex + 1],
                    image.pixels[pixelIndex + 2]
                )
            }

            if let bestColor {
                colors[index] = bestColor
            }

            if index % 1500 == 0 {
                progress(Double(index) / Double(vertexTotal))
            }
        }

        progress(1)
        return AreaScanColoredMesh(vertices: vertices, normals: normals, colors: colors, faces: faces)
    }

    static func export(
        mesh: AreaScanColoredMesh,
        keyframes: [AreaScanKeyframe],
        folderURL: URL,
        progress: @escaping (Double) -> Void
    ) throws -> AreaScanExportResult {
        let output = folderURL.appendingPathComponent("Model", isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

        let plyURL = output.appendingPathComponent("room-colored.ply")
        let objURL = output.appendingPathComponent("room-colored.obj")
        let usdzCandidate = output.appendingPathComponent("room-colored.usdz")
        let manifestURL = folderURL.appendingPathComponent("scan.json")

        progress(0.05)
        try writeBinaryPLY(mesh: mesh, to: plyURL)
        progress(0.40)
        try writeOBJ(mesh: mesh, to: objURL)
        progress(0.68)

        let usdzURL: URL?
        if writeUSDZ(mesh: mesh, to: usdzCandidate) {
            usdzURL = usdzCandidate
        } else {
            try? FileManager.default.removeItem(at: usdzCandidate)
            usdzURL = nil
        }
        progress(0.84)

        let coloredCount = mesh.colors.reduce(0) { partial, color in
            partial + (color == SIMD3<UInt8>(142, 142, 142) ? 0 : 1)
        }
        let outputNames = [plyURL.lastPathComponent, objURL.lastPathComponent] + (usdzURL.map { [$0.lastPathComponent] } ?? [])
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
            schemaVersion: 1,
            createdAt: Date(),
            appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown",
            vertexCount: mesh.vertexCount,
            faceCount: mesh.faceCount,
            keyframeCount: keyframes.count,
            coloredVertexCount: coloredCount,
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
            plyURL: plyURL,
            objURL: objURL,
            usdzURL: usdzURL,
            manifestURL: manifestURL
        )
    }

    static func makeScene(mesh: AreaScanColoredMesh) -> SCNScene {
        let scene = SCNScene()
        let geometry = makeGeometry(mesh: mesh)
        let node = SCNNode(geometry: geometry)
        node.name = "3ELiDAR-ColoredMesh"
        scene.rootNode.addChildNode(node)

        let (center, radius) = bounds(mesh.vertices)
        let camera = SCNCamera()
        camera.zNear = 0.01
        camera.zFar = max(100, Double(radius * 20))
        let cameraNode = SCNNode()
        cameraNode.camera = camera
        cameraNode.position = SCNVector3(center.x, center.y + radius * 0.35, center.z + max(radius * 2.6, 1.0))
        let target = SCNNode()
        target.position = SCNVector3(center.x, center.y, center.z)
        scene.rootNode.addChildNode(target)
        cameraNode.constraints = [SCNLookAtConstraint(target: target)]
        scene.rootNode.addChildNode(cameraNode)

        return scene
    }

    private static func prepareImage(_ keyframe: AreaScanKeyframe) -> PreparedImage? {
        guard let image = UIImage(contentsOfFile: keyframe.imageURL.path)?.cgImage else { return nil }
        let width = image.width
        let height = image.height
        guard width > 0, height > 0 else { return nil }

        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let didRender = pixels.withUnsafeMutableBytes { rawBuffer -> Bool in
            guard let context = CGContext(
                data: rawBuffer.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }

            // Draw into a top-left-origin pixel buffer so ARKit intrinsics can be sampled directly.
            context.translateBy(x: 0, y: CGFloat(height))
            context.scaleBy(x: 1, y: -1)
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard didRender else { return nil }

        let transform = keyframe.cameraTransform
        let cameraPosition = SIMD3<Float>(transform.columns.3.x, transform.columns.3.y, transform.columns.3.z)
        return PreparedImage(
            pixels: pixels,
            width: width,
            height: height,
            worldToCamera: transform.inverse,
            intrinsics: keyframe.intrinsics,
            cameraPosition: cameraPosition
        )
    }

    private static func writeBinaryPLY(mesh: AreaScanColoredMesh, to url: URL) throws {
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
            let v = mesh.vertices[index]
            let n = index < mesh.normals.count ? mesh.normals[index] : SIMD3<Float>(0, 1, 0)
            let c = index < mesh.colors.count ? mesh.colors[index] : SIMD3<UInt8>(142, 142, 142)
            data.appendFloat32LE(v.x)
            data.appendFloat32LE(v.y)
            data.appendFloat32LE(v.z)
            data.appendFloat32LE(n.x)
            data.appendFloat32LE(n.y)
            data.appendFloat32LE(n.z)
            data.append(c.x)
            data.append(c.y)
            data.append(c.z)
        }

        for face in mesh.faces {
            data.append(UInt8(3))
            data.appendInt32LE(Int32(bitPattern: face.x))
            data.appendInt32LE(Int32(bitPattern: face.y))
            data.appendInt32LE(Int32(bitPattern: face.z))
        }

        try data.write(to: url, options: .atomic)
    }

    private static func writeOBJ(mesh: AreaScanColoredMesh, to url: URL) throws {
        FileManager.default.createFile(atPath: url.path, contents: nil)
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }

        try handle.write(contentsOf: Data("# 3ELiDAR colored mesh\n# Vertex RGB values follow XYZ on each v line.\n".utf8))
        var buffer = ""
        buffer.reserveCapacity(1_000_000)

        func flush() throws {
            guard !buffer.isEmpty else { return }
            try handle.write(contentsOf: Data(buffer.utf8))
            buffer.removeAll(keepingCapacity: true)
        }

        for index in mesh.vertices.indices {
            let v = mesh.vertices[index]
            let c = mesh.colors[index]
            buffer += String(format: "v %.6f %.6f %.6f %.5f %.5f %.5f\n", v.x, v.y, v.z, Double(c.x) / 255, Double(c.y) / 255, Double(c.z) / 255)
            if buffer.utf8.count > 900_000 { try flush() }
        }
        for n in mesh.normals {
            buffer += String(format: "vn %.6f %.6f %.6f\n", n.x, n.y, n.z)
            if buffer.utf8.count > 900_000 { try flush() }
        }
        for f in mesh.faces {
            let a = f.x + 1
            let b = f.y + 1
            let c = f.z + 1
            buffer += "f \(a)//\(a) \(b)//\(b) \(c)//\(c)\n"
            if buffer.utf8.count > 900_000 { try flush() }
        }
        try flush()
    }

    private static func writeUSDZ(mesh: AreaScanColoredMesh, to url: URL) -> Bool {
        try? FileManager.default.removeItem(at: url)
        let scene = SCNScene()
        scene.rootNode.addChildNode(SCNNode(geometry: makeGeometry(mesh: mesh)))
        return scene.write(to: url, options: nil, delegate: nil, progressHandler: nil)
    }

    private static func makeGeometry(mesh: AreaScanColoredMesh) -> SCNGeometry {
        var positionFloats: [Float] = []
        positionFloats.reserveCapacity(mesh.vertices.count * 3)
        for v in mesh.vertices { positionFloats.append(contentsOf: [v.x, v.y, v.z]) }

        var normalFloats: [Float] = []
        normalFloats.reserveCapacity(mesh.normals.count * 3)
        for n in mesh.normals { normalFloats.append(contentsOf: [n.x, n.y, n.z]) }

        var colorFloats: [Float] = []
        colorFloats.reserveCapacity(mesh.colors.count * 4)
        for c in mesh.colors {
            colorFloats.append(Float(c.x) / 255)
            colorFloats.append(Float(c.y) / 255)
            colorFloats.append(Float(c.z) / 255)
            colorFloats.append(1)
        }

        var indices: [UInt32] = []
        indices.reserveCapacity(mesh.faces.count * 3)
        for f in mesh.faces { indices.append(contentsOf: [f.x, f.y, f.z]) }

        let positionData = positionFloats.withUnsafeBytes { Data($0) }
        let normalData = normalFloats.withUnsafeBytes { Data($0) }
        let colorData = colorFloats.withUnsafeBytes { Data($0) }
        let indexData = indices.withUnsafeBytes { Data($0) }

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
        let colorSource = SCNGeometrySource(
            data: colorData,
            semantic: .color,
            vectorCount: mesh.colors.count,
            usesFloatComponents: true,
            componentsPerVector: 4,
            bytesPerComponent: MemoryLayout<Float>.size,
            dataOffset: 0,
            dataStride: MemoryLayout<Float>.size * 4
        )
        let element = SCNGeometryElement(
            data: indexData,
            primitiveType: .triangles,
            primitiveCount: mesh.faces.count,
            bytesPerIndex: MemoryLayout<UInt32>.size
        )
        let geometry = SCNGeometry(sources: [vertexSource, normalSource, colorSource], elements: [element])
        let material = SCNMaterial()
        material.diffuse.contents = UIColor.white
        material.lightingModel = .constant
        material.isDoubleSided = true
        geometry.materials = [material]
        return geometry
    }

    private static func bounds(_ vertices: [SIMD3<Float>]) -> (SIMD3<Float>, Float) {
        guard let first = vertices.first else { return (.zero, 1) }
        var minV = first
        var maxV = first
        for v in vertices.dropFirst() {
            minV = simd_min(minV, v)
            maxV = simd_max(maxV, v)
        }
        let center = (minV + maxV) * 0.5
        let radius = max(simd_length(maxV - minV) * 0.5, 0.5)
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
