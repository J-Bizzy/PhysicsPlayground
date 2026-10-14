//
//  SettingsView.swift
//  Physics Playground — Shell
//
//  The settings window. Every row does something the moment it is
//  flipped: volume and room tone apply instantly, the capsule switch
//  gates the recording. Opens from the palette bead's gear petal or
//  `-settingsOpen 1`.
//

import SwiftUI

struct SettingsView: View {
    static let windowID = "settings"

    @Environment(AppModel.self) private var appModel

    var body: some View {
        @Bindable var settings = appModel.settings

        ScrollView {
            VStack(alignment: .leading, spacing: DesignTokens.Panel.sectionSpacing) {
                Text("Settings")
                    .font(DesignTokens.TypeScale.cardTitle)

                PanelSection("Sound") {
                    row("Effects volume") {
                        // The ends say which way is louder, as the system's own
                        // volume control does.
                        Slider(value: $settings.masterVolume, in: 0...1) {
                            Text("Effects volume")
                        } minimumValueLabel: {
                            Image(systemName: "speaker.fill")
                                .foregroundStyle(.secondary)
                        } maximumValueLabel: {
                            Image(systemName: "speaker.wave.3.fill")
                                .foregroundStyle(.secondary)
                        }
                    }
                    Toggle("Lab room tone", isOn: $settings.ambientAudio)
                        .font(DesignTokens.TypeScale.control)
                }

                PanelSection("Time Capsule") {
                    Toggle("Record the last 30 seconds", isOn: $settings.timeCapsule)
                        .font(DesignTokens.TypeScale.control)
                    caption("Every lab remembers what just happened. Pause and "
                            + "a reel appears — pinch it to draw out a rail, "
                            + "then scrub the whole room backwards and walk "
                            + "around any moment. It costs a few megabytes per "
                            + "lab while it runs; switch it off and nothing is "
                            + "recorded.")
                }

            }
            .padding(DesignTokens.Panel.outerPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: Rows

    @ViewBuilder
    private func row(_ label: String,
                     @ViewBuilder control: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(DesignTokens.TypeScale.label)
            control()
        }
    }

    @ViewBuilder
    private func caption(_ text: String) -> some View {
        Text(text)
            .font(DesignTokens.TypeScale.footnote)
            .foregroundStyle(.secondary)
    }
}

#Preview(windowStyle: .automatic) {
    SettingsView()
        .environment(AppModel())
}
