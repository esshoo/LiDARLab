import ARKit
import Combine
import CoreImage
import Foundation
import RealityKit
import UIKit
import simd

final class AreaScanViewModel: NSObject, ObservableObject, ARSessionDelegate {
    @Published private(set) var isScanning = false
    @Published private(set) var isExporting = false
    @Published private(set) var trackingState = "متوقف"
    @Published private(set) var meshAnchorCount = 0
    @Published private(set) var vertexCount = 0
    @Published private(set) var faceCount = 0
    @Published private(set) var capturedFrameCount = 0
    @Published private(set) var exportProgress: Double = 0
    @Published private(set) var statusMessage = "ابدأ المسح ثم تحرّك ببطء داخل الغرفة."
    @Published private(set) var completedMesh: AreaScanTexturedMesh?
    @Published private(set) var exportResult: AreaScanExportResult?
    @Published var errorMessage: String?

    private weak var arView: ARView?
    private let fileManager = FileManager.default
    private let ciContext = CIContext(options: [.cacheIntermediates: false])
    private let captureQueue = DispatchQueue(label: "com.essam.3E.LiDARLab.color3d.keyframes", qos: .utility)
    private let stateLock = NSLock()

    private var scanningFlag = false
    private var activeGeneration = UUID()
    private var sessionFolderURL: URL?
    private var imagesFolderURL: URL?
    private var keyframes: [AreaScanKeyframe] = []
    private var lastCapturedTransform: simd_float4x4?
    private var lastCaptureTimestamp: TimeInterval = -100
    private var lastStatisticsTimestamp: TimeInterval = 0

    private var runtimeOptions = Color3DScanSettings.areaOptions

