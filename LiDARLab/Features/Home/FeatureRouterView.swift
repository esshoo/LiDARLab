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
            case .sceneMesh:
                SceneMeshView()
            case .arPlayground:
                ARPlaygroundView()
            case .deviceInfo:
                DeviceInfoView()
            default:
                ComingSoonView(feature: feature)
            }
        }
    }
}
