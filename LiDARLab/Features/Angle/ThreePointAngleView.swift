import ARKit
import RealityKit
import SwiftUI
import UIKit
import simd

private struct ProjectedAngleMeasurement: Equatable {
    let points: [CGPoint]
    let angleDegrees: Double?
}

private final class ThreePointAngleViewModel: NSObject, ObservableObject, ARSessionDelegate {
    @Published private(set) var projection = ProjectedAngleMeasurement(points: [], angleDegrees: nil)
    @Published private(set) var trackingState = "تهيئة"
    @Published private(set) var statusMessage = "حدد النقطة الأولى"
    @Published private(set) var errorMessage: String?

    private weak var arView: ARView?
    private var worldPoints: [SIMD3<Float>] = []

    var pointCount: Int { worldPoints.count }

    func attach(to arView: ARView) {
        self.arView = arView
        arView.automaticallyConfigureSession = false
        arView.session.delegate = self

        guard ARWorldTrackingConfiguration.isSupported else {
            errorMessage = "تتبع الواقع المعزز غير مدعوم على هذا الجهاز."
            return
        }

        let configuration = ARWorldTrackingConfiguration()
        configuration.worldAlignment = .gravity
        configuration.planeDetection = [.horizontal, .vertical]
        arView.session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
    }

    func stop() {
        arView?.session.pause()
    }

    func clearError() {
        errorMessage = nil
    }

    func reset() {
        worldPoints.removeAll()
        projection = ProjectedAngleMeasurement(points: [], angleDegrees: nil)
        statusMessage = "حدد النقطة الأولى"
    }

    func undo() {
        guard !worldPoints.isEmpty else { return }
        worldPoints.removeLast()
        updateStatus()
        updateProjection()
    }

    func addPoint(at screenPoint: CGPoint) {
        guard let arView else { return }

        if worldPoints.count == 3 {
            reset()
        }

        let result = arView.raycast(from: screenPoint, allowing: .existingPlaneGeometry, alignment: .any).first
            ?? arView.raycast(from: screenPoint, allowing: .existingPlaneInfinite, alignment: .any).first
            ?? arView.raycast(from: screenPoint, allowing: .estimatedPlane, alignment: .any).first

        guard let result else {
            statusMessage = "لم يُكتشف سطح عند هذه النقطة؛ حرّك الجهاز ببطء وحاول مرة أخرى"
            return
        }

        let column = result.worldTransform.columns.3
        worldPoints.append(SIMD3<Float>(column.x, column.y, column.z))
        updateStatus()
        updateProjection()
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func updateStatus() {
        switch worldPoints.count {
        case 0:
            statusMessage = "حدد النقطة الأولى"
        case 1:
            statusMessage = "حدد رأس الزاوية"
        case 2:
            statusMessage = "حدد النقطة الثالثة"
        default:
            statusMessage = "تم القياس؛ اضغط نقطة جديدة لبدء قياس آخر"
        }
    }

    private func measuredAngle() -> Double? {
        guard worldPoints.count == 3 else { return nil }
        let first = worldPoints[0] - worldPoints[1]
        let second = worldPoints[2] - worldPoints[1]
        let firstLength = simd_length(first)
        let secondLength = simd_length(second)
        guard firstLength > 0.0001, secondLength > 0.0001 else { return nil }

        let cosine = min(max(simd_dot(first / firstLength, second / secondLength), -1), 1)
        return Double(acos(cosine)) * 180 / .pi
    }

    private func updateProjection(frame: ARFrame? = nil) {
        guard let arView,
              let frame = frame ?? arView.session.currentFrame,
              arView.bounds.width > 0,
              arView.bounds.height > 0 else { return }

        let orientation = arView.window?.windowScene?.interfaceOrientation ?? .portrait
        let viewportSize = arView.bounds.size
        let screenPoints = worldPoints.map {
            frame.camera.projectPoint($0, orientation: orientation, viewportSize: viewportSize)
        }
        guard screenPoints.allSatisfy({ $0.x.isFinite && $0.y.isFinite }) else { return }
        projection = ProjectedAngleMeasurement(points: screenPoints, angleDegrees: measuredAngle())
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
}

struct ThreePointAngleView: View {
    private enum Panel { case help, result }

    @StateObject private var model = ThreePointAngleViewModel()
    @State private var panel: Panel?

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                ThreePointAngleARContainer(model: model)
                    .ignoresSafeArea(edges: .bottom)

                AngleMeasurementOverlay(projection: model.projection)
                    .allowsHitTesting(false)

                VStack {
                    HStack {
                        LiveCameraStatusBadge(
                            title: model.statusMessage,
                            detail: "\(model.pointCount)/3 • AR: \(model.trackingState)",
                            systemImage: "angle",
                            accent: .orange
                        )
                        Spacer()
                    }
                    .padding(.leading, 12)
                    .padding(.top, 10)
                    Spacer()
                }

                HStack {
                    Spacer()
                    LiveCameraSideRail {
                        LiveCameraSideButton(systemImage: "questionmark.circle", accessibilityLabel: "طريقة الاستخدام", isSelected: panel == .help) { toggle(.help) }
                        LiveCameraSideButton(systemImage: "angle", accessibilityLabel: "النتيجة", isSelected: panel == .result) { toggle(.result) }
                        LiveCameraSideButton(systemImage: "arrow.uturn.backward", accessibilityLabel: "تراجع", isEnabled: model.pointCount > 0) { model.undo() }
                        LiveCameraSideButton(systemImage: "trash", accessibilityLabel: "مسح القياس", tint: .red, isEnabled: model.pointCount > 0) { model.reset() }
                    }
                    .padding(.trailing, 10)
                }

                if let panel {
                    HStack {
                        Spacer()
                        panelView(panel).padding(.trailing, 72)
                    }
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                }

                VStack {
                    Spacer()
                    LiveCameraStatusBadge(
                        title: model.projection.angleDegrees.map { String(format: "%.2f°", $0) } ?? "اضغط على السطح لتحديد النقاط",
                        detail: model.projection.angleDegrees == nil ? "الضلع الأول ← رأس الزاوية ← الضلع الثاني" : "تم القياس",
                        systemImage: "scope",
                        accent: model.projection.angleDegrees == nil ? .cyan : .green
                    )
                    .padding(.bottom, 12)
                }
            }
            .animation(.easeInOut(duration: 0.18), value: panel != nil)
        }
        .background(.black)
        .navigationTitle("قياس الزوايا")
        .navigationBarTitleDisplayMode(.inline)
        .keepScreenAwakeForLiveTool(id: "measure.angle")
        .onDisappear { model.stop() }
        .alert("تعذر تشغيل قياس الزوايا", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.clearError() } }
        )) {
            Button("حسنًا", role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "خطأ غير معروف")
        }
    }

    private func toggle(_ newPanel: Panel) { panel = panel == newPanel ? nil : newPanel }

    @ViewBuilder
    private func panelView(_ panel: Panel) -> some View {
        switch panel {
        case .help:
            LiveCameraFloatingPanel(title: "طريقة القياس", systemImage: "questionmark.circle", onClose: { self.panel = nil }) {
                VStack(alignment: .leading, spacing: 8) {
                    Label("اضغط النقطة الأولى على الضلع الأول", systemImage: "1.circle")
                    Label("اضغط رأس الزاوية", systemImage: "2.circle")
                    Label("اضغط النقطة الثالثة على الضلع الثاني", systemImage: "3.circle")
                    Text("النقاط تثبت في العالم الحقيقي. لو لم يُكتشف السطح، حرّك الجهاز ببطء حتى يتحسن تتبع AR.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        case .result:
            LiveCameraFloatingPanel(title: "النتيجة", systemImage: "angle", onClose: { self.panel = nil }) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(model.projection.angleDegrees.map { String(format: "%.2f°", $0) } ?? "—")
                        .font(.system(.largeTitle, design: .rounded).monospacedDigit().bold())
                    LabeledContent("النقاط", value: "\(model.pointCount) / 3")
                    LabeledContent("حالة التتبع", value: model.trackingState)
                }
            }
        }
    }
}

