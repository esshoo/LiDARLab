import SwiftUI

struct ExportCenterView: View {
    private enum Filter: String, CaseIterable, Identifiable {
        case all
        case capture
        case room
        case recording
        case report

        var id: String { rawValue }
        var title: String {
            switch self {
            case .all: "الكل"
            case .capture: "الصور"
            case .room: "الغرف"
            case .recording: "الجلسات"
            case .report: "التقارير"
            }
        }
        var kind: ExportCenterItem.Kind? {
            switch self {
            case .all: nil
            case .capture: .capture
            case .room: .room
            case .recording: .recording
            case .report: .report
            }
        }
    }

    @StateObject private var model = ExportCenterViewModel()
    @State private var filter: Filter = .all
    @State private var searchText = ""
    @State private var shareItems: [Any] = []
    @State private var showingShareSheet = false
    @State private var itemToDelete: ExportCenterItem?
    @State private var itemToRename: ExportCenterItem?
    @State private var renameText = ""

    private var filteredItems: [ExportCenterItem] {
        model.items.filter { item in
            let matchesKind = filter.kind.map { item.kind == $0 } ?? true
            let matchesSearch = searchText.isEmpty
                || item.name.localizedCaseInsensitiveContains(searchText)
                || item.kind.title.localizedCaseInsensitiveContains(searchText)
            return matchesKind && matchesSearch
        }
    }

    var body: some View {
        List {
            Section {
                summaryPanel
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }

            Section {
                Picker("النوع", selection: $filter) {
                    ForEach(Filter.allCases) { item in Text(item.title).tag(item) }
                }
                .pickerStyle(.segmented)
            }

            Section("الملفات المحفوظة") {
                if filteredItems.isEmpty {
                    ContentUnavailableView(
                        searchText.isEmpty ? "لا توجد نتائج محفوظة" : "لا توجد نتائج مطابقة",
                        systemImage: "externaldrive.badge.questionmark",
                        description: Text(searchText.isEmpty ? "استخدم أدوات التطبيق لحفظ صور أو غرف أو جلسات." : "جرّب تغيير البحث أو الفلتر.")
                    )
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
                } else {
                    ForEach(filteredItems) { item in
                        exportRow(item)
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    itemToDelete = item
                                } label: {
                                    Label("حذف", systemImage: "trash")
                                }
                                Button {
                                    share(item)
                                } label: {
                                    Label("مشاركة", systemImage: "square.and.arrow.up")
                                }
                                .tint(.blue)
                            }
                            .contextMenu {
                                Button { share(item) } label: {
                                    Label("مشاركة الملفات", systemImage: "square.and.arrow.up")
                                }
                                Button {
                                    itemToRename = item
                                    renameText = item.name
                                } label: {
                                    Label("إعادة التسمية", systemImage: "pencil")
                                }
                                Divider()
                                Button(role: .destructive) { itemToDelete = item } label: {
                                    Label("حذف", systemImage: "trash")
                                }
                            }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("مركز التصدير")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "ابحث في الملفات")
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button { model.refresh() } label: {
                    Image(systemName: "arrow.clockwise")
                }
                Button { model.createCatalog() } label: {
                    Image(systemName: model.isWorking ? "hourglass" : "doc.badge.plus")
                }
                .disabled(model.isWorking)
            }
        }
        .refreshable { model.refresh() }
        .sheet(isPresented: $showingShareSheet) {
            ActivityView(items: shareItems)
        }
        .confirmationDialog("حذف العنصر نهائيًا؟", isPresented: Binding(
            get: { itemToDelete != nil },
            set: { if !$0 { itemToDelete = nil } }
        ), titleVisibility: .visible) {
            Button("حذف", role: .destructive) {
                if let itemToDelete { model.delete(itemToDelete) }
                itemToDelete = nil
            }
            Button("إلغاء", role: .cancel) { itemToDelete = nil }
        }
        .alert("إعادة التسمية", isPresented: Binding(
            get: { itemToRename != nil },
            set: { if !$0 { itemToRename = nil } }
        )) {
            TextField("الاسم الجديد", text: $renameText)
            Button("حفظ") {
                if let itemToRename { model.rename(itemToRename, to: renameText) }
                itemToRename = nil
            }
            Button("إلغاء", role: .cancel) { itemToRename = nil }
        } message: {
            Text("سيتم تغيير اسم المجلد أو الملف داخل مساحة التطبيق.")
        }
        .alert("تعذر إكمال العملية", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.clearError() } }
        )) {
            Button("حسنًا", role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "خطأ غير معروف")
        }
        .onChange(of: model.latestCatalogItems.count) { _, count in
            guard count > 0 else { return }
            shareItems = model.latestCatalogItems
            showingShareSheet = true
        }
    }

    private var summaryPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "externaldrive.fill")
                    .font(.title2)
                    .foregroundStyle(.cyan)
                VStack(alignment: .leading, spacing: 3) {
                    Text("مكتبة 3ELiDAR")
                        .font(.headline)
                    Text(model.statusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 105))], spacing: 9) {
                MetricChip(title: "العناصر", value: "\(model.items.count)", systemImage: "folder")
                MetricChip(title: "الملفات", value: "\(model.totalFiles)", systemImage: "doc.on.doc")
                MetricChip(title: "الحجم", value: ByteCountFormatter.string(fromByteCount: model.totalSize, countStyle: .file), systemImage: "internaldrive")
            }

            Button {
                model.createCatalog()
            } label: {
                Label(model.isWorking ? "جارٍ إنشاء الفهرس…" : "إنشاء فهرس JSON وCSV", systemImage: model.isWorking ? "hourglass" : "tablecells")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(model.isWorking)

            Text("عند ربط مجلد 3E تُحفظ النتائج داخل Apps/LiDARLab، وإلا تستخدم مساحة التطبيق الخاصة مؤقتًا.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private func exportRow(_ item: ExportCenterItem) -> some View {
        Button {
            share(item)
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(color(item.kind).opacity(0.14))
                        .frame(width: 44, height: 44)
                    Image(systemName: item.kind.systemImage)
                        .foregroundStyle(color(item.kind))
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.name)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(item.kind.title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("\(item.fileCount) ملف • \(ByteCountFormatter.string(fromByteCount: item.sizeBytes, countStyle: .file))")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 5) {
                    Image(systemName: "square.and.arrow.up")
                        .foregroundStyle(.secondary)
                    Text(item.modifiedAt, format: .dateTime.month().day().hour().minute())
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }

    private func share(_ item: ExportCenterItem) {
        shareItems = item.shareItems
        showingShareSheet = true
    }

    private func color(_ kind: ExportCenterItem.Kind) -> Color {
        switch kind {
        case .capture: .cyan
        case .room: .green
        case .recording: .red
        case .report: .orange
        }
    }
}
