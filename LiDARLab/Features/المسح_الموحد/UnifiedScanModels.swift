import Foundation
import SwiftUI

// MARK: - User-selectable operating model

enum UnifiedDeviceRole: String, CaseIterable, Identifiable, Codable {
    case sender
    case receiver
    case standalone

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sender: "إرسال البيانات"
        case .receiver: "استقبال البيانات ومعالجتها"
        case .standalone: "الالتقاط والمعالجة على هذا الجهاز"
        }
    }

    var shortTitle: String {
        switch self {
        case .sender: "مرسل"
        case .receiver: "مستقبل"
        case .standalone: "مستقل"
        }
    }

    var systemImage: String {
        switch self {
        case .sender: "arrow.up.circle"
        case .receiver: "arrow.down.circle"
        case .standalone: "iphone.gen3"
        }
    }
}

enum UnifiedScanMode: String, CaseIterable, Identifiable, Codable {
    case poseOnly = "pose_only"
    case scan2D = "scan2d"
    case geometry3D = "geometry3d"
    case color3D = "color3d"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .poseOnly: "مسار الجهاز"
        case .scan2D: "مسح 2D"
        case .geometry3D: "3D بدون ألوان"
        case .color3D: "3D بالألوان"
        }
    }

    var systemImage: String {
        switch self {
        case .poseOnly: "point.topleft.down.curvedto.point.bottomright.up"
        case .scan2D: "map"
        case .geometry3D: "cube.transparent"
        case .color3D: "cube.fill"
        }
    }

    var requiresDepth: Bool {
        self != .poseOnly
    }

    var implementedInCurrentCaptureCore: Bool {
        switch self {
        case .poseOnly, .scan2D: true
        case .geometry3D, .color3D: false
        }
    }
}

enum UnifiedSessionState: String, Codable {
    case idle
    case ready
    case recording
    case paused
    case finished
    case listening
    case failed

    var title: String {
        switch self {
        case .idle: "خامل"
        case .ready: "جاهز"
        case .recording: "تسجيل"
        case .paused: "متوقف مؤقتًا"
        case .finished: "انتهت الجلسة"
        case .listening: "بانتظار المرسل"
        case .failed: "فشل"
        }
    }

    var color: Color {
        switch self {
        case .recording: .red
        case .paused: .orange
        case .ready, .listening: .green
        case .failed: .red
        case .idle, .finished: .secondary
        }
    }
}

enum UnifiedConnectionKind: String, CaseIterable, Identifiable, Codable {
    case windowsWebSocket
    case appleDirectTCP

    var id: String { rawValue }

    var title: String {
        switch self {
        case .windowsWebSocket: "Windows عبر WebSocket"
        case .appleDirectTCP: "جهاز Apple مباشر"
        }
    }
}



enum UnifiedCoveragePreviewStyle: String, CaseIterable, Identifiable, Codable {
    case points
    case filledCells
    case outlinedCells
    case heatCells

    var id: String { rawValue }

    var title: String {
        switch self {
        case .points: "نقاط"
        case .filledCells: "خلايا ممتلئة"
        case .outlinedCells: "شبكة خلايا"
        case .heatCells: "تغطية حرارية"
        }
    }
}

enum UnifiedPathPreviewStyle: String, CaseIterable, Identifiable, Codable {
    case line
    case points
    case lineAndPoints

    var id: String { rawValue }

    var title: String {
        switch self {
        case .line: "خط"
        case .points: "نقاط"
        case .lineAndPoints: "خط ونقاط"
        }
    }
}

enum UnifiedDevicePreviewStyle: String, CaseIterable, Identifiable, Codable {
    case phoneAndFrustum
    case phoneOnly
    case arrow

    var id: String { rawValue }

    var title: String {
        switch self {
        case .phoneAndFrustum: "هاتف ومجال رؤية"
        case .phoneOnly: "هاتف"
        case .arrow: "سهم"
        }
    }
}
enum UnifiedThermalPolicy: String, CaseIterable, Identifiable, Codable {
    case warnOnly
    case stopDepthAtCritical
    case stopAllAtCritical

    var id: String { rawValue }

    var title: String {
        switch self {
        case .warnOnly: "تنبيه فقط — لا تغيير تلقائي"
        case .stopDepthAtCritical: "إيقاف Depth عند الحرارة الحرجة"
        case .stopAllAtCritical: "إيقاف كل الالتقاط عند الحرارة الحرجة"
        }
    }
}

struct UnifiedPreviewPoint: Hashable, Codable {
    var x: Float
    var z: Float
}

struct UnifiedPreviewCell: Hashable, Codable {
    var xIndex: Int
    var zIndex: Int
}

struct UnifiedPreviewSweep: Identifiable, Hashable, Codable {
    var id = UUID()
    var points: [UnifiedPreviewPoint]
}

struct UnifiedDiscoveredReceiver: Identifiable, Hashable {
    let id: String
    let name: String
    let endpointDescription: String
}

struct UnifiedCapabilityWarning: Identifiable {
    let id = UUID()
    let title: String
    let message: String
    let continueTitle: String
}
