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

    /// Consecutive days with at least one completion — CHECKED AGAINST
    /// THE CALENDAR ON LOAD, not just trusted.
    ///
    /// This was `UserDefaults.integer(forKey:)` and nothing else, so the
    /// stored number was believed forever. `recordStreakDay` resets it
    /// correctly when a gap is found — but only when you next complete
    /// something, and until then the app claims a streak that broke. Miss
    /// Wednesday and Thursday and Friday still reads "4-day streak",
    /// which is the one thing a streak must never do: a counter you
    /// cannot break is not a reason to come back.
    ///
    /// A streak survives only if its last day was today or yesterday.
    private(set) var streak: Int = ExperimentProgress.loadedStreak()

    private static func loadedStreak() -> Int {
        let defaults = UserDefaults.standard
        let stored = defaults.integer(forKey: "streak.count")
        guard stored > 0,
              let last = defaults.object(forKey: "streak.lastDay") as? Date
        else { return 0 }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        guard let yesterday = calendar.date(byAdding: .day, value: -1, to: today)
        else { return 0 }
        let day = calendar.startOfDay(for: last)
        return day == today || day == yesterday ? stored : 0
    }

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
        for module in modulesByRecency(appModel: appModel) {
            for entry in experiments(for: module.id, appModel: appModel)
            where !done.contains(entry.experiment.id) {
                return (module, entry.experiment)
            }
        }
        return nil
    }

    /// The labs, most recently visited first — the lab you are IN ahead
    /// of all of them.
    ///
    /// `nextStep` used to walk `ModuleCatalog` in its declaration order,
    /// so it recommended the first unfinished experiment in the first
    /// module, forever, to everybody. A new user standing in Pendulums
    /// was told "Opposites attract — Electric Fields"; the one line whose
    /// whole job is to say what to do next was pointing at a different
    /// room.
    ///
    /// `AppModel.lastPlayed(_:)` has existed the whole time, with a
    /// writer and NO reader. This is the reader.
    ///
    /// A module never opened sorts last rather than first: the point is
    /// to continue what you were doing, and an untouched lab is a
    /// suggestion rather than a continuation. Catalog order breaks ties,
    /// so the recommendation is stable for a user who has played nothing.
    static func modulesByRecency(appModel: AppModel) -> [ModuleDescriptor] {
        let catalog = ModuleCatalog.all(appModel: appModel)
        let order = Dictionary(uniqueKeysWithValues:
            catalog.enumerated().map { ($0.element.id, $0.offset) })
        return catalog.sorted { a, b in
            // The lab currently open always wins — you are standing in it.
            if a.id == appModel.activeModuleID { return true }
            if b.id == appModel.activeModuleID { return false }
            switch (appModel.lastPlayed(a.id), appModel.lastPlayed(b.id)) {
            case let (x?, y?): return x == y
                ? (order[a.id] ?? 0) < (order[b.id] ?? 0) : x > y
            case (_?, nil): return true
            case (nil, _?): return false
            case (nil, nil): return (order[a.id] ?? 0) < (order[b.id] ?? 0)
            }
        }
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


    /// The pendulum rig's experiments, folded into the Mechanics
    /// world's list. The ids keep their `pendulums.` prefix so earned
    /// progress survives the merge.
    private static func pendulumExperiments(_ model: PendulumsModel)
    -> [(experiment: Experiment, isMet: () -> Bool)] {
        [
                // The cold open, made into a thing you DO. The cradle is
                // the first image the module shows and had no rung of its
                // own; breaking it apart is the question it exists to ask.
                (Experiment(id: "pendulums.cradle", title: "Break the cradle",
                            detail: "Pull TWO balls back instead of one, and count what leaves the far end.",
                            step: "Draw two of the five steel balls back together and let them go — two should leave, not one at double speed. Nothing counts balls; it falls out of the contacts resolving in order."),
                 { model.pendulums.filter { $0.kind == .simple }.count >= 5
                     && model.pendulums.contains {
                         $0.kind == .simple && simd_length($0.state.velocity) > 0.35 } }),
                (Experiment(id: "pendulums.orbit", title: "Around the world",
                            detail: "Throw a bob into a true 3D orbit — sideways, hard.",
                            step: "Grab a bob and throw it sideways — across the swing plane, not along it."),
                 { model.pendulums.contains {
                     abs($0.state.position.z) > 0.15 && simd_length($0.state.velocity) > 0.5 } }),
                // The chaotic cousin, which arrived on 2026-08-02 with no
                // rung at all.
                (Experiment(id: "pendulums.chaos", title: "Never the same twice",
                            detail: "Set a double pendulum going hard enough to flip its elbow over.",
                            step: "Pull a double pendulum out of the second well and throw it. Watch the elbow go over the top — from there no two releases ever repeat."),
                 { model.pendulums.contains {
                     $0.kind == .double && abs($0.state.position.y) > 0.02
                         && simd_length($0.state.velocity) > 1.0 } }),
            ]
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
                        step: "The dipole is already here — if you cleared it, pull one charge out of the + well and one out of the −."),
             { model.charges.contains(where: \.isPositive)
                 && model.charges.contains(where: { !$0.isPositive }) }),
            (Experiment(id: "field.crowd", title: "Crowd control",
                        detail: "Shape the field with six or more charges at once.",
                        step: "Pull charges out of the + and − wells until six share the room, then drag them into a shape."),
             { model.charges.count >= 6 }),
            // The cyclotron circle — r = mv/qB, drawn in the air. This
            // replaced `field.gauss` on 2026-08-03 when the flux meter
            // left the prototype; anyone who earned the old rung keeps
            // it in their progress store, it just stops being counted.
            (Experiment(id: "field.cyclotron", title: "Round trip",
                        detail: "Bend the test charge into a closed circle with the uniform field.",
                        step: "Flick Uniform B on the switch bank, pull a test charge from its well and throw it sideways. The trail curves into a circle that closes on its own tail."),
             { model.magneticFieldOn && model.probeStatus == .running
                 && model.probeTrail.count >= 150 }),
        ]
    }

    /// The magnetic bench's experiments.
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
                        // "Tap Add magnet" until 2026-08-03. It is a
                        // WELL, and a well is reached into — the verb was
                        // wrong for the affordance it names.
                        step: "Reach into the Add magnet well and pull magnets out until four are floating."),
             { model.magnets.count >= 4 }),
            // The compass, which is the module's own stated best moment
            // ("the experience everyone actually remembers") and had no
            // rung of its own.
            (Experiment(id: "magnetism.handover", title: "Hand it to the planet",
                        detail: "Carry the compass far enough from the bench that Earth's field takes over.",
                        step: "Pick up the compass sphere and walk it away from the magnets. Around 30 cm out a 6 A·m² bar matches Earth's 50 µT — past that the needle stops answering the bench and settles on the planet, tipping 65° into the ground."),
             { model.compassOn && model.compassIsReadingEarth }),
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
                            step: "Tap the Moon disc on the world bank to the launcher's left, then pinch Fire — the arc stretches six times as far."),
                 { model.gravity < 2.0 && model.flights.contains {
                     $0.status == .flying && !$0.wasThrown
                 } }),
                // THE MODULE'S SIGNATURE MOMENT, and it had no rung.
                // Projectiles is the one bench that is 1:1 with the room —
                // it refuses `SpatialScale` for exactly this reason — and
                // catching a ball on your own tracked fingertips is the
                // thing that only works because of it. Nothing pointed at
                // it.
                (Experiment(id: "kinematics.catch", title: "Out of the air",
                            detail: "Catch a ball in your hand while it is still flying.",
                            step: "Fire one gently, or throw it up, and put a hand in its way. Your real fingertips are the catcher — the readout tells you the speed and the kinetic energy you just took out of it."),
                 { model.lastCatch != nil }),
            ]
        case "circuits":
            let model = appModel.circuitsModel
            return [
                (Experiment(id: "circuits.twoBulbs", title: "Double glow",
                            detail: "Light two bulbs at once.",
                            step: "Pull a second bulb out of the rack on your right and wire it across the battery beside the first."),
                 { model.components.filter { $0.kind == .bulb }
                     .filter { abs(model.readouts[$0.id]?.watts ?? 0) > 0.5 }.count >= 2 }),
                (Experiment(id: "circuits.slowpoke", title: "Slowpoke",
                            detail: "Get an electron's lap time under twelve hours — drift speed rises with current.",
                            step: "Flick True speed on the layers bank beside the bench, then push more current: add a battery in series, or lower the resistance."),
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
        case "electrostatics":
            return chargeExperiments(appModel.electromagnetismModel)
        case "magnetism":
            return magnetismExperiments(appModel.magnetismModel)
        case "pendulums":
            return pendulumExperiments(appModel.pendulumsModel)
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
                            step: "Tap a planet to select it, tap the Predict petal on its ring, drag the ghost to your guess, and let time run."),
                 { (model.bestPredictionMissAU ?? 1) < 0.1 }),
                (Experiment(id: "gravity.binary", title: "Twin suns",
                            detail: "Split the Sun into a binary pair.",
                            step: "Tap the Twin suns plate on the bank beside the system."),
                 { model.bodies.filter { $0.body.name.hasPrefix("Sun") }.count >= 2 }),
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

    @State private var emitter = Entity()

    var body: some View {
        RealityView { content in
            emitter.position = [0, 1.5, -0.9]
            content.add(emitter)
        }
        // A STRUCTURED TASK, tied to the view's lifetime.
        //
        // This was an unstructured `Task { }` created inside the make
        // closure, unstored and never cancelled, holding `appModel` and
        // its emitter strongly. `ExperimentCheckerView` is mounted per
        // module, so every lab you entered left behind another watcher
        // evaluating every predicate of a module you were no longer in,
        // twice a second, for the life of the process — and each one
        // could still fire a chime and a completion for a lab that was
        // not on screen.
        //
        // `.task` cancels on disappear, which is the whole fix. The loop
        // is otherwise unchanged: polling is right here, because these
        // predicates read live physics state that no observation would
        // usefully re-fire on.
        .task(id: moduleID) {
            // Built ONCE per module: the entries are constant and their
            // predicates are closures that read live state at call time
            // — rebuilding the whole array (and every closure in it)
            // twice a second was allocation on a timer for nothing.
            let entries = ExperimentCatalog.experiments(for: moduleID,
                                                        appModel: appModel)
            while !Task.isCancelled {
                for entry in entries
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
