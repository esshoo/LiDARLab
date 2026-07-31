import SwiftUI

struct SessionRecordingsView: View {
    private enum Section: String, CaseIterable, Identifiable {
        case record
        case library

        var id: String { rawValue }
        var title: String { self == .record ? "تسجيل" : "الجلسات" }
    }

    @StateObject private var model = SessionRecordingViewModel()
    @State private var section: Section = .record

    var body: some View {
        VStack(spacing: 0) {
            Picker("القسم", selection: $section) {
                ForEach(Section.allCases) { item in Text(item.title).tag(item) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.bar)

            if section == .record {
                SessionRecordingCaptureView(model: model)
            } else {
                RecordedSessionsLibraryView(model: model)
            }
        }
        .navigationTitle("تسجيل الجلسات")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: section) { _, value in
            if value == .library {
                if model.isRecording { model.stopRecording() }
                model.refreshSessions()
            }
        }
        .onDisappear { model.leaveView() }
        .alert("تعذر إكمال العملية", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.clearError() } }
        )) {
            Button("حسنًا", role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "خطأ غير معروف")
        }
    }
}

private struct SessionRecordingCaptureView: View {
    @ObservedObject var model: SessionRecordingViewModel
    @State private var sessionName = "Session"
    @State private var fps = 2.0
    @State private var duration = 60.0
    @State private var smoothedDepth = true
    @State private var showingShareSheet = false

    var body: some View {
        ZStack {
            RecordingARViewContainer(model: model)
                .ignoresSafeArea(edges: .bottom)

            VStack(spacing: 12) {
                settingsPanel
                Spacer(minLength: 12)
                CrosshairView()
                Spacer(minLength: 12)
                recordingPanel
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 14)
        }
        .background(.black)
        .sheet(isPresented: $showingShareSheet) {
            if let session = model.latestSession {
                ActivityView(items: session.shareItems)
            }
        }
        .onChange(of: fps) { _, value in model.framesPerSecond = value }
        .onChange(of: duration) { _, value in model.durationLimit = value }
        .onChange(of: smoothedDepth) { _, value in model.preferSmoothedDepth = value }
    }

    private var settingsPanel: some View {
        VStack(spacing: 10) {
            TextField("اسم الجلسة", text: $sessionName)
                .textFieldStyle(.roundedBorder)
                .disabled(model.isRecording || model.isFinalizing)

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) { settingPickers }
                VStack(spacing: 10) { settingPickers }
            }

