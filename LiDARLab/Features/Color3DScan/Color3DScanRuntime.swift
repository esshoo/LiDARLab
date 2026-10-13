import SwiftUI

extension View {
    func keepScreenAwakeDuringColor3DScan(_ active: Bool) -> some View {
        keepScreenAwakeForLiveTool(id: "color3d.scan", active: active)
    }
}
