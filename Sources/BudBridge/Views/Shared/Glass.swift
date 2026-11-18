import SwiftUI

// Liquid Glass on macOS 26 and later; the closest standard look on older systems.

extension View {
    /// A glass card surface (materials before macOS 26).
    @ViewBuilder
    func glassCard(cornerRadius: CGFloat) -> some View {
        if #available(macOS 26, *) {
            glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
        } else {
            background(.regularMaterial, in: .rect(cornerRadius: cornerRadius))
        }
    }

    /// The prominent action button style.
    @ViewBuilder
    func prominentButtonStyle() -> some View {
        if #available(macOS 26, *) {
            buttonStyle(.glassProminent)
        } else {
            buttonStyle(.borderedProminent)
        }
    }

    /// A toggle-like button: prominent when selected, plain glass otherwise.
    @ViewBuilder
    func selectableButtonStyle(isSelected: Bool) -> some View {
        if #available(macOS 26, *) {
            if isSelected { buttonStyle(.glassProminent) } else { buttonStyle(.glass) }
        } else {
            if isSelected { buttonStyle(.borderedProminent) } else { buttonStyle(.bordered) }
        }
    }
}

/// Groups glass shapes so they blend together on macOS 26; a plain container before that.
struct GlassGroup<Content: View>: View {
    var spacing: CGFloat
    @ViewBuilder var content: Content

    var body: some View {
        if #available(macOS 26, *) {
            GlassEffectContainer(spacing: spacing) { content }
        } else {
            content
        }
    }
}
