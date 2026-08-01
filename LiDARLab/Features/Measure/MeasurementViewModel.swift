import ARKit
import Combine
import Foundation
import RealityKit
import UIKit
import simd

final class MeasurementViewModel: NSObject, ObservableObject, ARSessionDelegate {
    @Published private(set) var projection = MeasurementProjection(points: [], segments: [])
    @Published private(set) var pointCount = 0
    @Published private(set) var totalDirectMeters: Double = 0
    @Published private(set) var totalHorizontalMeters: Double = 0
    @Published private(set) var totalVerticalMeters: Double = 0
    @Published private(set) var latestSegment: MeasurementSegmentRecord?
    @Published private(set) var trackingState = "تهيئة"
    @Published private(set) var statusMessage = "حرّك الجهاز ببطء ثم أضف النقطة الأولى"
    @Published private(set) var isClosedPath = false
    @Published private(set) var isSaving = false
    @Published private(set) var latestSavedItems: [Any] = []
    @Published private(set) var errorMessage: String?

    private weak var arView: ARView?
    private var worldPoints: [SIMD3<Float>] = []

    func attach(to arView: ARView) {
        self.arView = arView
        arView.automaticallyConfigureSession = false
        arView.session.delegate = self
        startSession(resetTracking: true)
    }

    func startSession(resetTracking: Bool) {
        guard ARWorldTrackingConfiguration.isSupported else {
            errorMessage = "تتبع الواقع المعزز غير مدعوم على هذا الجهاز."
            return
        }

        let configuration = ARWorldTrackingConfiguration()
        configuration.worldAlignment = .gravity
        configuration.planeDetection = [.horizontal, .vertical]
        if ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) {
            configuration.frameSemantics.insert(.sceneDepth)
        }

