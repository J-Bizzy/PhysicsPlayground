//
//  FieldReadoutCard.swift
//  Physics Playground — Electric Fields module
//
//  Everything this module measures, on one card standing with the
//  instruments instead of behind a dropdown called "Numbers".
//
//  It carries two things that used to be separate places in the window
//  panel: the probe's live physics (`PhysicsStatsView`), and the
//  apparatus readouts that appear only while their apparatus is
//  standing.
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
//  part of this file. The 50 kT paragraph is not commentary — DECISIONS
//  2026-07-31 says a migration that drops it "turns a disclosed fiction
//  into an undisclosed one". It travels with the value it qualifies,
//  because that is who it is addressed to: the person reading the
//  number.
//

import SwiftUI

struct FieldReadoutCard: View {
    @Environment(FieldModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            PhysicsStatsView()
            apparatusReadouts
        }
        .frame(maxWidth: 300, alignment: .leading)
        // THICK, not regular, and the ONE card that departs from the
        // house default. A screenshot with the field lines switched on
        // showed why: this card stands in a room whose physics is drawn
        // as bright translucent filaments, and a regular-material panel
        // behind them washed out to the point where the 50 kT
        // disclosure — the paragraph that must be read — was the least
        // legible text on screen.
        .readoutCard(material: .thickMaterial)
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
            Text("That field is fictional — about a thousand times the strongest magnet ever built. A 0.5 g ball needs it to curve at all. The circle r = mv/qB is exact regardless.")
                .font(DesignTokens.TypeScale.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
