import Foundation

func int(_ any: Any?) -> Int? {
    switch any {
    case let v as Int: v
    case let v as Double: Int(v)
    case let v as NSNumber: v.intValue
    case let v as String: Int(v.trimmingCharacters(in: .whitespaces))
    default: nil
    }
}

func string(_ any: Any?) -> String? {
    switch any {
    case let v as String: v
    case let v as NSNumber: v.stringValue
    default: nil
    }
}

/// `"31,62,1k,2k"` or `"0.7,1,1.5"` → numbers (`k` = ×1000).
func numbers(_ any: Any?) -> [Double] {
    guard let text = string(any), !text.isEmpty else { return [] }
    return text.split(separator: ",").compactMap { part in
        let s = part.trimmingCharacters(in: .whitespaces).lowercased()
        return s.hasSuffix("k") ? Double(s.dropLast()).map { $0 * 1000 } : Double(s)
    }
}

func hexBytes(_ any: Any?) -> [UInt8]? {
    guard let text = string(any), !text.isEmpty else { return nil }
    return [UInt8](hex: text)
}

/// `"00001001-0000-1000-8000-00805f9b34fb"` → `"1001"`.
func shortUUID(_ uuid: String?) -> String? {
    guard let uuid, uuid.count >= 8 else { return nil }
    return String(uuid.uppercased().dropFirst(4).prefix(4))
}

/// Display text from the panel, tidied (see `PanelText.tidy`).
func text(_ any: Any?) -> String? {
    string(any).map(PanelText.tidy)
}

/// Panel labels sometimes carry a second line; keep the first.
func cleanLabel(_ s: String) -> String {
    (s.split(separator: "\n").first.map(String.init) ?? s).trimmingCharacters(in: .whitespaces)
}

/// The settings lists are typed by hand and full of small slips: "5Minute", "Keep touching1.5S",
/// "Don‘t shut down", stray line breaks. Labels are tidied for display only; payloads are read
/// separately, so the bytes sent never change. Units follow the list's language.
public enum PanelText {
    /// Language of the settings list being parsed (`"en"` or `"pt"`), set by `ControlPanel(json:language:)`.
    @TaskLocal public static var language = "en"

    /// Obvious mistranslations in QCY's Portuguese lists.
    static let portugueseFixes = ["Prensa longa": "Toque longo"]

    public static func tidy(_ raw: String) -> String {
        let portuguese = language == "pt"
        var s = raw.replacing("‘", with: "’").replacing("´", with: "’")
        if portuguese {
            for (wrong, right) in portugueseFixes { s = s.replacing(wrong, with: right) }
        }
        // A duplicated entry in one panel ends in a stray "1" ("10Minute1", "Don‘t shut down1").
        s = s.replacing(/([A-Za-z])1$/) { "\($0.output.1)" }
        // "press1.5S" → "press 1.5S"
        s = s.replacing(/(\p{Ll})(\d)/) { "\($0.output.1) \($0.output.2)" }
        // "5Minute" → "5 minutes", "5Minuto" → "5 minutos"
        s = s.replacing(/(\d+)\s*[Mm]inut(?:es?|os?)\b/) { match in
            let n = match.output.1
            return switch (portuguese, n == "1") {
            case (true, true): "1 minuto"
            case (true, false): "\(n) minutos"
            case (false, true): "1 minute"
            case (false, false): "\(n) minutes"
            }
        }
        // "1.5S" → "1.5 seconds" / "1,5 segundos"
        s = s.replacing(/(\d+)(?:\.(\d+))?\s*[Ss]\b/) { match in
            let number = match.output.2.map { "\(match.output.1)\(portuguese ? "," : ".")\($0)" } ?? "\(match.output.1)"
            return "\(number) \(portuguese ? "segundos" : "seconds")"
        }
        // Spaces around line breaks, doubled spaces. Breaks stay: labels keep their first line.
        s = s.replacing(/[ \t]*\n[ \t]*/, with: "\n").replacing(/[ ]{2,}/, with: " ")
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
