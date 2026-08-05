import SwiftUI

struct FeatureRouterView: View {
    let feature: LiDARFeature
    private let capabilities = DeviceCapabilities.current

    @ViewBuilder
    var body: some View {
        if feature.phase == .comingSoon {
            ComingSoonView(feature: feature)
        } else if !feature.isSupported(by: capabilities) {
            UnsupportedFeatureView(feature: feature)
        } else {
            switch feature {
            case .depthCamera:
                DepthCameraView()
            case .distanceMeasure:
                DistanceMeasureView()
            case .angleMeasure:
                ThreePointAngleView()
            case .levelTool:
                LevelToolView()
            case .pointCloud:
                PointCloudView()
            case .sceneMesh:
                SceneMeshView()
            case .surfaceClassification:
                SurfaceClassificationView()
            case .planeDetection:
                PlaneDetectionView()
            case .arPlayground:
                ARPlaygroundView()
            case .depthPhoto:
                DepthPhotoView()
            case .computerBridge:
                StableScanView()
            case .roomScan:
                RoomScanView()
            case .sensorTests:
                SensorStabilityTestView()
            case .recordings:
                SessionRecordingsView()
            case .exportCenter:
                ExportCenterView()
            case .deviceInfo:
                DeviceInfoView()
            default:
                ComingSoonView(feature: feature)
            }
        }
    }
}
