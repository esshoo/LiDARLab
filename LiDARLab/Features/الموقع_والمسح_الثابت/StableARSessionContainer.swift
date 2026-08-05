@preconcurrency import ARKit
import SwiftUI
import UIKit

struct StableARSessionContainer: UIViewRepresentable {
    let pipeline: StableCapturePipeline
    let mode: StableScanMode
    let enabled: Bool
    let generation: Int

    func makeCoordinator() -> Coordinator {
        Coordinator(pipeline: pipeline)
    }

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.backgroundColor = .black
        context.coordinator.apply(mode: mode, enabled: enabled, generation: generation)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.apply(mode: mode, enabled: enabled, generation: generation)
    }

    static func dismantleUIView(_ uiView: UIView, coordinator: Coordinator) {
        coordinator.stop()
    }

    final class Coordinator: NSObject, ARSessionDelegate {
        private let pipeline: StableCapturePipeline
        private let session = ARSession()
        private var configuredMode: StableScanMode?
        private var configuredGeneration = -1
        private var isRunning = false

        init(pipeline: StableCapturePipeline) {
            self.pipeline = pipeline
            super.init()
            session.delegate = self
        }

        func apply(mode: StableScanMode, enabled: Bool, generation: Int) {
            guard enabled else {
                if isRunning {
                    session.pause()
                    isRunning = false
                }
                return
            }

            let requiresFreshConfiguration = configuredMode != mode || configuredGeneration != generation
            guard requiresFreshConfiguration || !isRunning else { return }

            let configuration = ARWorldTrackingConfiguration()
            configuration.worldAlignment = .gravity
            configuration.environmentTexturing = .none
            configuration.planeDetection = []

            // Location mode deliberately does not request depth resources.
            if mode == .scan2D,
               ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) {
                configuration.frameSemantics.insert(.sceneDepth)
            }

            let options: ARSession.RunOptions = requiresFreshConfiguration
                ? [.resetTracking, .removeExistingAnchors]
                : []
            session.run(configuration, options: options)
            configuredMode = mode
            configuredGeneration = generation
            isRunning = true
        }

        func stop() {
            session.delegate = nil
            session.pause()
            isRunning = false
        }

        func session(_ session: ARSession, didUpdate frame: ARFrame) {
            // No MainActor hop. The stable pipeline snapshots Pose first.
            pipeline.ingest(frame: frame)
        }

        func session(_ session: ARSession, didFailWithError error: Error) {
            pipeline.onError?("ARKit: \(error.localizedDescription)")
        }

        func sessionWasInterrupted(_ session: ARSession) {
            pipeline.onStatus?("تمت مقاطعة ARKit. لن يتم وصل المسار عبر الانقطاع.")
        }

        func sessionInterruptionEnded(_ session: ARSession) {
            pipeline.onStatus?("انتهت مقاطعة ARKit. ابدأ جلسة جديدة للحصول على مرجع نظيف عند الحاجة.")
        }
    }
}
