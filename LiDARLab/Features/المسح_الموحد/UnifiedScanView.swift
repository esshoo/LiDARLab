import SwiftUI

struct UnifiedScanView: View {
    @StateObject private var model = UnifiedScanViewModel()
    @State private var showSettings = false
    @State private var showStats = false
    @State private var showRolePicker = false
    @State private var showModePicker = false
    @State private var showGrid = true
    @State private var showPath = true
    @State private var showCoverage = true
    @State private var showCurrentRays = true
    @State private var showDevice = true
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            if model.needsARSession {
                UnifiedARViewContainer(model: model)
                    .frame(width: 1, height: 1)
                    .opacity(0.001)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }

            VStack(spacing: 10) {
                compactToolbar

                UnifiedLivePreviewView(
                    path: model.path,
                    coverageCells: model.coverageCells,
                    currentSweep: model.currentSweep,
                    currentPosition: model.currentPosition,
                    currentQuaternion: model.currentQuaternion,
                    coverageCellSize: model.previewCellSize,
                    coverageStyle: model.coveragePreviewStyle,
                    pathStyle: model.pathPreviewStyle,
                    deviceStyle: model.devicePreviewStyle,
                    showGrid: showGrid,
                    showPath: showPath,
                    showCoverage: showCoverage,
                    showCurrentRays: showCurrentRays,
                    showDevice: showDevice
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .allowsHitTesting(false)

                statusStrip
                controlBar
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 8)
        }
        .navigationTitle("المسح الموحد")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .fullScreenCover(isPresented: $showSettings) {
            UnifiedScanSettingsView(
                model: model,
                showGrid: $showGrid,
                showPath: $showPath,
                showCoverage: $showCoverage,
                showCurrentRays: $showCurrentRays,
                showDevice: $showDevice
            )
        }
        .fullScreenCover(isPresented: $showStats) {
            UnifiedScanStatsView(model: model)
        }
        .fullScreenCover(isPresented: $showRolePicker) {
            UnifiedRolePickerSheet(selectedRole: model.role) { selected in
                model.role = selected
                showRolePicker = false
            } onCancel: {
                showRolePicker = false
            }
        }
        .fullScreenCover(isPresented: $showModePicker) {
            UnifiedModePickerSheet(selectedMode: model.scanMode) { selected in
                model.scanMode = selected
                showModePicker = false
            } onCancel: {
                showModePicker = false
            }
        }
        .fullScreenCover(item: $model.capabilityWarning) { warning in
            UnifiedCapabilityWarningScreen(
                warning: warning,
                onContinue: { model.continueAfterCapabilityWarning() },
                onCancel: { model.cancelCapabilityWarning() }
            )
            .interactiveDismissDisabled(true)
        }
        .onAppear {
            model.setScanViewVisible(true)
            model.setApplicationActive(scenePhase == .active)
            model.applyRoleChange()
            updateOverlayState()
        }
        .onChange(of: model.role) { _, _ in model.applyRoleChange() }
        .onChange(of: scenePhase) { _, phase in
            model.setApplicationActive(phase == .active)
        }
        .onChange(of: showSettings) { _, _ in updateOverlayState() }
        .onChange(of: showStats) { _, _ in updateOverlayState() }
        .onChange(of: showRolePicker) { _, _ in updateOverlayState() }
        .onChange(of: showModePicker) { _, _ in updateOverlayState() }
        .onChange(of: model.capabilityWarning?.id) { _, _ in updateOverlayState() }
        .onDisappear {
            model.setScanViewVisible(false)
            model.setInterfaceOverlayPresented(false)
            model.shutdown()
        }
    }

    private func updateOverlayState() {
        model.setInterfaceOverlayPresented(
            showSettings || showStats || showRolePicker || showModePicker || model.capabilityWarning != nil
        )
    }

    private var compactToolbar: some View {
        HStack(spacing: 8) {
            Button {
                showRolePicker = true
            } label: {
                CompactMenuLabel(title: model.role.shortTitle, image: model.role.systemImage)
            }
            .buttonStyle(.plain)
            .disabled(model.settingsLocked)

            Button {
                showModePicker = true
            } label: {
                CompactMenuLabel(title: model.scanMode.title, image: model.scanMode.systemImage)
            }
            .buttonStyle(.plain)
            .disabled(model.settingsLocked)

            Spacer(minLength: 0)

            Button { showStats = true } label: {
                Image(systemName: "chart.bar.xaxis")
                    .frame(width: 40, height: 40)
                    .background(.thinMaterial, in: Circle())
            }
            .buttonStyle(.plain)
            .contentShape(Circle())
            .accessibilityLabel("الإحصائيات")

            Button { showSettings = true } label: {
                Image(systemName: "gearshape")
                    .frame(width: 40, height: 40)
                    .background(.thinMaterial, in: Circle())
            }
            .buttonStyle(.plain)
            .contentShape(Circle())
            .accessibilityLabel("الإعدادات")
        }
        .font(.subheadline.weight(.semibold))
    }

    private var statusStrip: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(model.sessionState.color)
                .frame(width: 8, height: 8)
            Text(model.sessionState.title)
                .font(.caption.weight(.bold))
            Divider().frame(height: 14)
            Text(model.connectionState.title)
                .font(.caption)
            Spacer(minLength: 4)
            Text(model.positionText)
                .font(.caption2.monospacedDigit())
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(.thinMaterial, in: Capsule())
        .overlay(alignment: .top) {
            Text(model.statusMessage)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .offset(y: -17)
                .padding(.horizontal, 6)
        }
    }

    @ViewBuilder
    private var controlBar: some View {
        HStack(spacing: 8) {
            if model.sessionState == .finished {
                Button { model.requestProcessing() } label: {
                    Label("معالجة", systemImage: "gearshape.2")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)
            }

            if model.role == .sender {
                Button {
                    model.isConnected ? model.disconnectSender() : model.connectSender()
                } label: {
                    Label(model.isConnected ? "فصل" : "اتصال", systemImage: model.isConnected ? "link.badge.minus" : "link")
                }
                .buttonStyle(.bordered)
                .disabled(model.settingsLocked)
            } else if model.role == .receiver,
                      model.connectionState != .listening,
                      model.connectionState != .connected {
                Button { model.startReceiver() } label: {
                    Label("استقبال", systemImage: "antenna.radiowaves.left.and.right")
                }
                .buttonStyle(.bordered)
            }

            if model.role != .receiver {
                Button {
                    model.requestStartSession()
                } label: {
                    Label("بدء", systemImage: "record.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .disabled(model.isRecording || model.isPaused || (model.role == .sender && !model.isConnected))
            }

            Button {
                model.pauseOrResume()
            } label: {
                Label(model.isPaused ? "استكمال" : "إيقاف", systemImage: model.isPaused ? "play.fill" : "pause.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(model.role == .receiver || (!model.isRecording && !model.isPaused))

            Button {
                model.finishSession()
            } label: {
                Label("إنهاء", systemImage: "stop.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .disabled(!model.isRecording && !model.isPaused)
        }
        .font(.caption.weight(.bold))
    }
}

private struct UnifiedCapabilityWarningScreen: View {
    let warning: UnifiedCapabilityWarning
    let onContinue: () -> Void
    let onCancel: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 22) {
                Spacer()
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 54))
                    .foregroundStyle(.orange)
                Text(warning.title)
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)
                Text(warning.message)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(5)
                    .padding(.horizontal, 24)
                Spacer()
                VStack(spacing: 12) {
                    Button(action: onContinue) {
                        Text(warning.continueTitle)
                            .font(.headline)
                            .frame(maxWidth: .infinity, minHeight: 54)
                    }
                    .buttonStyle(.borderedProminent)

                    Button(action: onCancel) {
                        Text("إلغاء")
                            .font(.headline)
                            .frame(maxWidth: .infinity, minHeight: 54)
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
            .navigationTitle("تأكيد التشغيل")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

private struct CompactMenuLabel: View {
    let title: String
    let image: String

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: image)
            Text(title).lineLimit(1)
            Image(systemName: "chevron.down").font(.caption2)
        }
        .padding(.horizontal, 10)
        .frame(minWidth: 78, minHeight: 40)
        .background(.thinMaterial, in: Capsule())
        .contentShape(Capsule())
    }
}

private struct UnifiedRolePickerSheet: View {
    let selectedRole: UnifiedDeviceRole
    let onSelect: (UnifiedDeviceRole) -> Void
    let onCancel: () -> Void

    var body: some View {
        NavigationStack {
            List {
                ForEach(UnifiedDeviceRole.allCases) { role in
                    Button {
                        onSelect(role)
                    } label: {
                        HStack(spacing: 14) {
                            Image(systemName: role.systemImage)
                                .frame(width: 28)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(role.title)
                                    .font(.body.weight(.semibold))
                                Text(role.shortTitle)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if role == selectedRole {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                            }
                        }
                        .contentShape(Rectangle())
                        .padding(.vertical, 6)
                    }
                    .buttonStyle(.plain)
                }
            }
            .navigationTitle("اختيار دور الجهاز")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("إلغاء", action: onCancel)
                }
            }
        }
    }
}

private struct UnifiedModePickerSheet: View {
    let selectedMode: UnifiedScanMode
    let onSelect: (UnifiedScanMode) -> Void
    let onCancel: () -> Void

    var body: some View {
        NavigationStack {
            List {
                ForEach(UnifiedScanMode.allCases) { mode in
                    Button {
                        onSelect(mode)
                    } label: {
                        HStack(spacing: 14) {
                            Image(systemName: mode.systemImage)
                                .frame(width: 28)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(mode.title)
                                    .font(.body.weight(.semibold))
                                if !mode.implementedInCurrentCaptureCore {
                                    Text("قابل للتجربة — يسجل Pose وDepth، وبناء 3D النهائي تحت التطوير")
                                        .font(.caption)
                                        .foregroundStyle(.orange)
                                }
                            }
                            Spacer()
                            if mode == selectedMode {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                            }
                        }
                        .contentShape(Rectangle())
                        .padding(.vertical, 6)
                    }
                    .buttonStyle(.plain)
                }
            }
            .navigationTitle("اختيار وضع المسح")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("إلغاء", action: onCancel)
                }
            }
        }
    }
}
