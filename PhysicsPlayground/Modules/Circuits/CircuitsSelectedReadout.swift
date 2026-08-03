//
//  CircuitsSelectedReadout.swift
//  Physics Playground — Circuits module
//
//  What the selected part is doing, floating above the part itself.
//
//  Moved out of `CircuitsControlsPanel` before that file was deleted —
//  its header called this "the live card floating above the selected
//  component", which was true of nothing: it was rendered inside the
//  panel's "Selected part" dropdown, two taps from a bench you were
//  supposed to be looking at, and `CircuitsRenderer.selectedAnchor` —
//  billboarded, parented, repositioned 14 cm above the selected part
//  every frame — carried nothing at all. The card is where its own
//  documentation always said it was now.
//
//  THE BUTTONS DID NOT COME WITH IT. Replace, Detach and the trash were
//  the other half of this view, and all three already exist as `Bloom`
//  petals on the part's own control ring (`CircuitsSpaceView.syncBloom`)
//  — reachable by tapping the part, which is also how this card appears.
//  Bringing them would have put two copies of one verb a few centimetres
//  apart in the same room. What was left when the duplicates went is a
//  READOUT, which is what the panel was reduced to being anyway.
//
//  THE ANCHOR LIVES UNDER `viewRoot`, which Electron View swells to 4×
//  and a two-handed pinch drives to 8×. A card parented there without
//  compensation is a wall-sized slab the moment you get in among the
//  electrons — the same failure Gravity Lab's rig makes, in a module
//  whose zoom goes further.
//
//  On quantisation: volts, amps and watts are re-solved every frame, and
//  an attachment is rasterised into a texture, so the values are rounded
//  to the precision they are displayed at. See `PendulumInfoCard`.
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
                    Text(String(format: "%.2f V   %.1f mA", volts, milliamps))
                        .font(DesignTokens.TypeScale.footnote.monospacedDigit())
                    Text(String(format: "%.2f W", watts))
                        .font(DesignTokens.TypeScale.footnote.monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                if component.kind == .capacitor {
                    let charge = (component.capacitorVoltage * 100).rounded() / 100
                    Text(String(format: "charged to %.2f V", charge))
                        .font(DesignTokens.TypeScale.footnote.monospacedDigit())
                        .foregroundStyle(DesignTokens.Palette.circuitsAccent)
                }

                // The one warning on this card, and it stays: a battery
                // past `overloadAmps` is a short, and a bench that let
                // you build one without saying so would be teaching the
                // wrong lesson silently.
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
