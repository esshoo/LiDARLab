import SwiftUI

struct ObjectScanView: View {
    private var captureSupported: Bool {
        Color3DScanSupport.objectCaptureSupported
    }

    private var reconstructionSupported: Bool {
        Color3DScanSupport.photogrammetrySupported
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Label("مسح جسم", systemImage: "cube.transparent")
                        .font(.title3.bold())

                    Text("مخصص للأجسام الصغيرة مثل التماثيل والأدوات والقطع المنفصلة. المسار المستهدف يعتمد على التقاط صور متعددة حول الجسم ثم إعادة بنائه كنموذج ثلاثي الأبعاد ملوّن.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 6)
            }

            Section("حالة الجهاز") {
                ObjectScanStateRow(
                    title: "التقاط Object Capture",
                    isReady: captureSupported
                )
                ObjectScanStateRow(
                    title: "إعادة البناء على الجهاز",
                    isReady: reconstructionSupported
                )
                ObjectScanStateRow(
                    title: "Scene Depth",
                    isReady: Color3DScanSupport.sceneDepthSupported
                )
            }

            if !captureSupported || !reconstructionSupported {
                Section {
                    Label {
                        Text("الجهاز الحالي لا يدعم كل متطلبات Object Capture. سيظل باقي التطبيق والأدوات القديمة متاحًا بصورة طبيعية.")
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                    .font(.footnote)
                }
            }

            Section("سير العمل") {
                ObjectScanStep(number: 1, title: "تحديد الجسم", detail: "ضع الجسم في إضاءة جيدة واترك مساحة للحركة حوله.")
                ObjectScanStep(number: 2, title: "الالتقاط", detail: "التقاط صور متداخلة من جميع الجوانب والارتفاعات.")
                ObjectScanStep(number: 3, title: "فحص التغطية", detail: "التأكد من عدم وجود مناطق كبيرة ناقصة قبل الإنهاء.")
                ObjectScanStep(number: 4, title: "إعادة البناء", detail: "تحويل الصور وبيانات العمق إلى Mesh وTexture.")
                ObjectScanStep(number: 5, title: "المراجعة والتصدير", detail: "عرض النموذج ثم حفظه بصيغة مناسبة.")
            }

            Section("المرحلة الحالية") {
                Text("تم تجهيز الأداة كبنية مستقلة والتحقق من قدرات الجهاز. سيتم توصيل جلسة Object Capture ومحرك إعادة البناء في الدفعة التالية بعد نجاح هذا البناء.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("مسح جسم")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct ObjectScanStateRow: View {
    let title: String
    let isReady: Bool

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Image(systemName: isReady ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(isReady ? .green : .secondary)
            Text(isReady ? "جاهز" : "غير مدعوم")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}

private struct ObjectScanStep: View {
    let number: Int
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.caption.bold())
                .foregroundStyle(.white)
                .frame(width: 26, height: 26)
                .background(Circle().fill(.cyan))

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 3)
    }
}
