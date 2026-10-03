import Foundation
import SwiftUI

struct Color3DScanSettingsView: View {
    @AppStorage(Color3DScanSettings.Key.roomQualityPreset) private var roomPresetRaw = Color3DScanQualityPreset.balanced.rawValue
    @AppStorage(Color3DScanSettings.Key.areaMaximumKeyframes) private var maximumKeyframes = 64
    @AppStorage(Color3DScanSettings.Key.areaImageMaxDimension) private var imageMaxDimension = 1024
    @AppStorage(Color3DScanSettings.Key.areaJPEGQuality) private var jpegQuality = 0.88
    @AppStorage(Color3DScanSettings.Key.areaMinimumCaptureInterval) private var captureInterval = 0.75
    @AppStorage(Color3DScanSettings.Key.areaMinimumTranslation) private var minimumTranslation = 0.10
    @AppStorage(Color3DScanSettings.Key.areaMinimumRotationDegrees) private var minimumRotationDegrees = 6.0
    @AppStorage(Color3DScanSettings.Key.areaMaximumTextureFrames) private var maximumTextureFrames = 12
    @AppStorage(Color3DScanSettings.Key.areaShowSceneMesh) private var showSceneMesh = true
    @AppStorage(Color3DScanSettings.Key.areaUseSmoothedDepth) private var useSmoothedDepth = true
    @AppStorage(Color3DScanSettings.Key.areaExportPLY) private var exportPLY = true
    @AppStorage(Color3DScanSettings.Key.areaExportOBJ) private var exportOBJ = true
    @AppStorage(Color3DScanSettings.Key.areaExportUSDZ) private var exportUSDZ = true

    @AppStorage(Color3DScanSettings.Key.objectDensityPreset) private var objectPresetRaw = ObjectScanDensityPreset.balanced.rawValue
    @AppStorage(Color3DScanSettings.Key.objectAutoCapture) private var objectAutoCapture = true
    @AppStorage(Color3DScanSettings.Key.objectHaptics) private var objectHaptics = true
    @AppStorage(Color3DScanSettings.Key.objectTargetImages) private var objectTargetImages = 48
    @AppStorage(Color3DScanSettings.Key.objectMinimumImages) private var objectMinimumImages = 16
    @AppStorage(Color3DScanSettings.Key.objectImageMaxDimension) private var objectImageMaxDimension = 1440
    @AppStorage(Color3DScanSettings.Key.objectJPEGQuality) private var objectJPEGQuality = 0.90
    @AppStorage(Color3DScanSettings.Key.objectCaptureInterval) private var objectCaptureInterval = 0.70
    @AppStorage(Color3DScanSettings.Key.objectAngularStepDegrees) private var objectAngularStepDegrees = 8.0
    @AppStorage(Color3DScanSettings.Key.objectHighFeatureSensitivity) private var objectHighFeatureSensitivity = true
    @AppStorage(Color3DScanSettings.Key.objectMasking) private var objectMasking = true
    @AppStorage(Color3DScanSettings.Key.objectUseSmoothedDepth) private var objectUseSmoothedDepth = true
    @AppStorage(Color3DScanSettings.Key.objectSizePreset) private var objectSizePresetRaw = ObjectScanSizePreset.medium.rawValue
    @AppStorage(Color3DScanSettings.Key.objectKeepSourceImages) private var keepObjectSourceImages = true

    @State private var showResetConfirmation = false

    private var selectedRoomPreset: Binding<Color3DScanQualityPreset> {
        Binding(
            get: { Color3DScanQualityPreset(rawValue: roomPresetRaw) ?? .balanced },
            set: { newValue in
                roomPresetRaw = newValue.rawValue
                Color3DScanSettings.applyAreaPreset(newValue)
                syncFromDefaults()
            }
        )
    }

    private var selectedObjectPreset: Binding<ObjectScanDensityPreset> {
        Binding(
            get: { ObjectScanDensityPreset(rawValue: objectPresetRaw) ?? .balanced },
            set: { newValue in
                objectPresetRaw = newValue.rawValue
                Color3DScanSettings.applyObjectPreset(newValue)
                syncFromDefaults()
            }
        )
    }

    private var selectedObjectSize: Binding<ObjectScanSizePreset> {
        Binding(
            get: { ObjectScanSizePreset(rawValue: objectSizePresetRaw) ?? .medium },
            set: { objectSizePresetRaw = $0.rawValue }
        )
    }

