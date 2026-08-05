import SwiftUI

struct UnifiedScanSettingsView: View {
    @ObservedObject var model: UnifiedScanViewModel
    @Binding var showGrid: Bool
    @Binding var showPath: Bool
    @Binding var showCoverage: Bool
    @Binding var showDevice: Bool
    @Environment(\.dismiss) private var dismiss
    @State private var section: Section = .connection

    private enum Section: String, CaseIterable, Identifiable {
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
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("قسم الإعدادات", selection: $section) {
                    ForEach(Section.allCases) { item in
                        Text(item.title).tag(item)
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)
                .padding(.vertical, 8)

                Form {
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
                ToolbarItem(placement: .confirmationAction) {
                    Button("تم") { dismiss() }
                }
            }
        }
        .interactiveDismissDisabled(model.settingsLocked)
    }

    @ViewBuilder
    private var connectionSettings: some View {
        Section("دور الجهاز") {
            Picker("الدور", selection: $model.role) {
                ForEach(UnifiedDeviceRole.allCases) { Text($0.title).tag($0) }
            }
            .disabled(model.settingsLocked)
            Picker("وضع المسح", selection: $model.scanMode) {
                ForEach(UnifiedScanMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .disabled(model.settingsLocked)
        }

        if model.role == .sender {
            Section("وجهة الإرسال") {
                Picker("نوع الاتصال", selection: $model.connectionKind) {
                    ForEach(UnifiedConnectionKind.allCases) { Text($0.title).tag($0) }
                }
                .disabled(model.settingsLocked || model.isConnected)

                TextField("IP أو اسم الجهاز", text: $model.serverIP)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.numbersAndPunctuation)
                    .disabled(model.settingsLocked || model.isConnected)

                if model.connectionKind == .windowsWebSocket {
                    TextField("منفذ Windows", text: $model.serverPort)
                        .keyboardType(.numberPad)
                        .disabled(model.settingsLocked || model.isConnected)
                } else {
                    Stepper("منفذ Apple المباشر: \(model.directPort)", value: $model.directPort, in: 1...65_535)
                        .disabled(model.settingsLocked || model.isConnected)
                    Picker("جهاز مكتشف", selection: $model.selectedReceiverID) {
                        Text("استخدام IP اليدوي").tag(String?.none)
                        ForEach(model.browser.receivers) { receiver in
                            Text(receiver.name).tag(Optional(receiver.id))
                        }
                    }
                    Button("إعادة البحث عن أجهزة Apple") { model.browser.start() }
                    Text(model.browser.statusText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } else if model.role == .receiver {
            Section("الاستقبال المباشر") {
                Stepper("المنفذ: \(model.directPort)", value: $model.directPort, in: 1...65_535)
                    .disabled(model.settingsLocked)
                Text("يُعلن الجهاز عن نفسه داخل الشبكة المحلية باسم 3ELiDAR عبر Bonjour.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var transferSettings: some View {
        Section("معدلات الإرسال") {
            Picker("موقع الجهاز", selection: $model.poseFPS) {
                ForEach(UnifiedScanViewModel.fpsChoices, id: \.self) { Text("\($0) FPS").tag($0) }
            }
            Picker("بيانات المسح", selection: $model.scanFPS) {
                ForEach(UnifiedScanViewModel.fpsChoices, id: \.self) { Text("\($0) FPS").tag($0) }
            }
            .disabled(model.scanMode == .poseOnly)
        }
        .disabled(model.settingsLocked)

        Section("Depth") {
            Picker("خطوة أخذ العينات", selection: $model.samplingStride) {
                ForEach(UnifiedScanViewModel.strideChoices, id: \.self) { Text("\($0)").tag($0) }
            }
            Toggle("إرسال Confidence", isOn: $model.sendConfidence)
            Picker("سياسة الحرارة", selection: $model.thermalPolicy) {
                ForEach(UnifiedThermalPolicy.allCases) { Text($0.title).tag($0) }
            }
            Text(model.estimatedTransferText)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .disabled(model.settingsLocked || model.scanMode == .poseOnly)

        Section {
            Text("لا يغير التطبيق هذه القيم تلقائيًا. أي تخفيف في البيانات يحدث فقط حسب الاختيار الظاهر هنا.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var previewSettings: some View {
        Section("الطبقات الخفيفة") {
            Toggle("شبكة المتر", isOn: $showGrid)
            Toggle("مسار الجهاز", isOn: $showPath)
            Toggle("تغطية المسح التقريبية", isOn: $showCoverage)
            Toggle("مكان واتجاه الجهاز", isOn: $showDevice)
        }
        Section("معدل وذاكرة المعاينة") {
            Picker("تحديث المعاينة", selection: $model.previewFPS) {
                ForEach(UnifiedScanViewModel.previewFPSChoices, id: \.self) { Text("\($0) FPS").tag($0) }
            }
            Stepper("حد نقاط المسار: \(model.previewPathLimit)", value: $model.previewPathLimit, in: 100...50_000, step: 100)
            Stepper("حد شرائح التغطية: \(model.previewSweepLimit)", value: $model.previewSweepLimit, in: 20...10_000, step: 20)
            Stepper("أشعة التغطية: \(model.previewHorizontalRays)", value: $model.previewHorizontalRays, in: 2...32)
        }
        .disabled(model.settingsLocked)
        Section("فلتر المعاينة فقط") {
            LabeledContent("أقل مسافة") {
                TextField("0.15", value: $model.previewMinimumDepth, format: .number.precision(.fractionLength(2)))
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
            }
            LabeledContent("أقصى مسافة") {
                TextField("5.0", value: $model.previewMaximumDepth, format: .number.precision(.fractionLength(2)))
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
            }
            Stepper("أقل Confidence: \(model.previewMinimumConfidence)", value: $model.previewMinimumConfidence, in: 0...2)
            Text("هذه القيم تخص الرسم الخفيف فقط ولا تحذف البيانات المسجلة.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .disabled(model.settingsLocked)
    }

    @ViewBuilder
    private var recordingSettings: some View {
        Section("حفظ الجلسة") {
            Toggle("حفظ نسخة محلية أثناء الإرسال", isOn: $model.saveLocalCopyWhenSending)
                .disabled(model.role != .sender || model.settingsLocked)
            Stepper("دفعة الكتابة: \(model.recorderFlushPackets) حزمة", value: $model.recorderFlushPackets, in: 1...1_000)
                .disabled(model.settingsLocked)
            Toggle("مزامنة التخزين عند كل دفعة", isOn: $model.recorderSynchronizeOnFlush)
                .disabled(model.settingsLocked)
            Text("إيقاف المزامنة المتكررة يقلل ضغط التخزين. عند إنهاء الجلسة تتم المزامنة النهائية دائمًا.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        Section("مكان الحفظ") {
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
        Section("نتيجة الفحص الاسترشادي") {
            ForEach(model.capabilitySummary, id: \.self) { Text($0) }
        }
        Section {
            Text("الفحص لا يقفل أي وضع. عند اختيار ميزة غير مؤكدة يظهر تحذير، ويمكن التجربة على أي حال ورؤية سبب النجاح أو الفشل الحقيقي.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
