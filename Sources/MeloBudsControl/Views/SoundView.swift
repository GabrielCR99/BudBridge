import QCYKit
import SwiftUI

struct SoundView: View {
    let control: ControlLink

    @State private var gains = Array(repeating: 0.0, count: GraphicEQ.frequencies.count)
    @State private var pendingPreset: EQPreset?

    private var activeID: UInt8? { control.settings.equalizer?.id }

    var body: some View {
        Form {
            Section("Presets") {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 10)], spacing: 10) {
                    ForEach(EQPreset.all) { preset in
                        PresetButton(title: preset.name, isSelected: activeID == preset.id) {
                            if preset.warning != nil { pendingPreset = preset } else { control.apply(preset: preset) }
                        }
                    }
                    PresetButton(title: "Custom", isSelected: control.settings.equalizer?.isCustom == true) {
                        control.apply(customGains: gains)
                    }
                }
                .padding(.vertical, 4)
            }

            Section {
                GraphicEQEditor(gains: $gains) {
                    control.apply(customGains: gains)
                }
                .frame(height: 220)
                HStack {
                    Button("Flat") {
                        gains = Array(repeating: 0, count: gains.count)
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
                Text("Your curve is layered on the MeloBuds Pro base tuning, like in the QCY app.")
            }

            Section("Channel Balance") {
                BalanceSlider(control: control)
            }
        }
        .formStyle(.grouped)
        .onAppear(perform: loadGains)
        .onChange(of: control.settings.equalizer) { loadGains() }
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

    private func loadGains() {
        if let stored = control.settings.equalizer?.graphicGains { gains = stored }
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
    var commit: () -> Void

    var body: some View {
        HStack(alignment: .bottom, spacing: 0) {
            VStack {
                Text("+8").font(.caption2)
                Spacer()
                Text("0").font(.caption2)
                Spacer()
                Text("−8").font(.caption2)
            }
            .foregroundStyle(.secondary)
            .padding(.bottom, 34)

            ForEach(gains.indices, id: \.self) { index in
                VStack(spacing: 6) {
                    Text(gains[index], format: .number.precision(.fractionLength(0)).sign(strategy: .always(includingZero: false)))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                    VerticalSlider(value: $gains[index], range: GraphicEQ.gainRange) { editing in
                        if !editing { commit() }
                    }
                    Text(GraphicEQ.label(for: GraphicEQ.frequencies[index]))
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
        .onAppear { value = Double(control.settings.balance ?? 50) }
        .onChange(of: control.settings.balance) { _, new in value = Double(new ?? 50) }
    }
}
