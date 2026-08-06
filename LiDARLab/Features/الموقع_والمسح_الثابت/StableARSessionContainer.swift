@preconcurrency import ARKit
import SceneKit
import SwiftUI
import UIKit

/// Displays the real ARKit camera feed and keeps one ARSession alive for the
/// current stable-core generation. Rendering never owns the recording policy;
/// every frame is forwarded to StableCapturePipeline first.
struct StableARSessionContainer: UIViewRepresentable {
    let pipeline: StableCapturePipeline
    let mode: StableScanMode
    let enabled: Bool
    let generation: Int

    func makeCoordinator() -> Coordinator {
        Coordinator(pipeline: pipeline)
    }

    func makeUIView(context: Context) -> ARSCNView {
        let view = ARSCNView(frame: .zero)
        view.backgroundColor = .black
        view.scene = SCNScene()
        view.automaticallyUpdatesLighting = false
        view.antialiasingMode = .none
        view.preferredFramesPerSecond = 60
        view.isPlaying = true
        view.session.delegate = context.coordinator
        context.coordinator.attach(view)
        context.coordinator.apply(mode: mode, enabled: enabled, generation: generation)
        return view
    }

    func updateUIView(_ uiView: ARSCNView, context: Context) {
        context.coordinator.attach(uiView)
        context.coordinator.apply(mode: mode, enabled: enabled, generation: generation)
    }

    static func dismantleUIView(_ uiView: ARSCNView, coordinator: Coordinator) {
        coordinator.stop()
        uiView.session.delegate = nil
        uiView.isPlaying = false
    }

    final class Coordinator: NSObject, ARSessionDelegate {
        private let pipeline: StableCapturePipeline
        private weak var sceneView: ARSCNView?
        private var configuredMode: StableScanMode?
        private var configuredGeneration = -1
        private var isRunning = false

        init(pipeline: StableCapturePipeline) {
            self.pipeline = pipeline
            super.init()
        }

        func attach(_ view: ARSCNView) {
            sceneView = view
            view.session.delegate = self
        }

        func apply(mode: StableScanMode, enabled: Bool, generation: Int) {
            guard let session = sceneView?.session else { return }
            guard enabled else {
                if isRunning {
                    session.pause()
                    isRunning = false
                }
                return
            }

            let generationChanged = configuredGeneration != generation
            let modeChanged = configuredMode != mode
            guard generationChanged || modeChanged || !isRunning else { return }

            let configuration = ARWorldTrackingConfiguration()
            configuration.worldAlignment = .gravity
            configuration.environmentTexturing = .none
            configuration.planeDetection = []
            configuration.isLightEstimationEnabled = true

            // Location mode deliberately avoids sceneDepth. 2D mode adds depth
            // without changing how Pose is recorded.
            if mode == .scan2D,
               ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) {
                configuration.frameSemantics.insert(.sceneDepth)
            }

            // A new generation is an explicit new coordinate system. Merely
            // resuming the same view does not reset tracking.
            let options: ARSession.RunOptions = generationChanged
                ? [.resetTracking, .removeExistingAnchors]
                : []
            session.run(configuration, options: options)
            configuredMode = mode
            configuredGeneration = generation
            isRunning = true
        }

        func stop() {
            sceneView?.session.pause()
            isRunning = false
        }

        func session(_ session: ARSession, didUpdate frame: ARFrame) {
            // No MainActor hop. Pose is snapshotted before depth/network/UI work.
            pipeline.ingest(frame: frame)
        }

        func session(_ session: ARSession, didFailWithError error: Error) {
            pipeline.onError?("ARKit: \(error.localizedDescription)")
        }

        func sessionWasInterrupted(_ session: ARSession) {
            pipeline.onStatus?("تمت مقاطعة ARKit. لن يتم وصل المسار عبر الانقطاع.")
        }

        func sessionInterruptionEnded(_ session: ARSession) {
            pipeline.onStatus?("انتهت مقاطعة ARKit. انتظر عودة التتبع الطبيعي قبل المتابعة.")
        }
    }
}
