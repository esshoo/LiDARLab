import Foundation
import SwiftUI

struct DistanceMeasureView: View {
    private enum Panel { case options, results }

    @StateObject private var model = MeasurementViewModel()
    @State private var useCentimeters = false
    @State private var showingSaveDialog = false
    @State private var measurementName = "قياس"
    @State private var shareItems: [Any] = []
    @State private var showingShareSheet = false
    @State private var panel: Panel?

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                MeasurementARViewContainer(model: model)
                    .ignoresSafeArea(edges: .bottom)

                MeasurementOverlay(projection: model.projection, useCentimeters: useCentimeters)
                    .allowsHitTesting(false)

                CrosshairView()
                    .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
                    .allowsHitTesting(false)

                VStack {
                    HStack {
                        LiveCameraStatusBadge(
                            title: model.statusMessage,
                            detail: "\(model.pointCount) نقطة • AR: \(model.trackingState)",
                            systemImage: "ruler"
                        )
                        Spacer()
                    }
                    .padding(.leading, 12)
                    .padding(.top, 10)
                    Spacer()
                }

                HStack {
                    Spacer()
                    LiveCameraSideRail {
                        LiveCameraSideButton(systemImage: "slider.horizontal.3", accessibilityLabel: "إعدادات القياس", isSelected: panel == .options) { toggle(.options) }
                        LiveCameraSideButton(systemImage: "chart.bar.xaxis", accessibilityLabel: "نتائج القياس", isSelected: panel == .results) { toggle(.results) }
                        LiveCameraSideButton(systemImage: "arrow.uturn.backward", accessibilityLabel: "تراجع", isEnabled: model.pointCount > 0) { model.undo() }
                        LiveCameraSideButton(systemImage: "square.and.arrow.down", accessibilityLabel: "حفظ", isEnabled: model.pointCount >= 2 && !model.isSaving) { showingSaveDialog = true }
                        LiveCameraSideButton(systemImage: "trash", accessibilityLabel: "مسح القياس", tint: .red, isEnabled: model.pointCount > 0) { model.clear() }
                    }
                    .padding(.trailing, 10)
                }

                if let panel {
                    HStack {
                        Spacer()
                        panelView(panel).padding(.trailing, 72)
                    }
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                }

                VStack {
                    Spacer()
                    LiveCameraBottomBar {
                        Button {
                            model.addPointAtCenter()
                        } label: {
                            Label("إضافة نقطة", systemImage: "plus.viewfinder")
                                .font(.headline)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .padding(.bottom, 12)
                }
            }
            .animation(.easeInOut(duration: 0.18), value: panel != nil)
        }
        .background(.black)
        .navigationTitle("القياس المتعدد")
        .navigationBarTitleDisplayMode(.inline)
        .keepScreenAwakeForLiveTool(id: "measure.distance")
        .onDisappear { model.stop() }
        .sheet(isPresented: $showingShareSheet) { ActivityView(items: shareItems) }
        .alert("حفظ القياس", isPresented: $showingSaveDialog) {
            TextField("اسم القياس", text: $measurementName)
            Button("حفظ") { model.saveMeasurement(named: measurementName) }
            Button("إلغاء", role: .cancel) {}
        } message: {
            Text("سيتم حفظ JSON وCSV وصورة للمشهد داخل مجلد Measurements.")
        }
        .alert("تعذر إكمال القياس", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.clearError() } }
        )) {
            Button("حسنًا", role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "خطأ غير معروف")
        }
        .onChange(of: model.latestSavedItems.count) { _, count in
            guard count > 0 else { return }
            shareItems = model.latestSavedItems
            showingShareSheet = true
            model.clearSavedItems()
        }
    }

    private func toggle(_ newPanel: Panel) { panel = panel == newPanel ? nil : newPanel }

    @ViewBuilder
    private func panelView(_ panel: Panel) -> some View {
        switch panel {
        case .options:
            LiveCameraFloatingPanel(title: "إعدادات القياس", systemImage: "slider.horizontal.3", onClose: { self.panel = nil }) {
                VStack(alignment: .leading, spacing: 12) {
                    Picker("الوحدة", selection: $useCentimeters) {
                        Text("متر").tag(false)
                        Text("سم").tag(true)
                    }
                    .pickerStyle(.segmented)

                    Button {
                        model.toggleClosedPath()
                    } label: {
                        Label(model.isClosedPath ? "فتح المسار" : "إغلاق المسار", systemImage: model.isClosedPath ? "lock.open" : "point.3.connected.trianglepath.dotted")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(model.pointCount < 3)

                    Button {
                        model.startSession(resetTracking: true)
                    } label: {
                        Label("إعادة التتبع", systemImage: "arrow.clockwise")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
            }
        case .results:
            LiveCameraFloatingPanel(title: "نتائج القياس", systemImage: "chart.bar.xaxis", onClose: { self.panel = nil }) {
                VStack(spacing: 10) {
                    resultMetric(title: "الإجمالي", value: formatted(model.totalDirectMeters), image: "sum")
                    resultMetric(title: "آخر ضلع", value: formatted(model.latestSegment?.directMeters), image: "ruler")
                    resultMetric(title: "أفقي", value: formatted(model.latestSegment?.horizontalMeters), image: "arrow.left.and.right")
                    resultMetric(title: "رأسي", value: formatted(model.latestSegment?.verticalMeters), image: "arrow.up.and.down")
                }
            }
        }
    }

    private func resultMetric(title: String, value: String, image: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: image).foregroundStyle(.cyan)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.caption2).foregroundStyle(.secondary)
                Text(value).font(.headline.monospacedDigit()).minimumScaleFactor(0.65).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(maxWidth: .infinity)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
    }

    private func formatted(_ meters: Double?) -> String {
        guard let meters else { return "—" }
        if useCentimeters { return String(format: "%.1f سم", meters * 100) }
        return String(format: "%.3f م", meters)
    }
}

private struct MeasurementOverlay: View {
    let projection: MeasurementProjection
    let useCentimeters: Bool

    var body: some View {
        ZStack {
            Canvas { context, _ in
                for segment in projection.segments {
                    var path = Path()
                    path.move(to: segment.start)
                    path.addLine(to: segment.end)
                    context.stroke(
                        path,
                        with: .color(.cyan),
                        style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round)
                    )
                }

                for point in projection.points {
                    let rect = CGRect(
                        x: point.screenPoint.x - 8,
                        y: point.screenPoint.y - 8,
                        width: 16,
                        height: 16
                    )
                    context.fill(Path(ellipseIn: rect), with: .color(.yellow))
                    context.stroke(Path(ellipseIn: rect), with: .color(.black), lineWidth: 2)
                    context.draw(
                        Text("\(point.index + 1)")
                            .font(.caption2.bold())
                            .foregroundStyle(.black),
                        at: point.screenPoint
                    )
                }
            }

            ForEach(projection.segments) { segment in
                Text(formatted(segment.directMeters))
                    .font(.caption.monospacedDigit().bold())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.ultraThinMaterial, in: Capsule())
                    .overlay(Capsule().stroke(.cyan.opacity(0.8), lineWidth: 1))
                    .position(segment.midpoint)
                    .offset(y: -14)
            }
        }
    }

    private func formatted(_ meters: Double) -> String {
        if useCentimeters {
            return String(format: "%.1f سم", meters * 100)
        }
        return String(format: "%.3f م", meters)
    }
}
