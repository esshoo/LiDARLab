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
            AreaScanRuntimeOptions(
                maximumKeyframes: 36,
                imageMaxDimension: 720,
                jpegQuality: 0.82,
                minimumCaptureInterval: 1.05,
                minimumTranslation: 0.14,
                minimumRotationDegrees: 8,
                maximumTextureFrames: 8,
                showSceneMeshWhileScanning: true,
                useSmoothedDepth: true,
                rejectUncertainTextures: true,
                depthOcclusionToleranceMeters: 0.18,
                maximumTextureDistanceMeters: 4.0,
                exportPLY: true,
                exportOBJ: true,
                exportUSDZ: true
            )
        case .balanced:
            AreaScanRuntimeOptions(
                maximumKeyframes: 64,
                imageMaxDimension: 1024,
                jpegQuality: 0.88,
                minimumCaptureInterval: 0.75,
                minimumTranslation: 0.10,
                minimumRotationDegrees: 6,
                maximumTextureFrames: 12,
                showSceneMeshWhileScanning: true,
                useSmoothedDepth: true,
                rejectUncertainTextures: true,
                depthOcclusionToleranceMeters: 0.12,
                maximumTextureDistanceMeters: 4.5,
                exportPLY: true,
                exportOBJ: true,
                exportUSDZ: true
            )
        case .high:
            AreaScanRuntimeOptions(
                maximumKeyframes: 96,
                imageMaxDimension: 1440,
                jpegQuality: 0.92,
                minimumCaptureInterval: 0.55,
                minimumTranslation: 0.07,
                minimumRotationDegrees: 4,
                maximumTextureFrames: 16,
                showSceneMeshWhileScanning: true,
                useSmoothedDepth: true,
                rejectUncertainTextures: true,
                depthOcclusionToleranceMeters: 0.09,
                maximumTextureDistanceMeters: 5.0,
                exportPLY: true,
                exportOBJ: true,
                exportUSDZ: true
            )
        case .ultra:
            AreaScanRuntimeOptions(
                maximumKeyframes: 140,
                imageMaxDimension: 1920,
                jpegQuality: 0.95,
                minimumCaptureInterval: 0.40,
                minimumTranslation: 0.05,
                minimumRotationDegrees: 3,
                maximumTextureFrames: 24,
                showSceneMeshWhileScanning: true,
                useSmoothedDepth: true,
                rejectUncertainTextures: true,
                depthOcclusionToleranceMeters: 0.07,
                maximumTextureDistanceMeters: 5.5,
                exportPLY: true,
                exportOBJ: true,
                exportUSDZ: true
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
    let rejectUncertainTextures: Bool
    let depthOcclusionToleranceMeters: Float
    let maximumTextureDistanceMeters: Float
    let exportPLY: Bool
    let exportOBJ: Bool
    let exportUSDZ: Bool

    var minimumRotationRadians: Float {
        minimumRotationDegrees * .pi / 180
    }
}

enum ObjectScanDensityPreset: String, CaseIterable, Identifiable, Hashable {
    case light
    case balanced
    case high
    case maximum

    var id: String { rawValue }

    var title: String {
        switch self {
        case .light: "خفيف"
        case .balanced: "متوازن"
        case .high: "عالي"
        case .maximum: "أقصى بيانات"
        }
    }

    var subtitle: String {
        switch self {
        case .light: "صور أقل ومعالجة أسرع"
        case .balanced: "مناسب لمعظم المجسمات"
        case .high: "تغطية أدق وتفاصيل أفضل"
        case .maximum: "أكبر عدد صور مسموح به في هذا الوضع"
        }
    }

