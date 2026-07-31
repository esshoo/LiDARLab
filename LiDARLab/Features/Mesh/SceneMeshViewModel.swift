import ARKit
import Combine
import RealityKit

final class SceneMeshViewModel: NSObject, ObservableObject, ARSessionDelegate {
    @Published private(set) var anchorCount = 0
    @Published private(set) var vertexCount = 0
    @Published private(set) var faceCount = 0
    @Published private(set) var trackingState = "بدء التتبع"
    @Published private(set) var errorMessage: String?

    private weak var arView: ARView?
    private var lastStatisticsUpdate: TimeInterval = 0

    func attach(to arView: ARView) {
        self.arView = arView
        arView.session.delegate = self
        run(reset: true)
    }

    func run(reset: Bool) {
        guard ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) else {
            errorMessage = "Scene Mesh غير مدعوم على هذا الجهاز."
            return
        }

        let configuration = ARWorldTrackingConfiguration()
        configuration.worldAlignment = .gravity
        configuration.planeDetection = [.horizontal, .vertical]
        configuration.sceneReconstruction = ARWorldTrackingConfiguration.supportsSceneReconstruction(.meshWithClassification)
            ? .meshWithClassification
            : .mesh

        let options: ARSession.RunOptions = reset ? [.resetTracking, .removeExistingAnchors] : []
        arView?.session.run(configuration, options: options)
    }

    func stop() {
        arView?.session.pause()
    }

    func clearError() {
        errorMessage = nil
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

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        guard frame.timestamp - lastStatisticsUpdate >= 0.5 else { return }
        lastStatisticsUpdate = frame.timestamp

        let meshAnchors = frame.anchors.compactMap { $0 as? ARMeshAnchor }
        let vertices = meshAnchors.reduce(0) { $0 + $1.geometry.vertices.count }
        let faces = meshAnchors.reduce(0) { $0 + $1.geometry.faces.count }

        DispatchQueue.main.async { [weak self] in
            self?.anchorCount = meshAnchors.count
            self?.vertexCount = vertices
            self?.faceCount = faces
        }
    }

    func session(_ session: ARSession, didFailWithError error: Error) {
        DispatchQueue.main.async { [weak self] in
            self?.errorMessage = error.localizedDescription
        }
    }
}
