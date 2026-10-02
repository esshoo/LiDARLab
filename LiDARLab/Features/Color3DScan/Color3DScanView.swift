import SwiftUI

struct Color3DScanView: View {
    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Label("المسح ثلاثي الأبعاد الملون", systemImage: "viewfinder")
                        .font(.title3.bold())

                    Text("قسم مستقل للمسح ثلاثي الأبعاد بالألوان. اختر مسح جسم صغير أو مسح غرفة ومساحة كاملة دون التأثير على أدوات التطبيق الحالية.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 6)
            }

            Section("نوع المسح") {
                NavigationLink {
                    ObjectScanView()
                } label: {
                    Color3DScanToolRow(
                        title: "مسح جسم",
                        subtitle: "تمثال، أداة أو قطعة صغيرة باستخدام الصور والعمق لإنتاج نموذج ملوّن.",
                        systemImage: "cube.transparent"
                    )
                }

                NavigationLink {
                    AreaScanView()
                } label: {
                    Color3DScanToolRow(
                        title: "مسح مكان / غرفة",
                        subtitle: "غرفة أو مساحة كاملة باستخدام LiDAR وبيانات الكاميرا مع مسار للجودة العالية.",
                        systemImage: "house.lodge"
                    )
                }
            }

            Section("قدرات الجهاز") {
                Color3DScanSupportRow(
                    title: "Scene Depth",
                    isSupported: Color3DScanSupport.sceneDepthSupported
                )
                Color3DScanSupportRow(
                    title: "Scene Mesh",
                    isSupported: Color3DScanSupport.meshSupported
                )
                Color3DScanSupportRow(
                    title: "تصنيف Mesh",
                    isSupported: Color3DScanSupport.meshClassificationSupported
                )
                Color3DScanSupportRow(
                    title: "Object Capture",
                    isSupported: Color3DScanSupport.objectCaptureSupported
                )
                Color3DScanSupportRow(
                    title: "Photogrammetry",
                    isSupported: Color3DScanSupport.photogrammetrySupported
                )
                Color3DScanSupportRow(
                    title: "RoomPlan",
                    isSupported: Color3DScanSupport.roomPlanSupported
                )

                HStack {
                    Text("iOS")
                    Spacer()
                    Text(Color3DScanSupport.systemVersionText)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }

            Section("التصدير المستهدف") {
                Color3DScanExportRow(format: "USDZ", detail: "النموذج الملوّن والمعاينة على أجهزة Apple")
                Color3DScanExportRow(format: "OBJ", detail: "Mesh مع مواد وTextures للاستخدام الخارجي")
                Color3DScanExportRow(format: "PLY", detail: "هندسة ونقاط للمراجعة والمعالجة")
            }

            Section("خطة التنفيذ") {
                Text("تم فصل هذا النظام بالكامل عن RoomScan وMesh والأدوات القديمة. المرحلة التالية تضيف محرك الالتقاط وإعادة البناء والحفظ داخل هذا القسم فقط.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("المسح 3D الملون")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct Color3DScanToolRow: View {
    let title: String
    let subtitle: String
    let systemImage: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(.cyan)
                .frame(width: 30)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 5)
    }
}

private struct Color3DScanSupportRow: View {
    let title: String
    let isSupported: Bool

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Label(
                isSupported ? "مدعوم" : "غير مدعوم",
                systemImage: isSupported ? "checkmark.circle.fill" : "xmark.circle.fill"
            )
            .font(.subheadline)
            .foregroundStyle(isSupported ? .green : .secondary)
        }
    }
}

private struct Color3DScanExportRow: View {
    let format: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "square.and.arrow.up")
                .foregroundStyle(.cyan)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(format)
                    .font(.headline.monospaced())
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}
