import QCYKit
import SwiftUI

struct SoundView: View {
    @Bindable var viewModel: SoundViewModel

    var body: some View {
        Form {
            if let eq = viewModel.equalizer {
                if viewModel.isEqualizerSupported {
                    presetsSection(title: eq.title)
                    effectsSection
                    if viewModel.hasCustomEqualizer { customSection(rebootTip: eq.rebootTip) }
                } else {
                    Section(eq.title) {
                        Text("The equalizer isn't supported for this model yet.")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            if let balance = viewModel.balanceTitle {
                Section(balance) {
                    BalanceSlider(viewModel: viewModel)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { viewModel.syncGains() }
        .onChange(of: viewModel.storedGains) { viewModel.syncGains() }
        .alert(viewModel.namingTitle, isPresented: Binding(
            get: { viewModel.naming != nil },
            set: { if !$0 { viewModel.naming = nil } }
        )) {
            TextField("Name", text: $viewModel.nameDraft)
            Button("Save") { viewModel.commitName() }
                .disabled(!viewModel.canCommitName)
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog(
            "Use \(viewModel.pendingPreset?.name ?? "")?",
            isPresented: Binding(get: { viewModel.pendingPreset != nil }, set: { if !$0 { viewModel.pendingPreset = nil } }),
            presenting: viewModel.pendingPreset
        ) { _ in
            Button("Apply and Restart") { viewModel.confirmPendingPreset() }
        } message: { preset in
            Text(preset.warning ?? "")
        }
    }

    private func presetsSection(title: String) -> some View {
        Section(title) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 10)], spacing: 10) {
                ForEach(viewModel.presets) { row in
                    PresetButton(title: row.preset.name, isSelected: row.isSelected) { viewModel.choose(row.preset) }
                }
                if viewModel.hasCustomEqualizer {
                    PresetButton(title: String(localized: "Custom"), isSelected: viewModel.isCustomSelected) {
                        viewModel.applyCustom()
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var effectsSection: some View {
        Section {
            ForEach(viewModel.savedEffects) { row in
                HStack {
                    Text(row.effect.name)
                    Spacer()
                    if row.isActive {
                        Image(systemName: "checkmark").foregroundStyle(.tint)
                    } else {
                        Button("Apply") { viewModel.apply(row.effect) }
                    }
                }
                .contextMenu {
                    Button("Rename…") { viewModel.startRenaming(row.effect) }
                    Button("Delete", role: .destructive) { viewModel.delete(row.effect) }
                }
            }
            if let unsaved = viewModel.unsavedActiveCurve {
                HStack {
                    VStack(alignment: .leading) {
                        Text("Custom curve on the earbuds")
                        Text("Not saved on this Mac yet").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Save As…") { viewModel.startSaving(unsaved) }
                }
            } else if viewModel.savedEffects.isEmpty {
                Text("No saved effects yet.").foregroundStyle(.secondary)
            }
        } header: {
            Text("My Sound Effects")
        } footer: {
            Text("Effects you create in the QCY phone app are stored on the phone, not the earbuds. To bring one over, select it in the phone app, tap Take Control here, then use Save As. Right-click a saved effect to rename or delete it.")
        }
    }

    private func customSection(rebootTip: String?) -> some View {
        Section {
            GraphicEQEditor(gains: $viewModel.gains, labels: viewModel.bandLabels, range: viewModel.gainRange) {
                viewModel.applyCustom()
            }
            .frame(height: 220)
            HStack {
                Button("Flat") { viewModel.flatten() }
                Spacer()
                Text("Changes apply when you release a slider.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Custom Equalizer")
        } footer: {
            if let rebootTip { Text(rebootTip) }
        }
    }
}

private struct PresetButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
        }
        .selectableButtonStyle(isSelected: isSelected)
    }
}

struct GraphicEQEditor: View {
    @Binding var gains: [Double]
    let labels: [String]
    let range: ClosedRange<Double>
    var commit: () -> Void

    var body: some View {
        HStack(alignment: .bottom, spacing: 0) {
            VStack {
                Text("+\(Int(range.upperBound))").font(.caption2)
                Spacer()
                Text("0").font(.caption2)
                Spacer()
                Text("−\(Int(-range.lowerBound))").font(.caption2)
            }
            .foregroundStyle(.secondary)
            .padding(.bottom, 34)

            ForEach(gains.indices, id: \.self) { index in
                VStack(spacing: 6) {
                    Text(gains[index], format: .number.precision(.fractionLength(0)).sign(strategy: .always(includingZero: false)))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                    VerticalSlider(value: $gains[index], range: range) { editing in
                        if !editing { commit() }
                    }
                    Text(index < labels.count ? labels[index] : "")
                        .font(.caption2.monospacedDigit())
                }
                .frame(maxWidth: .infinity)
            }
        }
    }
}

private struct VerticalSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    var onEditingChanged: (Bool) -> Void

    var body: some View {
        GeometryReader { proxy in
            Slider(value: $value, in: range, step: 0.5, onEditingChanged: onEditingChanged)
                .labelsHidden()
                .frame(width: proxy.size.height)
                .rotationEffect(.degrees(-90))
                .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
        }
    }
}

private struct BalanceSlider: View {
    @Bindable var viewModel: SoundViewModel

    var body: some View {
        HStack {
            Text("L").foregroundStyle(.secondary)
            Slider(value: $viewModel.balance, in: 0...100, step: 1) { editing in
                if !editing { viewModel.applyBalance() }
            }
            Text("R").foregroundStyle(.secondary)
            Button("Center") { viewModel.centerBalance() }
                .disabled(Int(viewModel.balance) == 50)
        }
        .onAppear { viewModel.syncBalance() }
        .onChange(of: viewModel.storedBalance) { viewModel.syncBalance() }
    }
}
