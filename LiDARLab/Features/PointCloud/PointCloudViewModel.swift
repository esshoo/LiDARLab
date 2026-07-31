import ARKit
import Combine
import SceneKit
import UIKit
import simd

final class PointCloudViewModel: NSObject, ObservableObject, ARSessionDelegate {
    @Published private(set) var pointCount = 0
    @Published private(set) var processedFrameCount = 0
    @Published private(set) var processingRate: Double = 0
    @Published private(set) var trackingState = "بدء التتبع"
    @Published private(set) var errorMessage: String?

    private struct PointSample {
        let position: SIMD3<Float>
        let depth: Float
        let confidence: UInt8
    }

    private weak var sceneView: ARSCNView?
    private let cloudNode = SCNNode()
    private let processingQueue = DispatchQueue(label: "com.esshoo.LiDARLab.point-cloud", qos: .userInitiated)
    private let settingsLock = NSLock()

    private var samples: [PointSample] = []
    private var isProcessing = false
    private var lastProcessedTimestamp: TimeInterval = 0
    private var rateWindowStart: TimeInterval = 0
    private var framesInRateWindow = 0

    private var accumulatesPoints = true
    private var highConfidenceOnly = false
    private var colorMode = "depth"
    private var samplingStep = 6
    private var pointSize: CGFloat = 5
    private let maximumPointCount = 80_000

    func attach(to sceneView: ARSCNView) {
        self.sceneView = sceneView
        sceneView.session.delegate = self
        sceneView.scene.rootNode.addChildNode(cloudNode)
        run(reset: true)
    }

    func updateSettings(
        accumulatesPoints: Bool,
        highConfidenceOnly: Bool,
        colorMode: String,
        samplingStep: Int,
        pointSize: CGFloat
    ) {
        settingsLock.lock()
        let accumulationChanged = self.accumulatesPoints != accumulatesPoints
        let visualChanged = self.colorMode != colorMode || self.pointSize != pointSize
        self.accumulatesPoints = accumulatesPoints
        self.highConfidenceOnly = highConfidenceOnly
        self.colorMode = colorMode
        self.samplingStep = samplingStep
        self.pointSize = pointSize
        settingsLock.unlock()

        if accumulationChanged && !accumulatesPoints {
            clearCloud()
        } else if visualChanged {
            rebuildGeometryOnMain()
        }
    }

    func run(reset: Bool) {
        guard ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) else {
            errorMessage = "Scene Depth غير مدعوم. تحتاج إلى جهاز مزود بحساس LiDAR."
            return
        }

