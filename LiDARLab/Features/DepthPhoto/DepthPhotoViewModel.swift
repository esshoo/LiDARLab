import ARKit
import Combine
import CoreImage
import RealityKit
import UIKit

struct DepthPhotoCapture: Identifiable {
    let id = UUID()
    let createdAt: Date
    let folderURL: URL
    let colorURL: URL
    let heatMapURL: URL
    let confidenceURL: URL?
    let rawDepthURL: URL
    let metadataURL: URL
    let previewImage: UIImage

    var shareItems: [Any] {
        [colorURL, heatMapURL, rawDepthURL, metadataURL] + (confidenceURL.map { [$0] } ?? [])
    }
}

private struct DepthPhotoMetadata: Codable {
    let capturedAt: Date
    let colorWidth: Int
    let colorHeight: Int
    let depthWidth: Int
    let depthHeight: Int
    let depthUnit: String
    let depthFormat: String
    let centerDistanceMeters: Float?
    let minimumDistanceMeters: Float?
    let maximumDistanceMeters: Float?
    let smoothedDepth: Bool
    let interfaceOrientation: String
    let cameraTransformColumnMajor: [Float]
    let cameraIntrinsicsColumnMajor: [Float]
}

final class DepthPhotoViewModel: NSObject, ObservableObject, ARSessionDelegate {
    @Published private(set) var heatMapImage: UIImage?
    @Published private(set) var centerDistance: Float?
    @Published private(set) var latestCapture: DepthPhotoCapture?
    @Published private(set) var isSaving = false
    @Published private(set) var statusMessage = "وجّه الكاميرا ثم التقط صورة العمق."
    @Published private(set) var errorMessage: String?

    var preferSmoothedDepth = true
    var showOnlyHighConfidence = false

    private weak var arView: ARView?
    private var latestFrame: ARFrame?
    private let processingQueue = DispatchQueue(label: "com.esshoo.LiDARLab.depth-photo", qos: .userInitiated)
    private let ciContext = CIContext(options: [.cacheIntermediates: true])
    private var lastPreviewTimestamp: TimeInterval = 0
    private var previewProcessing = false
    private var currentOrientation: UIInterfaceOrientation = .portrait

    func attach(to arView: ARView) {
        self.arView = arView
        arView.session.delegate = self
        startSession(resetTracking: true)
    }

    func startSession(resetTracking: Bool) {
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

    func updateOrientation(_ orientation: UIInterfaceOrientation) {
        currentOrientation = orientation
    }

    func stopSession() {
        arView?.session.pause()
    }

    func clearError() {
        errorMessage = nil
    }

    func capture() {
        guard !isSaving else { return }
        guard let frame = latestFrame ?? arView?.session.currentFrame else {
            errorMessage = "لم يصل إطار صالح من الكاميرا بعد."
            return
        }

        let depthData = selectedDepth(from: frame)
        guard let depthData else {
            errorMessage = "بيانات العمق غير جاهزة. حرّك الجهاز ببطء ثم جرّب مرة أخرى."
            return
        }

        let orientation = currentOrientation
        isSaving = true
        statusMessage = "جارٍ حفظ الصورة وبيانات العمق…"

        processingQueue.async { [weak self, frame, depthData] in
            guard let self else { return }
            do {
                let capture = try self.createCapture(frame: frame, depthData: depthData, orientation: orientation)
                DispatchQueue.main.async {
                    self.latestCapture = capture
                    self.isSaving = false
                    self.statusMessage = "تم حفظ حزمة الصورة بنجاح."
                }
            } catch {
                DispatchQueue.main.async {
                    self.isSaving = false
                    self.errorMessage = error.localizedDescription
                    self.statusMessage = "تعذر حفظ الصورة."
                }
            }
        }
    }

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        latestFrame = frame
        guard frame.timestamp - lastPreviewTimestamp >= 0.15 else { return }
        guard !previewProcessing, let depthData = selectedDepth(from: frame) else { return }

        lastPreviewTimestamp = frame.timestamp
        previewProcessing = true
        processingQueue.async { [weak self, depthData] in
            guard let self else { return }
            let result = self.processDepth(
                depthData,
                highConfidenceOnly: self.showOnlyHighConfidence,
                orientation: self.currentOrientation.imageOrientation
            )
            DispatchQueue.main.async {
                self.heatMapImage = result.heatMap
                self.centerDistance = result.center
                self.previewProcessing = false
            }
        }
    }

    func session(_ session: ARSession, didFailWithError error: Error) {
        DispatchQueue.main.async { [weak self] in
            self?.errorMessage = error.localizedDescription
        }
    }

    private func selectedDepth(from frame: ARFrame) -> ARDepthData? {
        if preferSmoothedDepth {
            return frame.smoothedSceneDepth ?? frame.sceneDepth
        }
        return frame.sceneDepth
    }

