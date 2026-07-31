import RealityKit
import SwiftUI

struct DepthARViewContainer: UIViewRepresentable {
    @ObservedObject var model: DepthSessionViewModel

    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero)
        arView.automaticallyConfigureSession = false
        model.attach(to: arView)
        return arView
    }

    func updateUIView(_ uiView: ARView, context: Context) {}

    static func dismantleUIView(_ uiView: ARView, coordinator: Void) {
        uiView.session.pause()
    }
}
