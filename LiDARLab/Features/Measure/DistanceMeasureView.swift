import Foundation
import SwiftUI

struct DistanceMeasureView: View {
    @StateObject private var model = MeasurementViewModel()
    @State private var useCentimeters = false
    @State private var showingSaveDialog = false
    @State private var measurementName = "قياس"
    @State private var shareItems: [Any] = []
    @State private var showingShareSheet = false

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                MeasurementARViewContainer(model: model)
                    .ignoresSafeArea(edges: .bottom)

                MeasurementOverlay(
                    projection: model.projection,
                    useCentimeters: useCentimeters
                )
                .allowsHitTesting(false)

                CrosshairView()
                    .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
                    .allowsHitTesting(false)

                VStack(spacing: 10) {
                    topPanel
                    Spacer(minLength: 120)
                    resultsPanel
                    controlsPanel
                }
                .padding(.horizontal, adaptiveHorizontalPadding(for: geometry.size.width))
                .padding(.top, 10)
                .padding(.bottom, 12)
            }
        }
        .background(.black)
        .navigationTitle("القياس المتعدد")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { model.stop() }
        .sheet(isPresented: $showingShareSheet) {
            ActivityView(items: shareItems)
        }
        .alert("حفظ القياس", isPresented: $showingSaveDialog) {
            TextField("اسم القياس", text: $measurementName)
            Button("حفظ") {
                model.saveMeasurement(named: measurementName)
            }
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

    private var topPanel: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(model.statusMessage)
                        .font(.headline)
                    Text("اضغط على أي سطح أو استخدم زر إضافة نقطة عند مؤشر المنتصف.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Text("\(model.pointCount) نقطة")
                    .font(.caption.monospacedDigit().bold())
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(.thinMaterial, in: Capsule())
            }

            HStack(spacing: 8) {
                Label("AR: \(model.trackingState)", systemImage: "location.viewfinder")
                    .font(.caption2.bold())
                Spacer()
                Picker("الوحدة", selection: $useCentimeters) {
                    Text("متر").tag(false)
                    Text("سم").tag(true)
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 170)
            }
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var resultsPanel: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                resultMetric(title: "الإجمالي", value: formatted(model.totalDirectMeters), image: "sum")
                resultMetric(title: "آخر ضلع", value: formatted(model.latestSegment?.directMeters), image: "ruler")
            }
            HStack(spacing: 10) {
                resultMetric(title: "أفقي", value: formatted(model.latestSegment?.horizontalMeters), image: "arrow.left.and.right")
                resultMetric(title: "رأسي", value: formatted(model.latestSegment?.verticalMeters), image: "arrow.up.and.down")
            }
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var controlsPanel: some View {
        VStack(spacing: 9) {
            Button {
                model.addPointAtCenter()
            } label: {
                Label("إضافة نقطة عند المؤشر", systemImage: "plus.viewfinder")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                Button {
                    model.undo()
                } label: {
                    Label("تراجع", systemImage: "arrow.uturn.backward")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(model.pointCount == 0)

                Button {
                    model.toggleClosedPath()
                } label: {
                    Label(model.isClosedPath ? "فتح المسار" : "إغلاق المسار", systemImage: model.isClosedPath ? "lock.open" : "point.3.connected.trianglepath.dotted")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(model.pointCount < 3)

                Button {
                    showingSaveDialog = true
                } label: {
                    Label(model.isSaving ? "جارٍ الحفظ" : "حفظ", systemImage: model.isSaving ? "hourglass" : "square.and.arrow.down")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(model.pointCount < 2 || model.isSaving)

                Menu {
                    Button(role: .destructive) {
                        model.clear()
                    } label: {
                        Label("مسح القياس", systemImage: "trash")
                    }
                    Button {
                        model.startSession(resetTracking: true)
                    } label: {
                        Label("إعادة التتبع", systemImage: "arrow.clockwise")
                    }
                } label: {
                    Label("المزيد", systemImage: "ellipsis.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            .font(.caption.bold())
        }
    }

    private func resultMetric(title: String, value: String, image: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: image)
                .foregroundStyle(.cyan)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.headline.monospacedDigit())
                    .minimumScaleFactor(0.65)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(maxWidth: .infinity)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
    }

    private func formatted(_ meters: Double?) -> String {
        guard let meters else { return "—" }
        if useCentimeters {
            return String(format: "%.1f سم", meters * 100)
        }
        return String(format: "%.3f م", meters)
    }

    private func adaptiveHorizontalPadding(for width: CGFloat) -> CGFloat {
        width >= 900 ? 28 : (width >= 600 ? 20 : 12)
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