    private func createCapture(
        frame: ARFrame,
        depthData: ARDepthData,
        orientation: UIInterfaceOrientation
    ) throws -> DepthPhotoCapture {
        let date = Date()
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let name = "DepthPhoto-\(formatter.string(from: date))"

        let storage = LiDARLabStorage.shared
        try storage.ensureDirectories()
        let folder = storage.capturesURL.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        guard let colorImage = makeCameraImage(frame.capturedImage, orientation: orientation),
              let colorData = colorImage.jpegData(compressionQuality: 0.94) else {
            throw NSError(domain: "DepthPhoto", code: 1, userInfo: [NSLocalizedDescriptionKey: "تعذر تحويل صورة الكاميرا."])
        }

        let processed = processDepth(
            depthData,
            highConfidenceOnly: showOnlyHighConfidence,
            orientation: orientation.imageOrientation
        )
        guard let heatMap = processed.heatMap,
              let heatData = heatMap.pngData() else {
            throw NSError(domain: "DepthPhoto", code: 2, userInfo: [NSLocalizedDescriptionKey: "تعذر إنشاء خريطة العمق."])
        }

        let colorURL = folder.appendingPathComponent("color.jpg")
        let heatURL = folder.appendingPathComponent("depth-heatmap.png")
        let rawURL = folder.appendingPathComponent("depth-float32.bin")
        let metadataURL = folder.appendingPathComponent("metadata.json")
        try colorData.write(to: colorURL, options: .atomic)
        try heatData.write(to: heatURL, options: .atomic)
        try rawDepthData(from: depthData.depthMap).write(to: rawURL, options: .atomic)

        var confidenceURL: URL?
        if let confidenceMap = depthData.confidenceMap,
           let confidenceImage = makeConfidenceImage(confidenceMap, orientation: orientation),
           let confidenceData = confidenceImage.pngData() {
            let url = folder.appendingPathComponent("confidence.png")
            try confidenceData.write(to: url, options: .atomic)
            confidenceURL = url
        }

        let colorWidth = CVPixelBufferGetWidth(frame.capturedImage)
        let colorHeight = CVPixelBufferGetHeight(frame.capturedImage)
        let metadata = DepthPhotoMetadata(
            capturedAt: date,
            colorWidth: colorWidth,
            colorHeight: colorHeight,
            depthWidth: CVPixelBufferGetWidth(depthData.depthMap),
            depthHeight: CVPixelBufferGetHeight(depthData.depthMap),
            depthUnit: "meter",
            depthFormat: "Float32 little-endian, tightly packed rows",
            centerDistanceMeters: processed.center,
            minimumDistanceMeters: processed.minimum,
            maximumDistanceMeters: processed.maximum,
            smoothedDepth: preferSmoothedDepth,
            interfaceOrientation: orientation.metadataName,
            cameraTransformColumnMajor: flatten(frame.camera.transform),
            cameraIntrinsicsColumnMajor: flatten(frame.camera.intrinsics)
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(metadata).write(to: metadataURL, options: .atomic)

        return DepthPhotoCapture(
            createdAt: date,
            folderURL: folder,
            colorURL: colorURL,
            heatMapURL: heatURL,
            confidenceURL: confidenceURL,
            rawDepthURL: rawURL,
            metadataURL: metadataURL,
            previewImage: colorImage
        )
    }

    private func makeCameraImage(_ pixelBuffer: CVPixelBuffer, orientation: UIInterfaceOrientation) -> UIImage? {
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        guard let cgImage = ciContext.createCGImage(ciImage, from: ciImage.extent) else { return nil }
        return UIImage(cgImage: cgImage, scale: 1, orientation: orientation.imageOrientation)
    }

    private func processDepth(
        _ depthData: ARDepthData,
        highConfidenceOnly: Bool,
        orientation: UIImage.Orientation
    ) -> (heatMap: UIImage?, center: Float?, minimum: Float?, maximum: Float?) {
        let depthMap = depthData.depthMap
        let confidenceMap = depthData.confidenceMap
        CVPixelBufferLockBaseAddress(depthMap, .readOnly)
        if let confidenceMap { CVPixelBufferLockBaseAddress(confidenceMap, .readOnly) }
        defer {
            CVPixelBufferUnlockBaseAddress(depthMap, .readOnly)
            if let confidenceMap { CVPixelBufferUnlockBaseAddress(confidenceMap, .readOnly) }
        }

        guard let base = CVPixelBufferGetBaseAddress(depthMap) else { return (nil, nil, nil, nil) }
        let width = CVPixelBufferGetWidth(depthMap)
        let height = CVPixelBufferGetHeight(depthMap)
        let stride = CVPixelBufferGetBytesPerRow(depthMap) / MemoryLayout<Float32>.stride
        let values = base.assumingMemoryBound(to: Float32.self)

        let confidenceWidth = confidenceMap.map(CVPixelBufferGetWidth) ?? 0
        let confidenceHeight = confidenceMap.map(CVPixelBufferGetHeight) ?? 0
        let confidenceStride = confidenceMap.map(CVPixelBufferGetBytesPerRow) ?? 0
        let confidenceValues: UnsafePointer<UInt8>? = confidenceMap
            .flatMap(CVPixelBufferGetBaseAddress)
            .map { UnsafePointer($0.assumingMemoryBound(to: UInt8.self)) }

        var rgba = [UInt8](repeating: 0, count: width * height * 4)
        var minimum = Float.greatestFiniteMagnitude
        var maximum: Float = 0
        var centerSamples: [Float] = []

        for y in 0..<height {
            for x in 0..<width {
                let depth = values[y * stride + x]
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
                let valid = depth.isFinite && depth > 0.05 && depth <= 8 && (!highConfidenceOnly || confidence == 2)
                let index = (y * width + x) * 4
                guard valid else {
                    rgba[index + 3] = 0
                    continue
                }

                minimum = min(minimum, depth)
                maximum = max(maximum, depth)
                if abs(x - width / 2) <= 3 && abs(y - height / 2) <= 3 {
                    centerSamples.append(depth)
                }

                let color = Self.heatColor(max(0, min(1, (depth - 0.2) / 4.8)))
                rgba[index] = color.0
                rgba[index + 1] = color.1
                rgba[index + 2] = color.2
                rgba[index + 3] = 215
            }
        }

        centerSamples.sort()
        let center = centerSamples.isEmpty ? nil : centerSamples[centerSamples.count / 2]
        let minValue = minimum == Float.greatestFiniteMagnitude ? nil : minimum
        let maxValue = maximum == 0 ? nil : maximum
        return (Self.makeRGBAImage(rgba, width: width, height: height, orientation: orientation), center, minValue, maxValue)
    }

    private func rawDepthData(from pixelBuffer: CVPixelBuffer) -> Data {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else { return Data() }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let packedRowBytes = width * MemoryLayout<Float32>.stride
        var data = Data(capacity: packedRowBytes * height)
        for row in 0..<height {
            let pointer = base.advanced(by: row * bytesPerRow).assumingMemoryBound(to: UInt8.self)
            data.append(contentsOf: UnsafeBufferPointer(start: pointer, count: packedRowBytes))
        }
        return data
    }

    private func makeConfidenceImage(_ map: CVPixelBuffer, orientation: UIInterfaceOrientation) -> UIImage? {
        CVPixelBufferLockBaseAddress(map, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(map, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(map) else { return nil }

        let width = CVPixelBufferGetWidth(map)
        let height = CVPixelBufferGetHeight(map)
        let stride = CVPixelBufferGetBytesPerRow(map)
        let values = base.assumingMemoryBound(to: UInt8.self)
        var rgba = [UInt8](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let value = values[y * stride + x]
                let gray: UInt8 = value == 2 ? 255 : (value == 1 ? 150 : 45)
                let index = (y * width + x) * 4
                rgba[index] = gray
                rgba[index + 1] = gray
                rgba[index + 2] = gray
                rgba[index + 3] = 255
            }
        }
        return Self.makeRGBAImage(rgba, width: width, height: height, orientation: orientation.imageOrientation)
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

    private static func heatColor(_ value: Float) -> (UInt8, UInt8, UInt8) {
        let t = max(0, min(1, value))
        let red = UInt8(max(0, min(255, 255 * min(1, max(0, 1.5 - abs(4 * t - 3))))))
        let green = UInt8(max(0, min(255, 255 * min(1, max(0, 1.5 - abs(4 * t - 2))))))
        let blue = UInt8(max(0, min(255, 255 * min(1, max(0, 1.5 - abs(4 * t - 1))))))
        return (red, green, blue)
    }

    private static func makeRGBAImage(
        _ pixels: [UInt8],
        width: Int,
        height: Int,
        orientation: UIImage.Orientation
    ) -> UIImage? {
        guard let provider = CGDataProvider(data: Data(pixels) as CFData) else { return nil }
        guard let cgImage = CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        ) else { return nil }
        return UIImage(cgImage: cgImage, scale: 1, orientation: orientation)
    }

    private func flatten(_ matrix: simd_float4x4) -> [Float] {
        [matrix.columns.0.x, matrix.columns.0.y, matrix.columns.0.z, matrix.columns.0.w,
         matrix.columns.1.x, matrix.columns.1.y, matrix.columns.1.z, matrix.columns.1.w,
         matrix.columns.2.x, matrix.columns.2.y, matrix.columns.2.z, matrix.columns.2.w,
         matrix.columns.3.x, matrix.columns.3.y, matrix.columns.3.z, matrix.columns.3.w]
    }

    private func flatten(_ matrix: simd_float3x3) -> [Float] {
        [matrix.columns.0.x, matrix.columns.0.y, matrix.columns.0.z,
         matrix.columns.1.x, matrix.columns.1.y, matrix.columns.1.z,
         matrix.columns.2.x, matrix.columns.2.y, matrix.columns.2.z]
    }
}

private extension UIInterfaceOrientation {
    var imageOrientation: UIImage.Orientation {
        switch self {
        case .portrait: .right
        case .portraitUpsideDown: .left
        case .landscapeLeft: .up
        case .landscapeRight: .down
        default: .right
        }
    }

    var metadataName: String {
        switch self {
        case .portrait: "portrait"
        case .portraitUpsideDown: "portraitUpsideDown"
        case .landscapeLeft: "landscapeLeft"
        case .landscapeRight: "landscapeRight"
        default: "unknown"
        }
    }
}
