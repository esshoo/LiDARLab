import Foundation
import SwiftUI

struct UnifiedScanSettingsView: View {
    let model: UnifiedScanViewModel
    @ObservedObject private var browser: UnifiedAppleReceiverBrowser
    @Binding private var showGrid: Bool
    @Binding private var showPath: Bool
    @Binding private var showCoverage: Bool
    @Binding private var showCurrentRays: Bool
    @Binding private var showDevice: Bool
    @Environment(\.dismiss) private var dismiss
    @State private var section: SettingsTab = .connection
    @State private var draft: UnifiedScanSettingsDraft
    private let captureSettingsLocked: Bool

    init(
        model: UnifiedScanViewModel,
        showGrid: Binding<Bool>,
        showPath: Binding<Bool>,
        showCoverage: Binding<Bool>,
        showCurrentRays: Binding<Bool>,
        showDevice: Binding<Bool>
    ) {
        self.model = model
        _browser = ObservedObject(wrappedValue: model.browser)
        _showGrid = showGrid
        _showPath = showPath
        _showCoverage = showCoverage
        _showCurrentRays = showCurrentRays
        _showDevice = showDevice
        captureSettingsLocked = model.settingsLocked
        _draft = State(
            initialValue: UnifiedScanSettingsDraft(
                model: model,
                showGrid: showGrid.wrappedValue,
                showPath: showPath.wrappedValue,
                showCoverage: showCoverage.wrappedValue,
                showCurrentRays: showCurrentRays.wrappedValue,
                showDevice: showDevice.wrappedValue
            )
        )
    }

    private enum SettingsTab: String, CaseIterable, Identifiable {
        case connection
        case transfer
        case preview
        case recording
        case capability

        var id: String { rawValue }
        var title: String {
            switch self {
            case .connection: "الاتصال"
            case .transfer: "نقل البيانات"
            case .preview: "العرض"
            case .recording: "التسجيل"
            case .capability: "الإمكانيات"
            }
        }

