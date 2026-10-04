import SwiftUI

struct Color3DScanView: View {
    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Label("المسح ثلاثي الأبعاد الملون", systemImage: "viewfinder")
                        .font(.title3.bold())

                    Text("هذا القسم مخصص للمسح ثلاثي الأبعاد الملون فقط: مسح مجسمات ملونة أو مسح منطقة/مكان ملون. أدوات RoomPlan والهندسة المعمارية تبقى في قسمها المستقل ولا تتكرر هنا.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 6)
            }

            Section("أدوات المسح") {
                NavigationLink {
                    ObjectScanView()
                } label: {
                    Color3DScanToolRow(
                        title: "مسح جسم ملوّن",
                        subtitle: "اختيار الهدف باللمس للتوجيه + ObjectCaptureView + Point Cloud/Capture Dial + Photogrammetry + USDZ.",
                        systemImage: "cube.transparent"
                    )
                }

                NavigationLink {
                    AreaScanView()
                } label: {
                    Color3DScanToolRow(
                        title: "مسح مكان / منطقة ملوّنة — Area Mode",
                        subtitle: "مسح بصري ملوّن لمنطقة أو سطح أو مشهد محدود باستخدام Object Capture Area Mode، مع USDZ وصور المصدر.",
                        systemImage: "square.3.layers.3d"
                    )
                }
            }

            Section("الإعدادات") {
                NavigationLink {
                    Color3DScanSettingsView()
                } label: {
                    Label("إعدادات جودة المسح والتصدير", systemImage: "gearshape.2.fill")
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
                    title: "مسح المجسم الموجّه",
                    isSupported: Color3DScanSupport.objectScanSupported
                )
                Color3DScanSupportRow(
                    title: "Photogrammetry",
                    isSupported: Color3DScanSupport.photogrammetrySupported
                )

                HStack {
                    Text("iOS")
                    Spacer()
                    Text(Color3DScanSupport.systemVersionText)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }

            Section("المخرجات الفعلية") {
                Color3DScanExportRow(
                    format: "USDZ ملوّن",
                    detail: "الناتج البصري للمجسمات وArea Mode بعد إعادة البناء عبر RealityKit Photogrammetry"
                )
                Color3DScanExportRow(
                    format: "Source Capture",
                    detail: "يمكن الاحتفاظ بصور Object Capture الأصلية لإعادة معالجة أعلى جودة على Mac"
                )
            }

            Section("مهم") {
                Text("هذا القسم لا يكرر RoomScan ولا يغيره. ملفات المسح الملون تحفظ تحت Captures/Color3D في مساحة تخزين 3ELiDAR الحالية.")
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
