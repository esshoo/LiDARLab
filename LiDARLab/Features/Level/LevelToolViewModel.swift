import ARKit
import Combine
import CoreMotion
import ImageIO
import RealityKit
import UIKit
import Vision

struct LevelLine: Equatable {
    let start: CGPoint
    let end: CGPoint

    var angleDegrees: Double {
        let deltaX = end.x - start.x
        let deltaY = end.y - start.y
        return atan2(deltaY, deltaX) * 180 / .pi
    }
}

struct LevelMeasurement {
    let signedHorizontalDeviation: Double
    let horizontalAngle: Double
    let verticalAngle: Double

    var isLevel: Bool { horizontalAngle <= 0.20 }

    var statusText: String {
        if horizontalAngle <= 0.20 {
            return "مستوٍ"
        }
        if horizontalAngle <= 0.50 {
            return "قريب جدًا من المستوى"
        }
        if horizontalAngle <= 1.00 {
            return "قريب من المستوى"
        }
        return signedHorizontalDeviation > 0 ? "مائل مع عقارب الساعة" : "مائل عكس عقارب الساعة"
    }

    static func calculate(lineAngle: Double, horizonAngle: Double) -> LevelMeasurement {
        var signed = lineAngle - horizonAngle
        while signed > 90 { signed -= 180 }
        while signed < -90 { signed += 180 }

        let horizontal = abs(signed)
        return LevelMeasurement(
            signedHorizontalDeviation: signed,
            horizontalAngle: horizontal,
            verticalAngle: abs(90 - horizontal)
        )
    }
}

struct DetectedLevelRectangle: Identifiable, Equatable {
    let id = UUID()
    let topLeft: CGPoint
    let topRight: CGPoint
    let bottomRight: CGPoint
    let bottomLeft: CGPoint
    let confidence: Float

    var points: [CGPoint] {
        [topLeft, topRight, bottomRight, bottomLeft]
    }

    var center: CGPoint {
        CGPoint(
            x: points.map(\.x).reduce(0, +) / 4,
            y: points.map(\.y).reduce(0, +) / 4
        )
    }

    var approximateArea: CGFloat {
        let width = hypot(topRight.x - topLeft.x, topRight.y - topLeft.y)
        let height = hypot(bottomLeft.x - topLeft.x, bottomLeft.y - topLeft.y)
        return width * height
    }

    func contains(_ point: CGPoint) -> Bool {
        let path = CGMutablePath()
        path.move(to: topLeft)
        path.addLine(to: topRight)
        path.addLine(to: bottomRight)
        path.addLine(to: bottomLeft)
        path.closeSubpath()
        return path.contains(point)
    }

    func closestHorizontalEdge(to horizonAngle: Double) -> LevelLine {
        let edges = [
            LevelLine(start: topLeft, end: topRight),
            LevelLine(start: bottomLeft, end: bottomRight),
            LevelLine(start: topLeft, end: bottomLeft),
            LevelLine(start: topRight, end: bottomRight)
        ]

        return edges.min { lhs, rhs in
            LevelMeasurement.calculate(lineAngle: lhs.angleDegrees, horizonAngle: horizonAngle).horizontalAngle
                < LevelMeasurement.calculate(lineAngle: rhs.angleDegrees, horizonAngle: horizonAngle).horizontalAngle
        } ?? LevelLine(start: topLeft, end: topRight)
    }
}

final class LevelToolViewModel: NSObject, ObservableObject, ARSessionDelegate {
    @Published private(set) var horizonAngleDegrees: Double = 0
    @Published private(set) var gravityReliabilityText = "جاري قراءة الجاذبية"
    @Published private(set) var rectangles: [DetectedLevelRectangle] = []
    @Published private(set) var selectedRectangleID: UUID?
    @Published private(set) var isDetecting = false
    @Published private(set) var statusMessage = "اضغط على لوحة أو إطار لاكتشاف حدوده"
    @Published private(set) var trackingState = "تهيئة"
    @Published private(set) var errorMessage: String?

    private weak var arView: ARView?
    private let motionManager = CMMotionManager()
    private let visionQueue = DispatchQueue(label: "com.esshoo.LiDARLab.level.vision", qos: .userInitiated)
    private var latestFrame: ARFrame?
    private var filteredGravity = CGPoint(x: 0, y: 1)

