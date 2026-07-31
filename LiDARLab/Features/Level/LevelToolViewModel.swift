import ARKit
import Combine
import ImageIO
import RealityKit
import UIKit
import Vision
import simd

struct LevelLine: Equatable {
    let start: CGPoint
    let end: CGPoint

    var angleDegrees: Double {
        let deltaX = end.x - start.x
        let deltaY = end.y - start.y
        return atan2(deltaY, deltaX) * 180 / .pi
    }

    var midpoint: CGPoint {
        CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2)
    }
}

struct ProjectedReferenceAxes: Equatable {
    let horizontal: LevelLine
    let vertical: LevelLine
    let origin: CGPoint
}

struct LevelMeasurement: Equatable {
    let signedHorizontalDeviation: Double
    let signedVerticalDeviation: Double

    var horizontalAngle: Double { abs(signedHorizontalDeviation) }
    var verticalAngle: Double { abs(signedVerticalDeviation) }
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
        return signedHorizontalDeviation > 0
            ? "الطرف الأيمن منخفض"
            : "الطرف الأيمن مرتفع"
    }

    static func screenMeasurement(lineAngle: Double, horizonAngle: Double) -> LevelMeasurement {
        var horizontal = lineAngle - horizonAngle
        while horizontal > 90 { horizontal -= 180 }
        while horizontal < -90 { horizontal += 180 }

        var vertical = horizontal >= 0 ? horizontal - 90 : horizontal + 90
        while vertical > 90 { vertical -= 180 }
        while vertical < -90 { vertical += 180 }

        return LevelMeasurement(
            signedHorizontalDeviation: horizontal,
            signedVerticalDeviation: vertical
        )
    }
}

struct TrackedLevelTarget: Equatable {
    let corners: [CGPoint]
    let horizontalLine: LevelLine
    let verticalLine: LevelLine
    let center: CGPoint
    let measurement: LevelMeasurement
    let confidence: Float
    let sourceText: String
}

private enum LevelDetectionSource: String {
    case vision = "اكتشاف تلقائي"
    case fourPoints = "تحديد بأربع نقاط"
}

private struct WorldLevelTarget {
    var corners: [SIMD3<Float>]
    let planeOrigin: SIMD3<Float>
    let planeNormal: SIMD3<Float>
    var observation: VNRectangleObservation?
    var confidence: Float
    let source: LevelDetectionSource
}

final class LevelToolViewModel: NSObject, ObservableObject, ARSessionDelegate {
    @Published private(set) var horizonAngleDegrees: Double = 0
    @Published private(set) var screenReferenceAxes: ProjectedReferenceAxes?
    @Published private(set) var wallReferenceAxes: ProjectedReferenceAxes?
    @Published private(set) var target: TrackedLevelTarget?
    @Published private(set) var draftCornerPoints: [CGPoint] = []
    @Published private(set) var isDetecting = false
    @Published private(set) var isTrackingTarget = false
    @Published private(set) var statusMessage = "اضغط على لوحة أو إطار لتثبيته"
    @Published private(set) var trackingState = "تهيئة"
    @Published private(set) var gravityReliabilityText = "تهيئة مرجع الجاذبية"
    @Published private(set) var errorMessage: String?

    private weak var arView: ARView?
    private let visionQueue = DispatchQueue(label: "com.esshoo.LiDARLab.level.vision", qos: .userInitiated)
    private var sequenceHandler = VNSequenceRequestHandler()
    private var latestFrame: ARFrame?
    private var worldTarget: WorldLevelTarget?
    private var draftWorldPoints: [SIMD3<Float>] = []
    private var draftPlaneOrigin: SIMD3<Float>?
    private var draftPlaneNormal: SIMD3<Float>?
    private var trackingInFlight = false
    private var lastTrackingTime: TimeInterval = 0
    private var smoothedCorners: [CGPoint]?
    private var smoothedHorizonAngle: Double?

    var automaticMeasurement: LevelMeasurement? {
        target?.measurement
    }

