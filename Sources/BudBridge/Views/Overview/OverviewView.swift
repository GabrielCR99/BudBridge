import SwiftUI

struct OverviewView: View {
    let viewModel: OverviewViewModel

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                BatteryFreshness(viewModel: viewModel.battery) {
                    GlassGroup(spacing: 16) {
                        HStack(spacing: 16) {
                            ForEach(viewModel.battery.slots) { slot in
                                BatteryCard(slot: slot)
                            }
                        }
                    }
                }

                if viewModel.showsNoiseControl {
                    GroupBox(viewModel.noise.title) {
                        NoiseModePicker(viewModel: viewModel.noise)
                            .padding(.vertical, 4)
                    }
                    .skeleton(viewModel.isLoading)
                }

                if viewModel.showsSettingsDownload {
                    GroupBox {
                        HStack(spacing: 12) {
                            if viewModel.settingsDownloadFailed {
                                Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange)
                            } else {
                                ProgressView().controlSize(.small)
                            }
                            Text(viewModel.settingsDownloadText)
                            Spacer()
                            if viewModel.settingsDownloadFailed {
                                Button("Try Again") { viewModel.retrySettingsDownload() }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 4)
                    }
                }

                GroupBox("Connections") {
                    VStack(alignment: .leading, spacing: 12) {
                        AudioConnectionRow(viewModel: viewModel.connections)
                        Divider()
                        ControlConnectionRow(viewModel: viewModel.connections)
                    }
                    .padding(.vertical, 4)
                }

                if viewModel.showsQuickSettings {
                    GroupBox("Quick Settings") {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(viewModel.switches.quickToggles, id: \.self) { item in
                                PanelToggle(viewModel: viewModel.switches, item: item)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 4)
                    }
                    .skeleton(viewModel.isLoading)
                }
            }
            .padding(24)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
        .restartConfirmation(viewModel.switches)
        .onAppear { viewModel.connections.refreshAudio() }
    }
}
