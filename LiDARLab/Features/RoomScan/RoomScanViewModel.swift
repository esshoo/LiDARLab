import Combine
import RoomPlan
import UIKit

struct RoomScanExport: Identifiable {
    let id = UUID()
    let folderURL: URL
    let jsonURL: URL
    let usdzURL: URL
    let kind: String

    var shareItems: [Any] { [jsonURL, usdzURL] }
}

@MainActor
final class RoomScanViewModel: NSObject, ObservableObject, RoomCaptureViewDelegate {
    @Published private(set) var isScanning = false
    @Published private(set) var isProcessing = false
    @Published private(set) var capturedRoom: CapturedRoom?
    @Published private(set) var latestExport: RoomScanExport?
    @Published private(set) var statusMessage = "ابدأ المسح وتحرك ببطء حول الغرفة."
    @Published private(set) var errorMessage: String?

    private weak var captureView: RoomCaptureView?
    private var pendingStart = false

    var wallCount: Int { capturedRoom?.walls.count ?? 0 }
    var doorCount: Int { capturedRoom?.doors.count ?? 0 }
    var windowCount: Int { capturedRoom?.windows.count ?? 0 }
    var openingCount: Int { capturedRoom?.openings.count ?? 0 }
    var objectCount: Int { capturedRoom?.objects.count ?? 0 }

    func attach(to view: RoomCaptureView) {
        captureView = view
        view.delegate = self
        if pendingStart {
            pendingStart = false
            startScan()
        }
    }

    func startScan() {
        guard RoomCaptureSession.isSupported else {
            errorMessage = "RoomPlan غير مدعوم على هذا الجهاز."
            return
        }
        guard let captureView else {
            pendingStart = true
            return
        }

        capturedRoom = nil
        latestExport = nil
        isProcessing = false
        statusMessage = "امسح الجدران والأبواب والنوافذ بحركة بطيئة."
        captureView.captureSession.run(configuration: RoomCaptureSession.Configuration())
        isScanning = true
    }

    func stopScan() {
        guard isScanning else { return }
        isScanning = false
        isProcessing = true
        statusMessage = "جارٍ معالجة نموذج الغرفة…"
        captureView?.captureSession.stop()
    }

    func stopWithoutProcessing() {
        isScanning = false
        captureView?.captureSession.stop(pauseARSession: true)
    }

    func exportParametric() {
        export(options: .parametric, kind: "Parametric")
    }

    func exportMesh() {
        export(options: .mesh, kind: "Mesh")
    }

    func clearError() {
        errorMessage = nil
    }

    func captureView(shouldPresent roomDataForProcessing: CapturedRoomData, error: Error?) -> Bool {
        if let error {
            isProcessing = false
            errorMessage = error.localizedDescription
            statusMessage = "حدث خطأ أثناء إنهاء المسح."
            return false
        }
        isScanning = false
        isProcessing = true
        statusMessage = "جارٍ إنشاء النموذج النهائي…"
        return true
    }

    func captureView(didPresent processedResult: CapturedRoom, error: Error?) {
        isProcessing = false
        if let error {
            errorMessage = error.localizedDescription
            statusMessage = "تعذر معالجة الغرفة."
            return
        }
        capturedRoom = processedResult
        statusMessage = "اكتمل المسح. راجع النموذج ثم صدّره."
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    private func export(options: CapturedRoom.USDExportOptions, kind: String) {
        guard let capturedRoom else {
            errorMessage = "أنهِ مسح الغرفة أولًا."
            return
        }

        do {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
            let name = "Room-\(formatter.string(from: Date()))-\(kind)"
            let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            let folder = documents.appendingPathComponent("LiDARLab/Rooms/\(name)", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

            let jsonURL = folder.appendingPathComponent("room.json")
            let usdzURL = folder.appendingPathComponent("room.usdz")
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(capturedRoom).write(to: jsonURL, options: .atomic)
            try capturedRoom.export(to: usdzURL, exportOptions: options)

            latestExport = RoomScanExport(folderURL: folder, jsonURL: jsonURL, usdzURL: usdzURL, kind: kind)
            statusMessage = "تم تصدير JSON وUSDZ بنمط \(kind)."
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
