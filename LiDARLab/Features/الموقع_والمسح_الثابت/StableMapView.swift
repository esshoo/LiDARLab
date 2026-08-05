import SwiftUI
import simd

struct StableMapView: View {
    let pathSegments: [StablePathSegment]
    let breakPoints: [StableBreakPoint]
    let coverageCells: [StableCoverageCell]
    let processedCells: [StableProcessedCell]
    let currentPose: StablePoseSample?
    let previewCellSize: Float
    var showCoverage = true
    var showProcessed = true

    var body: some View {
        Canvas { context, size in
            let transform = MapTransform(
                size: size,
                segments: pathSegments,
                coverage: showCoverage ? coverageCells : [],
                processed: showProcessed ? processedCells : [],
                currentPose: currentPose,
                previewCellSize: previewCellSize
            )
            drawGrid(context: &context, transform: transform)
            if showCoverage { drawCoverage(context: &context, transform: transform) }
            if showProcessed { drawProcessed(context: &context, transform: transform) }
            drawPath(context: &context, transform: transform)
            drawBreaks(context: &context, transform: transform)
            if let currentPose { drawDevice(context: &context, transform: transform, pose: currentPose) }
        }
        .background(Color(red: 0.02, green: 0.035, blue: 0.05))
        .allowsHitTesting(false)
        .accessibilityLabel("خريطة الموقع والمسح")
    }

    private func drawGrid(context: inout GraphicsContext, transform: MapTransform) {
        let minX = floor(transform.minimumX) - 1
        let maxX = ceil(transform.maximumX) + 1
        let minZ = floor(transform.minimumZ) - 1
        let maxZ = ceil(transform.maximumZ) + 1

        var minor = Path()
        if minX <= maxX {
            for x in Int(minX)...Int(maxX) {
                minor.move(to: transform.point(x: Float(x), z: Float(minZ)))
                minor.addLine(to: transform.point(x: Float(x), z: Float(maxZ)))
            }
        }
        if minZ <= maxZ {
            for z in Int(minZ)...Int(maxZ) {
                minor.move(to: transform.point(x: Float(minX), z: Float(z)))
                minor.addLine(to: transform.point(x: Float(maxX), z: Float(z)))
            }
        }
        context.stroke(minor, with: .color(.white.opacity(0.09)), lineWidth: 0.7)

        var axes = Path()
        axes.move(to: transform.point(x: Float(minX), z: 0))
        axes.addLine(to: transform.point(x: Float(maxX), z: 0))
        axes.move(to: transform.point(x: 0, z: Float(minZ)))
        axes.addLine(to: transform.point(x: 0, z: Float(maxZ)))
        context.stroke(axes, with: .color(.cyan.opacity(0.24)), lineWidth: 1)
    }

    private func drawCoverage(context: inout GraphicsContext, transform: MapTransform) {
        let side = max(1.0, CGFloat(previewCellSize) * transform.scale)
        for cell in coverageCells {
            let x = (Float(cell.ix) + 0.5) * previewCellSize
            let z = (Float(cell.iz) + 0.5) * previewCellSize
            let center = transform.point(x: x, z: z)
            let rect = CGRect(x: center.x - side / 2, y: center.y - side / 2, width: side, height: side)
            context.fill(Path(rect), with: .color(.cyan.opacity(0.16)))
        }
    }

    private func drawProcessed(context: inout GraphicsContext, transform: MapTransform) {
        let side = max(1.2, CGFloat(0.10) * transform.scale)
        for cell in processedCells {
            let center = transform.point(x: (Float(cell.ix) + 0.5) * 0.10, z: (Float(cell.iz) + 0.5) * 0.10)
            let strength = min(0.85, 0.28 + Double(cell.frameCount) * 0.035)
            let rect = CGRect(x: center.x - side / 2, y: center.y - side / 2, width: side, height: side)
            context.fill(Path(rect), with: .color(.white.opacity(strength)))
        }
    }

