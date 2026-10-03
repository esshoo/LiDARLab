import Foundation

enum Color3DScanQualityPreset: String, CaseIterable, Identifiable, Hashable {
    case fast
    case balanced
    case high
    case ultra

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fast: "سريع"
        case .balanced: "متوازن"
        case .high: "عالي"
        case .ultra: "فائق"
        }
    }

    var subtitle: String {
        switch self {
        case .fast: "أسرع معالجة وأقل حجم"
        case .balanced: "أفضل توازن للاستخدام اليومي"
        case .high: "صور أكثر وخامات أوضح"
        case .ultra: "أعلى تغطية وجودة متاحة داخل الهاتف"
        }
    }

    var recommended: AreaScanRuntimeOptions {
        switch self {
        case .fast:
            return AreaScanRuntimeOptions(
                maximumKeyframes: 36,
                imageMaxDimension: 720,
                jpegQuality: 0.82,
                minimumCaptureInterval: 1.05,
                minimumTranslation: 0.14,
                minimumRotationDegrees: 8,
                maximumTextureFrames: 8,
                showSceneMeshWhileScanning: true,
                useSmoothedDepth: true,
                exportPLY: true,
                exportOBJ: true,
                exportUSDZ: true,
                previewFreeCamera: true
            )
        case .balanced:
            return AreaScanRuntimeOptions(
                maximumKeyframes: 64,
                imageMaxDimension: 1024,
                jpegQuality: 0.88,
                minimumCaptureInterval: 0.75,
                minimumTranslation: 0.10,
                minimumRotationDegrees: 6,
                maximumTextureFrames: 12,
                showSceneMeshWhileScanning: true,
                useSmoothedDepth: true,
                exportPLY: true,
                exportOBJ: true,
                exportUSDZ: true,
                previewFreeCamera: true
            )
        case .high:
            return AreaScanRuntimeOptions(
                maximumKeyframes: 96,
                imageMaxDimension: 1440,
                jpegQuality: 0.92,
                minimumCaptureInterval: 0.55,
                minimumTranslation: 0.07,
                minimumRotationDegrees: 4,
                maximumTextureFrames: 16,
                showSceneMeshWhileScanning: true,
                useSmoothedDepth: true,
                exportPLY: true,
                exportOBJ: true,
                exportUSDZ: true,
                previewFreeCamera: true
            )
        case .ultra:
            return AreaScanRuntimeOptions(
                maximumKeyframes: 140,
                imageMaxDimension: 1920,
                jpegQuality: 0.95,
                minimumCaptureInterval: 0.40,
                minimumTranslation: 0.05,
                minimumRotationDegrees: 3,
                maximumTextureFrames: 24,
                showSceneMeshWhileScanning: true,
                useSmoothedDepth: true,
                exportPLY: true,
                exportOBJ: true,
                exportUSDZ: true,
                previewFreeCamera: true
            )
        }
    }
}

struct AreaScanRuntimeOptions {
    let maximumKeyframes: Int
    let imageMaxDimension: Int
    let jpegQuality: Double
    let minimumCaptureInterval: TimeInterval
    let minimumTranslation: Float
    let minimumRotationDegrees: Float
    let maximumTextureFrames: Int
    let showSceneMeshWhileScanning: Bool
    let useSmoothedDepth: Bool
    let exportPLY: Bool
    let exportOBJ: Bool
    let exportUSDZ: Bool
    let previewFreeCamera: Bool

    var minimumRotationRadians: Float {
        minimumRotationDegrees * .pi / 180
    }
}

struct ObjectScanRuntimeOptions {
    let autoCapture: Bool
    let haptics: Bool
    let minimumImagesBeforeFinish: Int
    let keepSourceImages: Bool
}

enum Color3DScanSettings {
    enum Key {
        static let roomQualityPreset = "color3d.settings.room.qualityPreset"
        static let areaMaximumKeyframes = "color3d.settings.area.maximumKeyframes"
        static let areaImageMaxDimension = "color3d.settings.area.imageMaxDimension"
        static let areaJPEGQuality = "color3d.settings.area.jpegQuality"
        static let areaMinimumCaptureInterval = "color3d.settings.area.minimumCaptureInterval"
        static let areaMinimumTranslation = "color3d.settings.area.minimumTranslation"
        static let areaMinimumRotationDegrees = "color3d.settings.area.minimumRotationDegrees"
        static let areaMaximumTextureFrames = "color3d.settings.area.maximumTextureFrames"
        static let areaShowSceneMesh = "color3d.settings.area.showSceneMesh"
        static let areaUseSmoothedDepth = "color3d.settings.area.useSmoothedDepth"
        static let areaExportPLY = "color3d.settings.area.exportPLY"
        static let areaExportOBJ = "color3d.settings.area.exportOBJ"
        static let areaExportUSDZ = "color3d.settings.area.exportUSDZ"
        static let previewFreeCamera = "color3d.settings.preview.freeCamera"
        static let objectAutoCapture = "color3d.settings.object.autoCapture"
        static let objectHaptics = "color3d.settings.object.haptics"
        static let objectMinimumImages = "color3d.settings.object.minimumImages"
        static let objectKeepSourceImages = "color3d.settings.object.keepSourceImages"
    }

    private static let defaults = UserDefaults.standard

