import SwiftUI

extension View {
    /// Shows the view as a loading placeholder: text and images become grey shapes that pulse gently,
    /// and controls are disabled. Used while the earbuds connect, so the layout doesn't jump when the
    /// real values arrive.
    func skeleton(_ isActive: Bool = true) -> some View {
        modifier(Skeleton(isActive: isActive))
    }
}

private struct Skeleton: ViewModifier {
    let isActive: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isDimmed = false

    func body(content: Content) -> some View {
        if isActive {
            content
                .redacted(reason: .placeholder)
                .disabled(true)
                // Only the opacity animates: a repeating animation on the whole view would also animate
                // its layout, making it drift as the window settles.
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.9).repeatForever()) {
                    $0.opacity(isDimmed ? 0.45 : 0.9)
                }
                .onAppear { isDimmed = !reduceMotion }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text("Loading"))
        } else {
            content
        }
    }
}
