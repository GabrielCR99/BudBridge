import Foundation
import OSLog
import QCYKit

/// Model catalog and settings lists, as the store needs them.
protocol PanelProviding: AnyObject {
    func model(_ vendorID: UInt16) -> ModelInfo?
    func isSupported(_ vendorID: UInt16) -> Bool
    /// The cached list for this model, if it was downloaded before; no network.
    func panel(for vendorID: UInt16) -> ControlPanel?
    /// Downloads the list QCY serves for this firmware (the latest one when `nil`), or `nil` on any failure.
    func refresh(vendorID: UInt16, firmware: String?) async -> ControlPanel?
}

/// Model catalog and settings lists ("control panels").
///
/// Like the Android app, BudBridge downloads each model's list from QCY when it first meets the
/// model, and caches it on disk. QCY's lists aren't redistributed with the app. Lists come in the
/// app's language: QCY serves Portuguese translations for `lang: pt`, and English otherwise.
final class PanelRepository: PanelProviding {
    /// `"pt"` when BudBridge runs in Portuguese, else `"en"`.
    let language: String

    private let cacheDirectory: URL?
    private let session: URLSession
    private let models: [UInt16: ModelInfo]
    private let log = Logger(subsystem: "io.github.gabrielcr99.BudBridge", category: "panels")

    /// - Parameters:
    ///   - resources: Folder holding `Panels/catalog.json` (the app bundle's resources by default).
    ///   - cacheDirectory: Where downloaded lists are cached, per language.
    init(
        resources: URL? = Bundle.main.resourceURL,
        cacheDirectory: URL? = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?.appending(path: "BudBridge/Panels"),
        language: String = Bundle.main.preferredLocalizations.first?.hasPrefix("pt") == true ? "pt" : "en",
        session: URLSession = .shared
    ) {
        self.cacheDirectory = cacheDirectory
        self.language = language
        self.session = session
        let url = resources?.appending(path: "Panels/catalog.json")
        let list = url.flatMap { try? JSONDecoder().decode([ModelInfo].self, from: Data(contentsOf: $0)) } ?? []
        models = Dictionary(list.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    func model(_ vendorID: UInt16) -> ModelInfo? { models[vendorID] }

    func isSupported(_ vendorID: UInt16) -> Bool {
        models[vendorID]?.supported == true && !ModelFamily(vendorID).isJieLi
    }

    func panel(for vendorID: UInt16) -> ControlPanel? {
        // QCY has no Portuguese list for a few models; those are cached in English.
        for language in language == "en" ? ["en"] : [language, "en"] {
            if let url = cacheURL(vendorID, language: language), let data = try? Data(contentsOf: url),
               let panel = try? ControlPanel(json: data, language: language) {
                return panel
            }
        }
        return nil
    }

    func refresh(vendorID: UInt16, firmware: String?) async -> ControlPanel? {
        if let panel = await download(vendorID: vendorID, firmware: firmware, language: language) { return panel }
        return language == "en" ? nil : await download(vendorID: vendorID, firmware: firmware, language: "en")
    }

    // MARK: - Private

    private func download(vendorID: UInt16, firmware: String?, language: String) async -> ControlPanel? {
        guard let endpoint = URL(string: "https://api.watch.qcy.com/product/findControlPanels") else { return nil }
        let firmware = firmware ?? "99.99.99"
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue(language, forHTTPHeaderField: "lang")
        request.setValue(language == "pt" ? "BR" : "US", forHTTPHeaderField: "country")
        request.setValue("android", forHTTPHeaderField: "sys_")
        request.setValue("4.0.7_717", forHTTPHeaderField: "app_version")
        request.httpBody = Data("modelId=\(vendorID)&firmwareVersion=\(firmware)".utf8)
        do {
            let (data, _) = try await session.data(for: request)
            let panel = try ControlPanel(json: data, language: language)
            if let url = cacheURL(vendorID, language: language) {
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try data.write(to: url, options: .atomic)
            }
            log.info("downloaded \(language, privacy: .public) panel for model \(vendorID) firmware \(firmware, privacy: .public)")
            return panel
        } catch {
            log.notice("panel download failed for model \(vendorID): \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private func cacheURL(_ vendorID: UInt16, language: String) -> URL? {
        cacheDirectory?.appending(path: "\(language)/\(vendorID).json")
    }
}
