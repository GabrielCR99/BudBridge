import SwiftUI

@Observable
final class Headphones {
    let control = ControlLink()
    let audio = AudioLink()
    let finder = FindTone()
}

@main
struct MeloBudsControlApp: App {
    @State private var headphones = Headphones()

    var body: some Scene {
        Window("MeloBuds Pro", id: "main") {
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
        if let level = control.battery?.lowestBud, control.isReady {
            Label("\(level)%", systemImage: "earbuds")
                .labelStyle(.titleAndIcon)
        } else {
            Image(systemName: "earbuds")
        }
    }
}
