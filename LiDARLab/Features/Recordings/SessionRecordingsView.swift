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
        .keepScreenAwakeForLiveTool(id: "recordings.live", active: section == .record)
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
    private enum Panel: String, Identifiable {
        case settings
        case metrics
        case latest

        var id: String { rawValue }
    }

    @ObservedObject var model: SessionRecordingViewModel
    @State private var sessionName = "Session"
    @State private var fps = 2.0
    @State private var duration = 60.0
    @State private var smoothedDepth = true
    @State private var showingShareSheet = false
    @State private var panel: Panel?

    var body: some View {
        ZStack {
            RecordingARViewContainer(model: model)
                .ignoresSafeArea(edges: .bottom)

            CrosshairView()
                .allowsHitTesting(false)

            VStack {
                HStack {
                    LiveCameraStatusBadge(
                        title: recordingStatusTitle,
                        detail: "\(formatDistance(model.centerDistance)) • \(model.frameCount) إطار",
                        systemImage: model.isRecording ? "record.circle.fill" : "camera.viewfinder",
                        accent: model.isRecording ? .red : (model.isFinalizing ? .orange : .cyan)
                    )
                    Spacer()
                }
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .allowsHitTesting(false)

            HStack {
                Spacer()
                VStack {
                    LiveCameraSideRail {
                        LiveCameraSideButton(
                            systemImage: "slider.horizontal.3",
                            accessibilityLabel: "إعدادات التسجيل",
                            isSelected: panel == .settings
                        ) {
                            togglePanel(.settings)
                        }

                        LiveCameraSideButton(
                            systemImage: "chart.bar.xaxis",
                            accessibilityLabel: "إحصائيات التسجيل",
                            isSelected: panel == .metrics
                        ) {
                            togglePanel(.metrics)
                        }

                        if model.latestSession != nil {
                            LiveCameraSideButton(
                                systemImage: "clock.arrow.circlepath",
                                accessibilityLabel: "آخر جلسة",
                                isSelected: panel == .latest
                            ) {
                                togglePanel(.latest)
                            }
                        }
                    }
                    Spacer()
                }
                .padding(.top, 66)
                .padding(.bottom, 84)
            }
            .padding(.trailing, 10)

            if let panel {
                HStack {
                    Spacer(minLength: 14)
                    panelView(panel)
                    Color.clear.frame(width: 62)
                }
                .padding(.horizontal, 10)
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }

            VStack {
                Spacer()
                LiveCameraBottomBar {
                    if model.isRecording {
                        Button(role: .destructive) {
                            model.stopRecording()
                        } label: {
                            Label("إيقاف وحفظ", systemImage: "stop.circle.fill")
                                .font(.headline)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                    } else {
                        Button {
                            applySettingsAndStart()
                        } label: {
                            Label(
                                model.isFinalizing ? "جارٍ الحفظ…" : "بدء التسجيل",
                                systemImage: model.isFinalizing ? "hourglass" : "record.circle.fill"
                            )
                            .font(.headline)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                        .disabled(model.isFinalizing)
                    }
                }
                .padding(.bottom, 12)
            }
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
        .animation(.easeInOut(duration: 0.18), value: panel)
    }

    private var recordingStatusTitle: String {
        if model.isRecording { return "جاري التسجيل" }
        if model.isFinalizing { return "جارٍ إنهاء الجلسة" }
        return model.statusMessage
    }

    private func togglePanel(_ value: Panel) {
        panel = panel == value ? nil : value
    }

    @ViewBuilder
    private func panelView(_ value: Panel) -> some View {
        switch value {
        case .settings:
            LiveCameraFloatingPanel(
                title: "إعدادات التسجيل",
                systemImage: "slider.horizontal.3",
                onClose: { panel = nil }
            ) {
                VStack(spacing: 11) {
                    TextField("اسم الجلسة", text: $sessionName)
                        .textFieldStyle(.roundedBorder)
                        .disabled(model.isRecording || model.isFinalizing)

                    VStack(alignment: .leading, spacing: 7) {
                        Text("معدل التسجيل")
                            .font(.caption.bold())
                        Picker("الإطارات", selection: $fps) {
                            Text("1 fps").tag(1.0)
                            Text("2 fps").tag(2.0)
                            Text("4 fps").tag(4.0)
                        }
                        .pickerStyle(.segmented)
                    }

                    VStack(alignment: .leading, spacing: 7) {
                        Text("المدة القصوى")
                            .font(.caption.bold())
                        Picker("المدة", selection: $duration) {
                            Text("30 ث").tag(30.0)
                            Text("60 ث").tag(60.0)
                            Text("120 ث").tag(120.0)
                        }
                        .pickerStyle(.segmented)
                    }

                    Toggle("استخدام العمق المنعّم", isOn: $smoothedDepth)
                        .font(.caption)

                    if model.isRecording || model.isFinalizing {
                        Text("الإعدادات مقفلة أثناء التسجيل والحفظ.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .disabled(model.isRecording || model.isFinalizing)
            }

        case .metrics:
            LiveCameraFloatingPanel(
                title: "حالة الجلسة",
                systemImage: "chart.bar.xaxis",
                onClose: { panel = nil }
            ) {
                VStack(alignment: .leading, spacing: 10) {
                    LabeledContent("الحالة", value: model.statusMessage)
                    LabeledContent("المسافة", value: formatDistance(model.centerDistance))
                    LabeledContent("المدة", value: formatTime(model.elapsedTime))
                    LabeledContent("الإطارات", value: "\(model.frameCount)")
                    LabeledContent("الإطارات المفقودة", value: "\(model.droppedFrames)")
                }
                .font(.caption)
            }

        case .latest:
            LiveCameraFloatingPanel(
                title: "آخر جلسة",
                systemImage: "clock.arrow.circlepath",
                onClose: { panel = nil }
            ) {
                if let session = model.latestSession {
                    VStack(spacing: 10) {
                        NavigationLink {
                            RecordedSessionPlaybackView(session: session)
                        } label: {
                            Label("تشغيل الجلسة", systemImage: "play.rectangle")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)

                        Button {
                            showingShareSheet = true
                        } label: {
                            Label("مشاركة الملفات", systemImage: "square.and.arrow.up")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }
                } else {
                    Text("لا توجد جلسة محفوظة بعد.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func applySettingsAndStart() {
        model.framesPerSecond = fps
        model.durationLimit = duration
        model.preferSmoothedDepth = smoothedDepth
        panel = nil
        model.startRecording(name: sessionName)
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
