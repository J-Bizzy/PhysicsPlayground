//
//  ElectromagnetismModule.swift
//  Physics Playground — Electromagnetism module
//
//  Catalog registration for Electric Fields: descriptor, readings and legend.
//

import SwiftUI
import PhysicsCore
import simd

@MainActor
enum ElectromagnetismModule {
    // Keys this bench's notebook history.
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
            legend: legendItems,
            isPaused: { appModel.electromagnetismModel.isPaused },
            togglePause: { appModel.electromagnetismModel.togglePauseRespectingScrub() },
            makeScene: {
                AnyView(FieldSpaceView().environment(appModel.electromagnetismModel))
            },
            captureReadings: { readings(appModel: appModel) },
            physicsNote: {
                // 50 kT is a stage light, not a measurement — about a thousand
                // times the strongest steady field ever built, needed to bend a
                // 0.5 g ball visibly. The circle r = mv/qB is exact regardless.
                appModel.electromagnetismModel.magneticFieldOn
                    ? "B is fictional at this strength; the circle r = mv/qB is exact."
                    : nil
            },
            adjustables: adjustables(appModel: appModel),
            timeScrub: .init(model: appModel.electromagnetismModel),
            reset: { appModel.electromagnetismModel.reset() }
        )
    }

    /// The two numbers the Physics box can turn: the plates' voltage and
    /// the uniform B. The test charge's q stays on the probe's own ring.
    static func adjustables(appModel: AppModel) -> [PhysicsAdjustable] {
        let model = appModel.electromagnetismModel
        // The box works in kV, kT and nC; the model in V, T and C.
        func scaled(_ range: ClosedRange<Double>, by factor: Double) -> ClosedRange<Double> {
            (range.lowerBound * factor)...(range.upperBound * factor)
        }
        return [
            .init(id: "plateVoltage", label: "Plate voltage ΔV", unit: "kV",
                  range: scaled(FieldModel.plateVoltageRange, by: 1e-3), decimals: 1,
                  read: { model.plateVoltage / 1000 },
                  write: { model.setPlateVoltage($0 * 1000) }),
            .init(id: "uniformB", label: "Uniform field B", unit: "kT",
                  range: scaled(FieldModel.magneticFieldRange, by: 1e-3), decimals: 0,
                  read: { model.magneticFieldTesla / 1000 },
                  write: { model.magneticFieldTesla = $0 * 1000 }),
        ]
    }

    /// The readings this bench writes into the lab notebook.
    static func readings(appModel: AppModel) -> [NotebookEntry.Reading] {
        let model = appModel.electromagnetismModel
        var rows: [NotebookEntry.Reading] = [
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
        if model.capacitorOn {
            rows.append(.init("Plate voltage",
                              PhysicsFormat.metric(model.plateVoltage, "V", decimals: 1)))
            rows.append(.init("Plate gap",
                              PhysicsFormat.fixed(model.plateSeparation, decimals: 3), "m"))
            rows.append(.init("E between plates",
                PhysicsFormat.metric(model.plateVoltage / model.plateSeparation,
                                     "V/m", decimals: 1)))
        }
        if model.magneticFieldOn {
            rows.append(.init("B", PhysicsFormat.metric(
                model.magneticFieldTesla, "T", decimals: 2)))
            rows.append(.init("Cyclotron radius",
                              PhysicsFormat.fixed(model.cyclotronRadius, decimals: 3), "m"))
        }
        return rows
    }

    static let legendItems: [LegendItem] = [
        LegendItem(
            swatch: .fill(DesignTokens.Palette.positive),
            text: "Positive charge"
        ),
        LegendItem(
            swatch: .fill(DesignTokens.Palette.negative),
            text: "Negative charge"
        ),
        LegendItem(
            swatch: .fill(DesignTokens.Palette.probePositive),
            text: "Positive test charge (accelerates via F = qE)"
        ),
        LegendItem(
            swatch: .fill(DesignTokens.Palette.probeNegative),
            text: "Negative test charge"
        ),
        LegendItem(
            swatch: .line(DesignTokens.Palette.fieldLine),
            text: "Field lines run from positive to negative"
        ),
        LegendItem(
            swatch: .stroke(DesignTokens.Palette.selectionHalo),
            text: "Halo marks the selected charge"
        ),
        LegendItem(
            swatch: .symbol("arrow.up.right", DesignTokens.Palette.fieldLine),
            text: "Arrowheads ride the field lines, pointing along E"
        ),
        // A disclosed fudge: `chargesRespond` moves source charges by an
        // overdamped mobility law (velocity ∝ force, capped), not F = ma. The
        // field, force and potential are exact Coulomb; only the travel is.
        LegendItem(
            swatch: .symbol("arrow.left.and.right", DesignTokens.Palette.fieldLine),
            text: "Free charges DRIFT rather than accelerate: with the switch on, a charge's speed is set by the force on it instead of its acceleration, so the flock slides into place and settles rather than overshooting and oscillating. The field, the force and the potential are exact Coulomb; only the travel is a simplification, chosen so a pair you release finds equilibrium in front of you instead of ringing about it forever."
        ),
    ]
}