    func attach(to arView: ARView) {
        self.arView = arView
        arView.automaticallyConfigureSession = false
        arView.session.delegate = self
        runSession(reset: true)
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
        arView?.session.pause()
    }

    func clearError() {
        errorMessage = nil
    }

    func clearSelection() {
        worldTarget = nil
        target = nil
        wallReferenceAxes = nil
        draftCornerPoints = []
        draftWorldPoints = []
        draftPlaneOrigin = nil
        draftPlaneNormal = nil
        smoothedCorners = nil
        sequenceHandler = VNSequenceRequestHandler()
        isTrackingTarget = false
        statusMessage = "اضغط على لوحة أو إطار لتثبيته"
    }

    func beginFourPointSelection() {
        clearSelection()
        statusMessage = "حدد الزوايا الأربع بالترتيب حول العنصر"
    }

    func undoDraftCorner() {
        guard !draftWorldPoints.isEmpty else { return }
        draftWorldPoints.removeLast()
        if !draftCornerPoints.isEmpty {
            draftCornerPoints.removeLast()
        }
        statusMessage = "تم تحديد \(draftWorldPoints.count) من 4 نقاط"
        if draftWorldPoints.isEmpty {
            draftPlaneOrigin = nil
            draftPlaneNormal = nil
        }
    }

    func handleAutomaticTap(at point: CGPoint) {
        detectRectangle(selecting: point)
    }

    func scanForRectangle() {
        guard let arView else { return }
        detectRectangle(selecting: CGPoint(x: arView.bounds.midX, y: arView.bounds.midY))
    }

    func addFourPointCorner(at point: CGPoint) {
        guard let arView,
              let frame = latestFrame ?? arView.session.currentFrame else {
            statusMessage = "انتظر حتى يبدأ تتبع الكاميرا"
            return
        }

        if draftWorldPoints.isEmpty {
            guard let plane = planeForSelection(at: point, frame: frame) else {
                statusMessage = "وجّه الجهاز إلى الحائط وانتظر اكتشاف سطحه"
                return
            }
            draftPlaneOrigin = plane.origin
            draftPlaneNormal = plane.normal
        }

        guard let planeOrigin = draftPlaneOrigin,
              let planeNormal = draftPlaneNormal,
              let worldPoint = intersectScreenPoint(point, planeOrigin: planeOrigin, planeNormal: planeNormal) else {
            statusMessage = "تعذر تثبيت هذه النقطة على السطح"
            return
        }

        draftWorldPoints.append(worldPoint)
        draftCornerPoints.append(point)

        guard draftWorldPoints.count == 4 else {
            statusMessage = "تم تحديد \(draftWorldPoints.count) من 4 نقاط"
            return
        }

        let ordered = orderCorners(screenPoints: draftCornerPoints, worldPoints: draftWorldPoints)
        let observation = makeVisionObservation(fromScreenPoints: ordered.screen, frame: frame)

        worldTarget = WorldLevelTarget(
            corners: ordered.world,
            planeOrigin: planeOrigin,
            planeNormal: planeNormal,
            observation: observation,
            confidence: 1,
            source: .fourPoints
        )
        draftCornerPoints = []
        draftWorldPoints = []
        isTrackingTarget = observation != nil
        statusMessage = "تم تثبيت العنصر على الحائط"
        smoothedCorners = nil
        updateProjection(using: frame)
    }