        let configuration = ARWorldTrackingConfiguration()
        configuration.worldAlignment = .gravity
        configuration.frameSemantics.insert(.sceneDepth)
        if ARWorldTrackingConfiguration.supportsFrameSemantics(.smoothedSceneDepth) {
            configuration.frameSemantics.insert(.smoothedSceneDepth)
        }
        let options: ARSession.RunOptions = reset ? [.resetTracking, .removeExistingAnchors] : []
        sceneView?.session.run(configuration, options: options)
    }

    func stop() { sceneView?.session.pause() }

    func clearCloud() {
        processingQueue.async { [weak self] in
            guard let self else { return }
            self.samples.removeAll(keepingCapacity: true)
            DispatchQueue.main.async {
                self.pointCount = 0
                self.cloudNode.childNodes.forEach { $0.removeFromParentNode() }
            }
        }
    }

    func clearError() { errorMessage = nil }

    func session(_ session: ARSession, cameraDidChangeTrackingState camera: ARCamera) {
        let text: String
        switch camera.trackingState {
        case .normal: text = "طبيعي"
        case .notAvailable: text = "غير متاح"
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

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        guard frame.timestamp - lastProcessedTimestamp >= 0.16, !isProcessing else { return }
        guard let depthData = frame.smoothedSceneDepth ?? frame.sceneDepth else { return }

        lastProcessedTimestamp = frame.timestamp
        isProcessing = true
        let cameraTransform = frame.camera.transform
        let intrinsics = frame.camera.intrinsics
        let imageResolution = frame.camera.imageResolution
        let timestamp = frame.timestamp

        processingQueue.async { [weak self, depthData] in
            guard let self else { return }
            self.process(
                depthData: depthData,
                cameraTransform: cameraTransform,
                intrinsics: intrinsics,
                imageResolution: imageResolution,
                timestamp: timestamp
            )
            self.isProcessing = false
        }
    }

    func session(_ session: ARSession, didFailWithError error: Error) {
        DispatchQueue.main.async { [weak self] in self?.errorMessage = error.localizedDescription }
    }

    private func process(
        depthData: ARDepthData,
        cameraTransform: simd_float4x4,
        intrinsics: simd_float3x3,
        imageResolution: CGSize,
        timestamp: TimeInterval
    ) {
        settingsLock.lock()
        let currentAccumulation = accumulatesPoints
        let currentHighConfidenceOnly = highConfidenceOnly
        let currentSamplingStep = samplingStep
        settingsLock.unlock()

        let depthMap = depthData.depthMap
        let confidenceMap = depthData.confidenceMap
        CVPixelBufferLockBaseAddress(depthMap, .readOnly)
        if let confidenceMap { CVPixelBufferLockBaseAddress(confidenceMap, .readOnly) }
        defer {
            CVPixelBufferUnlockBaseAddress(depthMap, .readOnly)
            if let confidenceMap { CVPixelBufferUnlockBaseAddress(confidenceMap, .readOnly) }
        }

        guard let depthBaseAddress = CVPixelBufferGetBaseAddress(depthMap) else { return }
        let width = CVPixelBufferGetWidth(depthMap)
        let height = CVPixelBufferGetHeight(depthMap)
        let depthStride = CVPixelBufferGetBytesPerRow(depthMap) / MemoryLayout<Float32>.stride
        let depthValues = depthBaseAddress.assumingMemoryBound(to: Float32.self)

        let confidenceWidth = confidenceMap.map(CVPixelBufferGetWidth) ?? 0
        let confidenceHeight = confidenceMap.map(CVPixelBufferGetHeight) ?? 0
        let confidenceStride = confidenceMap.map(CVPixelBufferGetBytesPerRow) ?? 0
        let confidenceValues: UnsafePointer<UInt8>? = confidenceMap
            .flatMap(CVPixelBufferGetBaseAddress)
            .map { UnsafePointer($0.assumingMemoryBound(to: UInt8.self)) }

        let scaleX = Float(width) / max(Float(imageResolution.width), 1)
        let scaleY = Float(height) / max(Float(imageResolution.height), 1)
        let fx = intrinsics.columns.0.x * scaleX
        let fy = intrinsics.columns.1.y * scaleY
        let cx = intrinsics.columns.2.x * scaleX
        let cy = intrinsics.columns.2.y * scaleY
        guard fx > 0, fy > 0 else { return }

        var frameSamples: [PointSample] = []
        frameSamples.reserveCapacity((width / currentSamplingStep) * (height / currentSamplingStep))

        for y in stride(from: 0, to: height, by: currentSamplingStep) {
            for x in stride(from: 0, to: width, by: currentSamplingStep) {
                let depth = depthValues[y * depthStride + x]
                guard depth.isFinite, depth >= 0.15, depth <= 6.0 else { continue }
                let confidence = confidenceValue(
                    x: x, y: y,
                    depthWidth: width, depthHeight: height,
                    confidenceWidth: confidenceWidth, confidenceHeight: confidenceHeight,
                    confidenceStride: confidenceStride, confidenceValues: confidenceValues
                )
                if currentHighConfidenceOnly && confidence < 2 { continue }

                let cameraX = (Float(x) - cx) * depth / fx
                let cameraY = -(Float(y) - cy) * depth / fy
                let worldPoint = cameraTransform * SIMD4<Float>(cameraX, cameraY, -depth, 1)
                frameSamples.append(PointSample(
                    position: SIMD3<Float>(worldPoint.x, worldPoint.y, worldPoint.z),
                    depth: depth,
                    confidence: confidence
                ))
            }
        }

        if currentAccumulation {
            samples.append(contentsOf: frameSamples)
            if samples.count > maximumPointCount {
                samples.removeFirst(samples.count - maximumPointCount)
            }
        } else {
            samples = frameSamples
        }

        framesInRateWindow += 1
        if rateWindowStart == 0 { rateWindowStart = timestamp }
        let elapsed = timestamp - rateWindowStart
        var calculatedRate: Double?
        if elapsed >= 1.0 {
            calculatedRate = Double(framesInRateWindow) / elapsed
            framesInRateWindow = 0
            rateWindowStart = timestamp
        }

        let geometrySamples = samples
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.processedFrameCount += 1
            self.pointCount = geometrySamples.count
            if let calculatedRate { self.processingRate = calculatedRate }
            self.rebuildGeometry(using: geometrySamples)
        }
    }

    private func confidenceValue(
        x: Int, y: Int,
        depthWidth: Int, depthHeight: Int,
        confidenceWidth: Int, confidenceHeight: Int,
        confidenceStride: Int,
        confidenceValues: UnsafePointer<UInt8>?
    ) -> UInt8 {
        guard let confidenceValues, confidenceWidth > 0, confidenceHeight > 0 else { return 0 }
        let mappedX = min(confidenceWidth - 1, x * confidenceWidth / max(depthWidth, 1))
        let mappedY = min(confidenceHeight - 1, y * confidenceHeight / max(depthHeight, 1))
        return confidenceValues[mappedY * confidenceStride + mappedX]
    }

    private func rebuildGeometryOnMain() {
        processingQueue.async { [weak self] in
            guard let self else { return }
            let geometrySamples = self.samples
            DispatchQueue.main.async { self.rebuildGeometry(using: geometrySamples) }
        }
    }

    private func rebuildGeometry(using geometrySamples: [PointSample]) {
        settingsLock.lock()
        let currentColorMode = colorMode
        let currentPointSize = pointSize
        settingsLock.unlock()

        cloudNode.childNodes.forEach { $0.removeFromParentNode() }
        guard !geometrySamples.isEmpty else { return }

        for group in groupedSamples(geometrySamples, colorMode: currentColorMode) where !group.points.isEmpty {
            let vertices = group.points.map { SCNVector3($0.x, $0.y, $0.z) }
            let source = SCNGeometrySource(vertices: vertices)
            let indices = Array(UInt32(0)..<UInt32(vertices.count))
            let element = SCNGeometryElement(indices: indices, primitiveType: .point)
            element.pointSize = currentPointSize
            element.minimumPointScreenSpaceRadius = max(1, currentPointSize * 0.45)
            element.maximumPointScreenSpaceRadius = currentPointSize * 1.6

            let geometry = SCNGeometry(sources: [source], elements: [element])
            let material = SCNMaterial()
            material.lightingModel = .constant
            material.diffuse.contents = group.color
            material.emission.contents = group.color
            material.readsFromDepthBuffer = true
            material.writesToDepthBuffer = true
            geometry.materials = [material]
            cloudNode.addChildNode(SCNNode(geometry: geometry))
        }
    }

    private func groupedSamples(
        _ geometrySamples: [PointSample],
        colorMode: String
    ) -> [(points: [SIMD3<Float>], color: UIColor)] {
        if colorMode == "monochrome" {
            return [(geometrySamples.map(\.position), .systemCyan)]
        }

        if colorMode == "confidence" {
            var low: [SIMD3<Float>] = []
            var medium: [SIMD3<Float>] = []
            var high: [SIMD3<Float>] = []
            for sample in geometrySamples {
                switch sample.confidence {
                case 2: high.append(sample.position)
                case 1: medium.append(sample.position)
                default: low.append(sample.position)
                }
            }
            return [(low, .systemRed), (medium, .systemYellow), (high, .systemGreen)]
        }

        var near: [SIMD3<Float>] = []
        var close: [SIMD3<Float>] = []
        var medium: [SIMD3<Float>] = []
        var far: [SIMD3<Float>] = []
        var veryFar: [SIMD3<Float>] = []
        for sample in geometrySamples {
            switch sample.depth {
            case ..<0.75: near.append(sample.position)
            case ..<1.5: close.append(sample.position)
            case ..<2.5: medium.append(sample.position)
            case ..<4.0: far.append(sample.position)
            default: veryFar.append(sample.position)
            }
        }
        return [
            (near, .systemRed),
            (close, .systemOrange),
            (medium, .systemYellow),
            (far, .systemGreen),
            (veryFar, .systemCyan)
        ]
    }
}
