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
}

/// Model catalog and settings lists ("control panels").
///
/// Lookup order mirrors the Android app: a copy fetched from QCY for this firmware (cached on disk),
/// else the snapshot bundled with the app.
final class PanelStore {
    private let log = Logger(subsystem: "dev.melobuds.control", category: "panels")
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
        for url in [cacheURL(vendorID), Bundle.main.url(forResource: "\(vendorID)", withExtension: "json", subdirectory: "Panels")] {
            if let url, let data = try? Data(contentsOf: url), let panel = try? ControlPanel(json: data) {
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
        request.setValue("en", forHTTPHeaderField: "lang")
        request.setValue("android", forHTTPHeaderField: "sys_")
        request.setValue("4.0.7_717", forHTTPHeaderField: "app_version")
        request.httpBody = Data("modelId=\(vendorID)&firmwareVersion=\(firmware)".utf8)
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            let panel = try ControlPanel(json: data)
            if let url = cacheURL(vendorID) {
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try data.write(to: url, options: .atomic)
            }
            log.info("refreshed panel for model \(vendorID) firmware \(firmware, privacy: .public)")
            return panel
        } catch {
            log.notice("panel refresh failed for model \(vendorID): \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private func cacheURL(_ vendorID: UInt16) -> URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appending(path: "MeloBudsControl/Panels/\(vendorID).json")
    }
}
