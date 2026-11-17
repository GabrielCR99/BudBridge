import SwiftUI

@Observable
final class Headphones {
    let control: ControlLink
    let audio = AudioLink()
    let finder = FindTone()

    init() {
        control = ControlLink(panels: PanelStore())
        control.pairedAudioAddresses = { [audio] in audio.pairedAddresses }
    }
}

@main
struct MeloBudsControlApp: App {
    @State private var headphones = Headphones()

    var body: some Scene {
        Window("QCY Earbuds", id: "main") {
            RootView()
                .environment(headphones)
                .frame(minWidth: 760, minHeight: 540)
        }
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(after: .toolbar) {
                Button("Refresh from Earbuds") { headphones.control.refresh() }
                    .keyboardShortcut("r")
            }
        }

        MenuBarExtra {
            MenuBarPanel()
                .environment(headphones)
        } label: {
            MenuBarLabel(control: headphones.control)
        }
        .menuBarExtraStyle(.window)
    }
}

private struct MenuBarLabel: View {
    let control: ControlLink

    var body: some View {
        if let level = control.state.battery?.lowestBud, control.isReady {
            Label("\(level)%", systemImage: "earbuds")
                .labelStyle(.titleAndIcon)
        } else {
            Image(systemName: "earbuds")
        }
    }
}