    var body: some View {
        Form {
            Section {
                Picker("جودة مسح الغرفة", selection: selectedRoomPreset) {
                    ForEach(Color3DScanQualityPreset.allCases) { preset in
                        VStack(alignment: .leading) {
                            Text(preset.title)
                            Text(preset.subtitle)
                        }
                        .tag(preset)
                    }
                }
                .pickerStyle(.navigationLink)

                Text("الجودة الأعلى تجمع صور RGB أكثر وبدقة أعلى. كثافة LiDAR الخام نفسها يحددها ARKit والجهاز.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } header: {
                Label("مسح الغرفة / المكان", systemImage: "house.lodge")
            }

            Section("تغطية الغرفة وجودة اللون") {
                Stepper("أقصى عدد لصور RGB: \(maximumKeyframes)", value: $maximumKeyframes, in: 12...180, step: 4)

                Picker("دقة صورة اللون", selection: $imageMaxDimension) {
                    Text("720 px").tag(720)
                    Text("1024 px").tag(1024)
                    Text("1440 px").tag(1440)
                    Text("1920 px").tag(1920)
                }

                percentageSlider(title: "جودة JPEG", value: $jpegQuality, range: 0.65...1.0)

                Stepper("عدد صور الخامات: \(maximumTextureFrames)", value: $maximumTextureFrames, in: 4...32, step: 2)

                decimalSlider(
                    title: "أقل فاصل بين الصور",
                    suffix: "ث",
                    value: $captureInterval,
                    range: 0.20...2.0,
                    step: 0.05
                )

                distanceSlider(
                    title: "أقل حركة لالتقاط صورة",
                    value: $minimumTranslation,
                    range: 0.02...0.30
                )

                degreeSlider(
                    title: "أقل دوران لالتقاط صورة",
                    value: $minimumRotationDegrees,
                    range: 1...15
                )
            }

            Section("LiDAR أثناء مسح الغرفة") {
                Toggle("استخدام Smoothed Scene Depth", isOn: $useSmoothedDepth)
                Toggle("إظهار شبكة LiDAR أثناء المسح", isOn: $showSceneMesh)
                Text("المعاينة بعد المسح تستخدم الآن عارض Apple/SceneKit القياسي مثل عارض RoomScan، بدون وضع Fly Camera القديم.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("ملفات تصدير الغرفة") {
                Toggle("PLY ملوّن", isOn: $exportPLY)
                Toggle("OBJ + MTL + Textures", isOn: $exportOBJ)
                Toggle("USDZ بخامات الصور", isOn: $exportUSDZ)
            }

            Section {
                Picker("كثافة بيانات المجسم", selection: selectedObjectPreset) {
                    ForEach(ObjectScanDensityPreset.allCases) { preset in
                        VStack(alignment: .leading) {
                            Text(preset.title)
                            Text(preset.subtitle)
                        }
                        .tag(preset)
                    }
                }
                .pickerStyle(.navigationLink)

                Picker("الحجم التقريبي للمجسم", selection: selectedObjectSize) {
                    ForEach(ObjectScanSizePreset.allCases) { preset in
                        VStack(alignment: .leading) {
                            Text(preset.title)
                            Text(preset.subtitle)
                        }
                        .tag(preset)
                    }
                }
                .pickerStyle(.navigationLink)

                Text("اختيار الحجم لا يفرض صندوقًا على المجسم؛ يستخدم فقط لضبط إرشادات المسافة أثناء الالتفاف حول الهدف الذي تختاره باللمس.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } header: {
                Label("مسح المجسمات", systemImage: "cube.transparent")
            }

            Section("كمية بيانات المجسم") {
                Toggle("التقاط تلقائي أثناء الالتفاف", isOn: $objectAutoCapture)
                Toggle("اهتزاز عند تحديد الهدف/التقاط صورة", isOn: $objectHaptics)

                Stepper("العدد المستهدف للصور: \(objectTargetImages)", value: $objectTargetImages, in: 12...120, step: 4)
                Stepper("أقل عدد صور قبل الإنهاء: \(objectMinimumImages)", value: $objectMinimumImages, in: 6...60, step: 2)

                Picker("دقة صور المجسم", selection: $objectImageMaxDimension) {
                    Text("1024 px").tag(1024)
                    Text("1440 px").tag(1440)
                    Text("1920 px").tag(1920)
                }

                percentageSlider(title: "جودة JPEG للمجسم", value: $objectJPEGQuality, range: 0.70...1.0)

                decimalSlider(
                    title: "أقل فاصل بين الصور",
                    suffix: "ث",
                    value: $objectCaptureInterval,
                    range: 0.25...2.0,
                    step: 0.05
                )

                degreeSlider(
                    title: "أقل زاوية جديدة لالتقاط صورة",
                    value: $objectAngularStepDegrees,
                    range: 2...20
                )
            }

            Section("إعادة بناء المجسم") {
                Toggle("حساسية عالية للتفاصيل", isOn: $objectHighFeatureSensitivity)
                Toggle("عزل المجسم عن الخلفية", isOn: $objectMasking)
                Toggle("استخدام Smoothed Depth عند اختيار الهدف", isOn: $objectUseSmoothedDepth)
                Toggle("الاحتفاظ بصور المصدر بعد إنشاء النموذج", isOn: $keepObjectSourceImages)

                Text("على iPhone إعادة البناء المحلية تستخدم مستوى RealityKit المحمول (.reduced). التحكم هنا يرفع أو يخفض جودة وكمية صور المصدر والتعرف على التفاصيل، وهو العامل الأهم قبل إعادة البناء.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section {
                Button("إعادة إعدادات المسح 3D للوضع الافتراضي", role: .destructive) {
                    showResetConfirmation = true
                }
            }
        }
        .navigationTitle("إعدادات المسح 3D")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            Color3DScanSettings.registerDefaults()
            syncFromDefaults()
        }
        .confirmationDialog("إعادة جميع إعدادات هذا القسم؟", isPresented: $showResetConfirmation) {
            Button("إعادة الافتراضي", role: .destructive) {
                Color3DScanSettings.resetAll()
                syncFromDefaults()
            }
            Button("إلغاء", role: .cancel) {}
        }
    }

    private func percentageSlider(title: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                Spacer()
                Text("\(Int(value.wrappedValue * 100))%")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            Slider(value: value, in: range, step: 0.01)
        }
    }

    private func decimalSlider(
        title: String,
        suffix: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                Spacer()
                Text(String(format: "%.2f %@", value.wrappedValue, suffix))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            Slider(value: value, in: range, step: step)
        }
    }

    private func distanceSlider(title: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                Spacer()
                Text("\(Int(value.wrappedValue * 100)) سم")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            Slider(value: value, in: range, step: 0.01)
        }
    }

