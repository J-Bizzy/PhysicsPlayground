//
//  SettingsView.swift
//  Physics Playground — Shell
//
//  The settings window: the first real UI over AppSettings. Every row
//  here obeys AppSettings' own rule — it does something the moment it
//  is flipped. Volume and room tone apply instantly; the two resets
//  act once, the destructive one behind a confirm.
//
//  Rows keep LEAVING and the deletions are the point. "Reduce motion"
//  duplicated a system accessibility switch the hub reads directly
//  (2026-07-31). "Home title" offered five typographic voices for a
//  decision already made. And the whole "Gallery" section — distance
//  and height sliders plus Recenter — went on 2026-08-03: repositioning
//  by rebuild DUPLICATED the gallery, and the replacement is spatial,
//  where it belongs — a grab bar under the gallery itself, remembered
//  across launches (`GalleryPlacement`). A settings screen is not a
//  museum of every choice the project ever weighed.
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

                PanelSection("Sound") {
                    row("Effects volume") {
                        Slider(value: $settings.masterVolume, in: 0...1)
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
                            + "around any moment. Off by default; it costs a "
                            + "few megabytes per lab while it runs.")
                }

                PanelSection("Onboarding") {
                    Button("Show hints again") {
                        settings.resetOnboardingTips()
                    }
                    .buttonStyle(.podQuiet)
                    caption("Every module's first-run hint appears once more.")
                }

                PanelSection("Progress") {
                    Button("Reset experiment progress…", role: .destructive) {
                        confirmingProgressReset = true
                    }
                    .buttonStyle(.podQuiet)
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
