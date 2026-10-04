import SwiftUI
import UIKit

private struct Color3DKeepAwakeModifier: ViewModifier {
    @AppStorage(Color3DScanSettings.Key.keepScreenAwake) private var keepScreenAwake = true
    let active: Bool

    @State private var isHoldingIdleTimer = false
    @State private var previousIdleTimerDisabled = false

    func body(content: Content) -> some View {
        content
            .onAppear { syncIdleTimer() }
            .onChange(of: active) { _ in syncIdleTimer() }
            .onChange(of: keepScreenAwake) { _ in syncIdleTimer() }
            .onDisappear { releaseIdleTimer() }
    }

    private func syncIdleTimer() {
        let shouldHold = active && keepScreenAwake
        if shouldHold && !isHoldingIdleTimer {
            previousIdleTimerDisabled = UIApplication.shared.isIdleTimerDisabled
            UIApplication.shared.isIdleTimerDisabled = true
            isHoldingIdleTimer = true
        } else if !shouldHold && isHoldingIdleTimer {
            releaseIdleTimer()
        }
    }

    private func releaseIdleTimer() {
        guard isHoldingIdleTimer else { return }
        UIApplication.shared.isIdleTimerDisabled = previousIdleTimerDisabled
        isHoldingIdleTimer = false
    }
}

extension View {
    func keepScreenAwakeDuringColor3DScan(_ active: Bool) -> some View {
        modifier(Color3DKeepAwakeModifier(active: active))
    }
}
