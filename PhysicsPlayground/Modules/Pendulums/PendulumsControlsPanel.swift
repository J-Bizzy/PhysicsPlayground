//
//  PendulumsControlsPanel.swift
//  Physics Playground — Pendulums module
//
//  The module's one-glance panel — and as of this pass it holds no
//  slider, no picker and no toggle. It makes pendulums, it runs the
//  clock's stop button, and otherwise it READS.
//
//  What left, and where each thing went:
//  · The three worlds → a standing bank of discs beside the rig, which
//    is also the readout for which world you are on.
//  · g → a rail under that bank. Neither the worlds nor g had any
//    physical extent to grab: in this module the extent belongs to the
//    CABLE (the length bead) and the BOB (the mass petal), and both were
//    already grips on the object itself.
//  · Air resistance and the four display layers → one five-plate switch
//    bank on the other side of the swing.
//  · Time → a rail under the worlds.
//
//  Per-BOB editing (length bead, mass petal, delete) lives on the bob:
//  tap it and its ring unfolds.
//

import PhysicsCore
import SwiftUI

struct PendulumsControlsPanel: View {
    @Environment(PendulumsModel.self) private var model

    /// `PhysicsCore.SurfaceGravity` — shared with Projectiles, which had
    /// its own copy of these numbers. Real bodies only: a pendulum in
    /// zero-g does not swing, so there is no period to show.
    private static let worlds = SurfaceGravity.bodies

    var body: some View {
        @Bindable var model = model

        VStack(spacing: DesignTokens.Panel.sectionSpacing) {
            PanelSection("Pendulums") {
                HStack(spacing: 12) {
                    Button {
                        self.model.addPendulum()
                    } label: {
                        Label("Add pendulum", systemImage: "plus.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.podProminent)
                    .disabled(self.model.pendulums.count >= PendulumsModel.pendulumBudget)

                    Button("Resonance ×5") {
                        self.model.loadResonancePreset()
                    }
                    .buttonStyle(.podQuiet)
                    .accessibilityHint("Five lengths, five periods — watch them drift apart and realign")
                }

                Text(worldText)
                    .font(DesignTokens.TypeScale.footnote.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Text("Tap a bob for its own controls — pull the bead to pay out cable, petals cycle its mass or delete it.")
                    .font(DesignTokens.TypeScale.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            CollapsedSection("The room") {
                Text("Worlds and g are a bank of discs and a rail to the "
                     + "right of the rig; what is drawn — and whether the "
                     + "air is real — is the switch bank to the left.")
                    .font(DesignTokens.TypeScale.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if !self.model.insightText.isEmpty {
                    Text(self.model.insightText)
                        .font(DesignTokens.TypeScale.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                // The trail-length picker was deleted rather than moved
                // (DECISIONS.md, 2026-07-29): a trail length is a
                // preference, not a physical quantity, and short is the
                // one that shows a swing's shape without painting over
                // the bob. `trailMode` stays on the model at that default.
            }

            CollapsedSection("Numbers") {
                PendulumInfoCard()
                Text("The selected bob — tap one to read it here.")
                    .font(DesignTokens.TypeScale.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// g, and the world it matches if it matches one. The bank beside the
    /// rig lights the same disc from the same comparison — this is the
    /// number behind that lamp, not a second opinion about it.
    private var worldText: String {
        let g = String(format: "%.2f m/s²", model.gravity)
        guard let world = Self.worlds
            .first(where: { abs($0.gravity - model.gravity) < 0.01 }) else {
            return "g = \(g) — between worlds"
        }
        return "g = \(g) — \(world.name)"
    }
}