    var selectedRectangle: DetectedLevelRectangle? {
        guard let selectedRectangleID else { return nil }
        return rectangles.first { $0.id == selectedRectangleID }
    }

    var selectedLine: LevelLine? {
        selectedRectangle?.closestHorizontalEdge(to: horizonAngleDegrees)
    }

    func attach(to arView: ARView) {
        self.arView = arView
        arView.automaticallyConfigureSession = false
        arView.session.delegate = self
        runSession(reset: true)
        startMotionUpdates()
    }

    func runSession(reset: Bool) {
        guard ARWorldTrackingConfiguration.isSupported else {
            errorMessage = "تتبع ARKit غير مدعوم على هذا الجهاز."
            return
        }

        let configuration = ARWorldTrackingConfiguration()
        configuration.worldAlignment = .gravity
        configuration.planeDetection = [.horizontal, .vertical]

        let options: ARSession.RunOptions = reset ? [.resetTracking, .removeExistingAnchors] : []
        arView?.session.run(configuration, options: options)
    }

    func stop() {
        motionManager.stopDeviceMotionUpdates()
        arView?.session.pause()
    }

    func clearError() {
        errorMessage = nil
    }

    func clearSelection() {
        rectangles = []
        selectedRectangleID = nil
        statusMessage = "اضغط على لوحة أو إطار لاكتشاف حدوده"
    }

    func handleTap(at point: CGPoint) {
        if selectExistingRectangle(at: point) {
            return
        }
        detectRectangles(selecting: point)
    }

    func scanForRectangles() {
        detectRectangles(selecting: nil)
    }

    private func selectExistingRectangle(at point: CGPoint) -> Bool {
        let containing = rectangles.filter { $0.contains(point) }
        let selected = containing.min { $0.approximateArea < $1.approximateArea }
            ?? rectangles.min { distance($0.center, point) < distance($1.center, point) }

        guard let selected, distance(selected.center, point) < 180 || selected.contains(point) else {
            return false
        }

        selectedRectangleID = selected.id
        statusMessage = "تم تحديد العنصر؛ اتبع قيمة الميل أثناء الضبط"
        return true
    }

