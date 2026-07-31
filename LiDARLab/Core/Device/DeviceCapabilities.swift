import ARKit
import AVFoundation
import Foundation
import UIKit

struct DeviceCapabilities {
    static let current = DeviceCapabilities()

    let worldTrackingSupported: Bool
    let sceneDepthSupported: Bool
    let smoothedDepthSupported: Bool
    let meshSupported: Bool
    let meshClassificationSupported: Bool
    let cameraAuthorization: AVAuthorizationStatus

    init() {
        worldTrackingSupported = ARWorldTrackingConfiguration.isSupported
        sceneDepthSupported = ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth)
        smoothedDepthSupported = ARWorldTrackingConfiguration.supportsFrameSemantics(.smoothedSceneDepth)
        meshSupported = ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh)
        meshClassificationSupported = ARWorldTrackingConfiguration.supportsSceneReconstruction(.meshWithClassification)
        cameraAuthorization = AVCaptureDevice.authorizationStatus(for: .video)
    }

    var lidarAvailable: Bool {
        sceneDepthSupported || meshSupported
    }

    var deviceSummary: String {
        lidarAvailable ? "LiDAR متاح" : "لا يوجد دعم LiDAR"
    }

    var systemDescription: String {
        "\(UIDevice.current.systemName) \(UIDevice.current.systemVersion)"
    }

    var cameraAuthorizationDescription: String {
        switch cameraAuthorization {
        case .authorized: "مسموح"
        case .denied: "مرفوض"
        case .restricted: "مقيّد"
        case .notDetermined: "لم يُطلب بعد"
        @unknown default: "غير معروف"
        }
    }
}
