import RealityKit
import SwiftUI

struct AreaScanARViewContainer: UIViewRepresentable {
    @ObservedObject var model: AreaScanViewModel

    func makeUIView(context: Context) -> ARView {
        let view = ARView(frame: .zero)
        view.automaticallyConfigureSession = false
        if Color3DScanSettings.areaOptions.showSceneMeshWhileScanning {
            view.debugOptions.insert(.showSceneUnderstanding)
        }
        model.attach(to: view)
        return view
    }

    func updateUIView(_ uiView: ARView, context: Context) {
        if Color3DScanSettings.areaOptions.showSceneMeshWhileScanning {
            uiView.debugOptions.insert(.showSceneUnderstanding)
        } else {
            uiView.debugOptions.remove(.showSceneUnderstanding)
        }
    }

    static func dismantleUIView(_ uiView: ARView, coordinator: Void) {
        uiView.session.pause()
    }
}
