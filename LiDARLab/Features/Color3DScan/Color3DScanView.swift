import SwiftUI

struct Color3DScanView: View {
    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Label("المسح ثلاثي الأبعاد الملون", systemImage: "viewfinder")
                        .font(.title3.bold())

                    Text("قسم مستقل للمسح ثلاثي الأبعاد الحقيقي. مسح المجسم يسمح باختيار الهدف باللمس ثم حساب التغطية حوله وجمع صور RGB لإعادة البناء، ومسح المكان يجمع LiDAR Scene Mesh وصور RGB ويكسو الأسطح بخامات فعلية.")
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
                        subtitle: "اختيار الهدف باللمس + تغطية محيطية + Photogrammetry على الجهاز + ملف USDZ.",
                        systemImage: "cube.transparent"
                    )
                }

                NavigationLink {
                    AreaScanView()
                } label: {
                    Color3DScanToolRow(
                        title: "مسح غرفة / مكان ملوّن",
                        subtitle: "LiDAR Scene Mesh + صور RGB + إسقاط ألوان + PLY/OBJ وUSDZ عند دعم التصدير.",
                        systemImage: "house.lodge"
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
                    format: "USDZ",
                    detail: "الناتج الأساسي لمسح المجسمات بعد الالتقاط الموجّه وإعادة البناء"
                )
                Color3DScanExportRow(
                    format: "OBJ + MTL + Textures",
                    detail: "Mesh الغرفة مع صور RGB كخامات فعلية وUV لكل وجه"
                )
                Color3DScanExportRow(
                    format: "PLY + RGB",
                    detail: "صيغة توافق بألوان Vertex مشتقة من الصور"
                )
                Color3DScanExportRow(
                    format: "JSON + RGB Frames",
                    detail: "Camera poses وintrinsics وصور المصدر للمراجعة أو التطوير اللاحق"
                )
            }

            Section("مهم") {
                Text("النظام الجديد لا يغير RoomScan أو Mesh أو أي أداة قديمة. ملفات المسح تحفظ تحت Captures/Color3D في مساحة تخزين 3ELiDAR الحالية.")
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
