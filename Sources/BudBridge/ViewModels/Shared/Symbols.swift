import Foundation

/// SF Symbols that only exist on newer systems, with fallbacks (the compiler doesn't check symbol names).
enum Symbols {
    /// `earbud.left` / `earbud.right` arrived in macOS 26.
    static var leftEarbud: String { if #available(macOS 26, *) { "earbud.left" } else { "earbuds" } }
    static var rightEarbud: String { if #available(macOS 26, *) { "earbud.right" } else { "earbuds" } }
    /// `headphones.slash` arrived in macOS 15.
    static var headphonesOff: String { if #available(macOS 15, *) { "headphones.slash" } else { "headphones" } }
}
