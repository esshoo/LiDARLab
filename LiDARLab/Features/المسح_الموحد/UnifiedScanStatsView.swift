import SwiftUI

struct UnifiedScanStatsView: View {
    @ObservedObject var model: UnifiedScanViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("الجلسة") {
                    LabeledContent("الحالة", value: model.sessionState.title)
                    LabeledContent("الدور", value: model.role.title)
                    LabeledContent("الوضع", value: model.scanMode.title)
                    LabeledContent("الجهاز البعيد", value: model.remoteDeviceName)
                    LabeledContent("الموقع", value: model.positionText)
                }
                Section("الالتقاط والنقل") {
                    LabeledContent("Frames ملتقطة", value: "\(model.framesCaptured)")
                    LabeledContent("Pose", value: "\(model.posePackets)")
                    LabeledContent("Scan", value: "\(model.scanPackets)")
                    LabeledContent("مستلمة", value: "\(model.packetsReceived)")
                    LabeledContent("متخطاة", value: "\(model.skippedFrames)")
                    LabeledContent("حجم النقل", value: model.transferredText)
                }
                Section("الحفظ") {
                    LabeledContent("الحزم المحفوظة", value: "\(model.recordedPackets)")
                    LabeledContent("الحجم المحفوظ", value: model.recordedText)
                    if let directory = model.currentSessionDirectory {
                        Text(directory.path)
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                    }
                }
                Section("الحالة الحية") {
                    LabeledContent("Tracking", value: model.trackingText)
                    LabeledContent("الحرارة", value: model.thermalText)
                    LabeledContent("Depth", value: model.depthText)
                }
                if let error = model.lastError {
                    Section("آخر خطأ") { Text(error).foregroundStyle(.red) }
                }
            }
            .navigationTitle("الإحصائيات")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("تم") { dismiss() } } }
        }
    }
}