    var recommended: ObjectScanRuntimeOptions {
        switch self {
        case .light:
            ObjectScanRuntimeOptions(
                autoCapture: true,
                haptics: true,
                targetImageCount: 24,
                minimumImagesBeforeFinish: 10,
                imageMaxDimension: 1024,
                jpegQuality: 0.84,
                minimumCaptureInterval: 1.00,
                minimumAngularStepDegrees: 14,
                highFeatureSensitivity: false,
                objectMasking: true,
                useSmoothedDepthForSelection: true,
                objectSizePreset: .medium,
                keepSourceImages: true
            )
        case .balanced:
            ObjectScanRuntimeOptions(
                autoCapture: true,
                haptics: true,
                targetImageCount: 48,
                minimumImagesBeforeFinish: 16,
                imageMaxDimension: 1440,
                jpegQuality: 0.90,
                minimumCaptureInterval: 0.70,
                minimumAngularStepDegrees: 8,
                highFeatureSensitivity: true,
                objectMasking: true,
                useSmoothedDepthForSelection: true,
                objectSizePreset: .medium,
                keepSourceImages: true
            )
        case .high:
            ObjectScanRuntimeOptions(
                autoCapture: true,
                haptics: true,
                targetImageCount: 72,
                minimumImagesBeforeFinish: 20,
                imageMaxDimension: 1920,
                jpegQuality: 0.94,
                minimumCaptureInterval: 0.50,
                minimumAngularStepDegrees: 5,
                highFeatureSensitivity: true,
                objectMasking: true,
                useSmoothedDepthForSelection: true,
                objectSizePreset: .medium,
                keepSourceImages: true
            )
        case .maximum:
            ObjectScanRuntimeOptions(
                autoCapture: true,
                haptics: true,
                targetImageCount: 100,
                minimumImagesBeforeFinish: 24,
                imageMaxDimension: 1920,
                jpegQuality: 0.97,
                minimumCaptureInterval: 0.35,
                minimumAngularStepDegrees: 3,
                highFeatureSensitivity: true,
                objectMasking: true,
                useSmoothedDepthForSelection: true,
                objectSizePreset: .medium,
                keepSourceImages: true
            )
        }
    }
}

enum ObjectScanSizePreset: String, CaseIterable, Identifiable, Hashable, Codable {
    case small
    case medium
    case large

    var id: String { rawValue }

    var title: String {
        switch self {
        case .small: "صغير"
        case .medium: "متوسط"
        case .large: "كبير"
        }
    }

    var subtitle: String {
        switch self {
        case .small: "تمثال صغير، أداة، قطعة مكتبية"
        case .medium: "كرسي، جهاز، صندوق، قطعة أثاث صغيرة"
        case .large: "قطعة أثاث كبيرة أو مجسم بحجم إنسان تقريبًا"
        }
    }

    var approximateDiameterMeters: Float {
        switch self {
        case .small: 0.25
        case .medium: 0.70
        case .large: 1.60
        }
    }

    var recommendedDistanceRange: ClosedRange<Float> {
        switch self {
        case .small: 0.28...1.10
        case .medium: 0.55...2.30
        case .large: 1.00...4.50
        }
    }
}

struct ObjectScanRuntimeOptions {
    let autoCapture: Bool
    let haptics: Bool
    let targetImageCount: Int
    let minimumImagesBeforeFinish: Int
    let imageMaxDimension: Int
    let jpegQuality: Double
    let minimumCaptureInterval: TimeInterval
    let minimumAngularStepDegrees: Float
    let highFeatureSensitivity: Bool
    let objectMasking: Bool
    let useSmoothedDepthForSelection: Bool
    let objectSizePreset: ObjectScanSizePreset
    let keepSourceImages: Bool

    var minimumAngularStepRadians: Float {
        minimumAngularStepDegrees * .pi / 180
    }
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
        static let areaRejectUncertainTextures = "color3d.settings.area.rejectUncertainTextures"
        static let areaDepthOcclusionTolerance = "color3d.settings.area.depthOcclusionTolerance"
        static let areaMaximumTextureDistance = "color3d.settings.area.maximumTextureDistance"
        static let areaExportPLY = "color3d.settings.area.exportPLY"
        static let areaExportOBJ = "color3d.settings.area.exportOBJ"
        static let areaExportUSDZ = "color3d.settings.area.exportUSDZ"

        static let objectDensityPreset = "color3d.settings.object.densityPreset"
        static let objectAutoCapture = "color3d.settings.object.autoCapture"
        static let objectHaptics = "color3d.settings.object.haptics"
        static let objectTargetImages = "color3d.settings.object.targetImages"
        static let objectMinimumImages = "color3d.settings.object.minimumImages"
        static let objectImageMaxDimension = "color3d.settings.object.imageMaxDimension"
        static let objectJPEGQuality = "color3d.settings.object.jpegQuality"
        static let objectCaptureInterval = "color3d.settings.object.captureInterval"
        static let objectAngularStepDegrees = "color3d.settings.object.angularStepDegrees"
        static let objectHighFeatureSensitivity = "color3d.settings.object.highFeatureSensitivity"
        static let objectMasking = "color3d.settings.object.masking"
        static let objectUseSmoothedDepth = "color3d.settings.object.useSmoothedDepth"
        static let objectSizePreset = "color3d.settings.object.sizePreset"
        static let objectKeepSourceImages = "color3d.settings.object.keepSourceImages"

