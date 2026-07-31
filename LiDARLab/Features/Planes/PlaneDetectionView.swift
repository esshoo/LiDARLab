import ARKit
import RealityKit
import SwiftUI
import simd

private enum PlaneFilter: String, CaseIterable, Identifiable {
    case all
    case horizontal
    case vertical

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "الكل"
        case .horizontal: "أفقي"
        case .vertical: "رأسي"
        }
    }
}

private struct PlaneScreenOverlay: Identifiable, Equatable {
    let id: UUID
    let points: [CGPoint]
    let center: CGPoint
    let alignment: ARPlaneAnchor.Alignment
    let classificationText: String
    let width: Float
    let height: Float
}

struct PlaneDetectionView: View {
    @StateObject private var model = PlaneDetectionViewModel()
    @State private var filter: PlaneFilter = .all

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                PlaneDetectionARViewContainer(model: model)
                    .ignoresSafeArea(edges: .bottom)

                PlaneOverlaysCanvas(overlays: visibleOverlays)
                    .allowsHitTesting(false)

                VStack(spacing: 12) {
                    controls
                    Spacer()
                    summaryPanel
                }
                .padding(.horizontal, geometry.size.width >= 600 ? 20 : 12)
                .padding(.vertical, 12)
            }
        }
        .background(.black)
        .navigationTitle("اكتشاف المستويات")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { model.stop() }
    }

    private var visibleOverlays: [PlaneScreenOverlay] {
        switch filter {
        case .all:
            model.overlays
        case .horizontal:
            model.overlays.filter { $0.alignment == .horizontal }
        case .vertical:
            model.overlays.filter { $0.alignment == .vertical }
        }
    }

    private var controls: some View {
        VStack(spacing: 10) {
            Picker("نوع السطح", selection: $filter) {
                ForEach(PlaneFilter.allCases) { item in
                    Text(item.title).tag(item)
                }
            }
            .pickerStyle(.segmented)

            HStack {
                Label("التتبع: \(model.trackingState)", systemImage: "location.viewfinder")
                    .font(.caption.bold())
                Spacer()
                Button {
                    model.restart()
                } label: {
                    Label("إعادة المسح", systemImage: "arrow.clockwise")
                        .font(.caption.bold())
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var summaryPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("حرّك الجهاز ببطء أمام الجدران والأرضية حتى تتسع الحدود المكتشفة.")
                .font(.caption)
                .foregroundStyle(.secondary)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 105), spacing: 9)], spacing: 9) {
                MetricChip(title: "كل المستويات", value: "\(model.overlays.count)", systemImage: "square.3.layers.3d")
                MetricChip(title: "أفقية", value: "\(model.horizontalCount)", systemImage: "rectangle.compress.vertical")
                MetricChip(title: "رأسية", value: "\(model.verticalCount)", systemImage: "rectangle.compress.horizontal")
            }
        }
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

private struct PlaneOverlaysCanvas: View {
    let overlays: [PlaneScreenOverlay]

    var body: some View {
        ZStack {
            Canvas { context, _ in
                for overlay in overlays where overlay.points.count == 4 {
                    var path = Path()
                    path.move(to: overlay.points[0])
                    for point in overlay.points.dropFirst() { path.addLine(to: point) }
                    path.closeSubpath()

                    let color: Color = overlay.alignment == .horizontal ? .cyan : .orange
                    context.fill(path, with: .color(color.opacity(0.16)))
                    context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: 2, dash: [7, 5]))
                }
            }

            ForEach(overlays) { overlay in
                Text("\(overlay.classificationText)  \(format(overlay.width)) × \(format(overlay.height)) م")
                    .font(.caption2.monospacedDigit().bold())
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(.ultraThinMaterial, in: Capsule())
                    .position(overlay.center)
            }
        }
    }

    private func format(_ value: Float) -> String {
        String(format: "%.2f", value)
    }
}

private final class PlaneDetectionViewModel: NSObject, ObservableObject, ARSessionDelegate {
    @Published private(set) var overlays: [PlaneScreenOverlay] = []
    @Published private(set) var trackingState = "تهيئة"

