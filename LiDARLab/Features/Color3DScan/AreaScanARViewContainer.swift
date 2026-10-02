import RealityKit
import SwiftUI

struct AreaScanARViewContainer: UIViewRepresentable {
    @ObservedObject var model: AreaScanViewModel

    func makeUIView(context: Context) -> ARView {
        let view = ARView(frame: .zero)
        view.automaticallyConfigureSession = false
        view.debugOptions.insert(.showSceneUnderstanding)
        model.attach(to: view)
        return view
    }

    func updateUIView(_ uiView: ARView, context: Context) {
        uiView.debugOptions.insert(.showSceneUnderstanding)
    }

    static func dismantleUIView(_ uiView: ARView, coordinator: Void) {
        uiView.session.pause()
    }
}
