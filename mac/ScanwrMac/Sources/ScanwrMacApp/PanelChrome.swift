import SwiftUI

struct PanelChrome: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            )
    }
}

extension View {
    func panelChrome() -> some View {
        modifier(PanelChrome())
    }
}

