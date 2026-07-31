import ARKit
import Combine
import RealityKit
import UIKit

@MainActor
final class ARPlaygroundViewModel: ObservableObject {
    @Published private(set) var objectCount = 0
    @Published private(set) var statusMessage = "اضغط على سطح لإضافة مكعب"

    private weak var arView: ARView?

    func attach(to arView: ARView) {
        self.arView = arView
        arView.automaticallyConfigureSession = false

        guard ARWorldTrackingConfiguration.isSupported else {
            statusMessage = "AR World Tracking غير مدعوم"
            return
        }

        let configuration = ARWorldTrackingConfiguration()
        configuration.planeDetection = [.horizontal, .vertical]

        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
            configuration.sceneReconstruction = .mesh
            arView.environment.sceneUnderstanding.options.insert(.occlusion)
            arView.environment.sceneUnderstanding.options.insert(.physics)
        }

        arView.session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
    }

    func placeObject(at location: CGPoint) {
        guard let arView else { return }
        guard let result = arView.raycast(from: location, allowing: .estimatedPlane, alignment: .any).first else {
            statusMessage = "لم يتم العثور على سطح؛ حرّك الجهاز ببطء"
            return
        }

        let mesh = MeshResource.generateBox(size: 0.09, cornerRadius: 0.012)
        let color = UIColor(
            hue: CGFloat.random(in: 0...1),
            saturation: 0.72,
            brightness: 0.95,
            alpha: 1
        )
        let material = SimpleMaterial(color: color, roughness: 0.22, isMetallic: true)
        let entity = ModelEntity(mesh: mesh, materials: [material])
        entity.position.y = 0.05
        entity.generateCollisionShapes(recursive: true)

        let translation = result.worldTransform.columns.3
        let anchor = AnchorEntity(world: SIMD3<Float>(translation.x, translation.y, translation.z))
        anchor.name = "LiDARLabPlacedObject"
        anchor.addChild(entity)
        arView.scene.addAnchor(anchor)
        arView.installGestures([.translation, .rotation, .scale], for: entity)

        objectCount += 1
        statusMessage = "تمت إضافة مكعب؛ يمكنك تحريكه وتدويره وتكبيره"
    }

    func clearObjects() {
        guard let arView else { return }
        let anchorsToRemove = arView.scene.anchors.filter { $0.name == "LiDARLabPlacedObject" }
        anchorsToRemove.forEach { arView.scene.removeAnchor($0) }
        objectCount = 0
        statusMessage = "تم مسح المجسمات"
    }

    func stop() {
        arView?.session.pause()
    }
}
