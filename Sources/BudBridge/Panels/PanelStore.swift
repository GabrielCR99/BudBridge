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
/// Like the Android app, BudBridge downloads each model's list from QCY when it first meets the
/// model, and caches it on disk. QCY's lists aren't redistributed with the app. Lists come in the
/// app's language: QCY serves Portuguese translations for `lang: pt`, and English otherwise.
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

    /// The cached list for this model, if it was downloaded before; no network.
    func panel(for vendorID: UInt16) -> ControlPanel? {
        for language in Set([language, "en"]).sorted(by: { first, _ in first == self.language }) {
            if let url = cacheURL(vendorID, language: language), let data = try? Data(contentsOf: url),
               let panel = try? ControlPanel(json: data, language: language) {
                return panel
            }
        }
        return nil
    }

    /// Downloads the list QCY serves for this firmware (the latest one when `nil`) and caches it.
    /// Returns `nil` on any failure; QCY has no Portuguese list for a few models, which then come in English.
    func refresh(vendorID: UInt16, firmware: String?) async -> ControlPanel? {
        if let panel = await download(vendorID: vendorID, firmware: firmware, language: language) { return panel }
        return language == "en" ? nil : await download(vendorID: vendorID, firmware: firmware, language: "en")
    }

    private func download(vendorID: UInt16, firmware: String?, language: String) async -> ControlPanel? {
        let firmware = firmware ?? "99.99.99"
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
            if let url = cacheURL(vendorID, language: language) {
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try data.write(to: url, options: .atomic)
            }
            log.info("downloaded \(language, privacy: .public) panel for model \(vendorID) firmware \(firmware, privacy: .public)")
            return panel
        } catch {
            log.notice("panel refresh failed for model \(vendorID): \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private func cacheURL(_ vendorID: UInt16, language: String) -> URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appending(path: "BudBridge/Panels/\(language)/\(vendorID).json")
    }
}
