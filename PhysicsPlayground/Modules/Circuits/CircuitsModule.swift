//
//  CircuitsModule.swift
//  Physics Playground — Circuit bench
//
//  What the circuit bench contributes to the catalog: its legend and
//  its notebook readings.
//
//  This is NOT a catalog entry any more. The workshop is the left-hand
//  station of the merged E&M world (EMWorldModule) rather than a module
//  of its own — its inductor current has always driven the magnet
//  bench's electromagnet, and that link was unwatchable while the two
//  benches were in different rooms. The bench's model, renderer, panel,
//  and physics are all unchanged; only its front door moved.
//

import SwiftUI
import PhysicsCore

@MainActor
enum CircuitsModule {
    /// The readings this bench writes into the lab notebook.
    /// Shared with the combined module that now hosts it.
    static func readings(appModel: AppModel) -> [NotebookEntry.Reading] {
        let model = appModel.circuitsModel
        var rows: [NotebookEntry.Reading] = [
            .init("Components", "\(model.components.count)"),
            .init("Wires", "\(model.wires.count)"),
        ]
        for component in model.components {
            guard let readout = model.readouts[component.id] else { continue }
            let name = component.kind.displayName
            rows.append(.init("\(name) current",
                              String(format: "%.4f", readout.amps), "A"))
            rows.append(.init("\(name) voltage",
                              String(format: "%.3f", readout.volts), "V"))
            rows.append(.init("\(name) power",
                              String(format: "%.4f", readout.watts), "W"))
        }
        return rows
    }

    /// The bench's full legend. The merged world curates its own
    /// shorter key from this and the magnet bench's; this stays as the
    /// complete one, and is what the bench would show if it ever
    /// stands alone again.
    static let legend: [LegendItem] = [
        LegendItem(
            swatch: .fill(Color(uiColor: DesignTokens.Palette.copperUI)),
            text: "Copper terminals — pinch one, then another, to wire them; pinch a wire to remove it"
        ),
        LegendItem(
            swatch: .fill(Color(uiColor: DesignTokens.Palette.electronUI)),
            text: "Electrons — they drift − to +, opposite the conventional current arrow, faster where the current is larger"
        ),
        LegendItem(
            swatch: .fill(.yellow),
            text: "Bulb glow = true power dissipated (P = I²R) — dim it by adding resistance"
        ),
        LegendItem(
            swatch: .line(Color(uiColor: DesignTokens.Palette.copperUI)),
            text: "Resistor bands show the real 4-band color code and repaint as you adjust the value"
        ),
        LegendItem(
            swatch: .symbol("bolt.badge.clock", DesignTokens.Palette.circuitsAccent),
            text: "Capacitors charge in real time — watch a bulb fade as its capacitor fills (τ = RC)"
        ),
    ]
}