        var image: String {
            switch self {
            case .connection: "antenna.radiowaves.left.and.right"
            case .transfer: "arrow.left.arrow.right"
            case .preview: "rectangle.on.rectangle"
            case .recording: "externaldrive"
            case .capability: "cpu"
            }
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("قسم الإعدادات", selection: $section) {
                    ForEach(SettingsTab.allCases) { item in
                        Label(item.title, systemImage: item.image).tag(item)
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)
                .padding(.vertical, 10)

                Form {
                    if captureSettingsLocked, section != .preview, section != .capability {
                        SwiftUI.Section {
                            Label(
                                "إعدادات الالتقاط مقفلة أثناء الجلسة. إعدادات العرض تظل متاحة.",
                                systemImage: "lock.fill"
                            )
                            .font(.caption)
                            .foregroundStyle(.orange)
                        }
                    }

                    switch section {
                    case .connection:
                        connectionSettings
                    case .transfer:
                        transferSettings
                    case .preview:
                        previewSettings
                    case .recording:
                        recordingSettings
                    case .capability:
                        capabilitySettings
                    }
                }
            }
            .navigationTitle("إعدادات المسح الموحد")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("إلغاء") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("تطبيق") { applyAndDismiss() }
                        .fontWeight(.bold)
                }
            }
            .safeAreaInset(edge: .bottom) {
                HStack(spacing: 12) {
                    Button("إلغاء") { dismiss() }
                        .buttonStyle(.bordered)
                        .frame(maxWidth: .infinity)
                    Button("تطبيق الإعدادات") { applyAndDismiss() }
                        .buttonStyle(.borderedProminent)
                        .frame(maxWidth: .infinity)
                }
                .padding(.horizontal)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial)
            }
        }
    }

    @ViewBuilder
    private var connectionSettings: some View {
        SwiftUI.Section("دور الجهاز") {
            Picker("الدور", selection: $draft.role) {
                ForEach(UnifiedDeviceRole.allCases) { Text($0.title).tag($0) }
            }
            Picker("وضع المسح", selection: $draft.scanMode) {
                ForEach(UnifiedScanMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
        }
        .disabled(captureSettingsLocked)

        if draft.role == .sender {
            SwiftUI.Section("وجهة الإرسال") {
                Picker("نوع الاتصال", selection: $draft.connectionKind) {
                    ForEach(UnifiedConnectionKind.allCases) { Text($0.title).tag($0) }
                }

                TextField("IP أو اسم الجهاز", text: $draft.serverIP)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.numbersAndPunctuation)

                if draft.connectionKind == .windowsWebSocket {
                    TextField("منفذ Windows", text: $draft.serverPort)
                        .keyboardType(.numberPad)
                } else {
                    Stepper("منفذ Apple المباشر: \(draft.directPort)", value: $draft.directPort, in: 1...65_535)
                    Picker("جهاز مكتشف", selection: $draft.selectedReceiverID) {
                        Text("استخدام IP اليدوي").tag(String?.none)
                        ForEach(browser.receivers) { receiver in
                            Text(receiver.name).tag(Optional(receiver.id))
                        }
                    }
                    Button("إعادة البحث عن أجهزة Apple") { browser.start() }
                    Text(browser.statusText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .disabled(captureSettingsLocked || model.isConnected)
        } else if draft.role == .receiver {
            SwiftUI.Section("الاستقبال المباشر") {
                Stepper("المنفذ: \(draft.directPort)", value: $draft.directPort, in: 1...65_535)
                Text("يعلن الجهاز عن نفسه داخل الشبكة المحلية عبر Bonjour.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .disabled(captureSettingsLocked)
        }
    }

    @ViewBuilder
    private var transferSettings: some View {
        SwiftUI.Section("معدلات الإرسال") {
            Picker("موقع الجهاز", selection: $draft.poseFPS) {
                ForEach(UnifiedScanViewModel.fpsChoices, id: \.self) { Text("\($0) FPS").tag($0) }
            }
            Picker("بيانات المسح", selection: $draft.scanFPS) {
                ForEach(UnifiedScanViewModel.fpsChoices, id: \.self) { Text("\($0) FPS").tag($0) }
            }
            .disabled(draft.scanMode == .poseOnly)
        }
        .disabled(captureSettingsLocked)

        SwiftUI.Section("Depth") {
            Picker("خطوة أخذ العينات", selection: $draft.samplingStride) {
                ForEach(UnifiedScanViewModel.strideChoices, id: \.self) { Text("\($0)").tag($0) }
            }
            Toggle("إرسال Confidence", isOn: $draft.sendConfidence)
            Picker("سياسة الحرارة", selection: $draft.thermalPolicy) {
                ForEach(UnifiedThermalPolicy.allCases) { Text($0.title).tag($0) }
            }
            Text(estimatedTransferText)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .disabled(captureSettingsLocked || draft.scanMode == .poseOnly)

        SwiftUI.Section {
            Text("لا يغير التطبيق هذه القيم تلقائيًا. البيانات المسجلة لا تختصر بسبب إعدادات العرض.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var previewSettings: some View {
        SwiftUI.Section("الطبقات") {
            Toggle("شبكة المتر", isOn: $draft.showGrid)
            Toggle("مسار الجهاز", isOn: $draft.showPath)
            Toggle("التغطية التراكمية", isOn: $draft.showCoverage)
            Toggle("أشعة اللحظة الحالية", isOn: $draft.showCurrentRays)
            Toggle("شكل الجهاز", isOn: $draft.showDevice)
        }

        SwiftUI.Section("طريقة عرض التغطية") {
            Picker("الأسلوب", selection: $draft.coveragePreviewStyle) {
                ForEach(UnifiedCoveragePreviewStyle.allCases) { style in
                    Text(style.title).tag(style)
                }
            }
            Picker("حجم خلية العرض", selection: $draft.previewCellSize) {
                Text("10 سم").tag(Float(0.10))
                Text("15 سم").tag(Float(0.15))
                Text("18 سم").tag(Float(0.18))
                Text("25 سم").tag(Float(0.25))
                Text("50 سم").tag(Float(0.50))
            }
            Text("الخلايا تراكمية طوال الجلسة ولا يوجد حذف زمني أو حد لعددها. هذا لا يغير Depth المسجلة.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .disabled(captureSettingsLocked)

        SwiftUI.Section("شكل المسار والجهاز") {
            Picker("المسار", selection: $draft.pathPreviewStyle) {
                ForEach(UnifiedPathPreviewStyle.allCases) { style in
                    Text(style.title).tag(style)
                }
            }
            Picker("الجهاز", selection: $draft.devicePreviewStyle) {
                ForEach(UnifiedDevicePreviewStyle.allCases) { style in
                    Text(style.title).tag(style)
                }
            }
        }

        SwiftUI.Section("معدل المعاينة") {
            Picker("تحديث المعاينة", selection: $draft.previewFPS) {
                ForEach(UnifiedScanViewModel.previewFPSChoices, id: \.self) { Text("\($0) FPS").tag($0) }
            }
            Stepper("أشعة اللحظة الحالية: \(draft.previewHorizontalRays)", value: $draft.previewHorizontalRays, in: 2...32)
            Text("لا توجد حدود لنقاط المسار أو تغطية الجلسة. لتقليل الذاكرة تستخدم التغطية خلايا مكانية فريدة بدل تخزين كل Polygon قديم.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .disabled(captureSettingsLocked)

        SwiftUI.Section("فلتر المعاينة فقط") {
            LabeledContent("أقل مسافة") {
                TextField("0.15", value: $draft.previewMinimumDepth, format: .number.precision(.fractionLength(2)))
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
            }
            LabeledContent("أقصى مسافة") {
                TextField("5.0", value: $draft.previewMaximumDepth, format: .number.precision(.fractionLength(2)))
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
            }
            Stepper("أقل Confidence: \(draft.previewMinimumConfidence)", value: $draft.previewMinimumConfidence, in: 0...2)
            Text("هذه القيم تخص الرسم الخفيف فقط. جميع الحزم الخام تستمر في الإرسال والحفظ دون حذف.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .disabled(captureSettingsLocked)
    }

    @ViewBuilder
    private var recordingSettings: some View {
        SwiftUI.Section("الشاشة والطاقة") {
            Toggle("إبقاء الشاشة مضيئة داخل شاشة المسح", isOn: $draft.keepScreenAwake)
            Text("عند تفعيل الخيار يمنع التطبيق القفل التلقائي أثناء فتح شاشة المسح. يعود مؤقت قفل الشاشة لطبيعته فور الخروج من الشاشة أو انتقال التطبيق إلى الخلفية.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }

        SwiftUI.Section("حفظ الجلسة") {
            Toggle("حفظ نسخة محلية أثناء الإرسال", isOn: $draft.saveLocalCopyWhenSending)
                .disabled(draft.role != .sender)
            Stepper("دفعة الكتابة: \(draft.recorderFlushPackets) حزمة", value: $draft.recorderFlushPackets, in: 1...1_000)
            Toggle("مزامنة التخزين عند كل دفعة", isOn: $draft.recorderSynchronizeOnFlush)
            Text("التسجيل Append-only إلى القرص. لا يُحذف Frame بسبب طريقة العرض أو سعة Preview.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .disabled(captureSettingsLocked)

        SwiftUI.Section("مكان الحفظ") {
            Text("Documents/3ELiDAR/Sessions")
                .font(.caption.monospaced())
            if let directory = model.currentSessionDirectory {
                Text(directory.lastPathComponent)
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
            }
        }
    }

    @ViewBuilder
    private var capabilitySettings: some View {
        SwiftUI.Section("نتيجة الفحص الاسترشادي") {
            ForEach(model.capabilitySummary, id: \.self) { Text($0) }
        }
        SwiftUI.Section {
            Text("الفحص لا يقفل أي وضع. عند فشل ميزة تظهر الرسالة الفعلية، وتظل البيانات التي نجح التقاطها محفوظة.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var estimatedTransferText: String {
        let poseBytes = 72 * draft.poseFPS
        guard draft.scanMode != .poseOnly else {
            return String(format: "Pose فقط: نحو %.3f Mbps", Double(poseBytes * 8) / 1_000_000)
        }
        let samples = max(1, (256 / max(1, draft.samplingStride)) * (192 / max(1, draft.samplingStride)))
        let bytesPerSample = draft.sendConfidence ? 3 : 2
        let totalBytes = poseBytes + samples * bytesPerSample * draft.scanFPS
        return String(format: "تقدير النقل: %.3f Mbps", Double(totalBytes * 8) / 1_000_000)
    }

    private func applyAndDismiss() {
        model.role = draft.role
        model.scanMode = draft.scanMode
        model.connectionKind = draft.connectionKind
        model.serverIP = draft.serverIP
        model.serverPort = draft.serverPort
        model.directPort = draft.directPort
        model.selectedReceiverID = draft.selectedReceiverID
        model.poseFPS = draft.poseFPS
        model.scanFPS = draft.scanFPS
        model.samplingStride = draft.samplingStride
        model.sendConfidence = draft.sendConfidence
        model.thermalPolicy = draft.thermalPolicy
        model.saveLocalCopyWhenSending = draft.saveLocalCopyWhenSending
        model.previewFPS = draft.previewFPS
        model.coveragePreviewStyle = draft.coveragePreviewStyle
        model.pathPreviewStyle = draft.pathPreviewStyle
        model.devicePreviewStyle = draft.devicePreviewStyle
        model.previewCellSize = draft.previewCellSize
        model.previewHorizontalRays = draft.previewHorizontalRays
        model.previewMinimumDepth = draft.previewMinimumDepth
        model.previewMaximumDepth = draft.previewMaximumDepth
        model.previewMinimumConfidence = draft.previewMinimumConfidence
        model.recorderFlushPackets = draft.recorderFlushPackets
        model.recorderSynchronizeOnFlush = draft.recorderSynchronizeOnFlush
        model.keepScreenAwake = draft.keepScreenAwake

        showGrid = draft.showGrid
        showPath = draft.showPath
        showCoverage = draft.showCoverage
        showCurrentRays = draft.showCurrentRays
        showDevice = draft.showDevice

        dismiss()
    }
}

private struct UnifiedScanSettingsDraft {
    var role: UnifiedDeviceRole
    var scanMode: UnifiedScanMode
    var connectionKind: UnifiedConnectionKind
    var serverIP: String
    var serverPort: String
    var directPort: Int
    var selectedReceiverID: String?
    var poseFPS: Int
    var scanFPS: Int
    var samplingStride: Int
    var sendConfidence: Bool
    var thermalPolicy: UnifiedThermalPolicy
    var saveLocalCopyWhenSending: Bool
    var previewFPS: Int
    var coveragePreviewStyle: UnifiedCoveragePreviewStyle
    var pathPreviewStyle: UnifiedPathPreviewStyle
    var devicePreviewStyle: UnifiedDevicePreviewStyle
    var previewCellSize: Float
    var previewHorizontalRays: Int
    var previewMinimumDepth: Float
    var previewMaximumDepth: Float
    var previewMinimumConfidence: Int
    var recorderFlushPackets: Int
    var recorderSynchronizeOnFlush: Bool
    var keepScreenAwake: Bool
    var showGrid: Bool
    var showPath: Bool
    var showCoverage: Bool
    var showCurrentRays: Bool
    var showDevice: Bool

    @MainActor
    init(
        model: UnifiedScanViewModel,
        showGrid: Bool,
        showPath: Bool,
        showCoverage: Bool,
        showCurrentRays: Bool,
        showDevice: Bool
    ) {
        role = model.role
        scanMode = model.scanMode
        connectionKind = model.connectionKind
        serverIP = model.serverIP
        serverPort = model.serverPort
        directPort = model.directPort
        selectedReceiverID = model.selectedReceiverID
        poseFPS = model.poseFPS
        scanFPS = model.scanFPS
        samplingStride = model.samplingStride
        sendConfidence = model.sendConfidence
        thermalPolicy = model.thermalPolicy
        saveLocalCopyWhenSending = model.saveLocalCopyWhenSending
        previewFPS = model.previewFPS
        coveragePreviewStyle = model.coveragePreviewStyle
        pathPreviewStyle = model.pathPreviewStyle
        devicePreviewStyle = model.devicePreviewStyle
        previewCellSize = model.previewCellSize
        previewHorizontalRays = model.previewHorizontalRays
        previewMinimumDepth = model.previewMinimumDepth
        previewMaximumDepth = model.previewMaximumDepth
        previewMinimumConfidence = model.previewMinimumConfidence
        recorderFlushPackets = model.recorderFlushPackets
        recorderSynchronizeOnFlush = model.recorderSynchronizeOnFlush
        keepScreenAwake = model.keepScreenAwake
        self.showGrid = showGrid
        self.showPath = showPath
        self.showCoverage = showCoverage
        self.showCurrentRays = showCurrentRays
        self.showDevice = showDevice
    }
}
