import Foundation
import Observation

/// Builds the services and view models, wires them together and owns navigation.
///
/// Views never create services or reach across screens; anything that spans screens
/// (like the audio link following the selected earbuds) is connected here.
@Observable
final class AppCoordinator {
    /// The main window's selected page, remembered across launches.
    var selectedPage: Page {
        didSet { defaults.set(selectedPage.rawValue, forKey: Keys.page) }
    }

    let root: RootViewModel
    let overview: OverviewViewModel
    let noiseControl: NoiseControlViewModel
    let sound: SoundViewModel
    let touchControls: TouchControlsViewModel
    let settings: SettingsViewModel
    let connections: ConnectionsViewModel
    let menuBar: MenuBarViewModel

    @ObservationIgnored private let store: HeadphonesStore
    @ObservationIgnored private let audio: any AudioConnecting
    @ObservationIgnored private let defaults: UserDefaults

    private enum Keys {
        static let page = "selectedPage"
    }

    init(
        transport: any ControlTransport = BLEConnection(),
        panels: any PanelProviding = PanelRepository(),
        audio: any AudioConnecting = AudioConnection(),
        finder: any FindTonePlaying = FindTone(),
        effects: EffectLibrary = EffectLibrary(),
        defaults: UserDefaults = .standard
    ) {
        let store = HeadphonesStore(transport: transport, panels: panels, defaults: defaults)
        self.store = store
        self.audio = audio
        self.defaults = defaults
        selectedPage = defaults.string(forKey: Keys.page).flatMap(Page.init(rawValue:)) ?? .overview

        root = RootViewModel(store: store)
        overview = OverviewViewModel(store: store, audio: audio)
        noiseControl = NoiseControlViewModel(store: store)
        sound = SoundViewModel(store: store, effects: effects)
        touchControls = TouchControlsViewModel(store: store)
        settings = SettingsViewModel(store: store, audio: audio, finder: finder)
        connections = ConnectionsViewModel(store: store, audio: audio)
        menuBar = MenuBarViewModel(store: store, audio: audio)

        // Earbuds paired with this Mac for audio are connected automatically over BLE,
        // and the audio link follows whichever earbuds the control link selects.
        store.pairedAudioAddresses = { [audio] in audio.pairedAddresses }
        store.onAdvertisementChange = { [audio] ad in audio.focus(on: ad) }
    }
}
