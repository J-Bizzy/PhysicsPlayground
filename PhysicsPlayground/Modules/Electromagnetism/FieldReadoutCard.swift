//
//  FieldReadoutCard.swift
//  Physics Playground — Electric Fields module
//
//  Everything this module measures, on one card standing with the
//  instruments instead of behind a dropdown called "Numbers".
//
//  It carries three things that used to be three separate places in the
//  window panel: the probe's live physics (`PhysicsStatsView`), the
//  apparatus readouts that appear only while their apparatus is standing,
//  and `GaussReadout`.
//
//  WHY THIS ONE IS NOT IN `FieldInstrumentLayout`, when every other piece
//  of furniture in this module is. Those invariants exist for a specific
//  reason, stated at the top of that file: an instrument carries an
//  input-targetable collider, and a collider near the physics can shield
//  a charge from a pinch — which is how this module was broken once
//  (`SpatialScaleHandle`, DECISIONS 2026-07-29). This card carries
//  `.allowsHitTesting(false)`: it is not an input target, it cannot
//  contend for a pinch, and the 0.12 m proximity margin it would be
//  measured against is `resolveCharge`'s fallback radius — a rule about
//  grabbing, which is not a thing you can do to this. What it needs is a
//  clear SIGHTLINE, not clearance, so it stands above the layers bank on
//  the left flank where nothing is drawn and nothing is grabbed.
//
//  THE DISCLOSURES COME WITH THE NUMBERS, and that is the load-bearing
//  part of this file. The 50 kT paragraph and the electron-clock
//  paragraph are not commentary — DECISIONS 2026-07-31 says a migration
//  that drops them "turns a disclosed fiction into an undisclosed one".
//  They travel with the value they qualify, because that is who they are
//  addressed to: the person reading the number.
//

import SwiftUI

struct FieldReadoutCard: View {
    @Environment(FieldModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            PhysicsStatsView()
            apparatusReadouts
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: 300, alignment: .leading)
        // THICK, not regular. A screenshot with the field lines
        // switched on showed why: this card stands in a room whose
        // physics is drawn as bright translucent filaments, and a
        // regular-material panel behind them washed out to the point
        // where the 50 kT disclosure — the paragraph that must be read —
        // was the least legible text on screen.
        .background(.thickMaterial,
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    /// Each block appears only while its apparatus is standing, so the
    /// card reports what is actually in the room rather than listing
    /// everything the module could do.
    @ViewBuilder
    private var apparatusReadouts: some View {
        if model.capacitorOn {
            Divider().opacity(0.4)
            let kilovolts = (model.plateVoltage / 1000).rounded()
            let gradient = ((model.plateVoltage / model.plateSeparation / 1000)
                            * 10).rounded() / 10
            let centimetres = (model.plateSeparation * 100).rounded()
            Text(String(format: "ΔV %.0f kV   E = V/d = %.1f kV/m   d = %.0f cm",
                        kilovolts, gradient, centimetres))
                .font(DesignTokens.TypeScale.footnote.monospacedDigit())
            Text("Uniform field in the gap. The rail under the plates sets ΔV; grabbing a plate sets d.")
                .font(DesignTokens.TypeScale.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }

        if model.magneticFieldOn {
            Divider().opacity(0.4)
            let radius = (model.cyclotronRadius * 100).rounded()
            if model.electronMode {
                let millitesla = (model.electronFieldTesla * 1000 * 100).rounded() / 100
                Text(String(format: "B %.2f mT   r = mv/qB = %.0f cm",
                            millitesla, radius))
                    .font(DesignTokens.TypeScale.footnote.monospacedDigit())
                // Disclosed where it is READ. The display clock is the
                // fiction here, and the physics is not.
                Text("A real electron at 2×10⁶ m/s: a tenth of a millitesla bends an 11 cm circle. Display time runs 10⁷× slow; the physics is SI-exact.")
                    .font(DesignTokens.TypeScale.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                let kilotesla = (model.magneticFieldTesla / 1000).rounded()
                Text(String(format: "B %.0f kT   r = mv/qB = %.0f cm",
                            kilotesla, radius))
                    .font(DesignTokens.TypeScale.footnote.monospacedDigit())
                // This number is a stage light, not a measurement, and it
                // has to say so where it is READ. It followed the NUMBER
                // out of the panel rather than the control, for the same
                // reason it once followed the number out from under the
                // slider that set it.
                //
                // 50 kT is about a thousand times the strongest steady
                // field ever built on Earth; it takes that much to visibly
                // bend a 0.5 g, 10 nC ball, because q/m is ~10¹¹ smaller
                // than an electron's. The geometry stays exact either way.
                Text("That field is fictional — about a thousand times the strongest magnet ever built. A 0.5 g ball needs it to curve at all. The circle r = mv/qB is exact regardless; pick the electron on the particle bank for a real particle in a real field.")
                    .font(DesignTokens.TypeScale.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
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
            // "Cycle it to the bubble" named a gesture that did not
            // exist — the kind had no control at all until the bank got
            // its "Open disc" plate on 2026-08-03. This is the third
            // time this module's copy has described an interaction it
            // did not have, after the tilt itself and the un-tiltable
            // disc; the rule that keeps catching it is to read the prose
            // next to the code.
            Text("Open surface: grab the disc's rim and turn it edge-on to the field, and the flux falls to zero. Switch Open disc off for the bubble, and Gauss's law.")
                .font(DesignTokens.TypeScale.footnote)
                .foregroundStyle(.secondary)
        }
    }
}
