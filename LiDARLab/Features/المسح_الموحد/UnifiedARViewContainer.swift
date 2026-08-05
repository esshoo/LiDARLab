import ARKit
import Foundation
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

    @MainActor
    final class Coordinator: NSObject, ARSessionDelegate {
        var model: UnifiedScanViewModel
        private let session = ARSession()
        private var configuredMode: UnifiedScanMode?
        nonisolated private let frameGate = UnifiedARFrameGate()

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

        nonisolated func session(_ session: ARSession, didUpdate frame: ARFrame) {
            guard frameGate.tryEnter() else { return }
            Task { @MainActor [weak self, frameGate] in
                defer { frameGate.leave() }
                self?.model.handle(frame: frame)
            }
        }

        nonisolated func session(_ session: ARSession, didFailWithError error: Error) {
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

private final class UnifiedARFrameGate: @unchecked Sendable {
    private let lock = NSLock()
    private var occupied = false

    func tryEnter() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !occupied else { return false }
        occupied = true
        return true
    }

    func leave() {
        lock.lock()
        occupied = false
        lock.unlock()
    }
}
