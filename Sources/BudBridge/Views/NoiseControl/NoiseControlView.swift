import QCYKit
import SwiftUI

struct NoiseControlView: View {
    let viewModel: NoiseControlViewModel

    var body: some View {
        Form {
            Section {
                NoiseModePicker(viewModel: viewModel.modes)
            }
            switch viewModel.content {
            case .scenes(let scenes, let strengths):
                sceneSection(scenes)
                if !strengths.isEmpty { strengthSection(strengths) }
            case .levels(let range, let value, let hasVocal, let isVocal):
                levelSection(range: range, value: value, hasVocal: hasVocal, isVocal: isVocal)
            case .none:
                EmptyView()
            case .waiting:
                Section {
                    Text("Waiting for the earbuds to report their current mode…")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }

    private func sceneSection(_ scenes: [NoiseControlViewModel.SceneRow]) -> some View {
        Section("Scene") {
            ForEach(scenes) { row in
                Button {
                    viewModel.select(row.scene)
                } label: {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(row.scene.name)
                            if let detail = row.scene.detail, !detail.isEmpty {
                                Text(detail).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        if row.isSelected {
                            Image(systemName: "checkmark").foregroundStyle(.tint)
                        }
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func strengthSection(_ strengths: [NoiseControlViewModel.StrengthOption]) -> some View {
        Section("Strength") {
            Picker("Strength", selection: Binding(
                get: { viewModel.value ?? strengths[0].value },
                set: { viewModel.setStrength($0) }
            )) {
                ForEach(strengths) { option in
                    Text(option.title).tag(option.value)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
    }

    private func levelSection(range: ClosedRange<Int>, value: Int, hasVocal: Bool, isVocal: Bool) -> some View {
        Section {
            if hasVocal {
                Toggle("Vocal enhancement", isOn: Binding(get: { isVocal }, set: { viewModel.setVocal($0) }))
            }
            if !isVocal {
                LabeledContent("Level") {
                    Slider(
                        value: Binding(get: { Double(value) }, set: { viewModel.setLevel(Int($0.rounded())) }),
                        in: Double(range.lowerBound)...Double(range.upperBound), step: 1
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
