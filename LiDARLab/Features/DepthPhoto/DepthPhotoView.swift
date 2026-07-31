import SwiftUI

struct DepthPhotoView: View {
    @StateObject private var model = DepthPhotoViewModel()
    @State private var overlayOpacity = 0.55
    @State private var useSmoothedDepth = true
    @State private var highConfidenceOnly = false
    @State private var shareItems: [Any] = []
    @State private var showingShareSheet = false

    private let capabilities = DeviceCapabilities.current

    var body: some View {
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

            VStack(spacing: 12) {
                controls
                Spacer(minLength: 10)
                CrosshairView()
                Spacer(minLength: 10)
                capturePanel
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 14)
        }
        .background(.black)
        .navigationTitle("صورة مع العمق")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: useSmoothedDepth) { _, value in model.preferSmoothedDepth = value }
        .onChange(of: highConfidenceOnly) { _, value in model.showOnlyHighConfidence = value }
        .onDisappear { model.stopSession() }
        .sheet(isPresented: $showingShareSheet) {
            ActivityView(items: shareItems)
        }
        .alert("تعذر إكمال العملية", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.clearError() } }
        )) {
            Button("حسنًا", role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "خطأ غير معروف")
        }
    }

    private var controls: some View {
        VStack(spacing: 10) {
            if capabilities.smoothedDepthSupported {
                Picker("نوع العمق", selection: $useSmoothedDepth) {
                    Text("خام").tag(false)
                    Text("منعّم").tag(true)
                }
                .pickerStyle(.segmented)
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    Toggle("ثقة مرتفعة فقط", isOn: $highConfidenceOnly)
                        .font(.caption)
                    Spacer(minLength: 8)
                    opacityControl
                }

                VStack(alignment: .leading, spacing: 10) {
                    Toggle("ثقة مرتفعة فقط", isOn: $highConfidenceOnly)
                        .font(.caption)
                    opacityControl
                }
            }
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private var opacityControl: some View {
        HStack(spacing: 8) {
            Image(systemName: "circle.lefthalf.filled")
            Slider(value: $overlayOpacity, in: 0...0.9)
                .frame(maxWidth: 150)
            Text("\(Int(overlayOpacity * 100))%")
                .font(.caption.monospacedDigit())
                .frame(width: 38)
        }
    }

    private var capturePanel: some View {
        VStack(spacing: 11) {
            HStack {
                Label(model.statusMessage, systemImage: model.latestCapture == nil ? "camera.filters" : "checkmark.circle.fill")
                    .font(.caption.bold())
                    .lineLimit(2)
                Spacer()
                Text(format(model.centerDistance))
                    .font(.caption.monospacedDigit().bold())
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    captureButton
                    if let capture = model.latestCapture {
                        shareButton(capture)
                    }
                }
                VStack(spacing: 10) {
                    captureButton
                    if let capture = model.latestCapture {
                        shareButton(capture)
                    }
                }
            }

            if let capture = model.latestCapture {
                HStack(spacing: 10) {
                    Image(uiImage: capture.previewImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 58, height: 58)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    VStack(alignment: .leading, spacing: 3) {
                        Text("آخر حزمة محفوظة")
                            .font(.caption.bold())
                        Text(capture.folderURL.lastPathComponent)
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                }
            }
        }
        .padding(13)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
    }

    private var captureButton: some View {
        Button {
            model.capture()
        } label: {
            Label(model.isSaving ? "جارٍ الحفظ…" : "التقاط وحفظ", systemImage: model.isSaving ? "hourglass" : "camera.shutter.button.fill")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(model.isSaving)
    }

    private func shareButton(_ capture: DepthPhotoCapture) -> some View {
        Button {
            shareItems = capture.shareItems
            showingShareSheet = true
        } label: {
            Label("مشاركة الملفات", systemImage: "square.and.arrow.up")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
    }

    private func format(_ distance: Float?) -> String {
        guard let distance else { return "—" }
        return String(format: "%.2f m", distance)
    }
}