    private func drawPath(context: inout GraphicsContext, transform: MapTransform) {
        for segment in pathSegments where segment.points.count >= 2 {
            var path = Path()
            if let first = segment.points.first {
                path.move(to: transform.point(x: first.x, z: first.z))
                for point in segment.points.dropFirst() {
                    path.addLine(to: transform.point(x: point.x, z: point.z))
                }
            }
            context.stroke(path, with: .color(.green), style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
        }
    }

    private func drawBreaks(context: inout GraphicsContext, transform: MapTransform) {
        for item in breakPoints {
            let point = transform.point(x: item.x, z: item.z)
            let rect = CGRect(x: point.x - 4, y: point.y - 4, width: 8, height: 8)
            context.fill(Path(ellipseIn: rect), with: .color(.orange))
        }
    }

    private func drawDevice(context: inout GraphicsContext, transform: MapTransform, pose: StablePoseSample) {
        let quaternion = pose.quaternion.simdValue
        let forward3 = quaternion.act(SIMD3<Float>(0, 0, -1))
        var forward = SIMD2<Float>(forward3.x, forward3.z)
        if simd_length(forward) < 0.001 { forward = SIMD2(0, -1) }
        forward = simd_normalize(forward)
        let right = SIMD2<Float>(-forward.y, forward.x)
        let origin = SIMD2<Float>(pose.px, pose.pz)

        let halfWidth: Float = 0.10
        let halfLength: Float = 0.18
        let rightOffset = right * halfWidth
        let forwardOffset = forward * halfLength
        let frontRight = origin + rightOffset + forwardOffset
        let frontLeft = origin - rightOffset + forwardOffset
        let backLeft = origin - rightOffset - forwardOffset
        let backRight = origin + rightOffset - forwardOffset
        let corners: [SIMD2<Float>] = [frontRight, frontLeft, backLeft, backRight]
        var phone = Path()
        phone.move(to: transform.point(x: corners[0].x, z: corners[0].y))
        for corner in corners.dropFirst() { phone.addLine(to: transform.point(x: corner.x, z: corner.y)) }
        phone.closeSubpath()
        context.fill(phone, with: .color(.orange))
        context.stroke(phone, with: .color(.white.opacity(0.9)), lineWidth: 1)

        let leftRay = origin + forward * 0.72 + right * 0.38
        let rightRay = origin + forward * 0.72 - right * 0.38
        var fan = Path()
        fan.move(to: transform.point(x: origin.x, z: origin.y))
        fan.addLine(to: transform.point(x: leftRay.x, z: leftRay.y))
        fan.addLine(to: transform.point(x: rightRay.x, z: rightRay.y))
        fan.closeSubpath()
        context.fill(fan, with: .color(.orange.opacity(0.12)))
        context.stroke(fan, with: .color(.orange.opacity(0.4)), lineWidth: 1)
    }
}

private struct MapTransform {
    let scale: CGFloat
    let centerX: Float
    let centerZ: Float
    let screenCenter: CGPoint
    let minimumX: Float
    let maximumX: Float
    let minimumZ: Float
    let maximumZ: Float

    init(
        size: CGSize,
        segments: [StablePathSegment],
        coverage: [StableCoverageCell],
        processed: [StableProcessedCell],
        currentPose: StablePoseSample?,
        previewCellSize: Float
    ) {
        var minX: Float = -2
        var maxX: Float = 2
        var minZ: Float = -2
        var maxZ: Float = 2

        func include(_ x: Float, _ z: Float) {
            minX = min(minX, x)
            maxX = max(maxX, x)
            minZ = min(minZ, z)
            maxZ = max(maxZ, z)
        }

        for segment in segments {
            for point in segment.points { include(point.x, point.z) }
        }
        for cell in coverage {
            include(Float(cell.ix) * previewCellSize, Float(cell.iz) * previewCellSize)
        }
        for cell in processed {
            include(Float(cell.ix) * 0.10, Float(cell.iz) * 0.10)
        }
        if let currentPose { include(currentPose.px, currentPose.pz) }

        let padding: Float = 1.2
        minX -= padding
        maxX += padding
        minZ -= padding
        maxZ += padding
        let rangeX = max(1, maxX - minX)
        let rangeZ = max(1, maxZ - minZ)
        let usableWidth = max(1, size.width - 24)
        let usableHeight = max(1, size.height - 24)
        scale = min(usableWidth / CGFloat(rangeX), usableHeight / CGFloat(rangeZ))
        centerX = (minX + maxX) / 2
        centerZ = (minZ + maxZ) / 2
        screenCenter = CGPoint(x: size.width / 2, y: size.height / 2)
        minimumX = minX
        maximumX = maxX
        minimumZ = minZ
        maximumZ = maxZ
    }

    func point(x: Float, z: Float) -> CGPoint {
        // ARKit forward is -Z. Canvas Y grows downward, so raw Z maps naturally.
        CGPoint(
            x: screenCenter.x + CGFloat(x - centerX) * scale,
            y: screenCenter.y + CGFloat(z - centerZ) * scale
        )
    }
}
