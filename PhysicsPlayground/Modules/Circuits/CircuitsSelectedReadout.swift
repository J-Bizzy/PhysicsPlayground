//
//  CircuitsSelectedReadout.swift
//  Physics Playground — Circuits module
//
//  What the selected part is doing, floating above the part itself. The
//  card's anchor (`CircuitsRenderer.selectedAnchor`) hangs under
//  `viewRoot` and is counter-scaled against the zoom there.
//
//  Volts/amps/watts are re-solved every frame and rasterised into a
//  texture, so they are rounded to the precision they display at.
//

import SwiftUI

struct CircuitsSelectedReadout: View {
    @Environment(CircuitsModel.self) private var model

    var body: some View {
        if let component = model.selectedComponent {
            VStack(alignment: .leading, spacing: 4) {
                Text(component.kind.displayName)
                    .font(DesignTokens.TypeScale.sectionHeader)

                if let readout = model.readouts[component.id] {
                    let volts = (abs(readout.volts) * 100).rounded() / 100
                    let milliamps = (abs(readout.amps) * 1000 * 10).rounded() / 10
                    let watts = (abs(readout.watts) * 100).rounded() / 100
                    Text("\(PhysicsFormat.measurement(volts, "V", decimals: 2))   "
                         + PhysicsFormat.measurement(milliamps, "mA", decimals: 1))
                        .font(DesignTokens.TypeScale.footnote.monospacedDigit())
                    Text(PhysicsFormat.measurement(watts, "W", decimals: 2))
                        .font(DesignTokens.TypeScale.footnote.monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                if component.kind == .capacitor {
                    let charge = (component.capacitorVoltage * 100).rounded() / 100
                    Text("charged to \(PhysicsFormat.measurement(charge, "V", decimals: 2))")
                        .font(DesignTokens.TypeScale.footnote.monospacedDigit())
                        .foregroundStyle(DesignTokens.Palette.circuitsAccent)
                }

                // The coil the inductance implies; the field layer draws its field, so
                // the card names it.
                if component.kind == .inductor {
                    let turns = CircuitsModel.inductorTurns(henries: component.value)
                    Text("≈\(turns.formatted()) turns · air core")
                        .font(DesignTokens.TypeScale.footnote.monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                // A rated part says how hard it is working, or that it is done.
                if let rating = CircuitsModel.powerRating(for: component.kind) {
                    if component.failed {
                        Label("scorched — replace it", systemImage: "flame.fill")
                            .font(DesignTokens.TypeScale.footnote)
                            .foregroundStyle(.red)
                    } else {
                        let load = (abs(model.dissipation(id: component.id)) * 100).rounded() / 100
                        Text("\(PhysicsFormat.measurement(load, "W", decimals: 2)) of "
                             + "\(PhysicsFormat.measurement(rating, "W", decimals: 0)) rating")
                            .font(DesignTokens.TypeScale.footnote.monospacedDigit())
                            .foregroundStyle(load > rating ? .red : .secondary)
                    }
                }

                if component.kind == .acSource {
                    let hertz = (component.acFrequency * 10).rounded() / 10
                    Text(PhysicsFormat.measurement(hertz, "Hz", decimals: 1))
                        .font(DesignTokens.TypeScale.footnote.monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                // A battery past `overloadAmps` is a short — say so.
                if component.kind == .battery,
                   abs(model.readouts[component.id]?.amps ?? 0) > CircuitsModel.overloadAmps {
                    Label("short circuit", systemImage: "exclamationmark.triangle.fill")
                        .font(DesignTokens.TypeScale.footnote)
                        .foregroundStyle(.red)
                }
            }
            .readoutCard()
            .accessibilityElement(children: .combine)
        }
    }
}
