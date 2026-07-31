import RealityKit
import SwiftUI

struct DepthPhotoARViewContainer: UIViewRepresentable {
    @ObservedObject var model: DepthPhotoViewModel

    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero)
        arView.automaticallyConfigureSession = false
        model.attach(to: arView)
        model.updateOrientation(.portrait)
        return arView
    }

    func updateUIView(_ uiView: ARView, context: Context) {
        model.updateOrientation(uiView.window?.windowScene?.interfaceOrientation ?? .portrait)
    }

    static func dismantleUIView(_ uiView: ARView, coordinator: Void) {
        uiView.session.pause()
    }
}
