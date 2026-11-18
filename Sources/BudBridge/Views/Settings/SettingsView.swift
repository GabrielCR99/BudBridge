import QCYKit
import SwiftUI

/// Everything else the model's settings list offers: switches, value lists, wear detection,
/// rename, find, and reset commands, in panel order.
struct SettingsView: View {
    @Bindable var viewModel: SettingsViewModel

    var body: some View {
        Form {
            if !viewModel.items.isEmpty {
                Section("Features") {
                    ForEach(viewModel.items) { item in
                        switch item {
                        case .toggle(let toggle):
                            PanelToggle(viewModel: viewModel.switches, item: toggle)
                        case .choice(let choice):
                            choicePicker(choice)
                        }
                    }
                }
            }
            if let wear = viewModel.wearPanel {
                wearSection(wear)
            }
            if let rename = viewModel.renamePanel {
                Section(rename.title) {
                    HStack {
                        TextField("Bluetooth name", text: $viewModel.nameDraft, prompt: Text(viewModel.namePlaceholder))
                        Button("Rename") { viewModel.rename() }
                            .disabled(!viewModel.canRename)
                    }
                }
            }
            if viewModel.hasFindEarbuds {
                Section {
                    LabeledContent("Find earbuds") {
                        Button(viewModel.isFindSoundPlaying ? "Stop Sound" : "Play Sound") { viewModel.toggleFindSound() }
                            .disabled(!viewModel.canPlayFindSound)
                    }
                } footer: {
                    Text("Plays a loud chirp through the earbuds while they're connected to this Mac.")
                }
            }
            Section("About") {
                ForEach(viewModel.about) { row in
                    LabeledContent(row.label, value: row.value)
                }
            }
            if !viewModel.actions.isEmpty {
                Section {
                    ForEach(viewModel.actions) { action in
                        Button("\(action.title)…", role: action.isDestructive ? .destructive : nil) {
                            viewModel.pendingAction = action
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .restartConfirmation(viewModel.switches)
        .confirmationDialog(
            "\(viewModel.pendingAction?.title ?? "")?",
            isPresented: Binding(get: { viewModel.pendingAction != nil }, set: { if !$0 { viewModel.pendingAction = nil } }),
            presenting: viewModel.pendingAction
        ) { action in
            Button(action.title, role: action.isDestructive ? .destructive : nil) { viewModel.confirmPendingAction() }
        } message: { _ in
            Text(viewModel.pendingActionMessage)
        }
    }

    private func choicePicker(_ choice: ChoiceItem) -> some View {
        let selection = viewModel.selection(for: choice)
        return Picker(choice.title, selection: Binding(
            get: { selection?.payload ?? [] },
            set: { payload in
                if let option = choice.options.first(where: { $0.payload == payload }) {
                    viewModel.select(option, in: choice)
                }
            }
        )) {
            if selection == nil {
                Text("—").tag([UInt8]())
            }
            ForEach(choice.options) { option in
                Text(option.name).tag(option.payload)
            }
        }
    }

    private func wearSection(_ panel: WearDetectionPanel) -> some View {
        let wear = viewModel.wear
        return Section {
            Toggle("Wear detection", isOn: Binding(get: { wear.isEnabled }, set: { viewModel.setWear(enabled: $0) }))
            if !panel.musicOptions.isEmpty {
                Picker("Music", selection: Binding(get: { wear.music }, set: { viewModel.setWear(music: $0) })) {
                    ForEach(panel.musicOptions) { option in
                        Text(option.name).tag(option.payload.first ?? 0)
                    }
                }
                .disabled(!wear.isEnabled)
            }
            if let ancMessage = panel.ancMessage, !ancMessage.isEmpty {
                Toggle(isOn: Binding(get: { wear.followsANC }, set: { viewModel.setWear(followsANC: $0) })) {
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
