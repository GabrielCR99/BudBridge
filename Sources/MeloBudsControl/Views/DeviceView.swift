import QCYKit
import SwiftUI

struct DeviceView: View {
    @Environment(Headphones.self) private var headphones
    @State private var newName = ""
    @State private var confirmation: Confirmation?

    private enum Confirmation: String, Identifiable {
        case reset, factoryReset
        var id: Self { self }
    }

    var body: some View {
        let control = headphones.control
        let settings = control.settings
        Form {
            Section("Wear Detection") {
                let wear = settings.wearDetection ?? WearDetection(isEnabled: false, music: .off, followsANC: false)
                Toggle("Wear detection", isOn: Binding(
                    get: { wear.isEnabled },
                    set: { on in var w = wear; w.isEnabled = on; control.set(wearDetection: w) }
                ))
                Picker("Music", selection: Binding(
                    get: { wear.music },
                    set: { music in var w = wear; w.music = music; control.set(wearDetection: w) }
                )) {
                    ForEach(WearDetection.Music.allCases) { Text($0.title).tag($0) }
                }
                .disabled(!wear.isEnabled)
                Toggle("Turn noise canceling off when removed", isOn: Binding(
                    get: { wear.followsANC },
                    set: { on in var w = wear; w.followsANC = on; control.set(wearDetection: w) }
                ))
                .disabled(!wear.isEnabled)
            }

            Section("Sounds") {
                Picker("Prompt volume", selection: Binding(
                    get: { settings.beepVolume ?? .medium },
                    set: { control.set(beepVolume: $0) }
                )) {
                    ForEach(BeepVolume.allCases) { Text($0.title).tag($0) }
                }
                Picker("Voice prompt language", selection: Binding(
                    get: { settings.promptLanguage ?? .english },
                    set: { control.set(promptLanguage: $0) }
                )) {
                    ForEach(PromptLanguage.allCases) { Text($0.title).tag($0) }
                }
                LabeledContent("Find earbuds") {
                    Button(headphones.finder.isPlaying ? "Stop Sound" : "Play Sound") {
                        headphones.finder.toggle()
                    }
                    .disabled(!headphones.audio.isConnected && !headphones.finder.isPlaying)
                }
            }

            Section {
                Toggle("Sleep mode", isOn: Binding(
                    get: { settings.sleepMode ?? false },
                    set: { control.set(sleepMode: $0) }
                ))
                Picker("Power off after disconnecting", selection: Binding(
                    get: { settings.autoPowerOff ?? .fiveMinutes },
                    set: { control.set(autoPowerOff: $0) }
                )) {
                    ForEach(AutoPowerOff.allCases) { Text($0.title).tag($0) }
                }
            } header: {
                Text("Power")
            } footer: {
                Text("Sleep mode disables touch controls. Put the earbuds back in the case to leave it.")
            }

            Section("Name") {
                HStack {
                    TextField("Bluetooth name", text: $newName, prompt: Text(settings.deviceName ?? "QCY MeloBuds Pro"))
                    Button("Rename") {
                        control.rename(to: newName)
                        newName = ""
                    }
                    .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }

            Section("About") {
                LabeledContent("Model", value: "QCY MeloBuds Pro")
                LabeledContent("Firmware", value: control.firmware?.display ?? "—")
                if let address = headphones.audio.address {
                    LabeledContent("Address", value: address)
                }
            }

            Section {
                Button("Reset Settings…") { confirmation = .reset }
                Button("Factory Reset…", role: .destructive) { confirmation = .factoryReset }
            } footer: {
                Text("Take off both earbuds and keep them close to each other first.")
            }
        }
        .formStyle(.grouped)
        .confirmationDialog(
            confirmation == .factoryReset ? "Factory reset the earbuds?" : "Reset all settings?",
            isPresented: Binding(get: { confirmation != nil }, set: { if !$0 { confirmation = nil } }),
            presenting: confirmation
        ) { kind in
            switch kind {
            case .reset: Button("Reset Settings") { control.resetToDefaults() }
            case .factoryReset: Button("Factory Reset", role: .destructive) { control.factoryReset() }
            }
        } message: { kind in
            Text(kind == .factoryReset
                 ? "This erases all pairings. You'll need to pair the earbuds again with every device."
                 : "Noise control, equalizer and touch controls return to their defaults.")
        }
    }
}