    private func detectRectangle(selecting targetPoint: CGPoint) {
        guard !isDetecting else { return }
        guard let frame = latestFrame ?? arView?.session.currentFrame,
              let arView,
              arView.bounds.width > 0,
              arView.bounds.height > 0 else {
            statusMessage = "انتظر لحظة حتى تبدأ الكاميرا"
            return
        }

        isDetecting = true
        statusMessage = "جاري تحديد حدود العنصر..."

        let viewportSize = arView.bounds.size
        let orientation = interfaceOrientation
        let displayTransform = frame.displayTransform(for: orientation, viewportSize: viewportSize)
        let pixelBuffer = frame.capturedImage
        let targetVisionPoint = visionPoint(fromScreenPoint: targetPoint, displayTransform: displayTransform, viewportSize: viewportSize)
        let region = regionOfInterest(around: targetVisionPoint)

        visionQueue.async { [weak self] in
            guard let self else { return }

            let request = VNDetectRectanglesRequest()
            request.maximumObservations = 20
            request.minimumConfidence = 0.30
            request.minimumAspectRatio = 0.05
            request.maximumAspectRatio = 1.0
            request.minimumSize = 0.025
            request.quadratureTolerance = 45
            request.regionOfInterest = region

            do {
                let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up)
                try handler.perform([request])

                let observations = request.results ?? []
                let selected = self.bestObservation(
                    from: observations,
                    targetPoint: targetPoint,
                    displayTransform: displayTransform,
                    viewportSize: viewportSize
                )

                DispatchQueue.main.async {
                    self.isDetecting = false

                    guard let selected else {
                        self.statusMessage = "لم تظهر حدود واضحة؛ استخدم وضع 4 نقاط لأي شكل"
                        return
                    }

                    self.lockTarget(
                        observation: selected,
                        targetPoint: targetPoint,
                        frame: frame,
                        displayTransform: displayTransform,
                        viewportSize: viewportSize
                    )
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

    private func bestObservation(
        from observations: [VNRectangleObservation],
        targetPoint: CGPoint,
        displayTransform: CGAffineTransform,
        viewportSize: CGSize
    ) -> VNRectangleObservation? {
        let candidates = observations.map { observation -> (VNRectangleObservation, [CGPoint], CGFloat) in
            let points = screenPoints(for: observation, displayTransform: displayTransform, viewportSize: viewportSize)
            let area = polygonArea(points)
            return (observation, points, area)
        }
        .filter { candidate in
            candidate.1.allSatisfy { $0.x.isFinite && $0.y.isFinite } && candidate.2 > 500
        }

        return candidates.max { lhs, rhs in
            score(points: lhs.1, area: lhs.2, confidence: lhs.0.confidence, target: targetPoint)
                < score(points: rhs.1, area: rhs.2, confidence: rhs.0.confidence, target: targetPoint)
        }?.0
    }

    private func score(points: [CGPoint], area: CGFloat, confidence: Float, target: CGPoint) -> CGFloat {
        let path = polygonPath(points)
        let center = averagePoint(points)
        let distance = hypot(center.x - target.x, center.y - target.y)
        let containsBonus: CGFloat = path.contains(target) ? 10_000 : 0
        return containsBonus + area * 0.02 + CGFloat(confidence) * 1_000 - distance * 4
    }

    private func lockTarget(
        observation: VNRectangleObservation,
        targetPoint: CGPoint,
        frame: ARFrame,
        displayTransform: CGAffineTransform,
        viewportSize: CGSize
    ) {
        guard let plane = planeForSelection(at: targetPoint, frame: frame) else {
            statusMessage = "تم التعرف على الشكل لكن لم يُكتشف سطح الحائط بعد"
            return
        }

        let screenCorners = screenPoints(for: observation, displayTransform: displayTransform, viewportSize: viewportSize)
        let worldCorners = screenCorners.compactMap {
            intersectScreenPoint($0, planeOrigin: plane.origin, planeNormal: plane.normal)
        }

        guard worldCorners.count == 4, targetSizeIsReasonable(worldCorners) else {
            statusMessage = "اقترب قليلًا من العنصر وحاول مرة أخرى"
            return
        }

        worldTarget = WorldLevelTarget(
            corners: worldCorners,
            planeOrigin: plane.origin,
            planeNormal: plane.normal,
            observation: observation,
            confidence: observation.confidence,
            source: .vision
        )
        sequenceHandler = VNSequenceRequestHandler()
        smoothedCorners = nil
        isTrackingTarget = true
        statusMessage = "تم تثبيت العنصر وتتبع حدوده"
        updateProjection(using: frame)
    }

    private func planeForSelection(at point: CGPoint, frame: ARFrame) -> (origin: SIMD3<Float>, normal: SIMD3<Float>)? {
        guard let arView else { return nil }

        let result = arView.raycast(from: point, allowing: .existingPlaneGeometry, alignment: .vertical).first
            ?? arView.raycast(from: point, allowing: .existingPlaneInfinite, alignment: .vertical).first
            ?? arView.raycast(from: point, allowing: .estimatedPlane, alignment: .vertical).first
            ?? arView.raycast(from: point, allowing: .estimatedPlane, alignment: .any).first

        guard let result else { return nil }

        let origin = result.worldTransform.columns.3.xyz
        var normal: SIMD3<Float>
        if let planeAnchor = result.anchor as? ARPlaneAnchor {
            normal = simd_normalize(planeAnchor.transform.columns.1.xyz)
        } else {
            normal = simd_normalize(result.worldTransform.columns.1.xyz)
        }

        let cameraPosition = frame.camera.transform.columns.3.xyz
        if simd_dot(normal, cameraPosition - origin) < 0 {
            normal *= -1
        }
        return (origin, normal)
    }

    private func intersectScreenPoint(
        _ point: CGPoint,
        planeOrigin: SIMD3<Float>,
        planeNormal: SIMD3<Float>
    ) -> SIMD3<Float>? {
        guard let ray = arView?.ray(through: point) else { return nil }
        let denominator = simd_dot(ray.direction, planeNormal)
        guard abs(denominator) > 0.0001 else { return nil }

        let distance = simd_dot(planeOrigin - ray.origin, planeNormal) / denominator
        guard distance > 0 else { return nil }
        return ray.origin + ray.direction * distance
    }

    private func targetSizeIsReasonable(_ points: [SIMD3<Float>]) -> Bool {
        guard points.count == 4 else { return false }
        let lengths = [
            simd_distance(points[0], points[1]),
            simd_distance(points[1], points[2]),
            simd_distance(points[2], points[3]),
            simd_distance(points[3], points[0])
        ]
        guard let smallest = lengths.min(), let largest = lengths.max() else { return false }
        return smallest > 0.015 && largest < 6
    }

    private func updateProjection(using frame: ARFrame) {
        guard let arView,
              arView.bounds.width > 0,
              arView.bounds.height > 0 else { return }

        let viewportSize = arView.bounds.size
        let orientation = interfaceOrientation

        let rawHorizon = gravityHorizonAngle(
            frame: frame,
            orientation: orientation,
            viewportSize: viewportSize
        )
        updateStableHorizon(rawHorizon)
        screenReferenceAxes = makeScreenReferenceAxes(
            center: CGPoint(x: viewportSize.width / 2, y: viewportSize.height / 2),
            horizonAngle: horizonAngleDegrees,
            viewportSize: viewportSize
        )

        if let worldTarget {
            let projected = worldTarget.corners.map {
                frame.camera.projectPoint($0, orientation: orientation, viewportSize: viewportSize)
            }

            guard projected.allSatisfy({ $0.x.isFinite && $0.y.isFinite }) else { return }
            let stableCorners = smooth(points: projected)
            let metrics = targetMetrics(
                worldCorners: worldTarget.corners,
                planeNormal: worldTarget.planeNormal
            )

            let horizontalLine = LevelLine(
                start: stableCorners[metrics.horizontalEdge.0],
                end: stableCorners[metrics.horizontalEdge.1]
            )
            let verticalLine = LevelLine(
                start: stableCorners[metrics.verticalEdge.0],
                end: stableCorners[metrics.verticalEdge.1]
            )
            let center = averagePoint(stableCorners)

            wallReferenceAxes = projectWorldAxes(
                origin: metrics.center,
                horizontalAxis: metrics.horizontalAxis,
                verticalAxis: metrics.verticalAxis,
                frame: frame,
                orientation: orientation,
                viewportSize: viewportSize
            )

            target = TrackedLevelTarget(
                corners: stableCorners,
                horizontalLine: horizontalLine,
                verticalLine: verticalLine,
                center: center,
                measurement: LevelMeasurement(
                    signedHorizontalDeviation: metrics.horizontalDeviation,
                    signedVerticalDeviation: metrics.verticalDeviation
                ),
                confidence: worldTarget.confidence,
                sourceText: worldTarget.source.rawValue
            )
            gravityReliabilityText = "مرجع العالم مثبت بالجاذبية"
        } else {
            wallReferenceAxes = nil
            gravityReliabilityText = frame.camera.trackingState.isNormal
                ? "اتجاه الجاذبية ثابت"
                : "انتظر استقرار التتبع"

            if !draftWorldPoints.isEmpty {
                draftCornerPoints = draftWorldPoints.map {
                    frame.camera.projectPoint($0, orientation: orientation, viewportSize: viewportSize)
                }
            }
        }
    }

    private func targetMetrics(
        worldCorners: [SIMD3<Float>],
        planeNormal: SIMD3<Float>
    ) -> (
        center: SIMD3<Float>,
        horizontalAxis: SIMD3<Float>,
        verticalAxis: SIMD3<Float>,
        horizontalEdge: (Int, Int),
        verticalEdge: (Int, Int),
        horizontalDeviation: Double,
        verticalDeviation: Double
    ) {
        let center = worldCorners.reduce(SIMD3<Float>(repeating: 0), +) / Float(worldCorners.count)
        let worldUp = SIMD3<Float>(0, 1, 0)
        var normal = simd_normalize(planeNormal)
        var vertical = worldUp - normal * simd_dot(worldUp, normal)

        if simd_length(vertical) < 0.05 {
            vertical = SIMD3<Float>(0, 0, 1)
        }
        vertical = simd_normalize(vertical)
        if simd_dot(vertical, worldUp) < 0 { vertical *= -1 }

        let horizontal = simd_normalize(simd_cross(vertical, normal))

        let edges = [(0, 1), (1, 2), (2, 3), (3, 0)]
        var bestHorizontal = edges[0]
        var bestHorizontalDeviation = Double.greatestFiniteMagnitude
        var bestVertical = edges[1]
        var bestVerticalDeviation = Double.greatestFiniteMagnitude

        for edge in edges {
            let direction = simd_normalize(worldCorners[edge.1] - worldCorners[edge.0])
            let horizontalDeviation = signedAxisDeviation(direction: direction, primary: horizontal, secondary: vertical)
            let verticalDeviation = signedAxisDeviation(direction: direction, primary: vertical, secondary: horizontal)

            if abs(horizontalDeviation) < abs(bestHorizontalDeviation) {
                bestHorizontalDeviation = horizontalDeviation
                bestHorizontal = edge
            }
            if abs(verticalDeviation) < abs(bestVerticalDeviation) {
                bestVerticalDeviation = verticalDeviation
                bestVertical = edge
            }
        }

        return (
            center,
            horizontal,
            vertical,
            bestHorizontal,
            bestVertical,
            bestHorizontalDeviation,
            bestVerticalDeviation
        )
    }

    private func signedAxisDeviation(
        direction: SIMD3<Float>,
        primary: SIMD3<Float>,
        secondary: SIMD3<Float>
    ) -> Double {
        var direction = direction
        if simd_dot(direction, primary) < 0 { direction *= -1 }
        return Double(atan2(simd_dot(direction, secondary), simd_dot(direction, primary))) * 180 / .pi
    }

    private func gravityHorizonAngle(
        frame: ARFrame,
        orientation: UIInterfaceOrientation,
        viewportSize: CGSize
    ) -> Double {
        let transform = frame.camera.transform
        let position = transform.columns.3.xyz
        let forward = simd_normalize(-transform.columns.2.xyz)
        let worldUp = SIMD3<Float>(0, 1, 0)
        let origin = position + forward * 2

        let lower = frame.camera.projectPoint(
            origin - worldUp * 0.35,
            orientation: orientation,
            viewportSize: viewportSize
        )
        let upper = frame.camera.projectPoint(
            origin + worldUp * 0.35,
            orientation: orientation,
            viewportSize: viewportSize
        )

        guard lower.x.isFinite, lower.y.isFinite, upper.x.isFinite, upper.y.isFinite else {
            return horizonAngleDegrees
        }

        let verticalAngle = Double(atan2(upper.y - lower.y, upper.x - lower.x)) * 180 / .pi
        return normalizedAxisAngle(verticalAngle - 90)
    }

    private func makeScreenReferenceAxes(
        center: CGPoint,
        horizonAngle: Double,
        viewportSize: CGSize
    ) -> ProjectedReferenceAxes {
        let length = hypot(viewportSize.width, viewportSize.height) * 1.45
        let horizontal = line(center: center, angleDegrees: horizonAngle, length: length)
        let vertical = line(center: center, angleDegrees: horizonAngle + 90, length: length)
        return ProjectedReferenceAxes(horizontal: horizontal, vertical: vertical, origin: center)
    }

    private func projectWorldAxes(
        origin: SIMD3<Float>,
        horizontalAxis: SIMD3<Float>,
        verticalAxis: SIMD3<Float>,
        frame: ARFrame,
        orientation: UIInterfaceOrientation,
        viewportSize: CGSize
    ) -> ProjectedReferenceAxes? {
        let halfLength: Float = 0.55
        let horizontalStart = frame.camera.projectPoint(
            origin - horizontalAxis * halfLength,
            orientation: orientation,
            viewportSize: viewportSize
        )
        let horizontalEnd = frame.camera.projectPoint(
            origin + horizontalAxis * halfLength,
            orientation: orientation,
            viewportSize: viewportSize
        )
        let verticalStart = frame.camera.projectPoint(
            origin - verticalAxis * halfLength,
            orientation: orientation,
            viewportSize: viewportSize
        )
        let verticalEnd = frame.camera.projectPoint(
            origin + verticalAxis * halfLength,
            orientation: orientation,
            viewportSize: viewportSize
        )
        let center = frame.camera.projectPoint(origin, orientation: orientation, viewportSize: viewportSize)

        let points = [horizontalStart, horizontalEnd, verticalStart, verticalEnd, center]
        guard points.allSatisfy({ $0.x.isFinite && $0.y.isFinite }) else { return nil }

        return ProjectedReferenceAxes(
            horizontal: LevelLine(start: horizontalStart, end: horizontalEnd),
            vertical: LevelLine(start: verticalStart, end: verticalEnd),
            origin: center
        )
    }

    private func line(center: CGPoint, angleDegrees: Double, length: CGFloat) -> LevelLine {
        let radians = angleDegrees * .pi / 180
        let half = length / 2
        let offset = CGPoint(x: CGFloat(cos(radians)) * half, y: CGFloat(sin(radians)) * half)
        return LevelLine(
            start: CGPoint(x: center.x - offset.x, y: center.y - offset.y),
            end: CGPoint(x: center.x + offset.x, y: center.y + offset.y)
        )
    }

    private func updateStableHorizon(_ rawAngle: Double) {
        guard rawAngle.isFinite else { return }
        guard let current = smoothedHorizonAngle else {
            smoothedHorizonAngle = rawAngle
            horizonAngleDegrees = rawAngle
            return
        }

        let delta = normalizedAxisAngle(rawAngle - current)
        if abs(delta) < 0.12 {
            return
        }

        let alpha: Double
        switch abs(delta) {
        case 0..<0.5: alpha = 0.10
        case 0.5..<2.0: alpha = 0.35
        default: alpha = 0.75
        }

        let updated = normalizedAxisAngle(current + delta * alpha)
        smoothedHorizonAngle = updated
        horizonAngleDegrees = updated
    }

    private func smooth(points: [CGPoint]) -> [CGPoint] {
        guard let previous = smoothedCorners, previous.count == points.count else {
            smoothedCorners = points
            return points
        }

        let alpha: CGFloat = 0.22
        let updated = zip(previous, points).map { old, new -> CGPoint in
            let distance = hypot(new.x - old.x, new.y - old.y)
            if distance < 0.45 { return old }
            return CGPoint(
                x: old.x + (new.x - old.x) * alpha,
                y: old.y + (new.y - old.y) * alpha
            )
        }
        smoothedCorners = updated
        return updated
    }

    private func scheduleVisionTracking(for frame: ARFrame) {
        guard !trackingInFlight,
              let worldTarget,
              let observation = worldTarget.observation,
              frame.timestamp - lastTrackingTime >= 0.08,
              let arView else { return }

        trackingInFlight = true
        lastTrackingTime = frame.timestamp

        let viewportSize = arView.bounds.size
        let orientation = interfaceOrientation
        let displayTransform = frame.displayTransform(for: orientation, viewportSize: viewportSize)
        let pixelBuffer = frame.capturedImage
        let planeOrigin = worldTarget.planeOrigin
        let planeNormal = worldTarget.planeNormal

        visionQueue.async { [weak self] in
            guard let self else { return }

            let request = VNTrackRectangleRequest(rectangleObservation: observation)
            request.trackingLevel = .accurate
            request.isLastFrame = false

            do {
                try self.sequenceHandler.perform([request], on: pixelBuffer, orientation: .up)
                let result = request.results?.first as? VNRectangleObservation

                DispatchQueue.main.async {
                    self.trackingInFlight = false
                    guard let result, result.confidence >= 0.25 else {
                        self.isTrackingTarget = false
                        self.statusMessage = "التتبع البصري ضعيف؛ الرسم ما زال مثبتًا بالموقع"
                        return
                    }

                    let screenCorners = self.screenPoints(
                        for: result,
                        displayTransform: displayTransform,
                        viewportSize: viewportSize
                    )
                    let updatedWorld = screenCorners.compactMap {
                        self.intersectScreenPoint($0, planeOrigin: planeOrigin, planeNormal: planeNormal)
                    }

                    guard updatedWorld.count == 4,
                          self.targetSizeIsReasonable(updatedWorld),
                          var currentTarget = self.worldTarget else {
                        self.isTrackingTarget = false
                        return
                    }

                    let blend: Float = result.confidence > 0.7 ? 0.32 : 0.18
                    currentTarget.corners = zip(currentTarget.corners, updatedWorld).map { old, new in
                        old + (new - old) * blend
                    }
                    currentTarget.observation = result
                    currentTarget.confidence = result.confidence
                    self.worldTarget = currentTarget
                    self.isTrackingTarget = true
                    self.statusMessage = "العنصر مثبت ويتتبع بصريًا"
                    self.updateProjection(using: frame)
                }
            } catch {
                DispatchQueue.main.async {
                    self.trackingInFlight = false
                    self.isTrackingTarget = false
                }
            }
        }
    }

    private func screenPoints(
        for observation: VNRectangleObservation,
        displayTransform: CGAffineTransform,
        viewportSize: CGSize
    ) -> [CGPoint] {
        [
            convertVisionPoint(observation.topLeft, using: displayTransform, viewportSize: viewportSize),
            convertVisionPoint(observation.topRight, using: displayTransform, viewportSize: viewportSize),
            convertVisionPoint(observation.bottomRight, using: displayTransform, viewportSize: viewportSize),
            convertVisionPoint(observation.bottomLeft, using: displayTransform, viewportSize: viewportSize)
        ]
    }

    private func convertVisionPoint(
        _ point: CGPoint,
        using displayTransform: CGAffineTransform,
        viewportSize: CGSize
    ) -> CGPoint {
        let imagePoint = CGPoint(x: point.x, y: 1 - point.y)
        let viewPoint = imagePoint.applying(displayTransform)
        return CGPoint(x: viewPoint.x * viewportSize.width, y: viewPoint.y * viewportSize.height)
    }

    private func visionPoint(
        fromScreenPoint point: CGPoint,
        displayTransform: CGAffineTransform,
        viewportSize: CGSize
    ) -> CGPoint {
        let normalizedView = CGPoint(
            x: point.x / max(viewportSize.width, 1),
            y: point.y / max(viewportSize.height, 1)
        )
        let imagePoint = normalizedView.applying(displayTransform.inverted())
        return CGPoint(
            x: min(max(imagePoint.x, 0), 1),
            y: min(max(1 - imagePoint.y, 0), 1)
        )
    }

    private func regionOfInterest(around point: CGPoint) -> CGRect {
        let width: CGFloat = 0.64
        let height: CGFloat = 0.64
        return CGRect(
            x: min(max(point.x - width / 2, 0), 1 - width),
            y: min(max(point.y - height / 2, 0), 1 - height),
            width: width,
            height: height
        )
    }

    private func makeVisionObservation(fromScreenPoints points: [CGPoint], frame: ARFrame) -> VNRectangleObservation? {
        guard let arView, points.count == 4 else { return nil }
        let viewportSize = arView.bounds.size
        let transform = frame.displayTransform(for: interfaceOrientation, viewportSize: viewportSize)
        let vision = points.map {
            visionPoint(fromScreenPoint: $0, displayTransform: transform, viewportSize: viewportSize)
        }
        return VNRectangleObservation(
            requestRevision: VNDetectRectanglesRequestRevision1,
            topLeft: vision[0],
            topRight: vision[1],
            bottomRight: vision[2],
            bottomLeft: vision[3]
        )
    }

    private func orderCorners(
        screenPoints: [CGPoint],
        worldPoints: [SIMD3<Float>]
    ) -> (screen: [CGPoint], world: [SIMD3<Float>]) {
        let pairs = zip(screenPoints, worldPoints).map { (screen: $0.0, world: $0.1) }
        let sortedByY = pairs.sorted { $0.screen.y < $1.screen.y }
        let top = sortedByY.prefix(2).sorted { $0.screen.x < $1.screen.x }
        let bottom = sortedByY.suffix(2).sorted { $0.screen.x < $1.screen.x }

        let ordered = [top[0], top[1], bottom[1], bottom[0]]
        return (ordered.map(\.screen), ordered.map(\.world))
    }

    private func polygonPath(_ points: [CGPoint]) -> CGPath {
        let path = CGMutablePath()
        guard let first = points.first else { return path }
        path.move(to: first)
        for point in points.dropFirst() { path.addLine(to: point) }
        path.closeSubpath()
        return path
    }

    private func polygonArea(_ points: [CGPoint]) -> CGFloat {
        guard points.count >= 3 else { return 0 }
        var sum: CGFloat = 0
        for index in points.indices {
            let next = points[(index + 1) % points.count]
            sum += points[index].x * next.y - next.x * points[index].y
        }
        return abs(sum) / 2
    }

    private func averagePoint(_ points: [CGPoint]) -> CGPoint {
        guard !points.isEmpty else { return .zero }
        return CGPoint(
            x: points.map(\.x).reduce(0, +) / CGFloat(points.count),
            y: points.map(\.y).reduce(0, +) / CGFloat(points.count)
        )
    }

    private func normalizedAxisAngle(_ angle: Double) -> Double {
        var value = angle
        while value > 90 { value -= 180 }
        while value < -90 { value += 180 }
        return value
    }

    private var interfaceOrientation: UIInterfaceOrientation {
        arView?.window?.windowScene?.interfaceOrientation ?? .portrait
    }

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.latestFrame = frame
            self.updateProjection(using: frame)
            self.scheduleVisionTracking(for: frame)
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

private extension SIMD4 where Scalar == Float {
    var xyz: SIMD3<Float> {
        SIMD3<Float>(x, y, z)
    }
}

private extension ARCamera.TrackingState {
    var isNormal: Bool {
        if case .normal = self { return true }
        return false
    }
}
