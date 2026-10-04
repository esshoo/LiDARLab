import SwiftUI

struct ObjectScanView: View {
    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Label("مسح مجسم ثلاثي الأبعاد ملوّن", systemImage: "cube.transparent.fill")
                        .font(.title3.bold())
                    Text("اختر طريقة الالتقاط قبل البدء. الطريقتان تنتهيان إلى Photogrammetry من RealityKit، لكن طريقة جمع الصور مختلفة.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 6)
            }

            Section("طريقة المسح") {
                NavigationLink {
                    GuidedObjectScanView()
                } label: {
                    ObjectScanModeRow(
                        title: "تحريك الكاميرا حول المجسم",
                        subtitle: "Object Capture الموجّه من Apple مع LiDAR وPoint Cloud وCapture Dial. هذا هو الوضع الأفضل لمعظم الحالات.",
                        systemImage: "iphone.gen3.radiowaves.left.and.right",
                        badge: "موصى به"
                    )
                }

                NavigationLink {
                    TurntableObjectScanView()
                } label: {
                    ObjectScanModeRow(
                        title: "تثبيت الكاميرا ولف المجسم",
                        subtitle: "ثبّت الآيفون على حامل ولف الجسم ببطء. التطبيق يلتقط صورًا متتابعة ثم يبني USDZ عبر Photogrammetry.",
                        systemImage: "arrow.triangle.2.circlepath.camera",
                        badge: "Turntable"
                    )
                }
            }

            Section("متى أستخدم كل وضع؟") {
                Label("الوضع الموجّه أفضل عندما تستطيع الحركة حول الجسم وتريد الاستفادة من LiDAR والتوجيه الحي.", systemImage: "figure.walk")
                Label("Turntable مناسب للأجسام الصغيرة والمتوسطة عندما يمكن تثبيت الكاميرا والخلفية والإضاءة تمامًا.", systemImage: "camera.metering.center.weighted")
                Label("الأجسام الشفافة أو شديدة الانعكاس تظل صعبة على Photogrammetry في كلا الوضعين.", systemImage: "exclamationmark.triangle")
            }
            .font(.subheadline)
        }
        .navigationTitle("مسح مجسم ملوّن")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct ObjectScanModeRow: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let badge: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage)
                .font(.title2)
                .foregroundStyle(.cyan)
                .frame(width: 34)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(title)
                        .font(.headline)
                    Text(badge)
                        .font(.caption2.bold())
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(.cyan.opacity(0.12), in: Capsule())
                        .foregroundStyle(.cyan)
                }
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 6)
    }
}
