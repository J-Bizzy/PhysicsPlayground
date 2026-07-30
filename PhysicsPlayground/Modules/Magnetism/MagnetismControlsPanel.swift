//
//  MagnetismControlsPanel.swift
//  Physics Playground — Magnetism module
//
//  The module's one-glance panel. The always-open card makes magnets
//  and frees or freezes them; the electromagnet (the live wire to the
//  Circuit Workshop), the display layers, and the compass reading wait
//  behind collapsed sections. Per-MAGNET editing (strength bead, flip
//  poles, delete) lives on the magnet: tap it and its ring unfolds.
//

import SwiftUI

struct MagnetismControlsPanel: View {
    @Environment(MagnetismModel.self) private var model

    var body: some View {
        @Bindable var model = model

        VStack(spacing: DesignTokens.Panel.sectionSpacing) {
            PanelSection("Magnets") {
                HStack(spacing: 12) {
                    Button {
                        self.model.addMagnet()
                    } label: {
                        Label("Add magnet", systemImage: "plus.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.podProminent)
                    .disabled(self.model.magnets.count >= MagnetismModel.magnetBudget)

                    Text("\(self.model.magnets.count) of \(MagnetismModel.magnetBudget)")
                        .font(DesignTokens.TypeScale.label.monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                Toggle("Magnets respond to forces", isOn: $model.dynamicsOn)
                    .font(DesignTokens.TypeScale.control)
                    .accessibilityHint("Free, they glide together head-to-tail and swing to align. Frozen, they hold exactly where you put them.")

                Text("Tap a magnet for its own controls — pull the bead for strength, petals flip its poles or delete it.")
                    .font(DesignTokens.TypeScale.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            CollapsedSection("Electromagnet") {
                Toggle("Electromagnet coil", isOn: $model.electromagnetOn)
                    .font(DesignTokens.TypeScale.control)
                    .accessibilityHint("A coil whose current comes LIVE from the Circuit Workshop bench")
                if self.model.electromagnetOn {
                    Text("Its current is whatever the Circuit Workshop's inductor carries right now. Build a loop over there, open its switch — this coil dies.")
                        .font(DesignTokens.TypeScale.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("moment \(self.model.electromagnetMoment, specifier: "%.2f") A·m²")
                        .font(DesignTokens.TypeScale.footnote.monospacedDigit())
                        .foregroundStyle(DesignTokens.Palette.magnetismAccent)
                }
            }

            CollapsedSection("Display") {
                Toggle("Field lines", isOn: $model.showFieldLines)
                    .font(DesignTokens.TypeScale.control)
                    .accessibilityHint("Closed loops — magnetic lines have no endpoints")
                Toggle("Compass grid", isOn: $model.showCompasses)
                    .font(DesignTokens.TypeScale.control)
                Toggle("Hand compass", isOn: $model.compassOn)
                    .font(DesignTokens.TypeScale.control)
            }

            CollapsedSection("Numbers") {
                Text("Compass reads \(self.model.compassMicroTesla, specifier: "%.1f") µT")
                    .font(DesignTokens.TypeScale.control.monospacedDigit())
                Text("Carry the hand compass through the field — its needle and this number follow B.")
                    .font(DesignTokens.TypeScale.footnote)
                    .foregroundStyle(.secondary)

                // Faraday's law was the only quantity in this app being
                // computed every frame and shown to nobody — ε = −N dΦ/dt
                // reached the user as a filament's brightness and nothing
                // else. Induction is the one law here you cannot infer
                // from a still image, so it needs a number that MOVES.
                if self.model.electromagnetOn {
                    Text("Coil EMF \(self.model.inducedEMF * 1000, specifier: "%.2f") mV")
                        .font(DesignTokens.TypeScale.control.monospacedDigit())
                        .foregroundStyle(DesignTokens.Palette.magnetismAccent)
                    Text("ε = −N dΦ/dt over 400 turns. Hold a magnet still inside the coil and it falls to zero — only *change* induces.")
                        .font(DesignTokens.TypeScale.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("Coil EMF needs the electromagnet — switch it on above, then wave a magnet through it.")
                        .font(DesignTokens.TypeScale.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}
