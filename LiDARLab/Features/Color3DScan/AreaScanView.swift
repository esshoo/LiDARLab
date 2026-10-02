import SwiftUI

struct AreaScanView: View {
    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Label("مسح مكان / غرفة", systemImage: "house.lodge")
                        .font(.title3.bold())

                    Text("نظام جديد مستقل لمسح غرفة أو مساحة كنموذج ثلاثي الأبعاد ملوّن. لن يغيّر RoomScan الحالي أو بياناته الهندسية.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 6)
            }

            Section("أوضاع المسح المخططة") {
                AreaScanModeRow(
                    title: "سريع — LiDAR + RGB",
                    subtitle: "Scene Mesh لحظي مع إطارات الكاميرا. مناسب لمساحات الغرف وسرعة الالتقاط.",
                    systemImage: "dot.radiowaves.left.and.right",
                    available: Color3DScanSupport.meshSupported && Color3DScanSupport.sceneDepthSupported
                )

                AreaScanModeRow(
                    title: "جودة أعلى — Object Capture",
                    subtitle: "مسار صور كثيف لإنتاج Texture أفضل عندما يدعم الجهاز والإصدار ذلك.",
                    systemImage: "camera.aperture",
                    available: Color3DScanSupport.areaModeAvailable
                )
            }

            Section("البيانات التي سيحفظها الوضع السريع") {
                AreaScanDataRow(title: "Mesh", detail: "Vertices + Faces + Normals")
                AreaScanDataRow(title: "Camera Pose", detail: "Transform لكل إطار مستخدم")
                AreaScanDataRow(title: "RGB Frames", detail: "صور مختارة لإسقاط اللون على النموذج")
                AreaScanDataRow(title: "Depth", detail: "Scene Depth عند توفره")
                AreaScanDataRow(title: "Metadata", detail: "الجلسة والجهاز والدقة والتوقيت")
            }

            Section("المرحلة الحالية") {
                Text("تم إنشاء واجهة مستقلة واكتشاف إمكانات الجهاز. التنفيذ التالي سيبدأ بالوضع السريع لأنه الأنسب للغرف، ثم نضيف مسار الجودة الأعلى بصورة منفصلة.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("مسح مكان / غرفة")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct AreaScanModeRow: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let available: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(.cyan)
                .frame(width: 30)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(title)
                        .font(.headline)
                    Spacer(minLength: 8)
                    Text(available ? "متاح" : "غير متاح")
                        .font(.caption.bold())
                        .foregroundStyle(available ? .green : .secondary)
                }
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct AreaScanDataRow: View {
    let title: String
    let detail: String

    var body: some View {
        HStack {
            Text(title)
                .font(.headline)
            Spacer()
            Text(detail)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
        }
    }
}
