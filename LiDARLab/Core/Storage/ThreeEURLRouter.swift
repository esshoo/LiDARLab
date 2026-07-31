import Foundation
import QuickLook
import SwiftUI

struct ThreeEOpenTarget: Identifiable {
    let id = UUID()
    let relativePath: String
    let url: URL
    let isDirectory: Bool
}

final class ThreeEURLRouter: ObservableObject {
    static let shared = ThreeEURLRouter()

    @Published var pendingTarget: ThreeEOpenTarget?
    @Published var errorMessage: String?
    @Published private(set) var homeRequestID = UUID()

    private init() {}

    func handle(_ incomingURL: URL, storage: LiDARLabStorage) {
        guard incomingURL.scheme?.lowercased() == ThreeEStorageConstants.urlScheme,
              incomingURL.host?.lowercased() == "open" else {
            errorMessage = "تم رفض رابط غير تابع لتطبيق 3ELiDAR."
            return
        }

        homeRequestID = UUID()
        pendingTarget = nil

        guard let components = URLComponents(url: incomingURL, resolvingAgainstBaseURL: false),
              let requestedPath = components.queryItems?.first(where: { $0.name == "path" })?.value,
              !requestedPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }

        do {
            let targetURL = try storage.urlForValidatedRelativePath(requestedPath)
            guard FileManager.default.fileExists(atPath: targetURL.path) else {
                errorMessage = "المسار غير موجود داخل مجلد 3E: \(requestedPath)"
                return
            }
            let values = try targetURL.resourceValues(forKeys: [.isDirectoryKey])
            pendingTarget = ThreeEOpenTarget(
                relativePath: requestedPath,
                url: targetURL,
                isDirectory: values.isDirectory == true
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func clearError() {
        errorMessage = nil
    }
}

struct ThreeEPathOpenView: View {
    let target: ThreeEOpenTarget
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if target.isDirectory {
                    directoryContents
                } else {
                    QuickLookPreview(url: target.url)
                        .ignoresSafeArea(edges: .bottom)
                }
            }
            .navigationTitle(target.url.lastPathComponent)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("إغلاق") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    ShareLink(item: target.url) {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
            }
        }
    }

    private var directoryContents: some View {
        let children = (try? FileManager.default.contentsOfDirectory(
            at: target.url,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ))?.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending } ?? []

        return List {
            Section("المسار النسبي") {
                Text(target.relativePath)
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
            }
            Section("المحتويات") {
                if children.isEmpty {
                    ContentUnavailableView("المجلد فارغ", systemImage: "folder")
                } else {
                    ForEach(children, id: \.self) { child in
                        HStack {
                            Image(systemName: ((try? child.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true) ? "folder.fill" : "doc.fill")
                                .foregroundStyle(.cyan)
                            Text(child.lastPathComponent)
                            Spacer()
                        }
                    }
                }
            }
        }
    }
}

private struct QuickLookPreview: UIViewControllerRepresentable {
    let url: URL

    func makeCoordinator() -> Coordinator {
        Coordinator(url: url)
    }

    func makeUIViewController(context: Context) -> QLPreviewController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: QLPreviewController, context: Context) {
        context.coordinator.url = url
        uiViewController.reloadData()
    }

    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        var url: URL

        init(url: URL) {
            self.url = url
        }

        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }

        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
            url as NSURL
        }
    }
}
