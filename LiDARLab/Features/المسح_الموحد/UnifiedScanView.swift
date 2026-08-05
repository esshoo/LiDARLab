import SwiftUI

struct UnifiedScanView: View {
    @StateObject private var model = UnifiedScanViewModel()
    @State private var showSettings = false
    @State private var showStats = false
    @State private var showGrid = true
    @State private var showPath = true
    @State private var showCoverage = true
    @State private var showDevice = true

    var body: some View {
        ZStack {
            if model.needsARSession {
                UnifiedARViewContainer(model: model)
                    .frame(width: 1, height: 1)
                    .opacity(0.001)
                    .allowsHitTesting(false)
            }

            VStack(spacing: 10) {
                compactToolbar

                UnifiedLivePreviewView(
                    path: model.path,
                    sweeps: model.coverageSweeps,
                    currentPosition: model.currentPosition,
                    currentQuaternion: model.currentQuaternion,
                    showGrid: showGrid,
                    showPath: showPath,
                    showCoverage: showCoverage,
                    showDevice: showDevice
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                statusStrip
                controlBar
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 8)
        }
        .navigationTitle("المسح الموحد")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .sheet(isPresented: $showSettings) {
            UnifiedScanSettingsView(
                model: model,
                showGrid: $showGrid,
                showPath: $showPath,
                showCoverage: $showCoverage,
                showDevice: $showDevice
            )
        }
        .sheet(isPresented: $showStats) {
            UnifiedScanStatsView(model: model)
                .presentationDetents([.medium, .large])
        }
        .alert(item: $model.capabilityWarning) { warning in
            Alert(
                title: Text(warning.title),
                message: Text(warning.message),
                primaryButton: .default(Text(warning.continueTitle)) {
                    model.continueAfterCapabilityWarning()
                },
                secondaryButton: .cancel(Text("إلغاء")) {
                    model.cancelCapabilityWarning()
                }
            )
        }
        .onAppear { model.applyRoleChange() }
        .onChange(of: model.role) { _, _ in model.applyRoleChange() }
        .onDisappear { model.shutdown() }
    }

    private var compactToolbar: some View {
        HStack(spacing: 8) {
            Menu {
                ForEach(UnifiedDeviceRole.allCases) { role in
                    Button {
                        model.role = role
                    } label: {
                        Label(role.title, systemImage: role.systemImage)
                    }
                }
            } label: {
                CompactMenuLabel(title: model.role.shortTitle, image: model.role.systemImage)
            }
            .disabled(model.settingsLocked)

            Menu {
                ForEach(UnifiedScanMode.allCases) { mode in
                    Button {
                        model.scanMode = mode
                    } label: {
                        HStack {
                            Label(mode.title, systemImage: mode.systemImage)
                            if !mode.implementedInCurrentCaptureCore { Text("— تجريبي") }
                        }
                    }
                }
            } label: {
                CompactMenuLabel(title: model.scanMode.title, image: model.scanMode.systemImage)
            }
            .disabled(model.settingsLocked)

            Spacer(minLength: 0)

            Button { showStats = true } label: {
                Image(systemName: "chart.bar.xaxis")
                    .frame(width: 34, height: 34)
                    .background(.thinMaterial, in: Circle())
            }
            .accessibilityLabel("الإحصائيات")

            Button { showSettings = true } label: {
                Image(systemName: "gearshape")
                    .frame(width: 34, height: 34)
                    .background(.thinMaterial, in: Circle())
            }
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
            } else if model.role == .receiver, model.connectionState != .listening, model.connectionState != .connected {
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

private struct CompactMenuLabel: View {
    let title: String
    let image: String

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: image)
            Text(title).lineLimit(1)
            Image(systemName: "chevron.down").font(.caption2)
        }
        .padding(.horizontal, 9)
        .frame(height: 34)
        .background(.thinMaterial, in: Capsule())
    }
}
