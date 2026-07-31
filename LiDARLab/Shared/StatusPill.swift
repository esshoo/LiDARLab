import SwiftUI

struct StatusPill: View {
    let text: String
    let kind: Kind

    enum Kind {
        case ready
        case comingSoon
        case unsupported

        var color: Color {
            switch self {
            case .ready: .green
            case .comingSoon: .orange
            case .unsupported: .red
            }
        }
    }

    var body: some View {
        Text(text)
            .font(.caption.bold())
            .foregroundStyle(kind.color)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(kind.color.opacity(0.14), in: Capsule())
            .overlay {
                Capsule().stroke(kind.color.opacity(0.28), lineWidth: 1)
            }
    }
}
