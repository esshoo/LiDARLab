import ARKit
import Combine
import CoreGraphics
import RealityKit
import UIKit

final class DepthSessionViewModel: NSObject, ObservableObject, ARSessionDelegate {
    @Published private(set) var heatMapImage: UIImage?
    @Published private(set) var centerDistance: Float?
    @Published private(set) var minimumDistance: Float?
    @Published private(set) var maximumDistance: Float?
    @Published private(set) var centerConfidence = "غير متاح"
    @Published private(set) var errorMessage: String?

    var preferSmoothedDepth = true
    var showOnlyHighConfidence = false
    var isFrozen = false

    private weak var arView: ARView?
    private let shouldGenerateHeatmap: Bool
    private let processingQueue = DispatchQueue(label: "com.esshoo.LiDARLab.depth-processing", qos: .userInitiated)
    private var lastProcessedTimestamp: TimeInterval = 0
    private var isProcessing = false

    init(generateHeatmap: Bool = true) {
        shouldGenerateHeatmap = generateHeatmap
        super.init()
    }

    func attach(to arView: ARView) {
        self.arView = arView
        arView.session.delegate = self
        startSession(resetTracking: true)
    }

    func startSession(resetTracking: Bool) {
        guard ARWorldTrackingConfiguration.isSupported else {
            errorMessage = "AR World Tracking غير مدعوم على هذا الجهاز."
            return
        }
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

        let options: ARSession.RunOptions = resetTracking ? [.resetTracking, .removeExistingAnchors] : []
        arView?.session.run(configuration, options: options)
    }

    func stopSession() {
        arView?.session.pause()
    }

    func clearError() {
        errorMessage = nil
    }

    func session(_ session: ARSession, didFailWithError error: Error) {
        DispatchQueue.main.async { [weak self] in
            self?.errorMessage = error.localizedDescription
        }
    }

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        guard !isFrozen else { return }
        guard frame.timestamp - lastProcessedTimestamp >= 0.12 else { return }
        guard !isProcessing else { return }

        let depthData: ARDepthData?
        if preferSmoothedDepth {
            depthData = frame.smoothedSceneDepth ?? frame.sceneDepth
        } else {
            depthData = frame.sceneDepth
        }

        guard let depthData else { return }
        lastProcessedTimestamp = frame.timestamp
        isProcessing = true

        processingQueue.async { [weak self, depthData] in
            self?.process(depthData: depthData)
            self?.isProcessing = false
        }
    }

    private func process(depthData: ARDepthData) {
        let depthMap = depthData.depthMap
        let confidenceMap = depthData.confidenceMap

        CVPixelBufferLockBaseAddress(depthMap, .readOnly)
        if let confidenceMap {
            CVPixelBufferLockBaseAddress(confidenceMap, .readOnly)
        }

        defer {
            CVPixelBufferUnlockBaseAddress(depthMap, .readOnly)
            if let confidenceMap {
                CVPixelBufferUnlockBaseAddress(confidenceMap, .readOnly)
            }
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

        var minimum = Float.greatestFiniteMagnitude
        var maximum: Float = 0
        var centerSamples: [Float] = []
        centerSamples.reserveCapacity(49)

        let centerX = width / 2
        let centerY = height / 2
        let centerRadius = 3

        var pixels = shouldGenerateHeatmap ? [UInt8](repeating: 0, count: width * height * 4) : []

        for y in 0..<height {
            for x in 0..<width {
                let depth = depthValues[y * depthStride + x]
                let isValidDepth = depth.isFinite && depth > 0.05 && depth <= 8.0

                let confidence = confidenceValue(
                    x: x,
                    y: y,
                    depthWidth: width,
                    depthHeight: height,
                    confidenceWidth: confidenceWidth,
                    confidenceHeight: confidenceHeight,
                    confidenceStride: confidenceStride,
                    confidenceValues: confidenceValues
                )

                if isValidDepth && (!showOnlyHighConfidence || confidence == 2) {
                    minimum = min(minimum, depth)
                    maximum = max(maximum, depth)

                    if abs(x - centerX) <= centerRadius && abs(y - centerY) <= centerRadius {
                        centerSamples.append(depth)
                    }
                }

                guard shouldGenerateHeatmap else { continue }
                let pixelIndex = (y * width + x) * 4

                guard isValidDepth, !showOnlyHighConfidence || confidence == 2 else {
                    pixels[pixelIndex + 3] = 0
                    continue
                }

                let normalized = max(0, min(1, (depth - 0.20) / 4.80))
                let color = Self.heatColor(normalized)
                pixels[pixelIndex] = color.red
                pixels[pixelIndex + 1] = color.green
                pixels[pixelIndex + 2] = color.blue
                pixels[pixelIndex + 3] = 205
            }
        }

        centerSamples.sort()
        let measuredCenter = centerSamples.isEmpty ? nil : centerSamples[centerSamples.count / 2]
        let centerConfidenceValue = confidenceValue(
            x: centerX,
            y: centerY,
            depthWidth: width,
            depthHeight: height,
            confidenceWidth: confidenceWidth,
            confidenceHeight: confidenceHeight,
            confidenceStride: confidenceStride,
            confidenceValues: confidenceValues
        )

        let generatedImage = shouldGenerateHeatmap ? Self.makeImage(pixels: pixels, width: width, height: height) : nil
        let publishedMinimum = minimum == Float.greatestFiniteMagnitude ? nil : minimum
        let publishedMaximum = maximum == 0 ? nil : maximum

        DispatchQueue.main.async { [weak self] in
            self?.centerDistance = measuredCenter
            self?.minimumDistance = publishedMinimum
            self?.maximumDistance = publishedMaximum
            self?.centerConfidence = Self.confidenceDescription(centerConfidenceValue)
            if let generatedImage {
                self?.heatMapImage = generatedImage
            }
        }
    }

    private func confidenceValue(
        x: Int,
        y: Int,
        depthWidth: Int,
        depthHeight: Int,
        confidenceWidth: Int,
        confidenceHeight: Int,
        confidenceStride: Int,
        confidenceValues: UnsafePointer<UInt8>?
    ) -> UInt8 {
        guard let confidenceValues, confidenceWidth > 0, confidenceHeight > 0 else { return 0 }
        let mappedX = min(confidenceWidth - 1, x * confidenceWidth / max(depthWidth, 1))
        let mappedY = min(confidenceHeight - 1, y * confidenceHeight / max(depthHeight, 1))
        return confidenceValues[mappedY * confidenceStride + mappedX]
    }

    private static func confidenceDescription(_ value: UInt8) -> String {
        switch value {
        case 2: "مرتفعة"
        case 1: "متوسطة"
        case 0: "منخفضة"
        default: "غير معروفة"
        }
    }

    private static func heatColor(_ value: Float) -> (red: UInt8, green: UInt8, blue: UInt8) {
        let t = max(0, min(1, value))
        let red = UInt8(max(0, min(255, 255 * min(1, max(0, 1.5 - abs(4 * t - 3))))))
        let green = UInt8(max(0, min(255, 255 * min(1, max(0, 1.5 - abs(4 * t - 2))))))
        let blue = UInt8(max(0, min(255, 255 * min(1, max(0, 1.5 - abs(4 * t - 1))))))
        return (red, green, blue)
    }

    private static func makeImage(pixels: [UInt8], width: Int, height: Int) -> UIImage? {
        guard let provider = CGDataProvider(data: Data(pixels) as CFData) else { return nil }
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)

        guard let image = CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo,
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        ) else {
            return nil
        }

        return UIImage(cgImage: image, scale: 1, orientation: .right)
    }
}
