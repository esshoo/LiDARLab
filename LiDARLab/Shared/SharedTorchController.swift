import AVFoundation
import SwiftUI

@MainActor
final class SharedTorchController: ObservableObject {
    @Published private(set) var isAvailable = false
    @Published private(set) var isOn = false
    @Published private(set) var level: Float = 0
    @Published private(set) var statusText = "الكشاف غير متاح"

    private var videoDevice: AVCaptureDevice? {
        AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
            ?? AVCaptureDevice.default(for: .video)
    }

    init() {
        refreshAvailability()
    }

    var levelTitle: String {
        guard isOn else { return "الكشاف مغلق" }
        if level < 0.35 { return "كشاف منخفض" }
        if level < 0.75 { return "كشاف متوسط" }
        return "كشاف قوي"
    }

    func refreshAvailability() {
        guard let device = videoDevice else {
            isAvailable = false
            isOn = false
            level = 0
            statusText = "لا توجد كاميرا خلفية متاحة"
            return
        }
        isAvailable = device.hasTorch && device.isTorchModeSupported(.on)
        isOn = device.torchMode == .on
        level = isOn ? max(device.torchLevel, 0.01) : 0
        statusText = isAvailable ? levelTitle : "الكشاف غير متاح على هذا الجهاز"
    }

    func cycleLevel() {
        guard isAvailable else {
            refreshAvailability()
            return
        }
        if !isOn {
            setLevel(0.18)
        } else if level < 0.35 {
            setLevel(0.50)
        } else if level < 0.75 {
            setLevel(1.0)
        } else {
            turnOff()
        }
    }

    func setLevel(_ requestedLevel: Float) {
        guard let device = videoDevice else {
            refreshAvailability()
            return
        }
        guard device.isTorchAvailable else {
            statusText = "الكشاف غير متاح مؤقتًا؛ قد تكون حرارة الجهاز مرتفعة"
            return
        }
        do {
            try device.lockForConfiguration()
            defer { device.unlockForConfiguration() }
            let supportedMaximum = min(AVCaptureDevice.maxAvailableTorchLevel, 1.0)
            let safeLevel = min(max(requestedLevel, 0.01), supportedMaximum)
            try device.setTorchModeOn(level: safeLevel)
            isAvailable = true
            isOn = true
            level = safeLevel
            statusText = levelTitle
        } catch {
            isOn = false
            level = 0
            statusText = "تعذر تشغيل الكشاف: \(error.localizedDescription)"
        }
    }

    func turnOff() {
        guard let device = videoDevice else {
            isOn = false
            level = 0
            return
        }
        do {
            try device.lockForConfiguration()
            defer { device.unlockForConfiguration() }
            if device.isTorchModeSupported(.off) {
                device.torchMode = .off
            }
            isOn = false
            level = 0
            statusText = isAvailable ? "الكشاف مغلق" : "الكشاف غير متاح"
        } catch {
            statusText = "تعذر إطفاء الكشاف: \(error.localizedDescription)"
        }
    }
}

struct SharedTorchButton: View {
    @ObservedObject var controller: SharedTorchController
    var compact = false

    var body: some View {
        Button {
            controller.cycleLevel()
        } label: {
            if compact {
                Image(systemName: controller.isOn ? "flashlight.on.fill" : "flashlight.off.fill")
                    .font(.title3)
                    .frame(width: 44, height: 42)
            } else {
                Label(
                    controller.levelTitle,
                    systemImage: controller.isOn ? "flashlight.on.fill" : "flashlight.off.fill"
                )
                .frame(maxWidth: .infinity)
            }
        }
        .buttonStyle(.borderedProminent)
        .tint(controller.isOn ? .yellow : .gray)
        .disabled(!controller.isAvailable)
        .accessibilityHint("اضغط للتبديل بين منخفض ومتوسط وقوي ثم إيقاف")
    }
}
