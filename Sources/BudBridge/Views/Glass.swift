import SwiftUI

// Liquid Glass on macOS 26 and later; the closest standard look on older systems.
// Also SF Symbols that only exist on newer systems (the compiler doesn't check symbol names).

enum Symbols {
    /// `earbud.left` / `earbud.right` arrived in macOS 26.
    static var leftEarbud: String { if #available(macOS 26, *) { "earbud.left" } else { "earbuds" } }
    static var rightEarbud: String { if #available(macOS 26, *) { "earbud.right" } else { "earbuds" } }
    /// `headphones.slash` arrived in macOS 15.
    static var headphonesOff: String { if #available(macOS 15, *) { "headphones.slash" } else { "headphones" } }
}

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
