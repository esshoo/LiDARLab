import SwiftUI

struct LiveCameraSideButton: View {
    let systemImage: String
    let accessibilityLabel: String
    var isSelected = false
    var tint: Color? = nil
    var isEnabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .semibold))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(isEnabled ? (tint ?? (isSelected ? .cyan : .primary)) : .secondary)
        .background(.ultraThinMaterial, in: Circle())
        .overlay {
            Circle()
                .stroke(isSelected ? Color.cyan.opacity(0.85) : Color.primary.opacity(0.08), lineWidth: isSelected ? 1.4 : 1)
        }
        .shadow(radius: 6, y: 2)
        .disabled(!isEnabled)
        .accessibilityLabel(accessibilityLabel)
    }
}

struct LiveCameraSideRail<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 10) {
            content
        }
        .padding(7)
        .background(.thinMaterial, in: Capsule())
        .overlay {
            Capsule().stroke(Color.primary.opacity(0.06), lineWidth: 1)
        }
    }
}

struct LiveCameraFloatingPanel<Content: View>: View {
    let title: String
    let systemImage: String
    let onClose: () -> Void
    let content: Content

    init(
        title: String,
        systemImage: String,
        onClose: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.systemImage = systemImage
        self.onClose = onClose
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Label(title, systemImage: systemImage)
                    .font(.headline)
                Spacer(minLength: 8)
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.caption.bold())
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.plain)
                .background(.thinMaterial, in: Circle())
                .accessibilityLabel("إغلاق")
            }

            Divider()
            content
        }
        .padding(14)
        .frame(maxWidth: 330, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.primary.opacity(0.07), lineWidth: 1)
        }
        .shadow(radius: 14, y: 6)
    }
}

struct LiveCameraStatusBadge: View {
    let title: String
    var detail: String? = nil
    var systemImage = "viewfinder"
    var accent: Color = .cyan

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .foregroundStyle(accent)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.caption.bold())
                    .lineLimit(1)
                if let detail, !detail.isEmpty {
                    Text(detail)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay { Capsule().stroke(Color.primary.opacity(0.06), lineWidth: 1) }
    }
}

struct LiveCameraBottomBar<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        HStack(spacing: 10) {
            content
        }
        .padding(10)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay { Capsule().stroke(Color.primary.opacity(0.06), lineWidth: 1) }
        .shadow(radius: 8, y: 3)
    }
}
