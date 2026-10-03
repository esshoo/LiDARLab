import SwiftUI

struct Color3DScanSettingsView: View {
    @AppStorage(Color3DScanSettings.Key.appleAreaAutoCapture) private var areaAutoCapture = true
    @AppStorage(Color3DScanSettings.Key.appleAreaHaptics) private var areaHaptics = true
    @AppStorage(Color3DScanSettings.Key.appleAreaOverCapture) private var areaOverCapture = false
    @AppStorage(Color3DScanSettings.Key.appleAreaKeepSourceImages) private var areaKeepSourceImages = true
    @AppStorage(Color3DScanSettings.Key.appleAreaMinimumImages) private var areaMinimumImages = 12

    @AppStorage(Color3DScanSettings.Key.objectAutoCapture) private var objectAutoCapture = true
    @AppStorage(Color3DScanSettings.Key.objectHaptics) private var objectHaptics = true
    @AppStorage(Color3DScanSettings.Key.appleObjectOverCapture) private var objectOverCapture = false
    @AppStorage(Color3DScanSettings.Key.objectMinimumImages) private var objectMinimumImages = 12
    @AppStorage(Color3DScanSettings.Key.appleObjectRecommendedPasses) private var objectRecommendedPasses = 3
    @AppStorage(Color3DScanSettings.Key.objectHighFeatureSensitivity) private var objectHighFeatureSensitivity = true
    @AppStorage(Color3DScanSettings.Key.objectMasking) private var objectMasking = true
    @AppStorage(Color3DScanSettings.Key.objectKeepSourceImages) private var objectKeepSourceImages = true
    @AppStorage(Color3DScanSettings.Key.objectSizePreset) private var objectSizePresetRaw = ObjectScanSizePreset.medium.rawValue

    @State private var showResetConfirmation = false

    private var selectedObjectSize: Binding<ObjectScanSizePreset> {
        Binding(
            get: { ObjectScanSizePreset(rawValue: objectSizePresetRaw) ?? .medium },
            set: { objectSizePresetRaw = $0.rawValue }
        )
    }

    var body: some View {
        Form {
            Section {
                Toggle("التقاط تلقائي", isOn: $areaAutoCapture)
                Toggle("اهتزازات أثناء الالتقاط", isOn: $areaHaptics)
                Toggle("Over Capture", isOn: $areaOverCapture)
                Stepper("أقل عدد صور قبل السماح بالإنهاء: \(areaMinimumImages)", value: $areaMinimumImages, in: 1...100)
                Toggle("الاحتفاظ بصور المصدر", isOn: $areaKeepSourceImages)
            } header: {
                Label("مسح الغرفة / المكان — Apple Area Mode", systemImage: "house.lodge")
            } footer: {
                Text("هذا الوضع يستخدم Object Capture Area Mode الرسمي. لا توجد إعدادات حقيقية لكثافة نقاط LiDAR أو دقة JPEG داخل ObjectCaptureSession، لذلك لا نعرض منزلقات وهمية. جودة الالتقاط تتحسن بالتغطية الجيدة، تداخل الصور، والحركة البطيئة من أكثر من ارتفاع.")
            }

            Section {
                Picker("الحجم التقريبي", selection: selectedObjectSize) {
                    ForEach(ObjectScanSizePreset.allCases) { preset in
                        Text(preset.title).tag(preset)
                    }
                }
                .pickerStyle(.navigationLink)

                Toggle("التقاط تلقائي", isOn: $objectAutoCapture)
                Toggle("اهتزازات أثناء الالتقاط", isOn: $objectHaptics)
                Toggle("Over Capture", isOn: $objectOverCapture)
                Stepper("أقل عدد صور قبل الإنهاء: \(objectMinimumImages)", value: $objectMinimumImages, in: 1...60)
                Stepper("عدد الجولات الموصى به: \(objectRecommendedPasses)", value: $objectRecommendedPasses, in: 1...5)
                Toggle("High Feature Sensitivity", isOn: $objectHighFeatureSensitivity)
                Toggle("Object Masking", isOn: $objectMasking)
                Toggle("الاحتفاظ بصور المصدر", isOn: $objectKeepSourceImages)
            } header: {
                Label("مسح المجسمات — Object Capture", systemImage: "cube.transparent")
            } footer: {
                Text("كمية البيانات الفعلية تتحكم فيها الجولات، Over Capture، والإيقاف اليدوي. أثناء المسح سيعرض Apple Capture Dial والـPoint Cloud بدل نسبة تقديرية مصنوعة من عدد الصور.")
            }

            Section("المعالجة على iPhone") {
                LabeledContent("جودة إعادة البناء", value: "Reduced")
                Text("RealityKit يدعم .reduced فقط لإعادة البناء على iOS. للحصول على تفاصيل أعلى لمساحات كبيرة، احتفظ بصور المصدر لمعالجتها لاحقًا على Mac بمستوى أعلى.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section {
                Button("استعادة الإعدادات الافتراضية", role: .destructive) {
                    showResetConfirmation = true
                }
            }
        }
        .navigationTitle("إعدادات المسح 3D")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { Color3DScanSettings.registerDefaults() }
        .confirmationDialog("استعادة إعدادات المسح الافتراضية؟", isPresented: $showResetConfirmation) {
            Button("استعادة", role: .destructive) {
                Color3DScanSettings.resetAll()
                areaAutoCapture = true
                areaHaptics = true
                areaOverCapture = false
                areaKeepSourceImages = true
                areaMinimumImages = 12
                objectAutoCapture = true
                objectHaptics = true
                objectOverCapture = false
                objectMinimumImages = 16
                objectRecommendedPasses = 3
                objectHighFeatureSensitivity = true
                objectMasking = true
                objectKeepSourceImages = true
                objectSizePresetRaw = ObjectScanSizePreset.medium.rawValue
            }
            Button("إلغاء", role: .cancel) {}
        }
    }
}
