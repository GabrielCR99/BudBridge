import QCYKit
import SwiftUI

/// Everything else the model's settings list offers: switches, value lists, wear detection,
/// rename, find, and reset commands, in panel order.
struct SettingsView: View {
    @Environment(Headphones.self) private var headphones
    @State private var pendingToggle: ToggleItem?
    @State private var pendingAction: ActionItem?
    @State private var newName = ""

    var body: some View {
        let control = headphones.control
        let panel = control.panel
        Form {
            if let items = panel?.settings, !items.isEmpty {
                Section("Features") {
                    ForEach(items) { item in
                        switch item {
                        case .toggle(let toggle):
                            PanelToggle(control: control, item: toggle, pending: $pendingToggle)
                        case .choice(let choice):
                            ChoicePicker(control: control, item: choice)
                        }
                    }
                }
            }

            if let wear = panel?.wearDetection {
                WearDetectionSection(control: control, panel: wear)
            }

            if let rename = panel?.rename {
                Section(rename.title) {
                    HStack {
                        TextField("Bluetooth name", text: $newName,
                                  prompt: Text(control.state.deviceName ?? control.modelName))
                        Button("Rename") {
                            control.rename(to: newName)
                            newName = ""
                        }
                        .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }

            if panel?.hasFindEarbuds == true {
                Section {
                    LabeledContent("Find earbuds") {
                        Button(headphones.finder.isPlaying ? "Stop Sound" : "Play Sound") {
                            headphones.finder.toggle()
                        }
                        .disabled(!headphones.audio.isConnected && !headphones.finder.isPlaying)
                    }
                } footer: {
                    Text("Plays a loud chirp through the earbuds while they're connected to this Mac.")
                }
            }

            Section("About") {
                LabeledContent("Model", value: control.modelName)
                LabeledContent("Firmware", value: control.state.firmware?.display ?? "—")
                if let address = headphones.audio.address {
                    LabeledContent("Address", value: address)
                }
                if let ad = control.advertisement {
                    LabeledContent("Model ID", value: "\(ad.vendorID) (0x\(String(ad.vendorID, radix: 16, uppercase: true)))")
                }
            }

            if let actions = panel?.actions, !actions.isEmpty {
                Section {
                    ForEach(actions) { action in
                        Button("\(action.title)…", role: action.isDestructive ? .destructive : nil) {
                            pendingAction = action
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .restartConfirmation($pendingToggle, control: control)
        .confirmationDialog(
            "\(pendingAction?.title ?? "")?",
            isPresented: Binding(get: { pendingAction != nil }, set: { if !$0 { pendingAction = nil } }),
            presenting: pendingAction
        ) { action in
            Button(action.title, role: action.isDestructive ? .destructive : nil) { control.run(action) }
        } message: { action in
            Text(action.message ?? "This can't be undone.")
        }
    }
}

private struct ChoicePicker: View {
    let control: ControlLink
    let item: ChoiceItem

    var body: some View {
        Picker(item.title, selection: Binding(
            get: { item.selection(in: control.state)?.payload ?? [] },
            set: { payload in
                if let option = item.options.first(where: { $0.payload == payload }) {
                    control.select(option, in: item)
                }
            }
        )) {
            if item.selection(in: control.state) == nil {
                Text("—").tag([UInt8]())
            }
            ForEach(item.options) { option in
                Text(option.name).tag(option.payload)
            }
        }
    }
}

private struct WearDetectionSection: View {
    let control: ControlLink
    let panel: WearDetectionPanel

    var body: some View {
        let wear = control.state.wearDetection ?? WearDetection(isEnabled: false, music: 0, followsANC: false)
        Section {
            Toggle("Wear detection", isOn: Binding(
                get: { wear.isEnabled },
                set: { on in var w = wear; w.isEnabled = on; control.set(wearDetection: w) }
            ))
            if !panel.musicOptions.isEmpty {
                Picker("Music", selection: Binding(
                    get: { wear.music },
                    set: { music in var w = wear; w.music = music; control.set(wearDetection: w) }
                )) {
                    ForEach(panel.musicOptions) { option in
                        Text(option.name).tag(option.payload.first ?? 0)
                    }
                }
                .disabled(!wear.isEnabled)
            }
            if let ancMessage = panel.ancMessage, !ancMessage.isEmpty {
                Toggle(isOn: Binding(
                    get: { wear.followsANC },
                    set: { on in var w = wear; w.followsANC = on; control.set(wearDetection: w) }
                )) {
                    Text(ancMessage)
                }
                .disabled(!wear.isEnabled)
            }
        } header: {
            Text(panel.title)
        } footer: {
            if let message = panel.message, !message.isEmpty { Text(message) }
        }
    }
}