        let options: ARSession.RunOptions = resetTracking ? [.resetTracking, .removeExistingAnchors] : []
        arView?.session.run(configuration, options: options)
        if resetTracking {
            clear()
            statusMessage = "أُعيد التتبع؛ حرّك الجهاز ببطء ثم أضف النقطة الأولى"
        }
    }

    func stop() {
        arView?.session.pause()
    }

    func addPointAtCenter() {
        guard let arView else { return }
        let center = CGPoint(x: arView.bounds.midX, y: arView.bounds.midY)
        addPoint(at: center)
    }

    func addPoint(at screenPoint: CGPoint) {
        guard let arView else { return }

        if isClosedPath {
            clear()
        }

        let result = arView.raycast(
            from: screenPoint,
            allowing: .existingPlaneGeometry,
            alignment: .any
        ).first
            ?? arView.raycast(
                from: screenPoint,
                allowing: .existingPlaneInfinite,
                alignment: .any
            ).first
            ?? arView.raycast(
                from: screenPoint,
                allowing: .estimatedPlane,
                alignment: .any
            ).first

        guard let result else {
            statusMessage = "لم يُكتشف سطح عند المؤشر. حرّك الجهاز ببطء وحاول مرة أخرى."
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
            return
        }

        let translation = result.worldTransform.columns.3
        worldPoints.append(SIMD3<Float>(translation.x, translation.y, translation.z))
        recalculate()
        updateProjection()
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    func undo() {
        guard !worldPoints.isEmpty else { return }
        if isClosedPath {
            isClosedPath = false
        } else {
            worldPoints.removeLast()
        }
        recalculate()
        updateProjection()
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
    }

    func clear() {
        worldPoints.removeAll()
        isClosedPath = false
        projection = MeasurementProjection(points: [], segments: [])
        recalculate()
    }

    func toggleClosedPath() {
        guard worldPoints.count >= 3 else {
            statusMessage = "تحتاج إلى ثلاث نقاط على الأقل لإغلاق المسار."
            return
        }
        isClosedPath.toggle()
        recalculate()
        updateProjection()
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    func clearError() {
        errorMessage = nil
    }

    func clearSavedItems() {
        latestSavedItems = []
    }

    func saveMeasurement(named proposedName: String) {
        guard worldPoints.count >= 2 else {
            errorMessage = "أضف نقطتين على الأقل قبل الحفظ."
            return
        }
        guard !isSaving else { return }

        isSaving = true
        latestSavedItems = []

        do {
            let storage = LiDARLabStorage.shared
            try storage.ensureDirectories()
            let cleanName = storage.sanitizedName(proposedName, fallback: "Measurement")
            let measurementId = UUID()
            let folderName = "\(storage.timestampedName(prefix: cleanName))-\(measurementId.uuidString.prefix(8))"
            let folderURL = storage.measurementsURL.appendingPathComponent(folderName, isDirectory: true)
            try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)

            let now = Date()
            let segmentRecords = makeSegments()
            let document = MeasurementDocument(
                schemaVersion: 1,
                measurementId: measurementId,
                name: cleanName,
                createdAt: now,
                updatedAt: now,
                appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown",
                isClosedPath: isClosedPath,
                points: worldPoints.map { MeasurementVector3($0) },
                segments: segmentRecords,
                totalDirectMeters: segmentRecords.reduce(0) { $0 + $1.directMeters },
                totalHorizontalMeters: segmentRecords.reduce(0) { $0 + $1.horizontalMeters },
                totalVerticalMeters: segmentRecords.reduce(0) { $0 + $1.verticalMeters },
                trackingStateAtSave: trackingState
            )

            let jsonURL = folderURL.appendingPathComponent("measurement.json")
            let csvURL = folderURL.appendingPathComponent("segments.csv")
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(document).write(to: jsonURL, options: .atomic)
            try makeCSV(document.segments).write(to: csvURL, atomically: true, encoding: .utf8)

            guard let arView else {
                finishSaving(items: [jsonURL, csvURL], message: "تم حفظ القياس بصيغتي JSON وCSV.")
                return
            }

            arView.snapshot(saveToHDR: false) { [weak self] image in
                guard let self else { return }
                var items: [Any] = [jsonURL, csvURL]
                if let image,
                   let data = image.jpegData(compressionQuality: 0.90) {
                    let imageURL = folderURL.appendingPathComponent("preview.jpg")
                    do {
                        try data.write(to: imageURL, options: .atomic)
                        items.append(imageURL)
                    } catch {
                        DispatchQueue.main.async {
                            self.errorMessage = "تم حفظ القياس، لكن تعذر حفظ صورة المعاينة: \(error.localizedDescription)"
                        }
                    }
                }
                self.finishSaving(items: items, message: "تم حفظ القياس وصورة المشهد بنجاح.")
            }
        } catch {
            isSaving = false
            errorMessage = error.localizedDescription
        }
    }

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        DispatchQueue.main.async { [weak self] in
            self?.updateProjection(frame: frame)
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

    private func recalculate() {
        pointCount = worldPoints.count
        let segments = makeSegments()
        latestSegment = segments.last
        totalDirectMeters = segments.reduce(0) { $0 + $1.directMeters }
        totalHorizontalMeters = segments.reduce(0) { $0 + $1.horizontalMeters }
        totalVerticalMeters = segments.reduce(0) { $0 + $1.verticalMeters }

        switch worldPoints.count {
        case 0:
            statusMessage = "حرّك الجهاز ببطء ثم أضف النقطة الأولى"
        case 1:
            statusMessage = "أضف النقطة الثانية لبدء القياس"
        default:
            statusMessage = isClosedPath
                ? "المسار مغلق. اضغط إضافة نقطة لبدء قياس جديد."
                : "أضف نقاطًا أخرى أو احفظ القياس الحالي"
        }
    }

    private func makeSegments() -> [MeasurementSegmentRecord] {
        guard worldPoints.count >= 2 else { return [] }
        var pairs: [(Int, Int)] = (0..<(worldPoints.count - 1)).map { ($0, $0 + 1) }
        if isClosedPath, worldPoints.count >= 3 {
            pairs.append((worldPoints.count - 1, 0))
        }

        return pairs.enumerated().map { offset, pair in
            let start = worldPoints[pair.0]
            let end = worldPoints[pair.1]
            let delta = end - start
            return MeasurementSegmentRecord(
                index: offset + 1,
                startPointIndex: pair.0,
                endPointIndex: pair.1,
                directMeters: Double(simd_length(delta)),
                horizontalMeters: Double(simd_length(SIMD2<Float>(delta.x, delta.z))),
                verticalMeters: Double(abs(delta.y))
            )
        }
    }

    private func updateProjection(frame: ARFrame? = nil) {
        guard let arView,
              let frame = frame ?? arView.session.currentFrame,
              arView.bounds.width > 0,
              arView.bounds.height > 0 else { return }

        let orientation = arView.window?.windowScene?.interfaceOrientation ?? .portrait
        let viewportSize = arView.bounds.size
        let projectedPoints = worldPoints.enumerated().compactMap { index, point -> ProjectedMeasurementPoint? in
            let projected = frame.camera.projectPoint(point, orientation: orientation, viewportSize: viewportSize)
            guard projected.x.isFinite, projected.y.isFinite else { return nil }
            return ProjectedMeasurementPoint(index: index, screenPoint: projected)
        }

        guard projectedPoints.count == worldPoints.count else { return }
        let byIndex = Dictionary(uniqueKeysWithValues: projectedPoints.map { ($0.index, $0.screenPoint) })
        let projectedSegments = makeSegments().compactMap { segment -> ProjectedMeasurementSegment? in
            guard let start = byIndex[segment.startPointIndex],
                  let end = byIndex[segment.endPointIndex] else { return nil }
            return ProjectedMeasurementSegment(
                index: segment.index,
                start: start,
                end: end,
                directMeters: segment.directMeters,
                horizontalMeters: segment.horizontalMeters,
                verticalMeters: segment.verticalMeters
            )
        }
        projection = MeasurementProjection(points: projectedPoints, segments: projectedSegments)
    }

    private func makeCSV(_ segments: [MeasurementSegmentRecord]) -> String {
        var lines = ["segment,start_point,end_point,direct_m,horizontal_m,vertical_m"]
        for segment in segments {
            lines.append([
                String(segment.index),
                String(segment.startPointIndex + 1),
                String(segment.endPointIndex + 1),
                String(format: "%.6f", segment.directMeters),
                String(format: "%.6f", segment.horizontalMeters),
                String(format: "%.6f", segment.verticalMeters)
            ].joined(separator: ","))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private func finishSaving(items: [Any], message: String) {
        DispatchQueue.main.async { [weak self] in
            self?.isSaving = false
            self?.latestSavedItems = items
            self?.statusMessage = message
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
    }
}
