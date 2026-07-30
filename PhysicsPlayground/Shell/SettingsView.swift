//
//  SettingsView.swift
//  Physics Playground — Shell
//
//  The settings window: the first real UI over AppSettings. Every row
//  here obeys AppSettings' own rule — it does something the moment it
//  is flipped. Reduce motion, volume, and room tone apply instantly;
//  the arc sliders commit on release (each commit rebuilds the whole
//  constellation, so per-tick commits would thrash it); the two resets
//  act once, the destructive one behind a confirm.
//
//  Opens from the palette bead's gear petal, or `-settingsOpen 1` from
//  the command line. Lives in its own glass window so it works with or
//  without the immersive space.
//

import SwiftUI

struct SettingsView: View {
    static let windowID = "settings"

    @Environment(AppModel.self) private var appModel
    @State private var confirmingProgressReset = false

    var body: some View {
        @Bindable var settings = appModel.settings

        ScrollView {
            VStack(alignment: .leading, spacing: DesignTokens.Panel.sectionSpacing) {
                Text("Settings")
                    .font(DesignTokens.TypeScale.cardTitle)

                section("Comfort") {
                    Toggle("Reduce motion", isOn: $settings.reduceMotion)
                        .font(DesignTokens.TypeScale.control)
                    caption("Stills the idle life of the hub — the bob, the "
                            + "sway, the running miniatures.")
                }

                section("Sound") {
                    row("Effects volume") {
                        Slider(value: $settings.masterVolume, in: 0...1)
                    }
                    Toggle("Lab room tone", isOn: $settings.ambientAudio)
                        .font(DesignTokens.TypeScale.control)
                }

                section("Home title") {
                    Picker("Style", selection: $settings.titleStyle) {
                        Text("Show me all three").tag(HubTitleStyle.audition)
                        Text("Bubble (original)").tag(HubTitleStyle.bubble.rawValue)
                        Text("Frosted glass").tag(HubTitleStyle.frosted.rawValue)
                        Text("Machined plaque").tag(HubTitleStyle.plaque.rawValue)
                        Text("Bold poster").tag(HubTitleStyle.poster.rawValue)
                    }
                    .font(DesignTokens.TypeScale.control)
                    .onChange(of: settings.titleStyle) {
                        // The wordmark and signs are built once, in the
                        // scene's make closure; bumping the version is
                        // what tears the gallery down and rebuilds it
                        // in the new voice.
                        settings.layoutVersion += 1
                    }
                    caption("The face the app's name and the two door signs "
                            + "are set in. \"Show me all three\" hangs the "
                            + "candidates side by side in the gallery so they "
                            + "can be compared at a glance.")
                }

                section("Gallery") {
                    meterRow("Gallery distance", value: settings.arcDistance) {
                        Slider(value: $settings.arcDistance, in: 1.5...3.0) { editing in
                            if !editing { settings.layoutVersion += 1 }
                        }
                    }
                    meterRow("Gallery height", value: settings.arcHeight) {
                        Slider(value: $settings.arcHeight, in: 1.0...1.8) { editing in
                            if !editing { settings.layoutVersion += 1 }
                        }
                    }
                    Button("Recenter gallery", action: recenter)
                        .font(DesignTokens.TypeScale.control)
                        .disabled(appModel.room.lookRay == nil)
                    caption("Swings the gallery round to face you. "
                            + "Needs headset tracking — unavailable in the simulator.")
                }

                section("Onboarding") {
                    Button("Show hints again") {
                        settings.resetOnboardingTips()
                    }
                    .font(DesignTokens.TypeScale.control)
                    caption("Every module's first-run hint appears once more.")
                }

                section("Progress") {
                    Button("Reset experiment progress…", role: .destructive) {
                        confirmingProgressReset = true
                    }
                    .font(DesignTokens.TypeScale.control)
                    caption("Clears every completed experiment and the streak. "
                            + "There is no undo.")
                }
            }
            .padding(DesignTokens.Panel.outerPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .confirmationDialog(
            "Reset all experiment progress?",
            isPresented: $confirmingProgressReset,
            titleVisibility: .visible
        ) {
            Button("Reset everything", role: .destructive) {
                appModel.experiments.resetAll()
            }
            Button("Keep my progress", role: .cancel) {}
        } message: {
            Text("Every completion mark and the streak are wiped. "
                 + "The labs themselves are untouched.")
        }
    }

    /// Yaw that swings the arc (built toward −Z) round to the user's
    /// current horizontal look direction: rotating (0, 0, −1) by θ about
    /// Y gives (−sin θ, 0, −cos θ), so θ = atan2(−dx, −dz).
    private func recenter() {
        guard let ray = appModel.room.lookRay else { return }
        appModel.settings.hubYaw = atan2(-Float(ray.direction.x),
                                         -Float(ray.direction.z))
        appModel.settings.layoutVersion += 1
    }

    // MARK: Rows

    @ViewBuilder
    private func section(_ title: String,
                         @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.Panel.rowSpacing) {
            Text(title)
                .font(DesignTokens.TypeScale.sectionHeader)
                .foregroundStyle(.secondary)
            content()
        }
    }

    @ViewBuilder
    private func row(_ label: String,
                     @ViewBuilder control: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(DesignTokens.TypeScale.label)
            control()
        }
    }

    /// A slider row with the live value beside its label, so dragging
    /// gives feedback even though the arc only rebuilds on release.
    @ViewBuilder
    private func meterRow(_ label: String, value: Double,
                          @ViewBuilder control: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(label)
                    .font(DesignTokens.TypeScale.label)
                Spacer()
                Text(value, format: .number.precision(.fractionLength(1)))
                    .font(DesignTokens.TypeScale.label)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                + Text(" m")
                    .font(DesignTokens.TypeScale.footnote)
                    .foregroundStyle(.secondary)
            }
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
