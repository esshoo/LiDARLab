import Foundation
import SwiftUI

struct Color3DScanSettingsView: View {
    @AppStorage(Color3DScanSettings.Key.roomQualityPreset) private var presetRaw = Color3DScanQualityPreset.balanced.rawValue
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
    @AppStorage(Color3DScanSettings.Key.previewFreeCamera) private var previewFreeCamera = true
    @AppStorage(Color3DScanSettings.Key.objectAutoCapture) private var objectAutoCapture = true
    @AppStorage(Color3DScanSettings.Key.objectHaptics) private var objectHaptics = true
    @AppStorage(Color3DScanSettings.Key.objectMinimumImages) private var objectMinimumImages = 20
    @AppStorage(Color3DScanSettings.Key.objectKeepSourceImages) private var keepObjectSourceImages = true

    @State private var showResetConfirmation = false

    private var selectedPreset: Binding<Color3DScanQualityPreset> {
        Binding(
            get: { Color3DScanQualityPreset(rawValue: presetRaw) ?? .balanced },
            set: { newValue in
                presetRaw = newValue.rawValue
                Color3DScanSettings.applyPreset(newValue)
                syncFromDefaults()
            }
        )
    }

    var body: some View {
        Form {
            Section {
                Picker("جودة مسح الغرفة", selection: selectedPreset) {
                    ForEach(Color3DScanQualityPreset.allCases) { preset in
                        VStack(alignment: .leading) {
                            Text(preset.title)
                            Text(preset.subtitle)
                        }
                        .tag(preset)
                    }
                }
                .pickerStyle(.navigationLink)

                Text("الجودة الأعلى تجمع صور RGB أكثر وبدقة أعلى. كثافة نقاط LiDAR الخام نفسها يتحكم فيها ARKit والجهاز، ولا يمكن إجبار الحساس على دقة أعلى من قدرته.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } header: {
                Label("مسح الغرفة / المكان", systemImage: "house.lodge")
            }

            Section("التغطية وجودة اللون") {
                Stepper("أقصى عدد لصور RGB: \(maximumKeyframes)", value: $maximumKeyframes, in: 12...180, step: 4)

                Picker("دقة صورة اللون", selection: $imageMaxDimension) {
                    Text("720 px").tag(720)
                    Text("1024 px").tag(1024)
                    Text("1440 px").tag(1440)
                    Text("1920 px").tag(1920)
                }

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("جودة JPEG")
                        Spacer()
                        Text("\(Int(jpegQuality * 100))%")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $jpegQuality, in: 0.65...1.0, step: 0.01)
                }

                Stepper("عدد صور الخامات: \(maximumTextureFrames)", value: $maximumTextureFrames, in: 4...32, step: 2)

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("أقل فاصل بين الصور")
                        Spacer()
                        Text(String(format: "%.2f ث", captureInterval))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $captureInterval, in: 0.20...2.0, step: 0.05)
                }

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("أقل حركة لالتقاط صورة")
                        Spacer()
                        Text("\(Int(minimumTranslation * 100)) سم")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $minimumTranslation, in: 0.02...0.30, step: 0.01)
                }

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("أقل دوران لالتقاط صورة")
                        Spacer()
                        Text("\(Int(minimumRotationDegrees))°")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $minimumRotationDegrees, in: 1...15, step: 1)
                }
            }

            Section("LiDAR والمعاينة") {
                Toggle("استخدام Smoothed Scene Depth", isOn: $useSmoothedDepth)
                Toggle("إظهار شبكة LiDAR أثناء المسح", isOn: $showSceneMesh)
                Toggle("فتح المعاينة بكاميرا حرة للدخول داخل الغرفة", isOn: $previewFreeCamera)
            }

            Section("ملفات التصدير") {
                Toggle("PLY ملوّن", isOn: $exportPLY)
                Toggle("OBJ + MTL + Textures", isOn: $exportOBJ)
                Toggle("USDZ بخامات الصور", isOn: $exportUSDZ)
                Text("OBJ وUSDZ يستخدمان صور الكاميرا كخامات فعلية بدل الاكتفاء بألوان نقاط الـMesh.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section {
                if #available(iOS 18.0, *) {
                    Toggle("التقاط تلقائي للصور", isOn: $objectAutoCapture)
                    Toggle("اهتزازات أثناء الالتقاط", isOn: $objectHaptics)
                } else {
                    LabeledContent("التقاط تلقائي / اهتزازات", value: "يتطلب iOS 18+")
                        .foregroundStyle(.secondary)
                }

                Stepper("أقل عدد صور قبل السماح بالإنهاء: \(objectMinimumImages)", value: $objectMinimumImages, in: 8...60, step: 2)
                Toggle("الاحتفاظ بصور المصدر بعد إنشاء النموذج", isOn: $keepObjectSourceImages)
            } header: {
                Label("مسح المجسمات", systemImage: "cube.transparent")
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

    private func syncFromDefaults() {
        let defaults = UserDefaults.standard
        presetRaw = defaults.string(forKey: Color3DScanSettings.Key.roomQualityPreset) ?? Color3DScanQualityPreset.balanced.rawValue
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
        previewFreeCamera = defaults.bool(forKey: Color3DScanSettings.Key.previewFreeCamera)
        objectAutoCapture = defaults.bool(forKey: Color3DScanSettings.Key.objectAutoCapture)
        objectHaptics = defaults.bool(forKey: Color3DScanSettings.Key.objectHaptics)
        objectMinimumImages = defaults.integer(forKey: Color3DScanSettings.Key.objectMinimumImages)
        keepObjectSourceImages = defaults.bool(forKey: Color3DScanSettings.Key.objectKeepSourceImages)
    }
}
