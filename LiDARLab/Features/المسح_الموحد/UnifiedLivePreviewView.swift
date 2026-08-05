import Foundation
import SwiftUI
import simd

struct UnifiedLivePreviewView: View {
    let path: [UnifiedPreviewPoint]
    let coverageCells: [UnifiedPreviewCell]
    let currentSweep: UnifiedPreviewSweep?
    let currentPosition: SIMD3<Float>
    let currentQuaternion: simd_quatf
    let coverageCellSize: Float
    let coverageStyle: UnifiedCoveragePreviewStyle
    let pathStyle: UnifiedPathPreviewStyle
    let deviceStyle: UnifiedDevicePreviewStyle
    let showGrid: Bool
    let showPath: Bool
    let showCoverage: Bool
    let showCurrentRays: Bool
    let showDevice: Bool

    var body: some View {
        GeometryReader { _ in
            Canvas { context, size in
                let bounds = drawingBounds
                let mapper = PreviewMapper(bounds: bounds, size: size)

                if showGrid {
                    drawGrid(context: &context, mapper: mapper)
                }
                if showCoverage {
                    drawCoverage(context: &context, mapper: mapper)
                }
                if showCurrentRays, let currentSweep {
                    drawCurrentSweep(currentSweep, context: &context, mapper: mapper)
                }
                if showPath {
                    drawPath(context: &context, mapper: mapper)
                }
                if showDevice {
                    drawDevice(context: &context, mapper: mapper)
                }
            }
            .background(
                LinearGradient(
                    colors: [Color.black.opacity(0.97), Color(red: 0.025, green: 0.05, blue: 0.075)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(alignment: .topLeading) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("معاينة خفيفة — البيانات الخام محفوظة بالكامل")
                        .font(.caption2.weight(.semibold))
                    Text("الخلايا تراكمية ولا تختفي؛ الأشعة تمثل اللحظة الحالية فقط")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(8)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
                .padding(10)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .contentShape(Rectangle())
    }

    private var drawingBounds: PreviewBounds {
        var minX = currentPosition.x
        var maxX = currentPosition.x
        var minZ = currentPosition.z
        var maxZ = currentPosition.z
        var hasOtherPoint = false

        func include(x: Float, z: Float) {
            minX = min(minX, x)
            maxX = max(maxX, x)
            minZ = min(minZ, z)
            maxZ = max(maxZ, z)
            hasOtherPoint = true
        }

        for point in path { include(x: point.x, z: point.z) }
        for cell in coverageCells {
            let centerX = (Float(cell.xIndex) + 0.5) * coverageCellSize
            let centerZ = (Float(cell.zIndex) + 0.5) * coverageCellSize
            include(x: centerX, z: centerZ)
        }
        if let currentSweep {
            for point in currentSweep.points { include(x: point.x, z: point.z) }
        }

        guard hasOtherPoint else {
            return PreviewBounds(minX: -2, maxX: 2, minZ: -2, maxZ: 2)
        }
        let width = max(1.5, maxX - minX)
        let height = max(1.5, maxZ - minZ)
        let margin = max(0.6, max(width, height) * 0.12)
        return PreviewBounds(
            minX: minX - margin,
            maxX: maxX + margin,
            minZ: minZ - margin,
            maxZ: maxZ + margin
        )
    }

    private func drawGrid(context: inout GraphicsContext, mapper: PreviewMapper) {
        let step: Float = mapper.worldWidth > 18 ? 5 : mapper.worldWidth > 8 ? 2 : 1
        let startX = floor(mapper.bounds.minX / step) * step
        let endX = ceil(mapper.bounds.maxX / step) * step
        let startZ = floor(mapper.bounds.minZ / step) * step
        let endZ = ceil(mapper.bounds.maxZ / step) * step

        var x = startX
        while x <= endX {
            var line = Path()
            line.move(to: mapper.point(x: x, z: mapper.bounds.minZ))
            line.addLine(to: mapper.point(x: x, z: mapper.bounds.maxZ))
            context.stroke(line, with: .color(.white.opacity(0.08)), lineWidth: 0.7)
            x += step
        }

        var z = startZ
        while z <= endZ {
            var line = Path()
            line.move(to: mapper.point(x: mapper.bounds.minX, z: z))
            line.addLine(to: mapper.point(x: mapper.bounds.maxX, z: z))
            context.stroke(line, with: .color(.white.opacity(0.08)), lineWidth: 0.7)
            z += step
        }
    }

    private func drawCoverage(context: inout GraphicsContext, mapper: PreviewMapper) {
        for cell in coverageCells {
            let rect = mapper.cellRect(cell, cellSize: coverageCellSize)
            switch coverageStyle {
            case .points:
                let diameter = max(2.0, min(6.0, rect.width * 0.45))
                let pointRect = CGRect(
                    x: rect.midX - diameter / 2,
                    y: rect.midY - diameter / 2,
                    width: diameter,
                    height: diameter
                )
                context.fill(Path(ellipseIn: pointRect), with: .color(.cyan.opacity(0.78)))
            case .filledCells:
                context.fill(Path(rect), with: .color(.cyan.opacity(0.22)))
            case .outlinedCells:
                context.stroke(Path(rect), with: .color(.cyan.opacity(0.45)), lineWidth: 0.65)
            case .heatCells:
                context.fill(Path(rect), with: .color(.orange.opacity(0.18)))
                context.stroke(Path(rect), with: .color(.yellow.opacity(0.16)), lineWidth: 0.35)
            }
        }
    }

    private func drawCurrentSweep(
        _ sweep: UnifiedPreviewSweep,
        context: inout GraphicsContext,
        mapper: PreviewMapper
    ) {
        guard let origin = sweep.points.first else { return }
        let mappedOrigin = mapper.point(origin)
        for point in sweep.points.dropFirst() {
            var ray = Path()
            ray.move(to: mappedOrigin)
            ray.addLine(to: mapper.point(point))
            context.stroke(ray, with: .color(.cyan.opacity(0.18)), lineWidth: 0.7)
        }
    }

    private func drawPath(context: inout GraphicsContext, mapper: PreviewMapper) {
        guard !path.isEmpty else { return }

        if pathStyle == .line || pathStyle == .lineAndPoints, path.count > 1 {
            var line = Path()
            line.move(to: mapper.point(path[0]))
            for point in path.dropFirst() { line.addLine(to: mapper.point(point)) }
            context.stroke(
                line,
                with: .color(.green.opacity(0.9)),
                style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round)
            )
        }

        if pathStyle == .points || pathStyle == .lineAndPoints {
            let stride = max(1, path.count / 1_500)
            for index in Swift.stride(from: 0, to: path.count, by: stride) {
                let point = mapper.point(path[index])
                context.fill(
                    Path(ellipseIn: CGRect(x: point.x - 1.8, y: point.y - 1.8, width: 3.6, height: 3.6)),
                    with: .color(.green.opacity(0.85))
                )
            }
        }
    }

    private func drawDevice(context: inout GraphicsContext, mapper: PreviewMapper) {
        let position = UnifiedPreviewPoint(x: currentPosition.x, z: currentPosition.z)
        let center = mapper.point(position)
        let worldForward3 = simd_normalize(currentQuaternion.act(SIMD3<Float>(0, 0, -1)))
        let horizontalMagnitude = simd_length(SIMD2<Float>(worldForward3.x, worldForward3.z))
        var forward = SIMD2<Float>(worldForward3.x, worldForward3.z)
        if horizontalMagnitude < 0.05 {
            let worldUp3 = currentQuaternion.act(SIMD3<Float>(0, 1, 0))
            forward = SIMD2<Float>(worldUp3.x, worldUp3.z)
        }
        if simd_length_squared(forward) < 0.0001 { forward = SIMD2<Float>(0, -1) }
        forward = simd_normalize(forward)
        let pitchDegrees = asin(max(-1, min(1, worldForward3.y))) * 180 / Float.pi

        if deviceStyle == .arrow {
            let endWorld = SIMD2<Float>(position.x, position.z) + forward * 0.55
            let end = mapper.point(x: endWorld.x, z: endWorld.y)
            var arrow = Path()
            arrow.move(to: center)
            arrow.addLine(to: end)
            context.stroke(arrow, with: .color(.orange), style: StrokeStyle(lineWidth: 3, lineCap: .round))
            context.fill(Path(ellipseIn: CGRect(x: center.x - 5, y: center.y - 5, width: 10, height: 10)), with: .color(.orange))
            return
        }

        if deviceStyle == .phoneAndFrustum {
            drawFrustum(
                context: &context,
                mapper: mapper,
                position: position,
                forward: forward,
                horizontalMagnitude: horizontalMagnitude
            )
        }

        let directionPoint = mapper.point(
            x: position.x + forward.x,
            z: position.z + forward.y
        )
        let angle = atan2(directionPoint.y - center.y, directionPoint.x - center.x) + .pi / 2
        let phoneRect = CGRect(x: -7, y: -14, width: 14, height: 28)
        let transform = CGAffineTransform(translationX: center.x, y: center.y).rotated(by: angle)
        let phonePath = Path(roundedRect: phoneRect, cornerRadius: 3).applying(transform)
        context.fill(phonePath, with: .color(.orange.opacity(0.92)))
        context.stroke(phonePath, with: .color(.white.opacity(0.85)), lineWidth: 1.1)

        let lens = CGPoint(x: 0, y: -9).applying(transform)
        context.fill(Path(ellipseIn: CGRect(x: lens.x - 1.6, y: lens.y - 1.6, width: 3.2, height: 3.2)), with: .color(.black.opacity(0.85)))
        drawPitchBadge(context: &context, center: center, pitchDegrees: pitchDegrees)
    }

    private func drawPitchBadge(
        context: inout GraphicsContext,
        center: CGPoint,
        pitchDegrees: Float
    ) {
        let title: String
        let symbol: String
        if pitchDegrees > 25 {
            title = "السقف"
            symbol = "↑"
        } else if pitchDegrees < -25 {
            title = "الأرض"
            symbol = "↓"
        } else {
            title = "أمام"
            symbol = "→"
        }
        let text = Text("\(symbol) \(title) \(Int(pitchDegrees.rounded()))°")
            .font(.caption2.bold())
            .foregroundColor(.orange)
        context.draw(text, at: CGPoint(x: center.x + 40, y: center.y - 28), anchor: .center)
    }

    private func drawFrustum(
        context: inout GraphicsContext,
        mapper: PreviewMapper,
        position: UnifiedPreviewPoint,
        forward: SIMD2<Float>,
        horizontalMagnitude: Float
    ) {
        let halfAngle = Float.pi / 6
        let baseDistance: Float = max(0.8, min(2.0, mapper.worldWidth * 0.10))
        let distance = baseDistance * max(0.12, horizontalMagnitude)
        let left = rotate(forward, radians: -halfAngle) * distance
        let right = rotate(forward, radians: halfAngle) * distance
        let origin = mapper.point(position)
        let leftPoint = mapper.point(x: position.x + left.x, z: position.z + left.y)
        let rightPoint = mapper.point(x: position.x + right.x, z: position.z + right.y)

        var frustum = Path()
        frustum.move(to: origin)
        frustum.addLine(to: leftPoint)
        frustum.addLine(to: rightPoint)
        frustum.closeSubpath()
        context.fill(frustum, with: .color(.orange.opacity(0.07)))
        context.stroke(frustum, with: .color(.orange.opacity(0.22)), lineWidth: 0.8)
    }

    private func rotate(_ vector: SIMD2<Float>, radians: Float) -> SIMD2<Float> {
        let cosine = cos(radians)
        let sine = sin(radians)
        return SIMD2<Float>(
            vector.x * cosine - vector.y * sine,
            vector.x * sine + vector.y * cosine
        )
    }
}

private struct PreviewBounds {
    let minX: Float
    let maxX: Float
    let minZ: Float
    let maxZ: Float
}

private struct PreviewMapper {
    let bounds: PreviewBounds
    let size: CGSize

    var worldWidth: Float { max(0.01, bounds.maxX - bounds.minX) }
    private var worldHeight: Float { max(0.01, bounds.maxZ - bounds.minZ) }

    func point(_ value: UnifiedPreviewPoint) -> CGPoint { point(x: value.x, z: value.z) }

    func point(x: Float, z: Float) -> CGPoint {
        let padding: CGFloat = 20
        let availableWidth = max(1, size.width - padding * 2)
        let availableHeight = max(1, size.height - padding * 2)
        let scale = min(availableWidth / CGFloat(worldWidth), availableHeight / CGFloat(worldHeight))
        let contentWidth = CGFloat(worldWidth) * scale
        let contentHeight = CGFloat(worldHeight) * scale
        let originX = (size.width - contentWidth) / 2
        let originY = (size.height - contentHeight) / 2
        return CGPoint(
            x: originX + CGFloat(x - bounds.minX) * scale,
            y: originY + CGFloat(bounds.maxZ - z) * scale
        )
    }

    func cellRect(_ cell: UnifiedPreviewCell, cellSize: Float) -> CGRect {
        let minX = Float(cell.xIndex) * cellSize
        let minZ = Float(cell.zIndex) * cellSize
        let maxX = minX + cellSize
        let maxZ = minZ + cellSize
        let topLeft = point(x: minX, z: maxZ)
        let bottomRight = point(x: maxX, z: minZ)
        return CGRect(
            x: min(topLeft.x, bottomRight.x),
            y: min(topLeft.y, bottomRight.y),
            width: max(1, abs(bottomRight.x - topLeft.x)),
            height: max(1, abs(bottomRight.y - topLeft.y))
        )
    }
}
