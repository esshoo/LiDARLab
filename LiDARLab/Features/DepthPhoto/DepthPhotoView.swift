import SwiftUI

struct DepthPhotoView: View {
    private enum Panel { case controls, latest }

    @StateObject private var model = DepthPhotoViewModel()
    @State private var overlayOpacity = 0.55
    @State private var useSmoothedDepth = true
    @State private var highConfidenceOnly = false
    @State private var shareItems: [Any] = []
    @State private var showingShareSheet = false
    @State private var panel: Panel?

    private let capabilities = DeviceCapabilities.current

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                DepthPhotoARViewContainer(model: model)
                    .ignoresSafeArea(edges: .bottom)

                if let image = model.heatMapImage {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .opacity(overlayOpacity)
                        .allowsHitTesting(false)
                        .clipped()
                        .ignoresSafeArea(edges: .bottom)
                }

                CrosshairView()
                    .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
                    .allowsHitTesting(false)

                VStack {
                    HStack {
                        LiveCameraStatusBadge(
                            title: format(model.centerDistance),
                            detail: model.statusMessage,
                            systemImage: "camera.filters"
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
                        LiveCameraSideButton(systemImage: "slider.horizontal.3", accessibilityLabel: "إعدادات صورة العمق", isSelected: panel == .controls) { toggle(.controls) }
                        LiveCameraSideButton(systemImage: "photo", accessibilityLabel: "آخر لقطة", isSelected: panel == .latest, isEnabled: model.latestCapture != nil) { toggle(.latest) }
                        if let capture = model.latestCapture {
                            LiveCameraSideButton(systemImage: "square.and.arrow.up", accessibilityLabel: "مشاركة آخر لقطة") {
                                shareItems = capture.shareItems
                                showingShareSheet = true
                            }
                        }
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
                            model.capture()
                        } label: {
                            Label(model.isSaving ? "جارٍ الحفظ…" : "التقاط وحفظ", systemImage: model.isSaving ? "hourglass" : "camera.shutter.button.fill")
                                .font(.headline)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(model.isSaving)
                    }
                    .padding(.bottom, 12)
                }
            }
            .animation(.easeInOut(duration: 0.18), value: panel != nil)
        }
        .background(.black)
        .navigationTitle("صورة مع العمق")
        .navigationBarTitleDisplayMode(.inline)
        .keepScreenAwakeForLiveTool(id: "depth.photo")
        .onChange(of: useSmoothedDepth) { _, value in model.preferSmoothedDepth = value }
        .onChange(of: highConfidenceOnly) { _, value in model.showOnlyHighConfidence = value }
        .onDisappear { model.stopSession() }
        .sheet(isPresented: $showingShareSheet) { ActivityView(items: shareItems) }
        .alert("تعذر إكمال العملية", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.clearError() } }
        )) {
            Button("حسنًا", role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "خطأ غير معروف")
        }
    }

    private func toggle(_ newPanel: Panel) { panel = panel == newPanel ? nil : newPanel }

    @ViewBuilder
    private func panelView(_ panel: Panel) -> some View {
        switch panel {
        case .controls:
            LiveCameraFloatingPanel(title: "إعدادات صورة العمق", systemImage: "slider.horizontal.3", onClose: { self.panel = nil }) {
                VStack(alignment: .leading, spacing: 12) {
                    if capabilities.smoothedDepthSupported {
                        Picker("نوع العمق", selection: $useSmoothedDepth) {
                            Text("خام").tag(false)
                            Text("منعّم").tag(true)
                        }
                        .pickerStyle(.segmented)
                    }
                    Toggle("ثقة مرتفعة فقط", isOn: $highConfidenceOnly)
                    HStack {
                        Image(systemName: "circle.lefthalf.filled")
                        Slider(value: $overlayOpacity, in: 0...0.9)
                        Text("\(Int(overlayOpacity * 100))%")
                            .font(.caption.monospacedDigit())
                    }
                }
            }
        case .latest:
            LiveCameraFloatingPanel(title: "آخر لقطة", systemImage: "photo", onClose: { self.panel = nil }) {
                if let capture = model.latestCapture {
                    VStack(alignment: .leading, spacing: 10) {
                        Image(uiImage: capture.previewImage)
                            .resizable()
                            .scaledToFit()
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        Text(capture.folderURL.lastPathComponent)
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                        Button {
                            shareItems = capture.shareItems
                            showingShareSheet = true
                        } label: {
                            Label("مشاركة الملفات", systemImage: "square.and.arrow.up")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }
                } else {
                    Text("لا توجد لقطة محفوظة بعد.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func format(_ distance: Float?) -> String {
        guard let distance else { return "—" }
        return String(format: "%.2f m", distance)
    }
}
