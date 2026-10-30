//
//  SettingsView.swift
//  Physics Playground — Shell
//
//  The settings window. Every row does something the moment it is
//  flipped: volume and room tone apply instantly, the capsule switch
//  gates the recording. Opens from the palette bead's gear petal or
//  `-settingsOpen 1`.
//

import RenderKit
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
                    .accessibilityAddTraits(.isHeader)

                ControlSection("Sound") {
                    ControlSlider("Effects volume", systemImage: "speaker.wave.2.fill",
                                  range: 0...1,
                                  read: { settings.masterVolume },
                                  write: { settings.masterVolume = $0 },
                                  format: { "\(Int(($0 * 100).rounded())) %" },
                                  speak: { "\(Int(($0 * 100).rounded())) percent" })
                    ControlToggle("Lab room tone", systemImage: "waveform",
                                  presentation: .row, isOn: $settings.ambientAudio)
                }

                ControlSection("Time Capsule") {
                    ControlToggle("Record the last 30 seconds",
                                  systemImage: "clock.arrow.circlepath",
                                  presentation: .row, isOn: $settings.timeCapsule)
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
