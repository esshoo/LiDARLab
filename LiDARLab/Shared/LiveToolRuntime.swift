import SwiftUI
import UIKit

@MainActor
enum LiveToolRuntimeSettings {
    static let keepScreenAwakeKey = "liveTools.keepScreenAwake"

    static var keepScreenAwake: Bool {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: keepScreenAwakeKey) == nil {
            let legacyKey = Color3DScanSettings.Key.keepScreenAwake
            if defaults.object(forKey: legacyKey) != nil {
                defaults.set(defaults.bool(forKey: legacyKey), forKey: keepScreenAwakeKey)
            } else {
                defaults.set(true, forKey: keepScreenAwakeKey)
            }
        }
        return defaults.bool(forKey: keepScreenAwakeKey)
    }
}

@MainActor
final class LiveToolAwakeManager {
    static let shared = LiveToolAwakeManager()

    private var holders: Set<String> = []
    private var previousIdleTimerDisabled = false
    private var ownsIdleTimer = false
    private var observers: [NSObjectProtocol] = []

    private init() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.reapply() }
        })
        observers.append(center.addObserver(
            forName: UIApplication.willResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.reapply() }
        })
    }

    deinit {
        let center = NotificationCenter.default
        observers.forEach(center.removeObserver)
    }

    func setActive(_ active: Bool, id: String, enabled: Bool = true) {
        if active && enabled {
            acquire(id: id)
        } else {
            release(id: id)
        }
    }

    func acquire(id: String) {
        guard !holders.contains(id) else {
            reapply()
            return
        }
        if holders.isEmpty {
            previousIdleTimerDisabled = UIApplication.shared.isIdleTimerDisabled
        }
        holders.insert(id)
        reapply()
    }

    func release(id: String) {
        guard holders.remove(id) != nil else { return }
        if holders.isEmpty {
            if ownsIdleTimer {
                UIApplication.shared.isIdleTimerDisabled = previousIdleTimerDisabled
            }
            ownsIdleTimer = false
        } else {
            reapply()
        }
    }

    private func reapply() {
        guard !holders.isEmpty else { return }
        UIApplication.shared.isIdleTimerDisabled = true
        ownsIdleTimer = true
    }
}

private struct LiveToolAwakeModifier: ViewModifier {
    let id: String
    let active: Bool
    @AppStorage(LiveToolRuntimeSettings.keepScreenAwakeKey) private var keepAwake = true

    func body(content: Content) -> some View {
        content
            .onAppear { sync() }
            .onChange(of: active) { _, _ in sync() }
            .onChange(of: keepAwake) { _, _ in sync() }
            .onDisappear {
                LiveToolAwakeManager.shared.release(id: id)
            }
    }

    @MainActor
    private func sync() {
        LiveToolAwakeManager.shared.setActive(active, id: id, enabled: keepAwake)
    }
}

extension View {
    func keepScreenAwakeForLiveTool(id: String, active: Bool = true) -> some View {
        modifier(LiveToolAwakeModifier(id: id, active: active))
    }
}
