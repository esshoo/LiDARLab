import ARKit
import SwiftUI
import UIKit

/// Hosts ARSession without rendering the camera feed or a 3D scene.
/// This keeps the device focused on capture, recording, and the lightweight map preview.
struct UnifiedARViewContainer: UIViewRepresentable {
    @ObservedObject var model: UnifiedScanViewModel

    func makeCoordinator() -> Coordinator {
        Coordinator(model: model)
    }

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.backgroundColor = .clear
        context.coordinator.start(mode: model.scanMode)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.model = model
        context.coordinator.update(mode: model.scanMode)
    }

    static func dismantleUIView(_ uiView: UIView, coordinator: Coordinator) {
        coordinator.stop()
    }

    final class Coordinator: NSObject, ARSessionDelegate {
        var model: UnifiedScanViewModel
        private let session = ARSession()
        private var configuredMode: UnifiedScanMode?

        init(model: UnifiedScanViewModel) {
            self.model = model
            super.init()
            session.delegate = self
        }

        func start(mode: UnifiedScanMode) {
            guard ARWorldTrackingConfiguration.isSupported else { return }
            configuredMode = mode
            let configuration = configuration(for: mode)
            session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
        }

        func update(mode: UnifiedScanMode) {
            guard mode != configuredMode, !model.settingsLocked else { return }
            start(mode: mode)
        }

        func stop() {
            session.delegate = nil
            session.pause()
        }

        func session(_ session: ARSession, didUpdate frame: ARFrame) {
            Task { @MainActor [weak self] in
                self?.model.handle(frame: frame)
            }
        }

        func session(_ session: ARSession, didFailWithError error: Error) {
            // The capability system is advisory; the actual tracking state/error
            // is surfaced by the view model without hiding or disabling the mode.
        }

        private func configuration(for mode: UnifiedScanMode) -> ARWorldTrackingConfiguration {
            let configuration = ARWorldTrackingConfiguration()
            configuration.worldAlignment = .gravity
            configuration.environmentTexturing = .none
            configuration.planeDetection = []
            configuration.isAutoFocusEnabled = true
            if mode.requiresDepth,
               ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) {
                configuration.frameSemantics.insert(.sceneDepth)
            }
            // No scene reconstruction, mesh, or live architectural processing.
            return configuration
        }
    }
}
