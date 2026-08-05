import Foundation
import SwiftUI

struct UnifiedScanStatsView: View {
    let model: UnifiedScanViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var snapshot: UnifiedScanStatsSnapshot
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    init(model: UnifiedScanViewModel) {
        self.model = model
        _snapshot = State(initialValue: UnifiedScanStatsSnapshot(model: model))
    }

    var body: some View {
        NavigationStack {
            List {
                SwiftUI.Section("الجلسة") {
                    LabeledContent("الحالة", value: snapshot.sessionState)
                    LabeledContent("الدور", value: snapshot.role)
                    LabeledContent("الوضع", value: snapshot.scanMode)
                    LabeledContent("الجهاز البعيد", value: snapshot.remoteDeviceName)
                    LabeledContent("الموقع", value: snapshot.position)
                }
                SwiftUI.Section("الالتقاط والنقل") {
                    LabeledContent("Frames ملتقطة", value: snapshot.framesCaptured)
                    LabeledContent("Pose", value: snapshot.posePackets)
                    LabeledContent("Scan", value: snapshot.scanPackets)
                    LabeledContent("مستلمة", value: snapshot.packetsReceived)
                    LabeledContent("متخطاة", value: snapshot.skippedFrames)
                    LabeledContent("حجم النقل", value: snapshot.transferred)
                    LabeledContent("خلايا Preview التراكمية", value: snapshot.coverageCells)
                }
                SwiftUI.Section("الحفظ") {
                    LabeledContent("الحزم المحفوظة", value: snapshot.recordedPackets)
                    LabeledContent("الحجم المحفوظ", value: snapshot.recorded)
                    if let directory = snapshot.sessionDirectory {
                        Text(directory)
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                    }
                }
                SwiftUI.Section("الحالة الحية") {
                    LabeledContent("Tracking", value: snapshot.tracking)
                    LabeledContent("الحرارة", value: snapshot.thermal)
                    LabeledContent("Depth", value: snapshot.depth)
                }
                if let error = snapshot.lastError {
                    SwiftUI.Section("آخر خطأ") {
                        Text(error).foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("الإحصائيات")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("إغلاق") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("تحديث") { snapshot = UnifiedScanStatsSnapshot(model: model) }
                }
            }
            .onReceive(timer) { _ in
                snapshot = UnifiedScanStatsSnapshot(model: model)
            }
        }
    }
}

private struct UnifiedScanStatsSnapshot {
    let sessionState: String
    let role: String
    let scanMode: String
    let remoteDeviceName: String
    let position: String
    let framesCaptured: String
    let posePackets: String
    let scanPackets: String
    let packetsReceived: String
    let skippedFrames: String
    let transferred: String
    let coverageCells: String
    let recordedPackets: String
    let recorded: String
    let sessionDirectory: String?
    let tracking: String
    let thermal: String
    let depth: String
    let lastError: String?

    init(model: UnifiedScanViewModel) {
        sessionState = model.sessionState.title
        role = model.role.title
        scanMode = model.scanMode.title
        remoteDeviceName = model.remoteDeviceName
        position = model.positionText
        framesCaptured = "\(model.framesCaptured)"
        posePackets = "\(model.posePackets)"
        scanPackets = "\(model.scanPackets)"
        packetsReceived = "\(model.packetsReceived)"
        skippedFrames = "\(model.skippedFrames)"
        transferred = model.transferredText
        coverageCells = "\(model.coverageCells.count)"
        recordedPackets = "\(model.recordedPackets)"
        recorded = model.recordedText
        sessionDirectory = model.currentSessionDirectory?.path
        tracking = model.trackingText
        thermal = model.thermalText
        depth = model.depthText
        lastError = model.lastError
    }
}
