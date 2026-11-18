import SwiftUI

/// A restrained halo follows the actual face silhouette, rather than adding a shape underneath.
struct FloatingAvatarShadow: ViewModifier {
    let accent: Color
    var enabled = true
    func body(content: Content) -> some View {
        content.compositingGroup()
            .shadow(color: accent.opacity(enabled ? 0.22 : 0), radius: 8, x: 0, y: 2)
    }
}