    private func degreeSlider(title: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                Spacer()
                Text("\(Int(value.wrappedValue))°")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            Slider(value: value, in: range, step: 1)
        }
    }

    private func syncFromDefaults() {
        let defaults = UserDefaults.standard
        roomPresetRaw = defaults.string(forKey: Color3DScanSettings.Key.roomQualityPreset) ?? Color3DScanQualityPreset.balanced.rawValue
        maximumKeyframes = defaults.integer(forKey: Color3DScanSettings.Key.areaMaximumKeyframes)
        imageMaxDimension = defaults.integer(forKey: Color3DScanSettings.Key.areaImageMaxDimension)
        jpegQuality = defaults.double(forKey: Color3DScanSettings.Key.areaJPEGQuality)
        captureInterval = defaults.double(forKey: Color3DScanSettings.Key.areaMinimumCaptureInterval)
        minimumTranslation = defaults.double(forKey: Color3DScanSettings.Key.areaMinimumTranslation)
        minimumRotationDegrees = defaults.double(forKey: Color3DScanSettings.Key.areaMinimumRotationDegrees)
        maximumTextureFrames = defaults.integer(forKey: Color3DScanSettings.Key.areaMaximumTextureFrames)
        showSceneMesh = defaults.bool(forKey: Color3DScanSettings.Key.areaShowSceneMesh)
        useSmoothedDepth = defaults.bool(forKey: Color3DScanSettings.Key.areaUseSmoothedDepth)
        exportPLY = defaults.bool(forKey: Color3DScanSettings.Key.areaExportPLY)
        exportOBJ = defaults.bool(forKey: Color3DScanSettings.Key.areaExportOBJ)
        exportUSDZ = defaults.bool(forKey: Color3DScanSettings.Key.areaExportUSDZ)

        objectPresetRaw = defaults.string(forKey: Color3DScanSettings.Key.objectDensityPreset) ?? ObjectScanDensityPreset.balanced.rawValue
        objectAutoCapture = defaults.bool(forKey: Color3DScanSettings.Key.objectAutoCapture)
        objectHaptics = defaults.bool(forKey: Color3DScanSettings.Key.objectHaptics)
        objectTargetImages = defaults.integer(forKey: Color3DScanSettings.Key.objectTargetImages)
        objectMinimumImages = defaults.integer(forKey: Color3DScanSettings.Key.objectMinimumImages)
        objectImageMaxDimension = defaults.integer(forKey: Color3DScanSettings.Key.objectImageMaxDimension)
        objectJPEGQuality = defaults.double(forKey: Color3DScanSettings.Key.objectJPEGQuality)
        objectCaptureInterval = defaults.double(forKey: Color3DScanSettings.Key.objectCaptureInterval)
        objectAngularStepDegrees = defaults.double(forKey: Color3DScanSettings.Key.objectAngularStepDegrees)
        objectHighFeatureSensitivity = defaults.bool(forKey: Color3DScanSettings.Key.objectHighFeatureSensitivity)
        objectMasking = defaults.bool(forKey: Color3DScanSettings.Key.objectMasking)
        objectUseSmoothedDepth = defaults.bool(forKey: Color3DScanSettings.Key.objectUseSmoothedDepth)
        objectSizePresetRaw = defaults.string(forKey: Color3DScanSettings.Key.objectSizePreset) ?? ObjectScanSizePreset.medium.rawValue
        keepObjectSourceImages = defaults.bool(forKey: Color3DScanSettings.Key.objectKeepSourceImages)
    }
}