    var isSupported: Bool {
        ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh)
    }

    func attach(to arView: ARView) {
        self.arView = arView
        arView.automaticallyConfigureSession = false
        arView.session.delegate = self
        runtimeOptions = Color3DScanSettings.areaOptions
        if runtimeOptions.showSceneMeshWhileScanning {
            arView.debugOptions.insert(.showSceneUnderstanding)
        } else {
            arView.debugOptions.remove(.showSceneUnderstanding)
        }
    }

    func startScan() {
        guard isSupported else {
            errorMessage = "Scene Mesh غير مدعوم على هذا الجهاز."
            return
        }
        guard let arView else {
            errorMessage = "عارض الواقع المعزز غير جاهز."
            return
        }

        runtimeOptions = Color3DScanSettings.areaOptions
        if runtimeOptions.showSceneMeshWhileScanning {
            arView.debugOptions.insert(.showSceneUnderstanding)
        } else {
            arView.debugOptions.remove(.showSceneUnderstanding)
        }

        do {
            let storage = LiDARLabStorage.shared
            try storage.ensureDirectories()
            let root = storage.capturesURL
                .appendingPathComponent("Color3D", isDirectory: true)
                .appendingPathComponent("Areas", isDirectory: true)
            try fileManager.createDirectory(at: root, withIntermediateDirectories: true)

            let folder = root.appendingPathComponent(
                storage.timestampedName(prefix: "AreaScan"),
                isDirectory: true
            )
            let images = folder.appendingPathComponent("Images", isDirectory: true)
            try fileManager.createDirectory(at: images, withIntermediateDirectories: true)

            stateLock.lock()
            scanningFlag = true
            activeGeneration = UUID()
            keyframes.removeAll(keepingCapacity: true)
            lastCapturedTransform = nil
            lastCaptureTimestamp = -100
            sessionFolderURL = folder
            imagesFolderURL = images
            let generation = activeGeneration
            stateLock.unlock()

            completedMesh = nil
            exportResult = nil
            exportProgress = 0
            capturedFrameCount = 0
            meshAnchorCount = 0
            vertexCount = 0
            faceCount = 0
            isExporting = false
            isScanning = true
            statusMessage = "المسح يعمل. امشِ ببطء ووجّه الكاميرا لكل الحوائط والأرضية والسقف والأثاث."

            let configuration = ARWorldTrackingConfiguration()
            configuration.worldAlignment = .gravity
            configuration.planeDetection = [.horizontal, .vertical]
            configuration.sceneReconstruction = ARWorldTrackingConfiguration.supportsSceneReconstruction(.meshWithClassification)
                ? .meshWithClassification
                : .mesh
            if ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) {
                configuration.frameSemantics.insert(.sceneDepth)
            }
            if runtimeOptions.useSmoothedDepth,
               ARWorldTrackingConfiguration.supportsFrameSemantics(.smoothedSceneDepth) {
                configuration.frameSemantics.insert(.smoothedSceneDepth)
            }

            // Keep this generation alive through the start call. It is checked by queued image work.
            _ = generation
            arView.session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
        } catch {
            setScanning(false)
            errorMessage = error.localizedDescription
        }
    }

    func stopAndBuildModel() {
        guard let arView else { return }

        stateLock.lock()
        let wasScanning = scanningFlag
        scanningFlag = false
        stateLock.unlock()
        guard wasScanning else { return }

        guard let frame = arView.session.currentFrame else {
            setScanning(false)
            errorMessage = "لا توجد بيانات AR كافية لإنهاء المسح."
            return
        }

        let meshAnchors = frame.anchors.compactMap { $0 as? ARMeshAnchor }
        guard !meshAnchors.isEmpty else {
            setScanning(false)
            errorMessage = "لم يتم التقاط أي Mesh. حرّك الهاتف داخل المكان لفترة أطول ثم حاول مرة أخرى."
            return
        }

        statusMessage = "نسخ هندسة LiDAR…"
        let chunks = meshAnchors.map(copyMeshChunk)
        arView.session.pause()
        setScanning(false)

        // Finish any JPEG already queued before freezing the keyframe list.
        captureQueue.sync {}

        stateLock.lock()
        let frames = keyframes
        let folder = sessionFolderURL
        stateLock.unlock()

        guard let folder else {
            errorMessage = "مجلد جلسة المسح غير متاح."
            return
        }

        isExporting = true
        exportProgress = 0
        statusMessage = "إسقاط ألوان الكاميرا على Mesh…"

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }

            let options = self.runtimeOptions
            let texturedMesh = Color3DMeshExporter.buildTexturedMesh(
                chunks: chunks,
                keyframes: frames,
                maximumTextureFrames: options.maximumTextureFrames,
                rejectUncertainTextures: options.rejectUncertainTextures,
                depthOcclusionToleranceMeters: options.depthOcclusionToleranceMeters,
                maximumTextureDistanceMeters: options.maximumTextureDistanceMeters
            ) { fraction in
                DispatchQueue.main.async {
                    self.exportProgress = fraction * 0.64
                    self.statusMessage = "بناء UV وربط صور الكاميرا… \(Int(fraction * 100))%"
                }
            }

            do {
                let result = try Color3DMeshExporter.export(
                    mesh: texturedMesh,
                    keyframes: frames,
                    folderURL: folder,
                    options: options
                ) { fraction in
                    DispatchQueue.main.async {
                        self.exportProgress = 0.64 + fraction * 0.36
                        self.statusMessage = "تصدير Mesh بخامات الصور… \(Int(fraction * 100))%"
                    }
                }

                DispatchQueue.main.async {
                    self.completedMesh = texturedMesh
                    self.exportResult = result
                    self.exportProgress = 1
                    self.isExporting = false
                    let coverage = texturedMesh.faceCount > 0
                        ? Int((Double(texturedMesh.texturedFaceCount) / Double(texturedMesh.faceCount)) * 100)
                        : 0
                    self.statusMessage = "اكتمل المسح بخامات RGB فعلية. تغطية الخامات: \(coverage)%"
                }
            } catch {
                DispatchQueue.main.async {
                    self.completedMesh = texturedMesh
                    self.isExporting = false
                    self.errorMessage = error.localizedDescription
                    self.statusMessage = "تم بناء Mesh المكسو بالصور ولكن فشل أحد ملفات التصدير."
                }
            }
        }
    }

    func cancelScan() {
        stateLock.lock()
        scanningFlag = false
        activeGeneration = UUID()
        stateLock.unlock()
        arView?.session.pause()
        setScanning(false)
        isExporting = false
        statusMessage = "تم إيقاف المسح."
    }

    func resetForNewScan() {
        cancelScan()
        completedMesh = nil
        exportResult = nil
        exportProgress = 0
        meshAnchorCount = 0
        vertexCount = 0
        faceCount = 0
        capturedFrameCount = 0
        trackingState = "متوقف"
        statusMessage = "ابدأ المسح ثم تحرّك ببطء داخل الغرفة."
        errorMessage = nil
    }

    func clearError() {
        errorMessage = nil
    }

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        stateLock.lock()
        let scanning = scanningFlag
        stateLock.unlock()
        guard scanning else { return }

        if frame.timestamp - lastStatisticsTimestamp >= 0.40 {
            lastStatisticsTimestamp = frame.timestamp
            let anchors = frame.anchors.compactMap { $0 as? ARMeshAnchor }
            let vertices = anchors.reduce(0) { $0 + $1.geometry.vertices.count }
            let faces = anchors.reduce(0) { $0 + $1.geometry.faces.count }
            DispatchQueue.main.async { [weak self] in
                self?.meshAnchorCount = anchors.count
                self?.vertexCount = vertices
                self?.faceCount = faces
            }
        }

        // Keep RGB/depth keyframes only while ARKit reports a stable camera pose.
        // Limited tracking is a major source of textures appearing on the wrong wall.
        if case .normal = frame.camera.trackingState {
            scheduleKeyframeIfNeeded(frame)
        }
    }

    func session(_ session: ARSession, cameraDidChangeTrackingState camera: ARCamera) {
        let text: String
        switch camera.trackingState {
        case .normal:
            text = "طبيعي"
        case .notAvailable:
            text = "غير متاح"
        case .limited(let reason):
            switch reason {
            case .initializing: text = "تهيئة"
            case .excessiveMotion: text = "حركة سريعة"
            case .insufficientFeatures: text = "تفاصيل قليلة"
            case .relocalizing: text = "إعادة تحديد الموقع"
            @unknown default: text = "محدود"
            }
        }
        DispatchQueue.main.async { [weak self] in self?.trackingState = text }
    }

    func session(_ session: ARSession, didFailWithError error: Error) {
        DispatchQueue.main.async { [weak self] in
            self?.setScanning(false)
            self?.errorMessage = error.localizedDescription
        }
    }

    private func scheduleKeyframeIfNeeded(_ frame: ARFrame) {
        let transform = frame.camera.transform

        stateLock.lock()
        guard scanningFlag,
              keyframes.count < runtimeOptions.maximumKeyframes,
              let imagesFolderURL else {
            stateLock.unlock()
            return
        }

        let elapsed = frame.timestamp - lastCaptureTimestamp
        guard elapsed >= runtimeOptions.minimumCaptureInterval else {
            stateLock.unlock()
            return
        }

        if let last = lastCapturedTransform {
            let p0 = SIMD3<Float>(last.columns.3.x, last.columns.3.y, last.columns.3.z)
            let p1 = SIMD3<Float>(transform.columns.3.x, transform.columns.3.y, transform.columns.3.z)
            let translation = simd_distance(p0, p1)

            let f0 = simd_normalize(SIMD3<Float>(last.columns.2.x, last.columns.2.y, last.columns.2.z))
            let f1 = simd_normalize(SIMD3<Float>(transform.columns.2.x, transform.columns.2.y, transform.columns.2.z))
            let dotValue = min(max(simd_dot(f0, f1), -1), 1)
            let angle = acos(dotValue)

            guard translation >= runtimeOptions.minimumTranslation || angle >= runtimeOptions.minimumRotationRadians else {
                stateLock.unlock()
                return
            }
        }

        lastCaptureTimestamp = frame.timestamp
        lastCapturedTransform = transform
        let generation = activeGeneration
        stateLock.unlock()

        captureQueue.async { [weak self, frame] in
            self?.saveKeyframe(
                frame: frame,
                folder: imagesFolderURL,
                generation: generation
            )
        }
    }

    private func saveKeyframe(
        frame: ARFrame,
        folder: URL,
        generation: UUID
    ) {
        let pixelBuffer = frame.capturedImage
        let originalWidth = CVPixelBufferGetWidth(pixelBuffer)
        let originalHeight = CVPixelBufferGetHeight(pixelBuffer)
        guard originalWidth > 0, originalHeight > 0 else { return }

        let targetMaxDimension = CGFloat(runtimeOptions.imageMaxDimension)
        let scale = min(1, targetMaxDimension / CGFloat(max(originalWidth, originalHeight)))
        let input = CIImage(cvPixelBuffer: pixelBuffer)
        let scaled = input.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        guard let cgImage = ciContext.createCGImage(scaled, from: scaled.extent.integral),
              let jpeg = UIImage(cgImage: cgImage).jpegData(compressionQuality: runtimeOptions.jpegQuality) else { return }

        stateLock.lock()
        guard generation == activeGeneration else {
            stateLock.unlock()
            return
        }
        // Recalculate the index under lock because multiple queued frames can finish close together.
        let index = keyframes.count + 1
        guard index <= runtimeOptions.maximumKeyframes else {
            stateLock.unlock()
            return
        }
        stateLock.unlock()

        let fileURL = folder.appendingPathComponent(String(format: "frame-%03d.jpg", index))
        do {
            try jpeg.write(to: fileURL, options: .atomic)
        } catch {
            return
        }

        var intrinsics = frame.camera.intrinsics
        let sx = Float(cgImage.width) / Float(originalWidth)
        let sy = Float(cgImage.height) / Float(originalHeight)
        intrinsics.columns.0.x *= sx
        intrinsics.columns.1.y *= sy
        intrinsics.columns.2.x *= sx
        intrinsics.columns.2.y *= sy

        let keyframe = AreaScanKeyframe(
            imageURL: fileURL,
            cameraTransform: frame.camera.transform,
            intrinsics: intrinsics,
            imageWidth: cgImage.width,
            imageHeight: cgImage.height,
            timestamp: frame.timestamp,
            depthMap: copyDepthMap(from: frame)
        )

        stateLock.lock()
        guard generation == activeGeneration else {
            stateLock.unlock()
            try? fileManager.removeItem(at: fileURL)
            return
        }
        keyframes.append(keyframe)
        let count = keyframes.count
        stateLock.unlock()

        DispatchQueue.main.async { [weak self] in
            self?.capturedFrameCount = count
        }
    }

    private func copyDepthMap(from frame: ARFrame) -> AreaScanDepthMap? {
        let depthData: ARDepthData?
        if runtimeOptions.useSmoothedDepth {
            depthData = frame.smoothedSceneDepth ?? frame.sceneDepth
        } else {
            depthData = frame.sceneDepth ?? frame.smoothedSceneDepth
        }
        guard let depthData else { return nil }

        let buffer = depthData.depthMap
        let width = CVPixelBufferGetWidth(buffer)
        let height = CVPixelBufferGetHeight(buffer)
        guard width > 0, height > 0 else { return nil }

        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { return nil }

        let sourceStride = CVPixelBufferGetBytesPerRow(buffer) / MemoryLayout<Float32>.size
        let source = base.assumingMemoryBound(to: Float32.self)
        var values = [Float](repeating: .nan, count: width * height)

        for y in 0..<height {
            let sourceRow = source.advanced(by: y * sourceStride)
            let destinationOffset = y * width
            for x in 0..<width {
                let value = sourceRow[x]
                values[destinationOffset + x] = value.isFinite && value > 0 ? value : .nan
            }
        }

        return AreaScanDepthMap(values: values, width: width, height: height)
    }

    private func copyMeshChunk(_ anchor: ARMeshAnchor) -> AreaScanMeshChunk {
        let geometry = anchor.geometry
        var vertices: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var faces: [SIMD3<UInt32>] = []
        vertices.reserveCapacity(geometry.vertices.count)
        normals.reserveCapacity(geometry.normals.count)
        faces.reserveCapacity(geometry.faces.count)

        for index in 0..<geometry.vertices.count {
            vertices.append(vector3(from: geometry.vertices, at: index))
        }
        for index in 0..<geometry.normals.count {
            normals.append(vector3(from: geometry.normals, at: index))
        }
        for faceIndex in 0..<geometry.faces.count {
            let indices = geometry.faces[faceIndex]
            guard indices.count >= 3 else { continue }
            faces.append(SIMD3<UInt32>(
                UInt32(bitPattern: indices[0]),
                UInt32(bitPattern: indices[1]),
                UInt32(bitPattern: indices[2])
            ))
        }

        return AreaScanMeshChunk(
            transform: anchor.transform,
            vertices: vertices,
            normals: normals,
            faces: faces
        )
    }

    private func vector3(from source: ARGeometrySource, at index: Int) -> SIMD3<Float> {
        let pointer = source.buffer.contents().advanced(by: source.offset + source.stride * index)
        let floats = pointer.assumingMemoryBound(to: Float.self)
        return SIMD3<Float>(floats[0], floats[1], floats[2])
    }

    private func setScanning(_ value: Bool) {
        stateLock.lock()
        scanningFlag = value
        stateLock.unlock()
        if Thread.isMainThread {
            isScanning = value
        } else {
            DispatchQueue.main.async { [weak self] in self?.isScanning = value }
        }
    }
}
