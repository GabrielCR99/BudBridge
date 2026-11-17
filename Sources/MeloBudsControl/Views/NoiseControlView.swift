import QCYKit
import SwiftUI

struct NoiseControlView: View {
    let control: ControlLink

    var body: some View {
        let current = control.settings.noiseControl ?? .off
        Form {
            Section {
                NoiseKindPicker(control: control, current: current)
            }

            switch current {
            case .noiseCanceling(let scene):
                sceneSection(scene)
            case .transparency(let level):
                transparencySection(level: level, vocal: false)
            case .vocalTransparency:
                transparencySection(level: 4, vocal: true)
            case .off:
                Section {
                    Text("Noise canceling and transparency are off.")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder
    private func sceneSection(_ scene: ANCScene) -> some View {
        Section("Scene") {
            ForEach(ANCScene.Kind.allCases) { kind in
                Button {
                    control.set(noiseControl: .noiseCanceling(kind.scene(strength: scene.strength ?? 2)))
                } label: {
                    HStack {
                        Label {
                            VStack(alignment: .leading) {
                                Text(kind.title)
                                Text(kind.detail).font(.caption).foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: kind.symbol)
                        }
                        Spacer()
                        if kind == scene.kind {
                            Image(systemName: "checkmark").foregroundStyle(.tint)
                        }
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
        }

        if let strength = scene.strength {
            Section("Strength") {
                Picker("Strength", selection: Binding(
                    get: { strength },
                    set: { control.set(noiseControl: .noiseCanceling(scene.with(strength: $0))) }
                )) {
                    Text("Light").tag(UInt8(0))
                    Text("Medium").tag(UInt8(1))
                    Text("Strong").tag(UInt8(2))
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
        }
    }

    @ViewBuilder
    private func transparencySection(level: UInt8, vocal: Bool) -> some View {
        Section("Transparency") {
            Toggle("Vocal enhancement", isOn: Binding(
                get: { vocal },
                set: { control.set(noiseControl: $0 ? .vocalTransparency : .transparency(level: level)) }
            ))
            if !vocal {
                LabeledContent("Ambient level") {
                    Slider(
                        value: Binding(
                            get: { Double(level) },
                            set: { control.set(noiseControl: .transparency(level: UInt8($0.rounded()))) }
                        ),
                        in: 1...6, step: 1
                    ) {
                        EmptyView()
                    } minimumValueLabel: {
                        Image(systemName: "speaker.wave.1")
                    } maximumValueLabel: {
                        Image(systemName: "speaker.wave.3")
                    }
                }
            }
        }
    }
}
