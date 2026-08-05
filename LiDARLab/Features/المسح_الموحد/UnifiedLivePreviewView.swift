import SwiftUI
import simd

struct UnifiedLivePreviewView: View {
    let path: [UnifiedPreviewPoint]
    let sweeps: [UnifiedPreviewSweep]
    let currentPosition: SIMD3<Float>
    let currentQuaternion: simd_quatf
    let showGrid: Bool
    let showPath: Bool
    let showCoverage: Bool
    let showDevice: Bool

    var body: some View {
        GeometryReader { proxy in
            Canvas { context, size in
                let bounds = drawingBounds
                let mapper = PreviewMapper(bounds: bounds, size: size)

                if showGrid {
                    drawGrid(context: &context, mapper: mapper, size: size)
                }
                if showCoverage {
                    drawCoverage(context: &context, mapper: mapper)
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
                    colors: [Color.black.opacity(0.96), Color(red: 0.035, green: 0.06, blue: 0.09)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(alignment: .topLeading) {
                Text("معاينة خفيفة — ليست النتيجة النهائية")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(8)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(10)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var drawingBounds: PreviewBounds {
        var points = path
        if showCoverage {
            for sweep in sweeps { points.append(contentsOf: sweep.points) }
        }
        points.append(UnifiedPreviewPoint(x: currentPosition.x, z: currentPosition.z))
        guard let first = points.first else {
            return PreviewBounds(minX: -2, maxX: 2, minZ: -2, maxZ: 2)
        }
        var minX = first.x
        var maxX = first.x
        var minZ = first.z
        var maxZ = first.z
        for point in points.dropFirst() {
            minX = min(minX, point.x)
            maxX = max(maxX, point.x)
            minZ = min(minZ, point.z)
            maxZ = max(maxZ, point.z)
        }
        let width = max(1.5, maxX - minX)
        let height = max(1.5, maxZ - minZ)
        let margin = max(0.6, max(width, height) * 0.12)
        return PreviewBounds(minX: minX - margin, maxX: maxX + margin, minZ: minZ - margin, maxZ: maxZ + margin)
    }

    private func drawGrid(context: inout GraphicsContext, mapper: PreviewMapper, size: CGSize) {
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
        for sweep in sweeps where sweep.points.count >= 3 {
            var shape = Path()
            shape.move(to: mapper.point(sweep.points[0]))
            for point in sweep.points.dropFirst() {
                shape.addLine(to: mapper.point(point))
            }
            shape.closeSubpath()
            context.fill(shape, with: .color(.cyan.opacity(0.045)))
            context.stroke(shape, with: .color(.cyan.opacity(0.10)), lineWidth: 0.5)
        }
    }

    private func drawPath(context: inout GraphicsContext, mapper: PreviewMapper) {
        guard path.count > 1 else { return }
        var line = Path()
        line.move(to: mapper.point(path[0]))
        for point in path.dropFirst() { line.addLine(to: mapper.point(point)) }
        context.stroke(line, with: .color(.green.opacity(0.9)), style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
    }

    private func drawDevice(context: inout GraphicsContext, mapper: PreviewMapper) {
        let position = UnifiedPreviewPoint(x: currentPosition.x, z: currentPosition.z)
        let center = mapper.point(position)
        let forward = currentQuaternion.act(SIMD3<Float>(0, 0, -0.45))
        let end = mapper.point(x: position.x + forward.x, z: position.z + forward.z)

        var arrow = Path()
        arrow.move(to: center)
        arrow.addLine(to: end)
        context.stroke(arrow, with: .color(.orange), style: StrokeStyle(lineWidth: 3, lineCap: .round))
        context.fill(Path(ellipseIn: CGRect(x: center.x - 6, y: center.y - 6, width: 12, height: 12)), with: .color(.orange))
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
}