    static func registerDefaults() {
        let options = Color3DScanQualityPreset.balanced.recommended
        defaults.register(defaults: [
            Key.roomQualityPreset: Color3DScanQualityPreset.balanced.rawValue,
            Key.areaMaximumKeyframes: options.maximumKeyframes,
            Key.areaImageMaxDimension: options.imageMaxDimension,
            Key.areaJPEGQuality: options.jpegQuality,
            Key.areaMinimumCaptureInterval: options.minimumCaptureInterval,
            Key.areaMinimumTranslation: Double(options.minimumTranslation),
            Key.areaMinimumRotationDegrees: Double(options.minimumRotationDegrees),
            Key.areaMaximumTextureFrames: options.maximumTextureFrames,
            Key.areaShowSceneMesh: options.showSceneMeshWhileScanning,
            Key.areaUseSmoothedDepth: options.useSmoothedDepth,
            Key.areaExportPLY: options.exportPLY,
            Key.areaExportOBJ: options.exportOBJ,
            Key.areaExportUSDZ: options.exportUSDZ,
            Key.previewFreeCamera: options.previewFreeCamera,
            Key.objectAutoCapture: true,
            Key.objectHaptics: true,
            Key.objectMinimumImages: 20,
            Key.objectKeepSourceImages: true
        ])
    }

    static var areaOptions: AreaScanRuntimeOptions {
        registerDefaults()
        return AreaScanRuntimeOptions(
            maximumKeyframes: max(12, defaults.integer(forKey: Key.areaMaximumKeyframes)),
            imageMaxDimension: max(480, defaults.integer(forKey: Key.areaImageMaxDimension)),
            jpegQuality: min(max(defaults.double(forKey: Key.areaJPEGQuality), 0.55), 1.0),
            minimumCaptureInterval: min(max(defaults.double(forKey: Key.areaMinimumCaptureInterval), 0.20), 3.0),
            minimumTranslation: Float(min(max(defaults.double(forKey: Key.areaMinimumTranslation), 0.02), 0.50)),
            minimumRotationDegrees: Float(min(max(defaults.double(forKey: Key.areaMinimumRotationDegrees), 1), 25)),
            maximumTextureFrames: max(4, defaults.integer(forKey: Key.areaMaximumTextureFrames)),
            showSceneMeshWhileScanning: defaults.bool(forKey: Key.areaShowSceneMesh),
            useSmoothedDepth: defaults.bool(forKey: Key.areaUseSmoothedDepth),
            exportPLY: defaults.bool(forKey: Key.areaExportPLY),
            exportOBJ: defaults.bool(forKey: Key.areaExportOBJ),
            exportUSDZ: defaults.bool(forKey: Key.areaExportUSDZ),
            previewFreeCamera: defaults.bool(forKey: Key.previewFreeCamera)
        )
    }

    static var objectOptions: ObjectScanRuntimeOptions {
        registerDefaults()
        return ObjectScanRuntimeOptions(
            autoCapture: defaults.bool(forKey: Key.objectAutoCapture),
            haptics: defaults.bool(forKey: Key.objectHaptics),
            minimumImagesBeforeFinish: max(8, defaults.integer(forKey: Key.objectMinimumImages)),
            keepSourceImages: defaults.bool(forKey: Key.objectKeepSourceImages)
        )
    }

    static func applyPreset(_ preset: Color3DScanQualityPreset) {
        let value = preset.recommended
        defaults.set(preset.rawValue, forKey: Key.roomQualityPreset)
        defaults.set(value.maximumKeyframes, forKey: Key.areaMaximumKeyframes)
        defaults.set(value.imageMaxDimension, forKey: Key.areaImageMaxDimension)
        defaults.set(value.jpegQuality, forKey: Key.areaJPEGQuality)
        defaults.set(value.minimumCaptureInterval, forKey: Key.areaMinimumCaptureInterval)
        defaults.set(Double(value.minimumTranslation), forKey: Key.areaMinimumTranslation)
        defaults.set(Double(value.minimumRotationDegrees), forKey: Key.areaMinimumRotationDegrees)
        defaults.set(value.maximumTextureFrames, forKey: Key.areaMaximumTextureFrames)
        defaults.set(value.showSceneMeshWhileScanning, forKey: Key.areaShowSceneMesh)
        defaults.set(value.useSmoothedDepth, forKey: Key.areaUseSmoothedDepth)
        defaults.set(value.exportPLY, forKey: Key.areaExportPLY)
        defaults.set(value.exportOBJ, forKey: Key.areaExportOBJ)
        defaults.set(value.exportUSDZ, forKey: Key.areaExportUSDZ)
        defaults.set(value.previewFreeCamera, forKey: Key.previewFreeCamera)
    }

    static func resetAll() {
        for key in [
            Key.roomQualityPreset,
            Key.areaMaximumKeyframes,
            Key.areaImageMaxDimension,
            Key.areaJPEGQuality,
            Key.areaMinimumCaptureInterval,
            Key.areaMinimumTranslation,
            Key.areaMinimumRotationDegrees,
            Key.areaMaximumTextureFrames,
            Key.areaShowSceneMesh,
            Key.areaUseSmoothedDepth,
            Key.areaExportPLY,
            Key.areaExportOBJ,
            Key.areaExportUSDZ,
            Key.previewFreeCamera,
            Key.objectAutoCapture,
            Key.objectHaptics,
            Key.objectMinimumImages,
            Key.objectKeepSourceImages
        ] {
            defaults.removeObject(forKey: key)
        }
        registerDefaults()
    }
}
