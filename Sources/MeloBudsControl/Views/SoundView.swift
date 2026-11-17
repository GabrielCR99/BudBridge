import QCYKit
import SwiftUI

struct SoundView: View {
    let control: ControlLink

    @State private var gains: [Double] = []
    @State private var pendingPreset: EQPreset?

    var body: some View {
        let eq = control.panel?.equalizer
        let selection = eq?.selection(in: control.state)
        Form {
            if let eq {
                if control.family?.isZR == true {
                    Section(eq.title) {
                        Text("The equalizer isn't supported for this model yet.")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Section(eq.title) {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 10)], spacing: 10) {
                            ForEach(eq.presets) { preset in
                                PresetButton(title: preset.name, isSelected: selection?.id == preset.id) {
                                    if preset.warning != nil { pendingPreset = preset } else { control.apply(preset: preset) }
                                }
                            }
                            if !eq.bands.isEmpty {
                                PresetButton(title: "Custom", isSelected: (selection?.id ?? 0) >= EQConfiguration.customID) {
                                    control.apply(customGains: gains)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }

                    if !eq.bands.isEmpty {
                        Section {
                            GraphicEQEditor(gains: $gains, labels: eq.bands.bandLabels, range: eq.gainRange) {
                                control.apply(customGains: gains)
                            }
                            .frame(height: 220)
                            HStack {
                                Button("Flat") {
                                    gains = Array(repeating: 0, count: eq.bands.count)
                                    control.apply(customGains: gains)
                                }
                                Spacer()
                                Text("Changes apply when you release a slider.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } header: {
                            Text("Custom Equalizer")
                        } footer: {
                            if let tip = eq.rebootTip { Text(tip) }
                        }
                    }
                }
            }

            if let balance = control.panel?.balance {
                Section(balance) {
                    BalanceSlider(control: control)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { loadGains(selection?.gains, bands: eq?.bands.count ?? 0) }
        .onChange(of: selection?.gains) { _, new in loadGains(new, bands: eq?.bands.count ?? 0) }
        .confirmationDialog(
            "Use \(pendingPreset?.name ?? "")?",
            isPresented: Binding(get: { pendingPreset != nil }, set: { if !$0 { pendingPreset = nil } }),
            presenting: pendingPreset
        ) { preset in
            Button("Apply and Restart") { control.apply(preset: preset) }
        } message: { preset in
            Text(preset.warning ?? "")
        }
    }

    private func loadGains(_ stored: [Double]?, bands: Int) {
        if let stored, stored.count == bands {
            gains = stored
        } else if gains.count != bands {
            gains = Array(repeating: 0, count: bands)
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
        .buttonStyle(isSelected ? AnyButtonStyle(.glassProminent) : AnyButtonStyle(.glass))
    }
}

/// Type-erases the two glass styles so the selection can switch between them.
private struct AnyButtonStyle: PrimitiveButtonStyle {
    private let make: (Configuration) -> AnyView

    init(_ style: some PrimitiveButtonStyle) {
        make = { AnyView(style.makeBody(configuration: $0)) }
    }

    func makeBody(configuration: Configuration) -> some View { make(configuration) }
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

struct BalanceSlider: View {
    let control: ControlLink
    @State private var value = 50.0

    var body: some View {
        HStack {
            Text("L").foregroundStyle(.secondary)
            Slider(value: $value, in: 0...100, step: 1) { editing in
                if !editing { control.set(balance: Int(value)) }
            }
            Text("R").foregroundStyle(.secondary)
            Button("Center") {
                value = 50
                control.set(balance: 50)
            }
            .disabled(Int(value) == 50)
        }
        .onAppear { value = Double(control.state.balance ?? 50) }
        .onChange(of: control.state.balance) { _, new in value = Double(new ?? 50) }
    }
}
