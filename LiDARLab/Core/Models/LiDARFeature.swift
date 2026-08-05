import Foundation

enum FeaturePhase: String {
    case ready
    case comingSoon
}

enum FeatureRequirement {
    case none
    case worldTracking
    case sceneDepth
    case sceneMesh
    case sceneMeshClassification
    case roomPlan
}

enum LiDARFeature: String, CaseIterable, Identifiable, Hashable {
    case depthCamera
    case distanceMeasure
    case angleMeasure
    case levelTool
    case pointCloud
    case sceneMesh
    case surfaceClassification
    case planeDetection
    case arPlayground
    case depthPhoto
    case computerBridge
    case roomScan
    case sensorTests
    case recordings
    case exportCenter
    case deviceInfo

    var id: String { rawValue }

    var title: String {
        switch self {
        case .depthCamera: "كاميرا العمق"
        case .distanceMeasure: "القياس المتعدد"
        case .angleMeasure: "قياس الزوايا"
        case .levelTool: "ميزان الميل والزاوية"
        case .pointCloud: "السحابة النقطية"
        case .sceneMesh: "شبكة المكان"
        case .surfaceClassification: "تصنيف الأسطح"
        case .planeDetection: "اكتشاف المستويات"
        case .arPlayground: "مختبر الواقع المعزز"
        case .depthPhoto: "صورة مع العمق"
        case .computerBridge: "البث إلى الكمبيوتر"
        case .roomScan: "مسح الغرف"
        case .sensorTests: "اختبارات الحساس"
        case .recordings: "تسجيل الجلسات"
        case .exportCenter: "مركز التصدير"
        case .deviceInfo: "معلومات الجهاز"
        }
    }

    var subtitle: String {
        switch self {
        case .depthCamera: "خريطة حرارية وقراءات عمق مباشرة"
        case .distanceMeasure: "مسارات متعددة وأطوال أفقية ورأسية مع الحفظ"
        case .angleMeasure: "قياس زاوية بين ثلاثة مواضع حقيقية"
        case .levelTool: "تثبيت العنصر على الحائط وقياس ميله بالنسبة للجاذبية"
        case .pointCloud: "تحويل العمق إلى نقاط ثلاثية الأبعاد"
        case .sceneMesh: "عرض شبكة البيئة المحيطة"
        case .surfaceClassification: "تمييز الجدران والأرضيات والأسقف"
        case .planeDetection: "اكتشاف الأسطح الأفقية والرأسية"
        case .arPlayground: "وضع وتحريك مجسمات داخل المكان"
        case .depthPhoto: "حفظ الصورة وخريطة العمق معًا"
        case .computerBridge: "إرسال موقع الهاتف مباشرة إلى برنامج Windows"
        case .roomScan: "مسح كل غرفة منفصلة وتثبيتها قبل الانتقال"
        case .sensorTests: "اختبار ثبات قراءة العمق وتذبذبها"
        case .recordings: "حفظ إطارات الصورة والعمق وإعادة عرضها"
        case .exportCenter: "إدارة الصور والغرف والقياسات والجلسات المحفوظة"
        case .deviceInfo: "فحص دعم LiDAR وخصائص ARKit"
        }
    }

    var systemImage: String {
        switch self {
        case .depthCamera: "camera.metering.matrix"
        case .distanceMeasure: "ruler"
        case .angleMeasure: "angle"
        case .levelTool: "level"
        case .pointCloud: "circle.grid.3x3.fill"
        case .sceneMesh: "cube.transparent"
        case .surfaceClassification: "square.3.layers.3d"
        case .planeDetection: "viewfinder.rectangular"
        case .arPlayground: "arkit"
        case .depthPhoto: "camera.filters"
        case .computerBridge: "desktopcomputer.and.arrow.down"
        case .roomScan: "house.lodge"
        case .sensorTests: "waveform.path.ecg"
        case .recordings: "record.circle"
        case .exportCenter: "square.and.arrow.up"
        case .deviceInfo: "iphone.gen3"
        }
    }

    var phase: FeaturePhase {
        switch self {
        case .depthCamera, .distanceMeasure, .angleMeasure, .levelTool, .pointCloud, .sceneMesh,
             .surfaceClassification, .planeDetection, .arPlayground, .depthPhoto, .computerBridge, .roomScan,
             .sensorTests, .recordings, .exportCenter, .deviceInfo:
            .ready
        default:
            .comingSoon
        }
    }

    var requirement: FeatureRequirement {
        switch self {
        case .deviceInfo, .exportCenter:
            .none
        case .angleMeasure, .levelTool, .planeDetection, .arPlayground, .computerBridge:
            .worldTracking
        case .depthCamera, .distanceMeasure, .pointCloud, .depthPhoto,
             .sensorTests, .recordings:
            .sceneDepth
        case .roomScan:
            .roomPlan
        case .sceneMesh:
            .sceneMesh
        case .surfaceClassification:
            .sceneMeshClassification
        }
    }

    func isSupported(by capabilities: DeviceCapabilities) -> Bool {
        switch requirement {
        case .none:
            true
        case .worldTracking:
            capabilities.worldTrackingSupported
        case .sceneDepth:
            capabilities.sceneDepthSupported
        case .sceneMesh:
            capabilities.meshSupported
        case .sceneMeshClassification:
            capabilities.meshClassificationSupported
        case .roomPlan:
            capabilities.roomPlanSupported
        }
    }

    var plannedCapabilities: [String] {
        switch self {
        case .pointCloud:
            ["عرض حي أو تراكمي", "تلوين حسب المسافة أو الثقة", "كثافة وحجم نقاط قابلان للتغيير"]
        case .surfaceClassification:
            ["تمييز الجدار والأرضية والسقف", "تصفية نوع واحد أو العرض الشبكي", "عدادات ونسبة التصنيف"]
        case .planeDetection:
            ["مستويات أفقية ورأسية", "حدود وأبعاد كل مستوى", "تثبيت علامات على السطح"]
        case .depthPhoto:
            ["الصورة الأصلية", "خريطة العمق", "تأثيرات الضباب والعزل"]
        case .computerBridge:
            ["إرسال Pose الحقيقي", "اختيار IP ومعدل الإرسال", "مراقبة التتبع والحرارة"]
        case .roomScan:
            ["جلسة مستقلة لكل غرفة", "ARSession مشتركة بين الغرف", "حفظ الغرف المجمدة ونموذج دمج للمقارنة"]
        case .recordings:
            ["تسجيل الصورة والعمق وحركة الكاميرا", "تشغيل مرئي للإطارات", "مشاركة ملفات الجلسة"]
        case .exportCenter:
            ["البحث والتصفية", "مشاركة وإعادة تسمية وحذف", "فهرس JSON وCSV"]
        default:
            []
        }
    }
}
