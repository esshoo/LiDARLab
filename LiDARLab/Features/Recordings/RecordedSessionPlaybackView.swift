import Combine
import SwiftUI
import UIKit

final class RecordedSessionPlaybackViewModel: ObservableObject {
    enum DisplayMode: String, CaseIterable, Identifiable {
        case color
        case depth

        var id: String { rawValue }
        var title: String { self == .color ? "الصورة" : "العمق" }
        var systemImage: String { self == .color ? "camera.fill" : "camera.filters" }
    }

    let session: RecordedSessionSummary
    @Published var frameIndex = 0
    @Published var displayMode: DisplayMode = .color
    @Published var isPlaying = false
    @Published var playbackRate = 1.0
    @Published private(set) var image: UIImage?
    @Published private(set) var errorMessage: String?

    private var lastAdvance = Date()

    init(session: RecordedSessionSummary) {
        self.session = session
        loadCurrentFrame()
    }

    var frames: [RecordedFrameMetadata] { session.manifest.frames }
    var currentFrame: RecordedFrameMetadata? {
        guard frames.indices.contains(frameIndex) else { return nil }
        return frames[frameIndex]
    }

    func togglePlayback() {
        guard !frames.isEmpty else { return }
        if frameIndex >= frames.count - 1, !isPlaying { frameIndex = 0 }
        isPlaying.toggle()
        lastAdvance = Date()
    }

    func tick() {
        guard isPlaying, !frames.isEmpty else { return }
        let baseFPS = max(0.5, session.manifest.requestedFramesPerSecond)
        let interval = 1.0 / (baseFPS * max(0.25, playbackRate))
        guard Date().timeIntervalSince(lastAdvance) >= interval else { return }
        lastAdvance = Date()
        if frameIndex < frames.count - 1 {
            frameIndex += 1
        } else {
            isPlaying = false
        }
    }

    func loadCurrentFrame() {
        guard let frame = currentFrame else {
            image = nil
            return
        }
        let relative = displayMode == .color ? frame.colorFile : frame.heatMapFile
        let url = session.folderURL.appendingPathComponent(relative)
        guard let loaded = UIImage(contentsOfFile: url.path) else {
            image = nil
            errorMessage = "تعذر قراءة الملف \(url.lastPathComponent)."
            return
        }
        image = loaded
    }

    func clearError() { errorMessage = nil }
}

struct RecordedSessionPlaybackView: View {
    @StateObject private var model: RecordedSessionPlaybackViewModel
    @State private var showingShareSheet = false
    private let timer = Timer.publish(every: 0.08, on: .main, in: .common).autoconnect()

    init(session: RecordedSessionSummary) {
        _model = StateObject(wrappedValue: RecordedSessionPlaybackViewModel(session: session))
    }

    var body: some View {
        VStack(spacing: 14) {
            playbackCanvas
            controls
            frameDetails
        }
        .padding(14)
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle(model.session.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingShareSheet = true
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
            }
        }
        .sheet(isPresented: $showingShareSheet) {
            ActivityView(items: model.session.shareItems)
        }
        .onReceive(timer) { _ in model.tick() }
        .onChange(of: model.frameIndex) { _, _ in model.loadCurrentFrame() }
        .onChange(of: model.displayMode) { _, _ in model.loadCurrentFrame() }
        .alert("تعذر عرض الإطار", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.clearError() } }
        )) {
            Button("حسنًا", role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "خطأ غير معروف")
        }
    }

    private var playbackCanvas: some View {
        GeometryReader { proxy in
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(.black)
                if let image = model.image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: proxy.size.width, maxHeight: proxy.size.height)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                } else {
                    ContentUnavailableView("لا يوجد إطار", systemImage: "photo.badge.exclamationmark")
                        .foregroundStyle(.white)
                }

                VStack {
                    HStack {
                        Text(model.displayMode.title)
                            .font(.caption.bold())
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(.ultraThinMaterial, in: Capsule())
                        Spacer()
                        Text("\(model.frameIndex + 1) / \(max(model.frames.count, 1))")
                            .font(.caption.monospacedDigit().bold())
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(.ultraThinMaterial, in: Capsule())
                    }
                    Spacer()
                }
                .padding(10)
            }
        }
        .frame(minHeight: 300)
    }

    private var controls: some View {
        VStack(spacing: 12) {
            Picker("نوع العرض", selection: $model.displayMode) {
                ForEach(RecordedSessionPlaybackViewModel.DisplayMode.allCases) { mode in
                    Label(mode.title, systemImage: mode.systemImage).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            if !model.frames.isEmpty {
                Slider(
                    value: Binding(
                        get: { Double(model.frameIndex) },
                        set: { model.frameIndex = Int($0.rounded()) }
                    ),
                    in: 0...Double(max(model.frames.count - 1, 0)),
                    step: 1
                )
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) { playbackButtons }
                VStack(spacing: 10) { playbackButtons }
            }
        }
        .padding(13)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
    }

    @ViewBuilder
    private var playbackButtons: some View {
        Button {
            model.togglePlayback()
        } label: {
            Label(model.isPlaying ? "إيقاف مؤقت" : "تشغيل", systemImage: model.isPlaying ? "pause.fill" : "play.fill")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)

        Picker("السرعة", selection: $model.playbackRate) {
            Text("0.5×").tag(0.5)
            Text("1×").tag(1.0)
            Text("2×").tag(2.0)
        }
        .pickerStyle(.segmented)
        .frame(maxWidth: 220)
    }

    private var frameDetails: some View {
        GroupBox("بيانات الإطار") {
            if let frame = model.currentFrame {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 130))], spacing: 10) {
                    MetricChip(title: "الوقت", value: String(format: "%.2f s", frame.relativeTimestamp), systemImage: "clock")
                    MetricChip(title: "المركز", value: distance(frame.centerDistanceMeters), systemImage: "scope")
                    MetricChip(title: "الأدنى", value: distance(frame.minimumDistanceMeters), systemImage: "arrow.down")
                    MetricChip(title: "الأعلى", value: distance(frame.maximumDistanceMeters), systemImage: "arrow.up")
                }
                Text(frame.trackingState)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 8)
            } else {
                Text("لا توجد بيانات محفوظة.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func distance(_ value: Float?) -> String {
        guard let value else { return "—" }
        return String(format: "%.2f m", value)
    }
}
