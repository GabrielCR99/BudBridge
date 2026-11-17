import QCYKit
import SwiftUI

struct NoiseControlView: View {
    let control: ControlLink

    var body: some View {
        if let panel = control.panel?.noiseControl {
            let value = NoiseValue.value(in: control.state)
            let mode = value.flatMap(panel.mode(for:))
            Form {
                Section {
                    NoiseModePicker(control: control, panel: panel)
                }
                if let mode, let value {
                    switch mode.kind {
                    case .scenes(let scenes):
                        sceneSections(scenes, value: value)
                    case .levels(let levels, let vocal):
                        levelSection(levels, vocal: vocal, value: value)
                    case .single:
                        EmptyView()
                    }
                } else {
                    Section {
                        Text("Waiting for the earbuds to report their current mode…")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .formStyle(.grouped)
        }
    }

    @ViewBuilder
    private func sceneSections(_ scenes: [NoiseScene], value: Int) -> some View {
        let current = scenes.first { $0.values.contains(value) }
        Section("Scene") {
            ForEach(scenes) { scene in
                Button {
                    // Keep the current strength step when switching scenes.
                    let step = current.map { value - $0.values.lowerBound } ?? (scene.values.count - 1)
                    control.setNoise(min(scene.values.lowerBound + step, scene.values.upperBound))
                } label: {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(scene.name)
                            if let detail = scene.detail, !detail.isEmpty {
                                Text(detail).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        if scene == current {
                            Image(systemName: "checkmark").foregroundStyle(.tint)
                        }
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
        }

        if let current, current.values.count > 1 {
            Section("Strength") {
                Picker("Strength", selection: Binding(get: { value }, set: { control.setNoise($0) })) {
                    ForEach(Array(current.values.enumerated()), id: \.element) { index, step in
                        Text("Level \(index + 1)").tag(step)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
        }
    }

    @ViewBuilder
    private func levelSection(_ levels: ClosedRange<Int>, vocal: Int?, value: Int) -> some View {
        let isVocal = vocal == value
        Section {
            if let vocal {
                Toggle("Vocal enhancement", isOn: Binding(
                    get: { isVocal },
                    set: { on in control.setNoise(on ? vocal : levels.lowerBound + (levels.count - 1) / 2) }
                ))
            }
            if !isVocal {
                LabeledContent("Level") {
                    Slider(
                        value: Binding(
                            get: { Double(levels.contains(value) ? value : levels.lowerBound) },
                            set: { control.setNoise(Int($0.rounded())) }
                        ),
                        in: Double(levels.lowerBound)...Double(levels.upperBound), step: 1
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
