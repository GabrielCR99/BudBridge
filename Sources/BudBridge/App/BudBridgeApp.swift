import SwiftUI

@main
struct BudBridgeApp: App {
    @State private var coordinator = AppCoordinator()

    var body: some Scene {
        Window("BudBridge", id: "main") {
            RootView(coordinator: coordinator)
                .frame(minWidth: 760, minHeight: 540)
        }
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(after: .toolbar) {
                Button("Refresh from Earbuds") { coordinator.root.refresh() }
                    .keyboardShortcut("r")
            }
        }

        MenuBarExtra {
            MenuBarPanel(viewModel: coordinator.menuBar)
        } label: {
            MenuBarLabel(viewModel: coordinator.menuBar.battery)
        }
        .menuBarExtraStyle(.window)
    }
}

private struct MenuBarLabel: View {
    let viewModel: BatteryViewModel

    var body: some View {
        if let level = viewModel.lowestBud {
            Label("\(level)%", systemImage: "earbuds")
                .labelStyle(.titleAndIcon)
        } else {
            Image(systemName: "earbuds")
        }
    }
}
