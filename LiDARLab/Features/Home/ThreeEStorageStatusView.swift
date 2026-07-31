import SwiftUI

struct ThreeEStorageStatusView: View {
    @ObservedObject var storage: LiDARLabStorage
    let chooseFolder: () -> Void

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                statusIcon
                statusText
                Spacer(minLength: 8)
                actionButton
            }

            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    statusIcon
                    statusText
                }
                actionButton
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(storage.isSharedFolderConnected ? Color.green.opacity(0.28) : Color.orange.opacity(0.28))
        }
    }

    private var statusIcon: some View {
        Image(systemName: storage.isSharedFolderConnected ? "folder.badge.checkmark" : "folder.badge.plus")
            .font(.title2)
            .foregroundStyle(storage.isSharedFolderConnected ? .green : .orange)
            .frame(width: 34)
    }

    private var statusText: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("تخزين مجموعة 3E")
                .font(.subheadline.weight(.semibold))
            Text(storage.source.title)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            Text(storage.statusMessage)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var actionButton: some View {
        Button(action: chooseFolder) {
            Label(
                storage.isSharedFolderConnected ? "تغيير مجلد 3E" : "اختيار مجلد 3E",
                systemImage: "folder"
            )
        }
        .buttonStyle(.borderedProminent)
        .tint(.cyan)
        .disabled(storage.source == .appGroup)
    }
}
