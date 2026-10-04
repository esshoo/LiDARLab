import Foundation
import SwiftUI

struct Color3DScanSettingsView: View {
    @AppStorage(Color3DScanSettings.Key.appleAreaAutoCapture) private var areaAutoCapture = true
    @AppStorage(Color3DScanSettings.Key.appleAreaHaptics) private var areaHaptics = true
    @AppStorage(Color3DScanSettings.Key.appleAreaOverCapture) private var areaOverCapture = false
    @AppStorage(Color3DScanSettings.Key.appleAreaKeepSourceImages) private var areaKeepSourceImages = true
    @AppStorage(Color3DScanSettings.Key.appleAreaMinimumImages) private var areaMinimumImages = 12
    @AppStorage(Color3DScanSettings.Key.appleAreaHighFeatureSensitivity) private var areaHighFeatureSensitivity = true
    @AppStorage(Color3DScanSettings.Key.appleAreaRecoverEntireScene) private var areaRecoverEntireScene = true

    @AppStorage(Color3DScanSettings.Key.objectAutoCapture) private var objectAutoCapture = true
    @AppStorage(Color3DScanSettings.Key.objectHaptics) private var objectHaptics = true
    @AppStorage(Color3DScanSettings.Key.appleObjectOverCapture) private var objectOverCapture = false
    @AppStorage(Color3DScanSettings.Key.objectMinimumImages) private var objectMinimumImages = 12
    @AppStorage(Color3DScanSettings.Key.appleObjectRecommendedPasses) private var objectRecommendedPasses = 3
    @AppStorage(Color3DScanSettings.Key.objectHighFeatureSensitivity) private var objectHighFeatureSensitivity = true
    @AppStorage(Color3DScanSettings.Key.objectMasking) private var objectMasking = true
    @AppStorage(Color3DScanSettings.Key.objectKeepSourceImages) private var objectKeepSourceImages = true
    @AppStorage(Color3DScanSettings.Key.objectSizePreset) private var objectSizePresetRaw = ObjectScanSizePreset.medium.rawValue
    @AppStorage(Color3DScanSettings.Key.appleObjectShowPreselectionMesh) private var objectShowPreselectionMesh = true
    @AppStorage(Color3DScanSettings.Key.appleObjectPreferCompletedPassBeforeFinish) private var objectPreferCompletedPassBeforeFinish = true

    @AppStorage(Color3DScanSettings.Key.turntableAutoCapture) private var turntableAutoCapture = true
    @AppStorage(Color3DScanSettings.Key.turntableImagesPerPass) private var turntableImagesPerPass = 48
    @AppStorage(Color3DScanSettings.Key.turntableCaptureInterval) private var turntableCaptureInterval = 0.85

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
                Toggle("حساسية تفاصيل عالية", isOn: $areaHighFeatureSensitivity)
                Toggle("استخراج كل هندسة المشهد", isOn: $areaRecoverEntireScene)
                Toggle("الاحتفاظ بصور المصدر", isOn: $areaKeepSourceImages)
            } header: {
                Label("مسح منطقة / سطح — Apple Area Mode", systemImage: "square.3.layers.3d")
            } footer: {
                Text("Area Mode هنا مخصص للمسح البصري الملون لمنطقة أو سطح أو مشهد محدود. عند تفعيل استخراج كل هندسة المشهد نوقف Object Masking ونتجاهل أي Bounding Box أثناء إعادة البناء.")
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
                Toggle("شبكة LiDAR أثناء اختيار الهدف", isOn: $objectShowPreselectionMesh)
                Toggle("تحذير قبل الإنهاء بدون جولات مكتملة", isOn: $objectPreferCompletedPassBeforeFinish)
                Toggle("الاحتفاظ بصور المصدر", isOn: $objectKeepSourceImages)
            } header: {
                Label("مسح المجسمات — Object Capture", systemImage: "cube.transparent")
            } footer: {
                Text("أثناء الالتقاط يعرض ObjectCaptureView نفسه Point Cloud وCapture Dial. بعد اكتمال كل جولة ينتقل التطبيق تلقائيًا إلى مراجعة Point Cloud قبل أن تختار جولة جديدة أو إنهاء المسح. شبكة LiDAR المبدئية تظهر فقط في مرحلة اختيار الهدف قبل تسليم الكاميرا إلى Object Capture.")
            }

            Section {
                Toggle("التقاط تلقائي أثناء دوران المجسم", isOn: $turntableAutoCapture)
                Stepper("صور لكل دورة: \(turntableImagesPerPass)", value: $turntableImagesPerPass, in: 18...120, step: 6)
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("الفاصل بين الصور")
                        Spacer()
                        Text(String(format: "%.2f ث", turntableCaptureInterval))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $turntableCaptureInterval, in: 0.35...3.0, step: 0.05)
                }
            } header: {
                Label("وضع Turntable — كاميرا ثابتة", systemImage: "arrow.triangle.2.circlepath.camera")
            } footer: {
                Text("ثبّت الهاتف على حامل ولف المجسم ببطء. عدد أكبر من الصور وفاصل أقصر يعطي تداخلًا أعلى لكنه يزيد وقت المعالجة. إعدادات High Feature Sensitivity وObject Masking والاحتفاظ بالصور تُشارك مع إعدادات Object Capture أعلاه.")
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
                areaHighFeatureSensitivity = true
                areaRecoverEntireScene = true
                objectAutoCapture = true
                objectHaptics = true
                objectOverCapture = false
                objectMinimumImages = 16
                objectRecommendedPasses = 3
                objectHighFeatureSensitivity = true
                objectMasking = true
                objectKeepSourceImages = true
                objectSizePresetRaw = ObjectScanSizePreset.medium.rawValue
                objectShowPreselectionMesh = true
                objectPreferCompletedPassBeforeFinish = true
                turntableAutoCapture = true
                turntableImagesPerPass = 48
                turntableCaptureInterval = 0.85
            }
            Button("إلغاء", role: .cancel) {}
        }
    }
}
