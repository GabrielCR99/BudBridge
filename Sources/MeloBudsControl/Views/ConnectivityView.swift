import QCYKit
import SwiftUI

struct ConnectivityView: View {
    @Environment(Headphones.self) private var headphones
    @State private var pendingChange: PendingChange?

    private enum PendingChange: Identifiable {
        case ldac(Bool), dualDevice(Bool)
        var id: String { "\(self)" }
    }

    var body: some View {
        let control = headphones.control
        Form {
            Section("This Mac") {
                AudioConnectionRow(audio: headphones.audio)
                ControlConnectionRow(control: control)
            }

            if control.isReady {
                Section {
                    Toggle(isOn: Binding(get: { control.settings.dualDevice ?? false },
                                         set: { pendingChange = .dualDevice($0) })) {
                        Label {
                            VStack(alignment: .leading) {
                                Text("Dual Device Connection")
                                Text("Stay connected to your phone and this Mac at the same time.")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        } icon: { Image(systemName: "laptopcomputer.and.iphone") }
                    }

                    Toggle(isOn: Binding(get: { control.settings.ldac ?? false },
                                         set: { pendingChange = .ldac($0) })) {
                        Label {
                            VStack(alignment: .leading) {
                                Text("LDAC")
                                Text("Hi-res audio for Android sources. macOS streams AAC or SBC instead.")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        } icon: { Image(systemName: "waveform.badge.plus") }
                    }

                    Toggle(isOn: Binding(get: { control.settings.lowLatency ?? false },
                                         set: { control.set(lowLatency: $0) })) {
                        Label {
                            VStack(alignment: .leading) {
                                Text("Gaming Mode")
                                Text("Lower audio latency at a small cost in stability.")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        } icon: { Image(systemName: "gamecontroller") }
                    }
                } header: {
                    Text("Earbud Features")
                } footer: {
                    if control.isRestarting {
                        Label("The earbuds are restarting to apply the change…", systemImage: "arrow.clockwise")
                    } else {
                        Text("LDAC and dual device connection can't be on together. Changing either restarts the earbuds.")
                    }
                }
                .toggleStyle(.switch)
                .disabled(control.isRestarting)
            } else {
                Section {
                    ControlUnavailableView(control: control)
                }
            }
        }
        .formStyle(.grouped)
        .confirmationDialog(title, isPresented: Binding(get: { pendingChange != nil },
                                                        set: { if !$0 { pendingChange = nil } })) {
            Button("Restart Earbuds") {
                switch pendingChange {
                case .ldac(let on): control.set(ldac: on)
                case .dualDevice(let on): control.set(dualDevice: on)
                case nil: break
                }
            }
        } message: {
            Text(message)
        }
    }

    private var title: String {
        switch pendingChange {
        case .ldac(let on): on ? "Turn On LDAC?" : "Turn Off LDAC?"
        case .dualDevice(let on): on ? "Turn On Dual Device Connection?" : "Turn Off Dual Device Connection?"
        case nil: ""
        }
    }

    private var message: String {
        switch pendingChange {
        case .ldac(true): "The earbuds will restart, and dual device connection and spatial sound will turn off."
        case .dualDevice(true): "The earbuds will restart, and LDAC will turn off."
        default: "The earbuds will restart to apply the change."
        }
    }
}
