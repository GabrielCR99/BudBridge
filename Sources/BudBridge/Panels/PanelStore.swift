import Foundation
import OSLog
import QCYKit

/// One entry of QCY's product list.
struct ModelInfo: Sendable, Decodable, Identifiable {
    var id: UInt16
    var name: String
    var kind: String
    var supported: Bool
    var note: String?

    /// The catalog stores its notes in English; these are the only three.
    var localizedNote: String? {
        switch note {
        case "Uses the JieLi connection protocol": String(localized: "Uses the JieLi connection protocol")
        case "QCY publishes no settings for this model": String(localized: "QCY publishes no settings for this model")
        case "A few of this model's features aren't available yet": String(localized: "A few of this model's features aren't available yet")
        default: note
        }
    }
}

/// Model catalog and settings lists ("control panels").
///
/// Lookup order mirrors the Android app: a copy fetched from QCY for this firmware (cached on disk),
/// else the snapshot bundled with the app. Lists come in the app's language: QCY serves Portuguese
/// translations for `lang: pt`, and English otherwise.
final class PanelStore {
    /// `"pt"` when BudBridge runs in Portuguese, else `"en"`.
    let language = Bundle.main.preferredLocalizations.first?.hasPrefix("pt") == true ? "pt" : "en"

    private let log = Logger(subsystem: "io.github.gabrielcr99.BudBridge", category: "panels")
    private let models: [UInt16: ModelInfo]

    init() {
        let url = Bundle.main.url(forResource: "catalog", withExtension: "json", subdirectory: "Panels")
        let list = url.flatMap { try? JSONDecoder().decode([ModelInfo].self, from: Data(contentsOf: $0)) } ?? []
        models = Dictionary(list.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
    }

    func model(_ vendorID: UInt16) -> ModelInfo? { models[vendorID] }

    func isSupported(_ vendorID: UInt16) -> Bool {
        models[vendorID]?.supported == true && !ModelFamily(vendorID).isJieLi
    }

    /// Cached or bundled panel; no network.
    func panel(for vendorID: UInt16) -> ControlPanel? {
        // QCY has no Portuguese list for a few models; those fall back to English.
        var sources: [(URL?, String)] = [(cacheURL(vendorID), language)]
        if language == "pt" {
            sources.append((Bundle.main.url(forResource: "\(vendorID)", withExtension: "json", subdirectory: "Panels/pt"), "pt"))
        }
        sources.append((Bundle.main.url(forResource: "\(vendorID)", withExtension: "json", subdirectory: "Panels"), "en"))
        for (url, language) in sources {
            if let url, let data = try? Data(contentsOf: url), let panel = try? ControlPanel(json: data, language: language) {
                return panel
            }
        }
        return nil
    }

    /// Fetches the panel QCY serves for this firmware and caches it. Returns `nil` on any failure.
    func refresh(vendorID: UInt16, firmware: String) async -> ControlPanel? {
        var request = URLRequest(url: URL(string: "https://api.watch.qcy.com/product/findControlPanels")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue(language, forHTTPHeaderField: "lang")
        request.setValue(language == "pt" ? "BR" : "US", forHTTPHeaderField: "country")
        request.setValue("android", forHTTPHeaderField: "sys_")
        request.setValue("4.0.7_717", forHTTPHeaderField: "app_version")
        request.httpBody = Data("modelId=\(vendorID)&firmwareVersion=\(firmware)".utf8)
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            let panel = try ControlPanel(json: data, language: language)
            if let url = cacheURL(vendorID) {
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try data.write(to: url, options: .atomic)
            }
            log.info("refreshed \(self.language, privacy: .public) panel for model \(vendorID) firmware \(firmware, privacy: .public)")
            return panel
        } catch {
            log.notice("panel refresh failed for model \(vendorID): \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private func cacheURL(_ vendorID: UInt16) -> URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appending(path: "BudBridge/Panels/\(language)/\(vendorID).json")
    }
}
