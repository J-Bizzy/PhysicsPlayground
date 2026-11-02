//
//  PendulumsModule.swift
//  Physics Playground — Pendulums module
//
//  Catalog registration, window controls, and the real-world story.
//

import PhysicsCore
import SwiftUI
import simd

@MainActor
enum PendulumsModule {
    static let id = "pendulums"

    static func descriptor(appModel: AppModel) -> ModuleDescriptor {
        ModuleDescriptor(
            id: id,
            title: "Pendulums",
            icon: "metronome.fill",
            accent: DesignTokens.Palette.pendulumsAccent,
            // The house dimming; Orbital Mechanics' 0.85 is the one deliberate exception.
            preferredDimming: 0.35,
            isPaused: { appModel.pendulumsModel.isPaused },
            togglePause: { appModel.pendulumsModel.togglePauseRespectingScrub() },
            makeScene: {
                AnyView(PendulumsSpaceView().environment(appModel.pendulumsModel))
            },
            readings: { readings(appModel: appModel) },
            more: more(appModel.pendulumsModel),
            timeScrub: .init(model: appModel.pendulumsModel),
            reset: { appModel.pendulumsModel.reset() }
        )
    }

    /// What More holds for the bench: the two arrow layers, and whether
    /// the air is real. (Acceleration was a third layer until 2026-10-14:
    /// its arrow was the Force layer's net arrow over m.)
    static func more(_ model: PendulumsModel) -> [MoreItem] {
        [
            .toggle(id: "velocity", title: "Velocity", symbol: "arrow.right",
                    isOn: { model.showVelocity }, set: { model.showVelocity = $0 }),
            .toggle(id: "force", title: "Force", symbol: "arrow.down.right",
                    isOn: { model.showForces }, set: { model.showForces = $0 }),
            // Not a display layer, and the title says so: off, the pendulum
            // is ideal and swings for ever.
            .toggle(id: "friction", title: "Air resistance", symbol: "wind",
                    isOn: { model.frictionOn }, set: { model.frictionOn = $0 }),
            // Two pendulums and a spring, ready to trade their swing.
            .action(id: "coupledPair", title: "Coupled pair", symbol: "link",
                    isEnabled: .when({ model.pendulums.count + 2 <= PendulumsModel.pendulumBudget },
                                     else: "No room for two more pendulums"),
                    run: { model.addCoupledPair() }),
            // A spring has no handle of its own to stretch, so its constant is a
            // slider — and only while there is a spring to set.
            .slider(PhysicsAdjustable(id: "springStiffness", label: "Spring",
                                      unit: "N/m", range: PendulumsModel.stiffnessRange,
                                      decimals: 1,
                                      read: { model.springStiffness },
                                      write: { model.setSpringStiffness($0) }),
                    isEnabled: .when({ !model.springs.isEmpty }, else: "Needs a coupled pair")),
        ]
    }

    /// The live numbers More shows.
    static func readings(appModel: AppModel) -> [Reading] {
        let model = appModel.pendulumsModel
        var rows: [Reading] = [
            .init("Pendulums", "\(model.pendulums.count)"),
            .init("Gravity", PhysicsFormat.fixed(model.gravity, decimals: 2), "m/s²"),
        ]
        if let selected = model.selected {
            rows.append(.init("Length", PhysicsFormat.fixed(selected.length, decimals: 3), "m"))
            rows.append(.init("Mass", PhysicsFormat.fixed(selected.mass, decimals: 3), "kg"))
            // A double pendulum writes no period: the formula is the
            // upper rod's alone and the system has none.
            if selected.kind != .double {
                let length = PhysicsFormat.fixed(selected.length, decimals: 3)
                let g = PhysicsFormat.fixed(model.gravity, decimals: 2)
                rows.append(.init("Period",
                                  PhysicsFormat.fixed(selected.period(gravity: model.gravity),
                                                      decimals: 3), "s",
                                  formula: "T = 2π√(L/g) = 2π√(\(length) m ÷ \(g) m/s²)"))
            }
            rows.append(.init("Speed",
                              PhysicsFormat.fixed(simd_length(selected.state.velocity),
                                                  decimals: 3), "m/s"))
            rows.append(contentsOf: coupledReadings(selected, model: model))
        }
        return rows
    }

    /// For a coupled bob: the spring, the two normal modes and the beat. The
    /// closed forms are for two identical pendulums, so they are shown only
    /// when the pair is one.
    static func coupledReadings(_ selected: PendulumsModel.Pendulum,
                                model: PendulumsModel) -> [Reading] {
        guard let partnerID = model.partner(of: selected.id),
              let partner = model.pendulums.first(where: { $0.id == partnerID }) else { return [] }
        var rows: [Reading] = [
            .init("Spring k", PhysicsFormat.fixed(model.springStiffness, decimals: 1), "N/m"),
        ]
        let identical = abs(partner.length - selected.length) < 0.005
            && abs(partner.mass - selected.mass) < 0.005
        guard identical else { return rows }
        let modes = CoupledPendulums.normalModes(length: selected.length, mass: selected.mass,
                                                 stiffness: model.springStiffness,
                                                 gravity: model.gravity)
        let g = PhysicsFormat.fixed(model.gravity, decimals: 2)
        let length = PhysicsFormat.fixed(selected.length, decimals: 3)
        let k = PhysicsFormat.fixed(model.springStiffness, decimals: 1)
        let mass = PhysicsFormat.fixed(selected.mass, decimals: 3)
        let inPhase = PhysicsFormat.fixed(modes.inPhase, decimals: 3)
        let antiPhase = PhysicsFormat.fixed(modes.antiPhase, decimals: 3)
        rows.append(.init("In step", inPhase, "rad/s",
                          formula: "ω₁ = √(g/L) = √(\(g) ÷ \(length))"))
        rows.append(.init("Against", antiPhase, "rad/s",
                          formula: "ω₂ = √(g/L + 2k/m) = √(\(g) ÷ \(length) + 2 × \(k) ÷ \(mass))"))
        rows.append(.init("Beat",
                          PhysicsFormat.fixed(2 * .pi / (modes.antiPhase - modes.inPhase),
                                              decimals: 2), "s",
                          formula: "T = 2π/(ω₂ − ω₁) = 2π/(\(antiPhase) − \(inPhase))"))
        return rows
    }
}
