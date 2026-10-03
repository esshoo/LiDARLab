import SceneKit
import SwiftUI

struct AreaScanPreviewView: UIViewRepresentable {
    let mesh: AreaScanTexturedMesh
    let freeCamera: Bool

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView(frame: .zero)
        let scene = Color3DMeshExporter.makeScene(mesh: mesh)
        view.scene = scene
        view.allowsCameraControl = true
        view.autoenablesDefaultLighting = false
        view.antialiasingMode = .multisampling4X
        view.backgroundColor = .black
        view.pointOfView = scene.rootNode.childNode(withName: "PreviewCamera", recursively: true)
        view.cameraControlConfiguration.allowsTranslation = true
        view.cameraControlConfiguration.autoSwitchToFreeCamera = true
        view.cameraControlConfiguration.flyModeVelocity = 0.8
        if freeCamera {
            view.defaultCameraController.interactionMode = .fly
        }
        return view
    }

    func updateUIView(_ uiView: SCNView, context: Context) {
        uiView.cameraControlConfiguration.allowsTranslation = true
        if freeCamera {
            uiView.defaultCameraController.interactionMode = .fly
        }
    }
}
