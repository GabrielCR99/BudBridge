import AppKit

/// The standard About panel, with a short description, the project link and the trademark notice.
enum AboutPanel {
    static let repository = URL(string: "https://github.com/GabrielCR99/BudBridge")

    static func show() {
        NSApp.activate()
        NSApp.orderFrontStandardAboutPanel(options: [.credits: credits])
    }

    private static var credits: NSAttributedString {
        let centered = NSMutableParagraphStyle()
        centered.alignment = .center
        centered.paragraphSpacing = 6
        let body: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: centered,
        ]
        let note = body.merging([
            .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize - 1),
            .foregroundColor: NSColor.secondaryLabelColor,
        ]) { _, new in new }

        let text = NSMutableAttributedString()
        text.append(NSAttributedString(
            string: String(localized: "An unofficial macOS app for QCY earbuds: noise control, EQ, touch controls and more.") + "\n",
            attributes: body))
        if let repository {
            var link = body
            link[.link] = repository
            text.append(NSAttributedString(string: String(localized: "Source code on GitHub") + "\n", attributes: link))
        }
        text.append(NSAttributedString(
            string: String(localized: "Not affiliated with QCY. “QCY” and “MeloBuds” are trademarks of their owner."),
            attributes: note))
        return text
    }
}