    private func detectRectangles(selecting targetPoint: CGPoint?) {
        guard !isDetecting else { return }
        guard let frame = latestFrame ?? arView?.session.currentFrame,
              let arView,
              arView.bounds.width > 0,
              arView.bounds.height > 0 else {
            statusMessage = "انتظر لحظة حتى تبدأ الكاميرا"
            return
        }

        isDetecting = true
        statusMessage = "جاري البحث عن لوحة أو إطار..."

        let viewportSize = arView.bounds.size
        let orientation = arView.window?.windowScene?.interfaceOrientation ?? .portrait
        let displayTransform = frame.displayTransform(for: orientation, viewportSize: viewportSize)
        let pixelBuffer = frame.capturedImage

        visionQueue.async { [weak self] in
            guard let self else { return }

            let request = VNDetectRectanglesRequest()
            request.maximumObservations = 12
            request.minimumConfidence = 0.45
            request.minimumAspectRatio = 0.10
            request.maximumAspectRatio = 1.0
            request.minimumSize = 0.08
            request.quadratureTolerance = 28

            do {
                let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up)
                try handler.perform([request])

                let detected = (request.results ?? []).map { observation in
                    DetectedLevelRectangle(
                        topLeft: self.convert(observation.topLeft, using: displayTransform, viewportSize: viewportSize),
                        topRight: self.convert(observation.topRight, using: displayTransform, viewportSize: viewportSize),
                        bottomRight: self.convert(observation.bottomRight, using: displayTransform, viewportSize: viewportSize),
                        bottomLeft: self.convert(observation.bottomLeft, using: displayTransform, viewportSize: viewportSize),
                        confidence: observation.confidence
                    )
                }
                .filter { rectangle in
                    rectangle.points.allSatisfy { point in
                        point.x.isFinite && point.y.isFinite
                    }
                }

                DispatchQueue.main.async {
                    self.isDetecting = false
                    self.rectangles = detected

                    guard !detected.isEmpty else {
                        self.selectedRectangleID = nil
                        self.statusMessage = "لم أتعرف على إطار واضح؛ استخدم الوضع اليدوي"
                        return
                    }

                    let selected: DetectedLevelRectangle?
                    if let targetPoint {
                        selected = detected.filter { $0.contains(targetPoint) }
                            .min { $0.approximateArea < $1.approximateArea }
                            ?? detected.min { self.distance($0.center, targetPoint) < self.distance($1.center, targetPoint) }
                    } else {
                        selected = detected.max { $0.approximateArea < $1.approximateArea }
                    }

                    self.selectedRectangleID = selected?.id
                    self.statusMessage = selected == nil
                        ? "تم العثور على إطارات؛ اضغط على المطلوب"
                        : "تم تحديد أقرب إطار؛ راقب درجة الميل"
                }
            } catch {
                DispatchQueue.main.async {
                    self.isDetecting = false
                    self.errorMessage = error.localizedDescription
                    self.statusMessage = "تعذر تحليل الصورة"
                }
            }
        }
    }

    private func convert(
        _ point: CGPoint,
        using displayTransform: CGAffineTransform,
        viewportSize: CGSize
    ) -> CGPoint {
        let imagePoint = CGPoint(x: point.x, y: 1 - point.y)
        let viewPoint = imagePoint.applying(displayTransform)
        return CGPoint(x: viewPoint.x * viewportSize.width, y: viewPoint.y * viewportSize.height)
    }

    private func distance(_ first: CGPoint, _ second: CGPoint) -> CGFloat {
        hypot(first.x - second.x, first.y - second.y)
    }

    private func startMotionUpdates() {
        guard motionManager.isDeviceMotionAvailable else {
            gravityReliabilityText = "حساس الحركة غير متاح"
            return
        }

        motionManager.deviceMotionUpdateInterval = 1.0 / 30.0
        motionManager.startDeviceMotionUpdates(using: .xArbitraryZVertical, to: .main) { [weak self] motion, error in
            guard let self else { return }
            if let error {
                self.errorMessage = error.localizedDescription
                return
            }
            guard let gravity = motion?.gravity else { return }

            let orientation = self.arView?.window?.windowScene?.interfaceOrientation ?? .portrait
            let screenGravity = self.screenGravity(from: gravity, orientation: orientation)
            let magnitude = hypot(screenGravity.x, screenGravity.y)

            guard magnitude > 0.05 else {
                self.gravityReliabilityText = "ضع الجهاز في وضع أقرب للرأسي"
                return
            }

            let normalized = CGPoint(x: screenGravity.x / magnitude, y: screenGravity.y / magnitude)
            let alpha: CGFloat = 0.18
            self.filteredGravity = CGPoint(
                x: self.filteredGravity.x * (1 - alpha) + normalized.x * alpha,
                y: self.filteredGravity.y * (1 - alpha) + normalized.y * alpha
            )

            let verticalAngle = Double(atan2(self.filteredGravity.y, self.filteredGravity.x)) * 180 / Double.pi
            self.horizonAngleDegrees = self.normalizedAxisAngle(verticalAngle - 90)
            self.gravityReliabilityText = magnitude > 0.30 ? "مرجع الجاذبية ثابت" : "دقة الجاذبية منخفضة والجهاز شبه أفقي"
        }
    }

    private func screenGravity(from gravity: CMAcceleration, orientation: UIInterfaceOrientation) -> CGPoint {
        switch orientation {
        case .portrait:
            CGPoint(x: CGFloat(gravity.x), y: CGFloat(-gravity.y))
        case .portraitUpsideDown:
            CGPoint(x: CGFloat(-gravity.x), y: CGFloat(gravity.y))
        case .landscapeLeft:
            CGPoint(x: CGFloat(-gravity.y), y: CGFloat(-gravity.x))
        case .landscapeRight:
            CGPoint(x: CGFloat(gravity.y), y: CGFloat(gravity.x))
        default:
            CGPoint(x: CGFloat(gravity.x), y: CGFloat(-gravity.y))
        }
    }

    private func normalizedAxisAngle(_ angle: Double) -> Double {
        var value = angle
        while value > 90 { value -= 180 }
        while value < -90 { value += 180 }
        return value
    }

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        latestFrame = frame
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

        DispatchQueue.main.async { [weak self] in
            self?.trackingState = text
        }
    }

    func session(_ session: ARSession, didFailWithError error: Error) {
        DispatchQueue.main.async { [weak self] in
            self?.errorMessage = error.localizedDescription
        }
    }
}
