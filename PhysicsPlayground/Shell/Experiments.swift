//
//  Experiments.swift
//  Physics Playground — Shell
//
//  The experiments layer: every module offers a few outcomes you can
//  only reach by actually doing the physics — no quiz, no text entry,
//  just the simulation noticing what your hands made happen. The
//  window lists them with live checkmarks, completion chimes the first
//  time it lands, and progress persists across launches.
//
//  (Rebuilt from the retired challenges layer, with experiments for
//  every module in the catalog.)
//

import Foundation
import Observation
import PhysicsCore
import RealityKit
import SwiftUI
import simd

struct Experiment: Identifiable {
    let id: String
    let title: String
    let detail: String
}

/// Completed-experiment bookkeeping, persisted across launches.
@MainActor
@Observable
final class ExperimentProgress {
    nonisolated static let key = "experiments.completed.v1"

    private(set) var completed: Set<String>

    init() {
        completed = Set(UserDefaults.standard.stringArray(forKey: Self.key) ?? [])
    }

    /// Marks an experiment done; returns true only the first time.
    @discardableResult
    func complete(_ id: String) -> Bool {
        guard !completed.contains(id) else { return false }
        completed.insert(id)
        UserDefaults.standard.set(completed.sorted(), forKey: Self.key)
        return true
    }
}

/// The experiments per module, each with a live predicate against the
/// module's model. Predicates read state the user genuinely has to
/// produce with their hands.
@MainActor
enum ExperimentCatalog {
    /// Every experiment across every module (for the hub's tally).
    static func total(appModel: AppModel) -> Int {
        ModuleCatalog.all(appModel: appModel)
            .map { experiments(for: $0.id, appModel: appModel).count }
            .reduce(0, +)
    }

    /// How many of the catalog's experiments are done (ignores any
    /// orphaned ids left in storage by retired experiments).
    static func completedCount(appModel: AppModel) -> Int {
        let done = appModel.experiments.completed
        return ModuleCatalog.all(appModel: appModel)
            .flatMap { experiments(for: $0.id, appModel: appModel) }
            .filter { done.contains($0.experiment.id) }
            .count
    }

