//
//  FieldControlsPanel.swift
//  Physics Playground — Electromagnetism module
//
//  The module's flat panel, and — since 2026-07-31 — a READOUT rather than
//  a control surface. There is no `Slider`, `Picker` or `Toggle` here, and
//  there is not meant to be one again.
//
//  What happened: this panel held seven toggles, six sliders and two
//  pickers in six stacked disclosure cards, two of which contained no
//  controls at all. Everything the module could do was buried in twisties —
//  the capacitor's voltage three levels down, a mode switch silently
//  swapping one slider for another behind a single label. That is the exact
//  condition the interaction law was written against (DECISIONS.md,
//  2026-07-29): "a quantity with physical extent is changed by changing
//  that extent; a quantity without extent is a discrete choice and gets a
//  labelled object in the room."
//
//  So every setting moved into the room — a layers bank for what exists,
//  wells for what you make, rails for the continuous quantities, and the
//  flux meter's own size and facing became the act of grabbing its edge.
//  See `FieldSpaceView` for the instruments and `FieldInstrumentLayout`
//  for where they stand.
//
//  What did NOT move, and why the panel survives: the numbers. The law
//  governs how a quantity is CHANGED and says nothing about how one is
//  shown, and a number you read wants to hold still and be legible — which
//  is what a flat card is good at. The lab notebook is flat for the same
//  reason and nobody thinks it should be a dial.
//
//  One button stays too. `Clear` is a bulk destructive action with no
//  honest physical analogue; "drag every charge back into the well" would
//  be cleverness, not clarity. Buttons were never what the exit criterion
//  banned.
//

import PhysicsCore
import SwiftUI

struct FieldControlsPanel: View {
    @Environment(FieldModel.self) private var model

    var body: some View {
        VStack(spacing: DesignTokens.Panel.sectionSpacing) {
            PanelSection("Charges") {
                chargeControls
            }
            CollapsedSection("Numbers") {
                PhysicsStatsView()
                apparatusReadouts
            }
        }
    }

    // MARK: Charges — one button, and directions to the room

    @ViewBuilder
    private var chargeControls: some View {
        Button(role: .destructive) {
            model.removeAllCharges()
        } label: {
            Label("Clear the field", systemImage: "trash.slash")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.podQuiet)
        .disabled(model.charges.isEmpty)
        .accessibilityLabel("Remove all charges")

        Text("""
             Everything else is in the room. Pull a charge out of the wells \
             on your right — it is in your hand the moment it exists. Tap one \
             for its own ring: pull the bead for strength, the petal to \
             delete. The switches on your left decide what exists at all.
             """)
            .font(DesignTokens.TypeScale.footnote)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

        Text(statusLine)
            .font(DesignTokens.TypeScale.footnote)
            .foregroundStyle(.secondary)
    }

    private var statusLine: String {
        let count = model.charges.count
        guard count > 0 else { return "No charges — pull one out of a well to see a field." }
        let selected = model.selectedCharge.map {
            "the halo marks the \($0.isPositive ? "red" : "blue") one you tapped"
        }
        return "\(count) charge\(count == 1 ? "" : "s") in the field\(selected.map { " — \($0)" } ?? "")."
    }

    // MARK: The apparatus, as numbers
    //
    // Each block appears only while its apparatus is standing, so the card
    // reports what is actually in the room rather than listing everything
    // the module could do.

