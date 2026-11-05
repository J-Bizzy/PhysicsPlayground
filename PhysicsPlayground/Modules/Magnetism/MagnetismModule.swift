//
//  MagnetismModule.swift
//  Physics Playground — Magnetism bench
//
//  Catalog entry and live readings. Bar magnets whose
//  looping field fills the room in 3D.
//

import SwiftUI
import PhysicsCore
import simd

@MainActor
enum MagnetismModule {
    static let id = "magnetism"

    static func descriptor(appModel: AppModel) -> ModuleDescriptor {
        ModuleDescriptor(
            id: id,
            title: "Magnetism",
            icon: "cylinder.fill",
            accent: DesignTokens.Palette.magnetismAccent,
            // Opens part-dimmed: the looping lines are the module.
            preferredDimming: 0.35,
            isPaused: { appModel.magnetismModel.isPaused },
            togglePause: { appModel.magnetismModel.togglePauseRespectingScrub() },
            makeScene: {
                AnyView(MagnetismSpaceView().environment(appModel.magnetismModel))
            },
            readings: { readings(appModel: appModel) },
            more: more(appModel.magnetismModel),
            timeScrub: .init(model: appModel.magnetismModel),
            reset: { appModel.magnetismModel.reset() }
        )
    }
    /// What More holds for the bench: whether the magnets are free, and
    /// what is drawn. A magnet's strength is drawn out of its own north
    /// pole, so it has no slider here.
    static func more(_ model: MagnetismModel) -> [MoreItem] {
        [
            // Not a display layer, and the title says what it does.
            .toggle(id: "dynamics", title: "Magnets move", symbol: "arrow.triangle.merge",
                    isOn: { model.dynamicsOn }, set: { model.dynamicsOn = $0 }),
            .toggle(id: "lines", title: "Field lines", symbol: "scribble",
                    isOn: { model.showFieldLines }, set: { model.showFieldLines = $0 }),
            // Whether the room stands on a planet. Only the compass reads it,
            // so it stands under the compass, and only while the compass is on.
            .group(lead: .toggle(id: "handCompass", title: "Hand compass",
                                 symbol: "location.north.circle",
                                 isOn: { model.compassOn }, set: { model.compassOn = $0 }),
                   reveals: { model.compassOn },
                   items: [
                       .toggle(id: "earth", title: "Earth's field", symbol: "globe",
                               isOn: { model.earthFieldOn }, set: { model.earthFieldOn = $0 }),
                   ]),
        ]
    }

    /// The live numbers More shows.
    static func readings(appModel: AppModel) -> [Reading] {
        let model = appModel.magnetismModel
        var rows: [Reading] = [
            .init("Magnets", "\(model.magnets.count)"),
            .init("|B| at center",
                  PhysicsFormat.metric(model.centerFieldMilliTesla / 1000, "T",
                                       decimals: 2),
                  formula: "B = Σ (μ₀/4π)(3(m·r̂)r̂ − m)/r³"),
        ]
        if let selected = model.selectedMagnet {
            // At the bead's tenth: three decimals here said the same magnet
            // was 6.000 in More and 6.0 on its own track.
            rows.append(.init("Selected moment",
                              PhysicsFormat.fixed(selected.strength, decimals: 1), "A·m²"))
            let others = model.magnets.filter { $0.id != selected.id }
            if !others.isEmpty {
                // Point dipole, matching the dynamics; see `MagnetismModel.step`.
                let force = MagneticField.netForce(on: selected, from: others)
                rows.append(.init("Force on it",
                                  PhysicsFormat.scientific(simd_length(force)), "N"))
                // U = −m·B summed over the other dipoles.
                let energy = others.reduce(0.0) {
                    $0 + MagneticField.potentialEnergy(of: selected, in: $1)
                }
                rows.append(.init("Potential energy",
                                  PhysicsFormat.scientific(energy), "J",
                                  formula: "U = −m·B"))
            }
        }
        if let coil = model.selectedCoil {
            // Faraday's law, as the numbers it relates: the linkage, how fast
            // it is changing, and what that drives through the LED.
            let winding = MagnetismModel.pickupCoil(coil)
            let wire = Double(winding.turns) * 2 * .pi * winding.radius
            rows.append(.init("Coil turns", coil.turns.formatted()))
            rows.append(.init("Flux linkage", PhysicsFormat.fixed(coil.linkage * 1000, decimals: 2), "mWb",
                              formula: "Λ = NΦ = N∮A·dl"))
            rows.append(.init("EMF", PhysicsFormat.fixed(coil.emf, decimals: 2), "V",
                              formula: "ε = −dΛ/dt"))
            rows.append(.init("LED current", PhysicsFormat.fixed(coil.current * 1000, decimals: 2), "mA",
                              formula: "ε = IR + V_{LED}(I)"))
            let gauge = PhysicsFormat.fixed(winding.wireDiameter * 1000, decimals: 2)
            rows.append(.init("Winding resistance", PhysicsFormat.fixed(winding.resistance, decimals: 0), "Ω",
                              formula: "R = ρL/A, L = \(PhysicsFormat.fixed(wire, decimals: 0)) m of \(gauge) mm copper"))
        }
        return rows
    }

}