    static func experiments(for moduleID: String, appModel: AppModel)
    -> [(experiment: Experiment, isMet: () -> Bool)] {
        switch moduleID {
        case "electrostatics":
            let model = appModel.electromagnetismModel
            return [
                (Experiment(id: "field.dipole", title: "Opposites attract",
                            detail: "Build a dipole — one positive and one negative charge sharing the field."),
                 { model.charges.contains(where: \.isPositive)
                     && model.charges.contains(where: { !$0.isPositive }) }),
                (Experiment(id: "field.crowd", title: "Crowd control",
                            detail: "Shape the field with six or more charges at once."),
                 { model.charges.count >= 6 }),
            ]
        case "kinematics":
            let model = appModel.kinematicsModel
            return [
                (Experiment(id: "kinematics.swish", title: "Swish",
                            detail: "Put a projectile through a hoop."),
                 { model.rings.reduce(0) { $0 + $1.score } >= 1 }),
                (Experiment(id: "kinematics.streak", title: "Sharpshooter",
                            detail: "Score five — moving hoops count double for style."),
                 { model.rings.reduce(0) { $0 + $1.score } >= 5 }),
            ]
        case "waves":
            let model = appModel.wavesModel
            return [
                (Experiment(id: "waves.duet", title: "Duet",
                            detail: "Run two sources at once and watch their ripples interfere."),
                 { model.sources.count >= 2 }),
                (Experiment(id: "waves.doppler", title: "Doppler run",
                            detail: "Send a source flying and see its wavefronts bunch ahead of it."),
                 { model.selectedIsFlying }),
            ]
        case "magnetism":
            let model = appModel.magnetismModel
            return [
                (Experiment(id: "magnetism.snap", title: "The snap",
                            detail: "Let two magnets pull together until they touch."),
                 { let magnets = model.magnets
                   for i in 0..<magnets.count {
                       for j in (i + 1)..<magnets.count
                       where simd_distance(magnets[i].position, magnets[j].position)
                           < MagnetismModel.magnetLength * 0.95 {
                           return true
                       }
                   }
                   return false }),
                (Experiment(id: "magnetism.bench", title: "Full bench",
                            detail: "Get all four bar magnets into the field at once."),
                 { model.magnets.count >= 4 }),
            ]
        case "circuits":
            let model = appModel.circuitsModel
            return [
                (Experiment(id: "circuits.twoBulbs", title: "Double glow",
                            detail: "Light two bulbs at once."),
                 { model.components.filter { $0.kind == .bulb }
                     .filter { abs(model.readouts[$0.id]?.watts ?? 0) > 0.5 }.count >= 2 }),
                (Experiment(id: "circuits.bright", title: "Overdrive",
                            detail: "Push one bulb past 2 W — series batteries help."),
                 { model.components.contains {
                     $0.kind == .bulb && abs(model.readouts[$0.id]?.watts ?? 0) > 2 } }),
                (Experiment(id: "circuits.charged", title: "Full tank",
                            detail: "Charge a capacitor past 8 V."),
                 { model.components.contains {
                     $0.kind == .capacitor && abs($0.capacitorVoltage) > 8 } }),
                (Experiment(id: "circuits.firstLight", title: "First light",
                            detail: "Light an LED in its safe range — series resistance is your friend."),
                 { model.components.contains { component in
                     component.kind == .led && !component.failed
                         && abs(model.readouts[component.id]?.amps ?? 0) > 0.005
                         && abs(model.readouts[component.id]?.amps ?? 0) < 0.03 } }),
            ]
        case "pendulums":
            let model = appModel.pendulumsModel
            return [
                (Experiment(id: "pendulums.orbit", title: "Around the world",
                            detail: "Throw a bob into a true 3D orbit — sideways, hard."),
                 { model.pendulums.contains {
                     abs($0.state.position.z) > 0.15 && simd_length($0.state.velocity) > 0.5 } }),
                (Experiment(id: "pendulums.high", title: "Over the top",
                            detail: "Get a bob swinging above its pivot."),
                 { model.pendulums.contains { $0.state.position.y > 0 } }),
            ]
        case "springs":
            let model = appModel.springsModel
            return [
                (Experiment(id: "springs.limit", title: "To the stops",
                            detail: "Pull the block to its maximum extension."),
                 { model.mode == .single
                     && abs(model.state.displacement) >= model.maxExtension * 0.97 }),
                (Experiment(id: "springs.transfer", title: "Energy heist",
                            detail: "In Coupled ×2, get 85% of the energy onto the second block."),
                 { guard model.mode == .coupled else { return false }
                   let pair = model.coupled.massEnergies(
                       stiffness: model.stiffness, coupling: model.coupling,
                       masses: SIMD2(model.mass, model.mass))
                   let total = pair.x + pair.y
                   return total > 0.005 && pair.y / total > 0.85 }),
            ]
        case "elasticfield":
            let model = appModel.waveMediumModel
            return [
                (Experiment(id: "elastic.pluck", title: "Make a splash",
                            detail: "Pull a point on the drumhead well off the flat."),
                 { model.sheet.heightRange.max > 0.17
                     || model.sheet.heightRange.min < -0.17 }),
                (Experiment(id: "elastic.resonance", title: "Ring it true",
                            detail: "Drive the drum to 90% resonance — park the sweep right on a mode."),
                 { model.driveOn && model.resonance > 0.9 }),
            ]
        case "optics":
            let model = appModel.opticsModel
            return [
                (Experiment(id: "optics.virtual", title: "Through the looking glass",
                            detail: "Make a virtual image (negative dᵢ) with the point source."),
                 { (model.imagePrediction?.imageDistance ?? 0) < 0 }),
                (Experiment(id: "optics.throw", title: "Long throw",
                            detail: "Form a real image more than 60 cm past the lens."),
                 { (model.imagePrediction?.imageDistance ?? 0) > 0.6 }),
            ]
        case "gravitylab":
            let model = appModel.gravityLabModel
            return [
                (Experiment(id: "gravity.unbound", title: "Escape velocity",
                            detail: "Throw a planet hard enough to unbind it from the Sun."),
                 { model.bodies.contains {
                     !$0.body.name.hasPrefix("Sun")
                         && model.readout(for: $0)?.isBound == false } }),
                (Experiment(id: "gravity.binary", title: "Twin suns",
                            detail: "Split the Sun into a binary pair."),
                 { model.bodies.filter { $0.body.name.hasPrefix("Sun") }.count >= 2 }),
            ]
        case "windtunnel":
            let model = appModel.windTunnelModel
            return [
                (Experiment(id: "wind.lift", title: "Magnus liftoff",
                            detail: "Spin the cylinder into more than 2 N/m of lift."),
                 { model.testBody == .cylinder && abs(model.liftPerSpan) > 2 }),
                (Experiment(id: "wind.slippery", title: "Slippery shape",
                            detail: "Find the body that slips through with under a tenth the cube's drag."),
                 { model.testBody.dragCoefficient < 0.105 }),
            ]
        default:
            return []
        }
    }
}

/// Invisible per-module watcher: polls the predicates twice a second
/// and chimes when one lands for the first time.
struct ExperimentCheckerView: View {
    let moduleID: String
    @Environment(AppModel.self) private var appModel

    var body: some View {
        RealityView { content in
            let emitter = Entity()
            emitter.position = [0, 1.5, -0.9]
            content.add(emitter)
            Task { @MainActor in
                while !Task.isCancelled {
                    for entry in ExperimentCatalog.experiments(for: moduleID, appModel: appModel)
                    where !appModel.experiments.completed.contains(entry.experiment.id) {
                        if entry.isMet(), appModel.experiments.complete(entry.experiment.id) {
                            SoundPalette.play(.chime, on: emitter, volume: 0.8)
                        }
                    }
                    try? await Task.sleep(for: .milliseconds(500))
                }
            }
        }
    }
}