        // Official RealityKit Object Capture / Area Mode settings.
        static let appleAreaAutoCapture = "color3d.settings.appleArea.autoCapture"
        static let appleAreaHaptics = "color3d.settings.appleArea.haptics"
        static let appleAreaOverCapture = "color3d.settings.appleArea.overCapture"
        static let appleAreaKeepSourceImages = "color3d.settings.appleArea.keepSourceImages"
        static let appleAreaMinimumImages = "color3d.settings.appleArea.minimumImages"
        static let appleAreaHighFeatureSensitivity = "color3d.settings.appleArea.highFeatureSensitivity"
        static let appleAreaRecoverEntireScene = "color3d.settings.appleArea.recoverEntireScene"

        static let appleObjectRecommendedPasses = "color3d.settings.appleObject.recommendedPasses"
        static let appleObjectOverCapture = "color3d.settings.appleObject.overCapture"
        static let appleObjectShowPreselectionMesh = "color3d.settings.appleObject.showPreselectionMesh"
        static let appleObjectPreferCompletedPassBeforeFinish = "color3d.settings.appleObject.preferCompletedPassBeforeFinish"
    }

    private static let defaults = UserDefaults.standard

    static func registerDefaults() {
        let area = Color3DScanQualityPreset.balanced.recommended
        let object = ObjectScanDensityPreset.balanced.recommended
        defaults.register(defaults: [
            Key.roomQualityPreset: Color3DScanQualityPreset.balanced.rawValue,
            Key.areaMaximumKeyframes: area.maximumKeyframes,
            Key.areaImageMaxDimension: area.imageMaxDimension,
            Key.areaJPEGQuality: area.jpegQuality,
            Key.areaMinimumCaptureInterval: area.minimumCaptureInterval,
            Key.areaMinimumTranslation: Double(area.minimumTranslation),
            Key.areaMinimumRotationDegrees: Double(area.minimumRotationDegrees),
            Key.areaMaximumTextureFrames: area.maximumTextureFrames,
            Key.areaShowSceneMesh: area.showSceneMeshWhileScanning,
            Key.areaUseSmoothedDepth: area.useSmoothedDepth,
            Key.areaRejectUncertainTextures: area.rejectUncertainTextures,
            Key.areaDepthOcclusionTolerance: Double(area.depthOcclusionToleranceMeters),
            Key.areaMaximumTextureDistance: Double(area.maximumTextureDistanceMeters),
            Key.areaExportPLY: area.exportPLY,
            Key.areaExportOBJ: area.exportOBJ,
            Key.areaExportUSDZ: area.exportUSDZ,

            Key.objectDensityPreset: ObjectScanDensityPreset.balanced.rawValue,
            Key.objectAutoCapture: object.autoCapture,
            Key.objectHaptics: object.haptics,
            Key.objectTargetImages: object.targetImageCount,
            Key.objectMinimumImages: object.minimumImagesBeforeFinish,
            Key.objectImageMaxDimension: object.imageMaxDimension,
            Key.objectJPEGQuality: object.jpegQuality,
            Key.objectCaptureInterval: object.minimumCaptureInterval,
            Key.objectAngularStepDegrees: Double(object.minimumAngularStepDegrees),
            Key.objectHighFeatureSensitivity: object.highFeatureSensitivity,
            Key.objectMasking: object.objectMasking,
            Key.objectUseSmoothedDepth: object.useSmoothedDepthForSelection,
            Key.objectSizePreset: object.objectSizePreset.rawValue,
            Key.objectKeepSourceImages: object.keepSourceImages,

            Key.appleAreaAutoCapture: true,
            Key.appleAreaHaptics: true,
            Key.appleAreaOverCapture: false,
            Key.appleAreaKeepSourceImages: true,
            Key.appleAreaMinimumImages: 12,
            Key.appleAreaHighFeatureSensitivity: true,
            Key.appleAreaRecoverEntireScene: true,

            Key.appleObjectRecommendedPasses: 3,
            Key.appleObjectOverCapture: false,
            Key.appleObjectShowPreselectionMesh: true,
            Key.appleObjectPreferCompletedPassBeforeFinish: true
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
            rejectUncertainTextures: defaults.bool(forKey: Key.areaRejectUncertainTextures),
            depthOcclusionToleranceMeters: Float(min(max(defaults.double(forKey: Key.areaDepthOcclusionTolerance), 0.04), 0.35)),
            maximumTextureDistanceMeters: Float(min(max(defaults.double(forKey: Key.areaMaximumTextureDistance), 1.0), 10.0)),
            exportPLY: defaults.bool(forKey: Key.areaExportPLY),
            exportOBJ: defaults.bool(forKey: Key.areaExportOBJ),
            exportUSDZ: defaults.bool(forKey: Key.areaExportUSDZ)
        )
    }

    static var objectOptions: ObjectScanRuntimeOptions {
        registerDefaults()
        let sizePreset = ObjectScanSizePreset(
            rawValue: defaults.string(forKey: Key.objectSizePreset) ?? ObjectScanSizePreset.medium.rawValue
        ) ?? .medium
        return ObjectScanRuntimeOptions(
            autoCapture: defaults.bool(forKey: Key.objectAutoCapture),
            haptics: defaults.bool(forKey: Key.objectHaptics),
            targetImageCount: min(max(defaults.integer(forKey: Key.objectTargetImages), 12), 140),
            minimumImagesBeforeFinish: min(max(defaults.integer(forKey: Key.objectMinimumImages), 6), 60),
            imageMaxDimension: max(720, defaults.integer(forKey: Key.objectImageMaxDimension)),
            jpegQuality: min(max(defaults.double(forKey: Key.objectJPEGQuality), 0.65), 1.0),
            minimumCaptureInterval: min(max(defaults.double(forKey: Key.objectCaptureInterval), 0.20), 3.0),
            minimumAngularStepDegrees: Float(min(max(defaults.double(forKey: Key.objectAngularStepDegrees), 2), 30)),
            highFeatureSensitivity: defaults.bool(forKey: Key.objectHighFeatureSensitivity),
            objectMasking: defaults.bool(forKey: Key.objectMasking),
            useSmoothedDepthForSelection: defaults.bool(forKey: Key.objectUseSmoothedDepth),
            objectSizePreset: sizePreset,
            keepSourceImages: defaults.bool(forKey: Key.objectKeepSourceImages)
        )
    }

    struct AppleAreaCaptureOptions {
        let autoCapture: Bool
        let haptics: Bool
        let overCapture: Bool
        let keepSourceImages: Bool
        let minimumImagesBeforeFinish: Int
        let highFeatureSensitivity: Bool
        let recoverEntireScene: Bool
    }

    struct AppleObjectCaptureOptions {
        let autoCapture: Bool
        let haptics: Bool
        let overCapture: Bool
        let keepSourceImages: Bool
        let minimumImagesBeforeFinish: Int
        let recommendedPasses: Int
        let highFeatureSensitivity: Bool
        let objectMasking: Bool
        let showPreselectionMesh: Bool
        let preferCompletedPassBeforeFinish: Bool
    }

    static var appleAreaOptions: AppleAreaCaptureOptions {
        registerDefaults()
        return AppleAreaCaptureOptions(
            autoCapture: defaults.bool(forKey: Key.appleAreaAutoCapture),
            haptics: defaults.bool(forKey: Key.appleAreaHaptics),
            overCapture: defaults.bool(forKey: Key.appleAreaOverCapture),
            keepSourceImages: defaults.bool(forKey: Key.appleAreaKeepSourceImages),
            minimumImagesBeforeFinish: min(max(defaults.integer(forKey: Key.appleAreaMinimumImages), 1), 100),
            highFeatureSensitivity: defaults.bool(forKey: Key.appleAreaHighFeatureSensitivity),
            recoverEntireScene: defaults.bool(forKey: Key.appleAreaRecoverEntireScene)
        )
    }

    static var appleObjectOptions: AppleObjectCaptureOptions {
        registerDefaults()
        let object = objectOptions
        return AppleObjectCaptureOptions(
            autoCapture: object.autoCapture,
            haptics: object.haptics,
            overCapture: defaults.bool(forKey: Key.appleObjectOverCapture),
            keepSourceImages: object.keepSourceImages,
            minimumImagesBeforeFinish: object.minimumImagesBeforeFinish,
            recommendedPasses: min(max(defaults.integer(forKey: Key.appleObjectRecommendedPasses), 1), 5),
            highFeatureSensitivity: object.highFeatureSensitivity,
            objectMasking: object.objectMasking,
            showPreselectionMesh: defaults.bool(forKey: Key.appleObjectShowPreselectionMesh),
            preferCompletedPassBeforeFinish: defaults.bool(forKey: Key.appleObjectPreferCompletedPassBeforeFinish)
        )
    }

    static func applyAreaPreset(_ preset: Color3DScanQualityPreset) {
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
        defaults.set(value.rejectUncertainTextures, forKey: Key.areaRejectUncertainTextures)
        defaults.set(Double(value.depthOcclusionToleranceMeters), forKey: Key.areaDepthOcclusionTolerance)
        defaults.set(Double(value.maximumTextureDistanceMeters), forKey: Key.areaMaximumTextureDistance)
        defaults.set(value.exportPLY, forKey: Key.areaExportPLY)
        defaults.set(value.exportOBJ, forKey: Key.areaExportOBJ)
        defaults.set(value.exportUSDZ, forKey: Key.areaExportUSDZ)
    }

    static func applyObjectPreset(_ preset: ObjectScanDensityPreset) {
        let currentSize = defaults.string(forKey: Key.objectSizePreset) ?? ObjectScanSizePreset.medium.rawValue
        let value = preset.recommended
        defaults.set(preset.rawValue, forKey: Key.objectDensityPreset)
        defaults.set(value.autoCapture, forKey: Key.objectAutoCapture)
        defaults.set(value.haptics, forKey: Key.objectHaptics)
        defaults.set(value.targetImageCount, forKey: Key.objectTargetImages)
        defaults.set(value.minimumImagesBeforeFinish, forKey: Key.objectMinimumImages)
        defaults.set(value.imageMaxDimension, forKey: Key.objectImageMaxDimension)
        defaults.set(value.jpegQuality, forKey: Key.objectJPEGQuality)
        defaults.set(value.minimumCaptureInterval, forKey: Key.objectCaptureInterval)
        defaults.set(Double(value.minimumAngularStepDegrees), forKey: Key.objectAngularStepDegrees)
        defaults.set(value.highFeatureSensitivity, forKey: Key.objectHighFeatureSensitivity)
        defaults.set(value.objectMasking, forKey: Key.objectMasking)
        defaults.set(value.useSmoothedDepthForSelection, forKey: Key.objectUseSmoothedDepth)
        defaults.set(currentSize, forKey: Key.objectSizePreset)
        defaults.set(value.keepSourceImages, forKey: Key.objectKeepSourceImages)
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
            Key.areaRejectUncertainTextures,
            Key.areaDepthOcclusionTolerance,
            Key.areaMaximumTextureDistance,
            Key.areaExportPLY,
            Key.areaExportOBJ,
            Key.areaExportUSDZ,
            Key.objectDensityPreset,
            Key.objectAutoCapture,
            Key.objectHaptics,
            Key.objectTargetImages,
            Key.objectMinimumImages,
            Key.objectImageMaxDimension,
            Key.objectJPEGQuality,
            Key.objectCaptureInterval,
            Key.objectAngularStepDegrees,
            Key.objectHighFeatureSensitivity,
            Key.objectMasking,
            Key.objectUseSmoothedDepth,
            Key.objectSizePreset,
            Key.objectKeepSourceImages,
            Key.appleAreaAutoCapture,
            Key.appleAreaHaptics,
            Key.appleAreaOverCapture,
            Key.appleAreaKeepSourceImages,
            Key.appleAreaMinimumImages,
            Key.appleAreaHighFeatureSensitivity,
            Key.appleAreaRecoverEntireScene,
            Key.appleObjectRecommendedPasses,
            Key.appleObjectOverCapture,
            Key.appleObjectShowPreselectionMesh,
            Key.appleObjectPreferCompletedPassBeforeFinish
        ] {
            defaults.removeObject(forKey: key)
        }
        registerDefaults()
    }
}
