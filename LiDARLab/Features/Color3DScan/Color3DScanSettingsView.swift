import Foundation
import SwiftUI

struct Color3DScanSettingsView: View {
    @AppStorage(Color3DScanSettings.Key.keepScreenAwake) private var keepScreenAwake = true
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
    @AppStorage(Color3DScanSettings.Key.turntableCaptureMode) private var turntableCaptureModeRaw = TurntableCaptureMode.smartAutomatic.rawValue
    @AppStorage(Color3DScanSettings.Key.turntableNoveltyThreshold) private var turntableNoveltyThreshold = 3.5
    @AppStorage(Color3DScanSettings.Key.turntableStabilityThreshold) private var turntableStabilityThreshold = 0.85
    @AppStorage(Color3DScanSettings.Key.turntableImagesPerPass) private var turntableImagesPerPass = 48
    @AppStorage(Color3DScanSettings.Key.turntableCaptureInterval) private var turntableCaptureInterval = 0.75

    @State private var showResetConfirmation = false

    private var selectedObjectSize: Binding<ObjectScanSizePreset> {
        Binding(
            get: { ObjectScanSizePreset(rawValue: objectSizePresetRaw) ?? .medium },
            set: { objectSizePresetRaw = $0.rawValue }
        )
    }


    private var selectedTurntableCaptureMode: Binding<TurntableCaptureMode> {
        Binding(
            get: { TurntableCaptureMode(rawValue: turntableCaptureModeRaw) ?? .smartAutomatic },
            set: {
                turntableCaptureModeRaw = $0.rawValue
                turntableAutoCapture = ($0 == .smartAutomatic)
            }
        )
    }

    var body: some View {
        Form {
            Section {
                Toggle("منع إطفاء الشاشة أثناء المسح", isOn: $keepScreenAwake)
            } header: {
                Label("عام أثناء المسح", systemImage: "display")
            } footer: {
                Text("عند التفعيل يوقف التطبيق مؤقتًا مؤقت قفل الشاشة فقط أثناء جلسة المسح، ثم يعيد السلوك السابق عند الخروج.")
            }

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
                Picker("طريقة الالتقاط", selection: selectedTurntableCaptureMode) {
                    ForEach(TurntableCaptureMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                Stepper("الحد الأعلى للصور في الجولة: \(turntableImagesPerPass)", value: $turntableImagesPerPass, in: 12...120, step: 6)

                if selectedTurntableCaptureMode.wrappedValue == .smartAutomatic {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("حساسية اكتشاف زاوية جديدة")
                            Spacer()
                            Text(String(format: "%.1f", turntableNoveltyThreshold))
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                        Slider(value: $turntableNoveltyThreshold, in: 0.5...12.0, step: 0.25)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("شرط هدوء الحركة")
                            Spacer()
                            Text(String(format: "%.2f", turntableStabilityThreshold))
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                        Slider(value: $turntableStabilityThreshold, in: 0.2...2.5, step: 0.05)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("أقل فاصل بين صورتين")
                            Spacer()
                            Text(String(format: "%.2f ث", turntableCaptureInterval))
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                        Slider(value: $turntableCaptureInterval, in: 0.25...2.0, step: 0.05)
                    }
                }
            } header: {
                Label("وضع Turntable — كاميرا ثابتة", systemImage: "arrow.triangle.2.circlepath.camera")
            } footer: {
                Text("في التلقائي الذكي يستخدم التطبيق تحليل تشابه بصري بين إطارات الكاميرا: لا يلتقط صورة جديدة إلا بعد تغيّر شكل المجسم عن اللقطات السابقة ثم هدوء الحركة. الوضع اليدوي لا يلتقط أي صورة إلا عند الضغط على زر التصوير.")
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
                keepScreenAwake = true
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
                turntableCaptureModeRaw = TurntableCaptureMode.smartAutomatic.rawValue
                turntableNoveltyThreshold = 3.5
                turntableStabilityThreshold = 0.85
                turntableImagesPerPass = 48
                turntableCaptureInterval = 0.75
            }
            Button("إلغاء", role: .cancel) {}
        }
    }
}