            Toggle("استخدام العمق المنعّم", isOn: $smoothedDepth)
                .font(.caption)
                .disabled(model.isRecording || model.isFinalizing)
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 17))
    }

    @ViewBuilder
    private var settingPickers: some View {
        Picker("الإطارات", selection: $fps) {
            Text("1 fps").tag(1.0)
            Text("2 fps").tag(2.0)
            Text("4 fps").tag(4.0)
        }
        .pickerStyle(.segmented)
        .disabled(model.isRecording || model.isFinalizing)

        Picker("المدة", selection: $duration) {
            Text("30 ث").tag(30.0)
            Text("60 ث").tag(60.0)
            Text("120 ث").tag(120.0)
        }
        .pickerStyle(.segmented)
        .disabled(model.isRecording || model.isFinalizing)
    }

    private var recordingPanel: some View {
        VStack(spacing: 11) {
            HStack(spacing: 10) {
                Circle()
                    .fill(model.isRecording ? .red : (model.isFinalizing ? .orange : .secondary))
                    .frame(width: 10, height: 10)
                Text(model.statusMessage)
                    .font(.caption.bold())
                    .lineLimit(2)
                Spacer()
                Text(formatDistance(model.centerDistance))
                    .font(.caption.monospacedDigit().bold())
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 105))], spacing: 9) {
                MetricChip(title: "المدة", value: formatTime(model.elapsedTime), systemImage: "timer")
                MetricChip(title: "الإطارات", value: "\(model.frameCount)", systemImage: "photo.stack")
                MetricChip(title: "المفقودة", value: "\(model.droppedFrames)", systemImage: "exclamationmark.triangle")
            }

            if model.isRecording {
                Button(role: .destructive) {
                    model.stopRecording()
                } label: {
                    Label("إيقاف وحفظ", systemImage: "stop.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .controlSize(.large)
            } else {
                Button {
                    model.framesPerSecond = fps
                    model.durationLimit = duration
                    model.preferSmoothedDepth = smoothedDepth
                    model.startRecording(name: sessionName)
                } label: {
                    Label(model.isFinalizing ? "جارٍ إنهاء الجلسة…" : "بدء التسجيل", systemImage: model.isFinalizing ? "hourglass" : "record.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .controlSize(.large)
                .disabled(model.isFinalizing)
            }

            if let session = model.latestSession {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) { latestActions(session) }
                    VStack(spacing: 10) { latestActions(session) }
                }
            }
        }
        .padding(13)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
    }

    @ViewBuilder
    private func latestActions(_ session: RecordedSessionSummary) -> some View {
        NavigationLink {
            RecordedSessionPlaybackView(session: session)
        } label: {
            Label("تشغيل الجلسة", systemImage: "play.rectangle")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)

        Button {
            showingShareSheet = true
        } label: {
            Label("مشاركة", systemImage: "square.and.arrow.up")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
    }

    private func formatTime(_ value: TimeInterval) -> String {
        let seconds = Int(value.rounded(.down))
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }

    private func formatDistance(_ value: Float?) -> String {
        guard let value else { return "—" }
        return String(format: "%.2f m", value)
    }
}

private struct RecordedSessionsLibraryView: View {
    @ObservedObject var model: SessionRecordingViewModel
    @State private var shareItems: [Any] = []
    @State private var showingShareSheet = false
    @State private var sessionToDelete: RecordedSessionSummary?

    var body: some View {
        Group {
            if model.savedSessions.isEmpty {
                ContentUnavailableView(
                    "لا توجد جلسات محفوظة",
                    systemImage: "record.circle",
                    description: Text("سجّل جلسة جديدة ثم ستظهر هنا للتشغيل والمشاركة.")
                )
            } else {
                List {
                    ForEach(model.savedSessions) { session in
                        NavigationLink {
                            RecordedSessionPlaybackView(session: session)
                        } label: {
                            sessionRow(session)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                sessionToDelete = session
                            } label: {
                                Label("حذف", systemImage: "trash")
                            }
                            Button {
                                shareItems = session.shareItems
                                showingShareSheet = true
                            } label: {
                                Label("مشاركة", systemImage: "square.and.arrow.up")
                            }
                            .tint(.blue)
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .refreshable { model.refreshSessions() }
            }
        }
        .onAppear { model.refreshSessions() }
        .sheet(isPresented: $showingShareSheet) {
            ActivityView(items: shareItems)
        }
        .confirmationDialog("حذف الجلسة؟", isPresented: Binding(
            get: { sessionToDelete != nil },
            set: { if !$0 { sessionToDelete = nil } }
        ), titleVisibility: .visible) {
            Button("حذف نهائيًا", role: .destructive) {
                if let sessionToDelete { model.delete(sessionToDelete) }
                sessionToDelete = nil
            }
            Button("إلغاء", role: .cancel) { sessionToDelete = nil }
        }
    }

    private func sessionRow(_ session: RecordedSessionSummary) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "record.circle.fill")
                .font(.title2)
                .foregroundStyle(.red)
                .frame(width: 34)
            VStack(alignment: .leading, spacing: 4) {
                Text(session.title)
                    .font(.headline)
                    .lineLimit(1)
                Text(session.createdAt, format: .dateTime.year().month().day().hour().minute())
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("\(session.frameCount) إطار • \(formatTime(session.duration)) • \(ByteCountFormatter.string(fromByteCount: session.sizeBytes, countStyle: .file))")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private func formatTime(_ value: TimeInterval) -> String {
        let seconds = Int(value.rounded())
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
}