    @ViewBuilder
    private var apparatusReadouts: some View {
        if model.capacitorOn {
            Divider().opacity(0.4)
            Text("ΔV \(model.plateVoltage / 1000, specifier: "%.0f") kV   E = V/d = \(model.plateVoltage / model.plateSeparation / 1000, specifier: "%.1f") kV/m   d = \(model.plateSeparation * 100, specifier: "%.0f") cm")
                .font(DesignTokens.TypeScale.footnote.monospacedDigit())
            Text("Uniform field in the gap. The rail under the plates sets ΔV; grabbing a plate sets d.")
                .font(DesignTokens.TypeScale.footnote)
                .foregroundStyle(.secondary)
        }

        if model.magneticFieldOn {
            Divider().opacity(0.4)
            if model.electronMode {
                Text("B \(model.electronFieldTesla * 1000, specifier: "%.2f") mT   r = mv/qB = \(model.cyclotronRadius * 100, specifier: "%.0f") cm")
                    .font(DesignTokens.TypeScale.footnote.monospacedDigit())
                // Disclosed where it is READ. The display clock is the
                // fiction here, and the physics is not.
                Text("A real electron at 2×10⁶ m/s: a tenth of a millitesla bends an 11 cm circle. Display time runs 10⁷× slow; the physics is SI-exact.")
                    .font(DesignTokens.TypeScale.footnote)
                    .foregroundStyle(.secondary)
            } else {
                Text("B \(model.magneticFieldTesla / 1000, specifier: "%.0f") kT   r = mv/qB = \(model.cyclotronRadius * 100, specifier: "%.0f") cm")
                    .font(DesignTokens.TypeScale.footnote.monospacedDigit())
                // This number is a stage light, not a measurement, and it
                // has to say so where it is READ. It used to live under the
                // slider that set it; the slider became a rail in the room,
                // and the disclosure followed the NUMBER rather than the
                // control, because that is who it is addressed to. A
                // migration that quietly dropped it would have turned a
                // disclosed fiction into an undisclosed one.
                //
                // 50 kT is about a thousand times the strongest steady
                // field ever built on Earth; it takes that much to visibly
                // bend a 0.5 g, 10 nC ball, because q/m is ~10¹¹ smaller
                // than an electron's. The geometry stays exact either way.
                Text("That field is fictional — about a thousand times the strongest magnet ever built. A 0.5 g ball needs it to curve at all. The circle r = mv/qB is exact regardless; pick the electron on the particle bank for a real particle in a real field.")
                    .font(DesignTokens.TypeScale.footnote)
                    .foregroundStyle(.secondary)
            }
        }

        if model.gaussSurfaceOn {
            Divider().opacity(0.4)
            GaussReadout()
        }
    }
}

/// Gauss's law, as numbers beside the surface that is measuring them.
///
/// A page can state ∮E·dA = Q/ε₀; it cannot let you move the surface. The
/// closed bubble is the demonstration — put a charge inside and the flux
/// jumps to exactly Q/ε₀, take it out and it drops to zero — and the open
/// disc is the contrast that makes it mean something, because its flux
/// depends entirely on how it is turned.
///
/// Both used to be set from here (a segmented picker, a radius slider).
/// They are the surface itself now: grab its edge to resize it, and swing
/// your hand out of the disc's plane to tilt it. That last gesture is new,
/// and it is worth knowing that the sentence below has been printed in this
/// panel since the disc was written while NOTHING in the app could tilt it —
/// `gaussSurfaceNormal` had two writers, its declaration and `reset()`.
struct GaussReadout: View {
    @Environment(FieldModel.self) private var model

    var body: some View {
        if let enclosed = model.gaussEnclosedCharge,
           let predicted = model.gaussPredictedFlux {
            VStack(alignment: .leading, spacing: 3) {
                Text("Φ measured  \(PhysicsFormat.scientific(model.gaussFlux)) N·m²/C")
                Text("Q enclosed  \(PhysicsFormat.scientific(enclosed)) C")
                Text("Q/ε₀        \(PhysicsFormat.scientific(predicted)) N·m²/C")
            }
            .font(DesignTokens.TypeScale.footnote.monospaced())
            Text("Closed surface: the flux is the enclosed charge over ε₀ and nothing else. Carry the bubble anywhere, turn it however you like — outside charges contribute exactly zero.")
                .font(DesignTokens.TypeScale.footnote)
                .foregroundStyle(.secondary)
        } else {
            Text("Φ  \(PhysicsFormat.scientific(model.gaussFlux)) N·m²/C")
                .font(DesignTokens.TypeScale.footnote.monospaced())
            Text("Open surface: grab the disc's rim and turn it edge-on to the field, and the flux falls to zero. Cycle it to the bubble for Gauss's law.")
                .font(DesignTokens.TypeScale.footnote)
                .foregroundStyle(.secondary)
        }
    }
}
