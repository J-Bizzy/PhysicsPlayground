//
//  Challenges.swift
//  Physics Playground — Shell
//
//  The challenges layer: each module offers a few goals the user can
//  only complete by actually doing the physics — no quiz, no text
//  entry, just the simulation noticing what your hands made happen.
//  Completion persists across launches and chimes when it lands.
//

import Foundation
import Observation
import PhysicsCore
import RealityKit
import SwiftUI
import simd

struct Challenge: Identifiable {
    let id: String
    let title: String
    let detail: String
}

/// Completed-challenge bookkeeping, persisted.
@MainActor
@Observable
final class ChallengeProgress {
    nonisolated static let key = "challenges.completed.v1"

    private(set) var completed: Set<String>

    init() {
        completed = Set(UserDefaults.standard.stringArray(forKey: Self.key) ?? [])
    }

    /// Marks a challenge done; returns true only on the first time.
    @discardableResult
    func complete(_ id: String) -> Bool {
        guard !completed.contains(id) else { return false }
        completed.insert(id)
        UserDefaults.standard.set(completed.sorted(), forKey: Self.key)
        return true
    }
}

/// The goals per module, each with a live predicate against the models.
@MainActor
enum ChallengeCatalog {
    /// Every challenge across every module (for the hub's tally).
    static func total(appModel: AppModel) -> Int {
        ModuleCatalog.all(appModel: appModel)
            .map { challenges(for: $0.id, appModel: appModel).count }
            .reduce(0, +)
    }

    static func challenges(for moduleID: String, appModel: AppModel)
    -> [(challenge: Challenge, isMet: () -> Bool)] {
        switch moduleID {
        case "circuits":
            let model = appModel.circuitsModel
            return [
                (Challenge(id: "circuits.twoBulbs", title: "Double glow",
                           detail: "Light two bulbs at once."),
                 { model.components.filter { $0.kind == .bulb }
                     .filter { abs(model.readouts[$0.id]?.watts ?? 0) > 0.5 }.count >= 2 }),
                (Challenge(id: "circuits.bright", title: "Overdrive",
                           detail: "Push one bulb past 2 W — series batteries help."),
                 { model.components.contains {
                     $0.kind == .bulb && abs(model.readouts[$0.id]?.watts ?? 0) > 2 } }),
                (Challenge(id: "circuits.charged", title: "Full tank",
                           detail: "Charge a capacitor past 8 V."),
                 { model.components.contains {
                     $0.kind == .capacitor && abs($0.capacitorVoltage) > 8 } }),
                (Challenge(id: "circuits.firstLight", title: "First light",
                           detail: "Light an LED in its safe range — series resistance is your friend."),
                 { model.components.contains { component in
                     component.kind == .led && !component.failed
                         && abs(model.readouts[component.id]?.amps ?? 0) > 0.005
                         && abs(model.readouts[component.id]?.amps ?? 0) < 0.03 } }),
            ]
        case "pendulums":
            let model = appModel.pendulumsModel
            return [
                (Challenge(id: "pendulums.orbit", title: "Around the world",
                           detail: "Throw a bob into a true 3D orbit — sideways, hard."),
                 { model.pendulums.contains {
                     abs($0.state.position.z) > 0.15 && simd_length($0.state.velocity) > 0.5 } }),
                (Challenge(id: "pendulums.high", title: "Over the top",
                           detail: "Get a bob swinging above its pivot."),
                 { model.pendulums.contains { $0.state.position.y > 0 } }),
            ]
        case "springs":
            let model = appModel.springsModel
            return [
                (Challenge(id: "springs.limit", title: "To the stops",
                           detail: "Pull the block to its maximum extension."),
                 { model.mode == .single
                     && abs(model.state.displacement) >= model.maxExtension * 0.97 }),
                (Challenge(id: "springs.transfer", title: "Energy heist",
                           detail: "In Coupled ×2, get 85% of the energy onto the second block."),
                 { guard model.mode == .coupled else { return false }
                   let pair = model.coupled.massEnergies(
                       stiffness: model.stiffness, coupling: model.coupling,
                       masses: SIMD2(model.mass, model.mass))
                   let total = pair.x + pair.y
                   return total > 0.005 && pair.y / total > 0.85 }),
            ]
        case "optics":
            let model = appModel.opticsModel
            return [
                (Challenge(id: "optics.virtual", title: "Through the looking glass",
                           detail: "Make a virtual image (negative dᵢ) with the point source."),
                 { (model.imagePrediction?.imageDistance ?? 0) < 0 }),
                (Challenge(id: "optics.throw", title: "Long throw",
                           detail: "Form a real image more than 60 cm past the lens."),
                 { (model.imagePrediction?.imageDistance ?? 0) > 0.6 }),
            ]
        case "gravitylab":
            let model = appModel.gravityLabModel
            return [
                (Challenge(id: "gravity.unbound", title: "Escape velocity",
                           detail: "Throw a planet hard enough to unbind it from the Sun."),
                 { model.bodies.contains {
                     $0.body.name != "Sun" && !($0.body.name.hasPrefix("Sun"))
                         && model.readout(for: $0)?.isBound == false } }),
                (Challenge(id: "gravity.binary", title: "Twin suns",
                           detail: "Split the Sun into a binary pair."),
                 { model.bodies.filter { $0.body.name.hasPrefix("Sun") }.count >= 2 }),
            ]
        case "windtunnel":
            let model = appModel.windTunnelModel
            return [
                (Challenge(id: "wind.lift", title: "Magnus liftoff",
                           detail: "Spin the cylinder into more than 2 N/m of lift."),
                 { model.testBody == .cylinder && abs(model.liftPerSpan) > 2 }),
            ]
        default:
            return []
        }
    }
}

/// The window-panel section listing this module's challenges.
struct ChallengesPanel: View {
    let moduleID: String
    @Environment(AppModel.self) private var appModel

    var body: some View {
        let entries = ChallengeCatalog.challenges(for: moduleID, appModel: appModel)
        if !entries.isEmpty {
            PanelSection("Challenges") {
                ForEach(entries, id: \.challenge.id) { entry in
                    let done = appModel.challenges.completed.contains(entry.challenge.id)
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: done ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(done ? .green : .secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.challenge.title)
                                .font(DesignTokens.TypeScale.control)
                            Text(entry.challenge.detail)
                                .font(DesignTokens.TypeScale.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }
}

/// Invisible per-module watcher: polls the predicates twice a second
/// and chimes when one lands for the first time.
struct ChallengeCheckerView: View {
    let moduleID: String
    @Environment(AppModel.self) private var appModel

    var body: some View {
        RealityView { content in
            let emitter = Entity()
            emitter.position = [0, 1.5, -0.9]
            content.add(emitter)
            Task { @MainActor in
                while !Task.isCancelled {
                    for entry in ChallengeCatalog.challenges(for: moduleID, appModel: appModel)
                    where !appModel.challenges.completed.contains(entry.challenge.id) {
                        if entry.isMet(), appModel.challenges.complete(entry.challenge.id) {
                            SoundPalette.play(.chime, on: emitter, volume: 0.8)
                        }
                    }
                    try? await Task.sleep(for: .milliseconds(500))
                }
            }
        }
    }
}
