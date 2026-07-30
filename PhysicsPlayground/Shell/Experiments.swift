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
    /// One concrete instruction — what to actually DO next.
    ///
    /// The experiments were a checklist in a side pod: a list of
    /// outcomes with no order and no next step, so they read as
    /// achievements to stumble into rather than as a path through the
    /// module. A `step` turns each into a thing you can be told to do,
    /// and the pod shows exactly one of them at a time — the first
    /// unfinished one — as the module's current task.
    var step: String = ""
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
        recordStreakDay()
        return true
    }

    // MARK: Streak — consecutive days with at least one completion.

    private(set) var streak: Int =
        UserDefaults.standard.integer(forKey: "streak.count")

    /// Whether today already counts toward the streak.
    var completedToday: Bool {
        guard let last = UserDefaults.standard.object(forKey: "streak.lastDay") as? Date
        else { return false }
        return Calendar.current.isDateInToday(last)
    }

    private func recordStreakDay() {
        let defaults = UserDefaults.standard
        let today = Calendar.current.startOfDay(for: Date())
        if let last = defaults.object(forKey: "streak.lastDay") as? Date {
            if Calendar.current.isDate(last, inSameDayAs: today) { return }
            let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: today)!
            streak = Calendar.current.isDate(last, inSameDayAs: yesterday) ? streak + 1 : 1
        } else {
            streak = 1
        }
        defaults.set(streak, forKey: "streak.count")
        defaults.set(today, forKey: "streak.lastDay")
    }

    /// Wipes every completion and the streak. The settings window's
    /// destructive reset; confirmed there before it reaches here.
    func resetAll() {
        completed = []
        streak = 0
        UserDefaults.standard.removeObject(forKey: Self.key)
        UserDefaults.standard.removeObject(forKey: "streak.count")
        UserDefaults.standard.removeObject(forKey: "streak.lastDay")
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

    /// The next thing to do, anywhere in the app.
    ///
    /// A tally that says "4 of 24 complete" tells you where you are and
    /// nothing about where to go — so the hub could only ever be a
    /// launcher. One concrete next step, with the module it belongs to,
    /// turns it into somewhere you come back TO.
    static func nextStep(appModel: AppModel)
    -> (module: ModuleDescriptor, experiment: Experiment)? {
        let done = appModel.experiments.completed
        for module in ModuleCatalog.all(appModel: appModel) {
            for entry in experiments(for: module.id, appModel: appModel)
            where !done.contains(entry.experiment.id) {
                return (module, entry.experiment)
            }
        }
        return nil
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


    /// The charges bench's experiments, folded into the E&M world's
    /// list when Electric Fields became its centre station. The IDs keep
    /// their `field.` prefix so a player who earned them before the
    /// merge keeps them.
    private static func chargeExperiments(_ model: FieldModel)
    -> [(experiment: Experiment, isMet: () -> Bool)] {
        [
            (Experiment(id: "field.dipole", title: "Opposites attract",
                        detail: "Build a dipole — one positive and one negative charge sharing the field.",
                        step: "The dipole is already here — if you cleared it, tap Add + and Add −."),
             { model.charges.contains(where: \.isPositive)
                 && model.charges.contains(where: { !$0.isPositive }) }),
            (Experiment(id: "field.crowd", title: "Crowd control",
                        detail: "Shape the field with six or more charges at once.",
                        step: "Tap Add + and Add − until six charges share the room, then drag them into a shape."),
             { model.charges.count >= 6 }),
        ]
    }

    /// The magnetic bench's experiments, folded into the merged Fields
    /// module's list.
    private static func magnetismExperiments(_ model: MagnetismModel)
    -> [(experiment: Experiment, isMet: () -> Bool)] {
        [
            (Experiment(id: "magnetism.snap", title: "The snap",
                        detail: "Let two magnets pull together until they touch.",
                            step: "Carry one magnet toward another until they jump together."),
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
                        detail: "Get all four bar magnets into the field at once.",
                            step: "Tap Add magnet until four are floating."),
             { model.magnets.count >= 4 }),
        ]
    }

    /// The experiments that exist ONLY because the two benches share a
    /// room. Each one needs both halves of the world at once, which is
    /// precisely what neither module could ask for while they were
    /// separate entries a hub apart.
    private static func linkExperiments(appModel: AppModel)
    -> [(experiment: Experiment, isMet: () -> Bool)] {
        let circuits = appModel.circuitsModel
        let magnetism = appModel.magnetismModel
        return [
            (Experiment(id: "em.powered", title: "Electromagnet",
                        detail: "Drive the coil from your own circuit — a current in a loop of wire IS a magnet.",
                        step: "Switch the electromagnet on in this window, then drag an inductor off the tray and wire it into the live loop. A cable runs across the room to the coil."),
             { magnetism.electromagnetOn && abs(circuits.inductorCurrent) > 0.01 }),

            (Experiment(id: "em.reach", title: "Action at a distance",
                        detail: "Push a bar magnet around using nothing but the current in your circuit.",
                        step: "With the coil powered, carry a bar magnet close to it — or carry the coil to the magnets — until the coil's field is what's moving them."),
             {
                 // The honest test is the force the coil actually
                 // exerts, not proximity: a dead coil sitting next to a
                 // magnet must not count.
                 guard let coil = magnetism.electromagnet else { return false }
                 return magnetism.magnets.contains {
                     simd_length(MagneticField.netForce(on: $0, from: [coil])) > 1e-4
                 }
             }),

            (Experiment(id: "em.faraday", title: "Run it backwards",
                        detail: "Make the coil generate instead of consume — ε = −N dΦ/dt.",
                        step: "With the coil on, sweep a bar magnet through it. Watch the coil EMF in this window jump while the magnet MOVES, and fall to zero the moment you hold it still."),
             { abs(magnetism.inducedEMF) > 0.001 }),
        ]
    }

    static func experiments(for moduleID: String, appModel: AppModel)
    -> [(experiment: Experiment, isMet: () -> Bool)] {
        switch moduleID {
        case "kinematics":
            let model = appModel.kinematicsModel
            return [
                (Experiment(id: "kinematics.range", title: "Range finder",
                            detail: "Land a shot more than three metres from the launcher.",
                            step: "Aim near 45° with the orange bead, then Fire — the range reads out where it lands."),
                 { (model.lastFlight?.range ?? 0) > 3.0 }),
                (Experiment(id: "kinematics.moonshot", title: "Moon shot",
                            detail: "Watch the same launch hang in lunar gravity.",
                            step: "Tap Moon in this window's World section, then Fire — the arc stretches six times as far."),
                 { model.gravity < 2.0 && model.flights.contains {
                     $0.status == .flying && !$0.wasThrown
                 } }),
            ]
        case "em":
            let model = appModel.circuitsModel
            return [
                (Experiment(id: "circuits.twoBulbs", title: "Double glow",
                            detail: "Light two bulbs at once.",
                            step: "Drag a second bulb off the tray and wire it across the battery beside the first."),
                 { model.components.filter { $0.kind == .bulb }
                     .filter { abs(model.readouts[$0.id]?.watts ?? 0) > 0.5 }.count >= 2 }),
                (Experiment(id: "circuits.slowpoke", title: "Slowpoke",
                            detail: "Get an electron's lap time under twelve hours — drift speed rises with current.",
                            step: "Turn on True electron speed in this window's Flow section, then push more current: add a battery in series, or lower the resistance."),
                 { model.driftLapTime < 12 * 3600 }),
                (Experiment(id: "circuits.bright", title: "Overdrive",
                            detail: "Push one bulb past 2 W — series batteries help.",
                            step: "Add a second battery in series with the first, then watch the bulb's watts climb."),
                 { model.components.contains {
                     $0.kind == .bulb && abs(model.readouts[$0.id]?.watts ?? 0) > 2 } }),
                (Experiment(id: "circuits.charged", title: "Full tank",
                            detail: "Charge a capacitor past 8 V.",
                            step: "Wire a capacitor across the battery and give it a few seconds to fill."),
                 { model.components.contains {
                     $0.kind == .capacitor && abs($0.capacitorVoltage) > 8 } }),
                (Experiment(id: "circuits.firstLight", title: "First light",
                            detail: "Light an LED in its safe range — series resistance is your friend.",
                            step: "Put an LED in series with a resistor of a few hundred ohms, then close the switch."),
                 { model.components.contains { component in
                     component.kind == .led && !component.failed
                         && abs(model.readouts[component.id]?.amps ?? 0) > 0.005
                         && abs(model.readouts[component.id]?.amps ?? 0) < 0.03 } }),
            ]
            + magnetismExperiments(appModel.magnetismModel)
            + chargeExperiments(appModel.electromagnetismModel)
            + linkExperiments(appModel: appModel)
        case "pendulums":
            let model = appModel.pendulumsModel
            return [
                (Experiment(id: "pendulums.orbit", title: "Around the world",
                            detail: "Throw a bob into a true 3D orbit — sideways, hard.",
                            step: "Grab a bob and throw it sideways — across the swing plane, not along it."),
                 { model.pendulums.contains {
                     abs($0.state.position.z) > 0.15 && simd_length($0.state.velocity) > 0.5 } }),
                (Experiment(id: "pendulums.high", title: "Over the top",
                            detail: "Get a bob swinging above its pivot.",
                            step: "Throw a bob hard enough upward to carry it above its own pivot."),
                 { model.pendulums.contains { $0.state.position.y > 0 } }),
            ]
        case "gravitylab":
            let model = appModel.gravityLabModel
            return [
                (Experiment(id: "gravity.unbound", title: "Escape velocity",
                            detail: "Throw a planet hard enough to unbind it from the Sun.",
                            step: "Grab a planet and throw it hard, away from the Sun — watch the readout say unbound."),
                 { model.bodies.contains {
                     !$0.body.name.hasPrefix("Sun")
                         && model.readout(for: $0)?.isBound == false } }),
                (Experiment(id: "gravity.prophet", title: "Prophet",
                            detail: "Predict where a planet will be — and miss by less than a tenth of an AU.",
                            step: "Tap a planet to select it, tap Predict an orbit in this window, drag the ghost to your guess, and let time run."),
                 { (model.bestPredictionMissAU ?? 1) < 0.1 }),
                (Experiment(id: "gravity.binary", title: "Twin suns",
                            detail: "Split the Sun into a binary pair.",
                            step: "Tap Twin suns in this window."),
                 { model.bodies.filter { $0.body.name.hasPrefix("Sun") }.count >= 2 }),
            ]
        case "windtunnel":
            let model = appModel.windTunnelModel
            return [
                (Experiment(id: "wind.lift", title: "Magnus liftoff",
                            detail: "Spin the cylinder into more than 2 N/m of lift.",
                            step: "Choose the Cylinder body in this window, then run Spin up until the lift arrow grows."),
                 { model.testBody == .cylinder && abs(model.liftPerSpan) > 2 }),
                (Experiment(id: "wind.slippery", title: "Slippery shape",
                            detail: "Find the body that slips through with under a tenth the cube's drag.",
                            step: "Work through the bodies in this window's Test body picker and compare how the smoke parts around each."),
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