private struct AngleMeasurementOverlay: View {
    let projection: ProjectedAngleMeasurement

    var body: some View {
        Canvas { context, _ in
            let points = projection.points
            guard !points.isEmpty else { return }

            if points.count >= 2 {
                var firstLine = Path()
                firstLine.move(to: points[0])
                firstLine.addLine(to: points[1])
                context.stroke(firstLine, with: .color(.orange), style: StrokeStyle(lineWidth: 4, lineCap: .round))
            }

            if points.count >= 3 {
                var secondLine = Path()
                secondLine.move(to: points[1])
                secondLine.addLine(to: points[2])
                context.stroke(secondLine, with: .color(.cyan), style: StrokeStyle(lineWidth: 4, lineCap: .round))
            }

            for (index, point) in points.enumerated() {
                let color: Color = index == 1 ? .yellow : (index == 0 ? .orange : .cyan)
                context.fill(
                    Path(ellipseIn: CGRect(x: point.x - 8, y: point.y - 8, width: 16, height: 16)),
                    with: .color(color)
                )
                context.draw(
                    Text("\(index + 1)").font(.caption2.bold()).foregroundStyle(.black),
                    at: point
                )
            }
        }
        .overlay {
            if projection.points.count == 3,
               let angle = projection.angleDegrees {
                Text(String(format: "%.2f°", angle))
                    .font(.headline.monospacedDigit().bold())
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.ultraThinMaterial, in: Capsule())
                    .overlay(Capsule().stroke(.yellow, lineWidth: 1.5))
                    .position(projection.points[1])
                    .offset(y: -28)
            }
        }
    }
}

private struct ThreePointAngleARContainer: UIViewRepresentable {
    @ObservedObject var model: ThreePointAngleViewModel

    func makeCoordinator() -> Coordinator {
        Coordinator(model: model)
    }

    func makeUIView(context: Context) -> ARView {
        let view = ARView(frame: .zero)
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.didTap(_:)))
        view.addGestureRecognizer(tap)
        context.coordinator.arView = view
        model.attach(to: view)
        return view
    }

    func updateUIView(_ uiView: ARView, context: Context) {}

    final class Coordinator: NSObject {
        let model: ThreePointAngleViewModel
        weak var arView: ARView?

        init(model: ThreePointAngleViewModel) {
            self.model = model
        }

        @objc func didTap(_ recognizer: UITapGestureRecognizer) {
            guard let arView else { return }
            model.addPoint(at: recognizer.location(in: arView))
        }
    }
}
