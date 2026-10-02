import ARKit
import Foundation
import RealityKit
import RoomPlan

struct Color3DScanSupport {
    static var sceneDepthSupported: Bool {
        ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth)
    }

    static var meshSupported: Bool {
        ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh)
    }

    static var meshClassificationSupported: Bool {
        ARWorldTrackingConfiguration.supportsSceneReconstruction(.meshWithClassification)
    }

    static var roomPlanSupported: Bool {
        RoomCaptureSession.isSupported
    }

    @MainActor
    static var objectCaptureSupported: Bool {
        ObjectCaptureSession.isSupported
    }

    static var photogrammetrySupported: Bool {
        PhotogrammetrySession.isSupported
    }

    @MainActor
    static var areaModeAvailable: Bool {
        if #available(iOS 18.0, *) {
            return ObjectCaptureSession.isSupported
        }
        return false
    }

    static var systemVersionText: String {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
    }
}