    private weak var arView: ARView?
    private var anchors: [UUID: ARPlaneAnchor] = [:]

    var horizontalCount: Int { overlays.filter { $0.alignment == .horizontal }.count }
    var verticalCount: Int { overlays.filter { $0.alignment == .vertical }.count }

    func attach(to arView: ARView) {
        self.arView = arView
        arView.automaticallyConfigureSession = false
        arView.session.delegate = self
        restart()
    }

    func restart() {
        anchors.removeAll()
        overlays = []

        let configuration = ARWorldTrackingConfiguration()
        configuration.worldAlignment = .gravity
        configuration.planeDetection = [.horizontal, .vertical]
        arView?.session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
    }

    func stop() {
        arView?.session.pause()
    }

    func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
        updateAnchors(anchors)
    }

    func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
        updateAnchors(anchors)
    }

    func session(_ session: ARSession, didRemove anchors: [ARAnchor]) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            for anchor in anchors { self.anchors.removeValue(forKey: anchor.identifier) }
        }
    }

    private func updateAnchors(_ updated: [ARAnchor]) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            for case let plane as ARPlaneAnchor in updated {
                self.anchors[plane.identifier] = plane
            }
        }
    }

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        DispatchQueue.main.async { [weak self] in
            self?.projectAnchors(using: frame)
        }
    }

    private func projectAnchors(using frame: ARFrame) {
        guard let arView, arView.bounds.width > 0, arView.bounds.height > 0 else { return }
        let viewport = arView.bounds.size
        let orientation = arView.window?.windowScene?.interfaceOrientation ?? .portrait

        overlays = anchors.values.compactMap { anchor in
            let halfWidth = anchor.extent.x / 2
            let halfHeight = anchor.extent.z / 2
            let center = anchor.center
            let localPoints = [
                SIMD3<Float>(center.x - halfWidth, 0, center.z - halfHeight),
                SIMD3<Float>(center.x + halfWidth, 0, center.z - halfHeight),
                SIMD3<Float>(center.x + halfWidth, 0, center.z + halfHeight),
                SIMD3<Float>(center.x - halfWidth, 0, center.z + halfHeight)
            ]
            let worldPoints = localPoints.map { point -> SIMD3<Float> in
                let world = anchor.transform * SIMD4<Float>(point.x, point.y, point.z, 1)
                return SIMD3<Float>(world.x, world.y, world.z)
            }
            let screenPoints = worldPoints.map {
                frame.camera.projectPoint($0, orientation: orientation, viewportSize: viewport)
            }
            guard screenPoints.allSatisfy({ $0.x.isFinite && $0.y.isFinite }) else { return nil }

            return PlaneScreenOverlay(
                id: anchor.identifier,
                points: screenPoints,
                center: average(screenPoints),
                alignment: anchor.alignment,
                classificationText: classificationText(anchor.classification),
                width: anchor.extent.x,
                height: anchor.extent.z
            )
        }
    }

    private func average(_ points: [CGPoint]) -> CGPoint {
        CGPoint(
            x: points.map(\.x).reduce(0, +) / CGFloat(points.count),
            y: points.map(\.y).reduce(0, +) / CGFloat(points.count)
        )
    }

    private func classificationText(_ classification: ARPlaneAnchor.Classification) -> String {
        switch classification {
        case .wall: "جدار"
        case .floor: "أرضية"
        case .ceiling: "سقف"
        case .table: "طاولة"
        case .seat: "مقعد"
        case .window: "نافذة"
        case .door: "باب"
        case .none: "سطح"
        @unknown default: "سطح"
        }
    }

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
}

private struct PlaneDetectionARViewContainer: UIViewRepresentable {
    @ObservedObject var model: PlaneDetectionViewModel

    func makeUIView(context: Context) -> ARView {
        let view = ARView(frame: .zero)
        model.attach(to: view)
        return view
    }

    func updateUIView(_ uiView: ARView, context: Context) {}

    static func dismantleUIView(_ uiView: ARView, coordinator: Void) {
        uiView.session.pause()
    }
}
