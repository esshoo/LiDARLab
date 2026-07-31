import SwiftUI

struct CrosshairView: View {
    var body: some View {
        ZStack {
            Circle()
                .stroke(.white.opacity(0.95), lineWidth: 2)
                .frame(width: 28, height: 28)
            Rectangle()
                .fill(.white)
                .frame(width: 2, height: 42)
            Rectangle()
                .fill(.white)
                .frame(width: 42, height: 2)
            Circle()
                .fill(.cyan)
                .frame(width: 6, height: 6)
        }
        .shadow(color: .black.opacity(0.55), radius: 4)
        .accessibilityLabel("مركز القياس")
    }
}
