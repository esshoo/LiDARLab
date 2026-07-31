import SwiftUI
import UIKit

struct DeviceInfoView: View {
    private let capabilities = DeviceCapabilities.current

    var body: some View {
        List {
            Section("الجهاز") {
                InfoRow(title: "نوع الجهاز", value: UIDevice.current.model, systemImage: "iphone")
                InfoRow(title: "النظام", value: capabilities.systemDescription, systemImage: "gear")
                InfoRow(title: "إصدار التطبيق", value: appVersion, systemImage: "shippingbox")
                InfoRow(title: "الذاكرة", value: formattedMemory, systemImage: "memorychip")
                InfoRow(title: "إذن الكاميرا", value: capabilities.cameraAuthorizationDescription, systemImage: "camera")
            }

            Section("ARKit وLiDAR") {
                CapabilityRow(title: "World Tracking", isSupported: capabilities.worldTrackingSupported)
                CapabilityRow(title: "Scene Depth", isSupported: capabilities.sceneDepthSupported)
                CapabilityRow(title: "Smoothed Scene Depth", isSupported: capabilities.smoothedDepthSupported)
                CapabilityRow(title: "Scene Mesh", isSupported: capabilities.meshSupported)
                CapabilityRow(title: "Mesh Classification", isSupported: capabilities.meshClassificationSupported)
                CapabilityRow(title: "RoomPlan", isSupported: capabilities.roomPlanSupported)
            }

            Section {
                HStack(spacing: 12) {
                    Image(systemName: capabilities.lidarAvailable ? "checkmark.seal.fill" : "xmark.seal.fill")
                        .foregroundStyle(capabilities.lidarAvailable ? .green : .red)
                        .font(.title2)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(capabilities.deviceSummary)
                            .font(.headline)
                        Text(capabilities.lidarAvailable ? "يمكن تشغيل تجارب العمق والشبكة." : "ستظل الوظائف في القائمة، لكن تجارب LiDAR لن تعمل.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("معلومات الجهاز")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var appVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
        return "\(version) (\(build))"
    }

    private var formattedMemory: String {
        ByteCountFormatter.string(fromByteCount: Int64(ProcessInfo.processInfo.physicalMemory), countStyle: .memory)
    }
}

private struct InfoRow: View {
    let title: String
    let value: String
    let systemImage: String

    var body: some View {
        HStack {
            Label(title, systemImage: systemImage)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
        }
    }
}

private struct CapabilityRow: View {
    let title: String
    let isSupported: Bool

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Label(isSupported ? "مدعوم" : "غير مدعوم", systemImage: isSupported ? "checkmark.circle.fill" : "xmark.circle.fill")
                .font(.subheadline.bold())
                .foregroundStyle(isSupported ? .green : .red)
        }
    }
}
