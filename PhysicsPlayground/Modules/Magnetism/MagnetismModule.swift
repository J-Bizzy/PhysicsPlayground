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
            adjustables: [
                // The selected magnet's moment, or the first magnet's when
                // nothing is selected: the box always has a magnet to turn.
                .init(id: "moment", label: "Magnet moment", unit: "A·m²",
                      range: MagnetismModel.strengthRange, decimals: 1,
                      read: {
                          let model = appModel.magnetismModel
                          return (model.selectedMagnet ?? model.magnets.first)?.strength ?? 0
                      },
                      write: {
                          let model = appModel.magnetismModel
                          if let target = model.selectedMagnet ?? model.magnets.first {
                              model.setStrength(id: target.id, $0)
                          }
                      }),
            ],
            timeScrub: .init(model: appModel.magnetismModel),
            reset: { appModel.magnetismModel.reset() }
        )
    }
    /// The live numbers the Physics box shows.
    static func readings(appModel: AppModel) -> [Reading] {
        let model = appModel.magnetismModel
        var rows: [Reading] = [
            .init("Magnets", "\(model.magnets.count)"),
            .init("|B| at center",
                  PhysicsFormat.metric(model.centerFieldMilliTesla / 1000, "T",
                                       decimals: 2)),
            .init("Magnets move", PhysicsFormat.state(model.dynamicsOn)),
        ]
        if let selected = model.selectedMagnet {
            rows.append(.init("Selected moment",
                              PhysicsFormat.fixed(selected.strength, decimals: 3), "A·m²"))
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
                                  PhysicsFormat.scientific(energy), "J"))
            }
        }
        return rows
    }

}
