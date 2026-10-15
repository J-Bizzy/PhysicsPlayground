//
//  ElectromagnetismModule.swift
//  Physics Playground — Electromagnetism module
//
//  Catalog registration for Electric Fields: descriptor and readings.
//

import SwiftUI
import PhysicsCore
import simd

@MainActor
enum ElectromagnetismModule {
    // The module's identity in the catalog.
    static let id = "electrostatics"

    static func descriptor(appModel: AppModel) -> ModuleDescriptor {
        ModuleDescriptor(
            id: id,
            title: "Electric Fields",
            shortTitle: "Fields",
            icon: "bolt.fill",
            accent: DesignTokens.Palette.electrostaticsAccent,
            // Opens part-dimmed: field lines are thin glowing filaments —
            // they need something to glow against.
            preferredDimming: 0.35,
            isPaused: { appModel.electromagnetismModel.isPaused },
            togglePause: { appModel.electromagnetismModel.togglePauseRespectingScrub() },
            makeScene: {
                AnyView(FieldSpaceView().environment(appModel.electromagnetismModel))
            },
            readings: { readings(appModel: appModel) },
            physicsNote: {
                // 50 kT is a stage light, not a measurement — about a thousand
                // times the strongest steady field ever built, needed to bend a
                // 0.5 g ball visibly. The circle r = mv/qB is exact regardless.
                appModel.electromagnetismModel.magneticFieldOn
                    ? "B is fictional at this strength; the circle r = mv/qB is exact."
                    : nil
            },
            more: more(appModel.electromagnetismModel),
            timeScrub: .init(model: appModel.electromagnetismModel),
            reset: { appModel.electromagnetismModel.reset() }
        )
    }

    /// What More holds for the field: what is drawn, how the charges
    /// behave, the two apparatus with their one number each, and Clear.
    /// A dependent control stands under the switch it needs, disabled
    /// until that switch is on.
    static func more(_ model: FieldModel) -> [MoreItem] {
        // More works in kV and kT; the model in V and T.
        func scaled(_ range: ClosedRange<Double>, by factor: Double) -> ClosedRange<Double> {
            (range.lowerBound * factor)...(range.upperBound * factor)
        }
        return [
            .toggle(id: "lines", title: "Field lines", symbol: "scribble",
                    isOn: { model.showLines }, set: { model.showLines = $0 }),
            // Surfaces of equal voltage, everywhere at right angles to the lines.
            .toggle(id: "equipotentials", title: "Equipotentials", symbol: "circle.circle",
                    isOn: { model.showEquipotentials }, set: { model.showEquipotentials = $0 }),
            .toggle(id: "free", title: "Free charges", symbol: "arrow.left.and.right",
                    isOn: { model.chargesRespond }, set: { model.chargesRespond = $0 }),
            // "Capacitor", not "Parallel plates": it names the apparatus.
            .toggle(id: "plates", title: "Capacitor", symbol: "square.split.2x1",
                    isOn: { model.capacitorOn }, set: { model.capacitorOn = $0 }),
            // A voltage has no extent to stretch; the plates' gap does, and
            // that is a drag on a plate.
            .slider(.init(id: "plateVoltage", label: "Plate voltage ΔV", unit: "kV",
                          range: scaled(FieldModel.plateVoltageRange, by: 1e-3), decimals: 1,
                          read: { model.plateVoltage / 1000 },
                          write: { model.setPlateVoltage($0 * 1000) }),
                    isEnabled: { model.capacitorOn }),
            // The CRT demo: the test charge fired crosswise through the gap.
            // It does not confirm: re-firing is the point.
            .action(id: "deflect", title: "Deflect shot", symbol: "arrow.turn.down.right",
                    isEnabled: { model.capacitorOn },
                    run: { model.launchProbeThroughGap() }),
            .toggle(id: "bfield", title: "Uniform B", symbol: "arrow.up",
                    isOn: { model.magneticFieldOn }, set: { model.magneticFieldOn = $0 }),
            .slider(.init(id: "uniformB", label: "Uniform field B", unit: "kT",
                          range: scaled(FieldModel.magneticFieldRange, by: 1e-3), decimals: 0,
                          read: { model.magneticFieldTesla / 1000 },
                          write: { model.magneticFieldTesla = $0 * 1000 }),
                    isEnabled: { model.magneticFieldOn }),
            // Everything placed goes, the test charge included; the switches
            // stay, because a layer is a setting, not a placed object.
            .action(id: "clear", title: "Clear all", symbol: "trash.slash",
                    confirms: true, destructive: true,
                    isEnabled: { !model.charges.isEmpty || model.probe != nil },
                    run: { model.clearEverything() }),
        ]
    }

    /// The live numbers More shows.
    static func readings(appModel: AppModel) -> [Reading] {
        let model = appModel.electromagnetismModel
        var rows: [Reading] = [
            .init("Charges", "\(model.charges.count)"),
            .init("Net charge",
                  PhysicsFormat.scientific(
                    model.charges.reduce(0) { $0 + $1.charge }), "C"),
        ]
        // The test charge's own physics, while one is in the room: the field
        // at it, the potential, the two force terms, and its motion.
        if let readout = model.probeReadout {
            rows.append(.init("Test charge q",
                              "\(model.probeIsPositive ? "+" : "−")"
                              + PhysicsFormat.fixed(model.probeChargeMagnitude * 1e9, decimals: 0),
                              "nC"))
            rows.append(.init("E at charge", PhysicsFormat.scientific(readout.fieldMagnitude), "N/C"))
            rows.append(.init("Potential", PhysicsFormat.scientific(readout.potential), "V"))
            rows.append(.init("Force qE", PhysicsFormat.scientific(readout.electricForce), "N"))
            if model.magneticFieldOn {
                rows.append(.init("Force qv×B", PhysicsFormat.scientific(readout.magneticForce), "N"))
            }
            rows.append(.init("Acceleration", PhysicsFormat.fixed(readout.acceleration), "m/s²"))
            rows.append(.init("Speed", PhysicsFormat.fixed(readout.speed), "m/s"))
        }
        if let selected = model.selectedCharge {
            rows.append(.init("Selected charge",
                              PhysicsFormat.scientific(selected.charge), "C"))
            rows.append(.init("|E| 10 cm away",
                PhysicsFormat.scientific(
                    simd_length(model.fieldVector(
                        at: selected.position + SIMD3(0.1, 0, 0)))), "N/C"))
        }
        // ΔV and B are More's own sliders; E between the plates is the
        // capacitor's callout, measured — V/d here contradicted it, since the
        // real plates fringe.
        if model.showEquipotentials {
            let step = FieldModel.equipotentialLevels(model.charges).step
            if step > 0 {
                rows.append(.init("Equipotentials every ΔV",
                                  PhysicsFormat.fixed(step / 1000, decimals: 0), "kV"))
            }
        }
        if model.capacitorOn {
            rows.append(.init("Plate gap",
                              PhysicsFormat.fixed(model.plateSeparation, decimals: 3), "m"))
        }
        if model.magneticFieldOn {
            rows.append(.init("Cyclotron radius",
                              PhysicsFormat.fixed(model.cyclotronRadius, decimals: 3), "m"))
        }
        return rows
    }

}
