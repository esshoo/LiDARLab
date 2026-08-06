import SwiftUI
import UIKit

/// Lightweight screen-space indication of the depth samples received in the
/// current LiDAR frame. It is preview-only and never changes the raw stream.
struct StableCameraCoverageOverlay: View {
    let samples: [StableCameraCoverageSample]
    let cameraImageWidth: Int
    let cameraImageHeight: Int
    let trackingNormal: Bool

    var body: some View {
        GeometryReader { proxy in
            Canvas { context, size in
                guard cameraImageWidth > 0, cameraImageHeight > 0 else { return }
                let orientation = currentInterfaceOrientation
                for sample in samples {
                    let point = projectedPoint(sample, in: size, orientation: orientation)
                    let radius: CGFloat = sample.confidence >= 2 ? 4.2 : 3.2
                    let rect = CGRect(
                        x: point.x - radius,
                        y: point.y - radius,
                        width: radius * 2,
                        height: radius * 2
                    )
                    context.fill(Path(ellipseIn: rect), with: .color(sampleColor(sample)))
                }
            }
            .allowsHitTesting(false)
        }
    }

    private var currentInterfaceOrientation: UIInterfaceOrientation {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        return scenes.first(where: { $0.activationState == .foregroundActive })?.interfaceOrientation
            ?? scenes.first?.interfaceOrientation
            ?? .portrait
    }

    private func projectedPoint(
        _ sample: StableCameraCoverageSample,
        in viewSize: CGSize,
        orientation: UIInterfaceOrientation
    ) -> CGPoint {
        let u = CGFloat(sample.u)
        let v = CGFloat(sample.v)
        let orientedU: CGFloat
        let orientedV: CGFloat
        let orientedImageSize: CGSize

        switch orientation {
        case .portrait:
            orientedU = 1 - v
            orientedV = u
            orientedImageSize = CGSize(width: CGFloat(cameraImageHeight), height: CGFloat(cameraImageWidth))
        case .portraitUpsideDown:
            orientedU = v
            orientedV = 1 - u
            orientedImageSize = CGSize(width: CGFloat(cameraImageHeight), height: CGFloat(cameraImageWidth))
        case .landscapeLeft:
            orientedU = 1 - u
            orientedV = 1 - v
            orientedImageSize = CGSize(width: CGFloat(cameraImageWidth), height: CGFloat(cameraImageHeight))
        default:
            orientedU = u
            orientedV = v
            orientedImageSize = CGSize(width: CGFloat(cameraImageWidth), height: CGFloat(cameraImageHeight))
        }

        let scale = max(
            viewSize.width / max(orientedImageSize.width, 1),
            viewSize.height / max(orientedImageSize.height, 1)
        )
        let drawnWidth = orientedImageSize.width * scale
        let drawnHeight = orientedImageSize.height * scale
        let offsetX = (viewSize.width - drawnWidth) / 2
        let offsetY = (viewSize.height - drawnHeight) / 2
        return CGPoint(
            x: offsetX + orientedU * drawnWidth,
            y: offsetY + orientedV * drawnHeight
        )
    }

    private func sampleColor(_ sample: StableCameraCoverageSample) -> Color {
        guard trackingNormal else { return .red.opacity(0.72) }
        switch sample.confidence {
        case 2...: return .green.opacity(0.68)
        case 1: return .yellow.opacity(0.64)
        default: return .orange.opacity(0.58)
        }
    }
}
