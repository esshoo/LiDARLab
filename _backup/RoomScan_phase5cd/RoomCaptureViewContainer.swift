import RoomPlan
import SwiftUI

/// Keeps one RoomCaptureView and one app-owned ARSession alive for the whole workflow.
/// The same ARSession is reused for separate rooms and is also loaded with a saved
/// ARWorldMap when an unfinished project is reopened.
struct RoomCaptureViewContainer: UIViewRepresentable {
    @ObservedObject var model: RoomScanViewModel

    func makeUIView(context: Context) -> RoomCaptureView {
        let view = RoomCaptureView(frame: .zero, arSession: model.sharedARSession)
        view.isModelEnabled = true
        model.attach(to: view)
        return view
    }

    func updateUIView(_ uiView: RoomCaptureView, context: Context) {}

    static func dismantleUIView(_ uiView: RoomCaptureView, coordinator: Void) {
        uiView.captureSession.stop(pauseARSession: true)
    }
}
