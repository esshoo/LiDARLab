import ARKit
import RealityKit
import SwiftUI

struct ComputerBridgeARViewContainer: UIViewRepresentable {
    @ObservedObject var model: ComputerBridgeViewModel

    func makeCoordinator() -> Coordinator {
        Coordinator(model: model)
    }

    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero)
        arView.automaticallyConfigureSession = false
        arView.session.delegate = context.coordinator

        let configuration = ARWorldTrackingConfiguration()
        configuration.worldAlignment = .gravity
        configuration.environmentTexturing = .none
        configuration.planeDetection = []

        // Read sceneDepth only. We deliberately do not enable scene reconstruction,
        // meshes, point-cloud rendering, or architectural analysis on the phone.
        if ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) {
            configuration.frameSemantics.insert(.sceneDepth)
        }

        arView.session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
        return arView
    }

    func updateUIView(_ uiView: ARView, context: Context) {}

    static func dismantleUIView(_ uiView: ARView, coordinator: Coordinator) {
        uiView.session.delegate = nil
        uiView.session.pause()
    }

    final class Coordinator: NSObject, ARSessionDelegate {
        private let model: ComputerBridgeViewModel

        init(model: ComputerBridgeViewModel) {
            self.model = model
        }

        func session(_ session: ARSession, didUpdate frame: ARFrame) {
            Task { @MainActor [weak self] in
                self?.model.handle(frame: frame)
            }
        }

        func session(_ session: ARSession, didFailWithError error: Error) {
            // ARKit normally attempts recovery. Tracking state remains visible.
        }
    }
}
