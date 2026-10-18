//
//  KinematicsModule.swift
//  Physics Playground — Kinematics: catalog registration — descriptor and readings.
//

import SwiftUI
import PhysicsCore

@MainActor
enum KinematicsModule {
    static let id = "kinematics"

    static func descriptor(appModel: AppModel) -> ModuleDescriptor {
        ModuleDescriptor(
            id: id,
            title: "Projectile Motion",
            shortTitle: "Projectiles",
            icon: "paperplane.fill",
            accent: DesignTokens.Palette.kinematicsAccent,
            // The house dimming (Orbital Mechanics' 0.85 is the one exception).
            preferredDimming: 0.35,
            isPaused: { appModel.kinematicsModel.isPaused },
            // Through the capsule: un-pausing from a scrubbed instant resumes from it.
            togglePause: { appModel.kinematicsModel.togglePauseRespectingScrub() },
            makeScene: {
                AnyView(KinematicsSpaceView().environment(appModel.kinematicsModel))
            },
            readings: { readings(appModel: appModel) },
            more: more(appModel.kinematicsModel),
            timeScrub: .init(model: appModel.kinematicsModel),
            reset: { appModel.kinematicsModel.reset() }
        )
    }

    /// What More holds for the throw: the two layers the room keeps until
    /// asked (2026-10-17), the world it happens on, its air, and the room's
    /// walls. Angle and speed are the aim bead; the ball is the fan over the
    /// launcher.
    static func more(_ model: KinematicsModel) -> [MoreItem] {
        [
            // The prediction: the arc, its apex and landing, the vacuum ghost.
            .toggle(id: "trajectory", title: "Trajectory",
                    symbol: "point.topleft.down.to.point.bottomright.curvepath",
                    isOn: { model.showsTrajectory },
                    set: { model.showsTrajectory = $0 }),
            // Every number in the room; the bead shows its own while held.
            .toggle(id: "numbers", title: "Numbers", symbol: "number",
                    isOn: { model.showsNumbers },
                    set: { model.showsNumbers = $0 }),
            // g was a world fan, a rail in the room and a rail in the box;
            // it is this one slider, which names the world it stands on.
            .slider(.init(id: "gravity", label: "Gravity", unit: "m/s²",
                          range: KinematicsModel.gravityRange, decimals: 2,
                          format: gravityReadout,
                          read: { model.gravity },
                          write: { model.gravity = gravityDetent($0) })),
            .toggle(id: "walls", title: "Walls bounce", symbol: "square.dashed",
                    isOn: { model.respectRoomWalls },
                    set: { model.respectRoomWalls = $0 }),
            .toggle(id: "air", title: "Air resistance", symbol: "wind",
                    isOn: { model.airResistance },
                    set: { model.airResistance = $0 }),
            // Wind blows through air or not at all.
            .slider(.init(id: "wind", label: "Wind", unit: "m/s",
                          range: KinematicsModel.windSpeedRange, decimals: 1,
                          read: { model.windSpeed },
                          write: { model.windSpeed = $0 }),
                    isEnabled: { model.airResistance }),
            // The custom ball's only free number; its diameter stays 10 cm.
            .slider(.init(id: "customMass", label: "Custom ball mass", unit: "kg",
                          range: KinematicsModel.customMassRange, decimals: 2,
                          read: { model.customMass },
                          write: { model.customMass = $0 }),
                    isEnabled: { model.kind == .custom }),
        ]
    }

    /// Within this of a world's g, the slider settles on it exactly: the
    /// hand can find Earth on a 0–30 track without a fine-tune.
    nonisolated static let gravityDetentWidth = 0.2

    nonisolated static func gravityDetent(_ g: Double) -> Double {
        KinematicsModel.gravityPresets
            .first { abs($0.gravity - g) <= gravityDetentWidth }?.gravity ?? g
    }

    /// "9.81 m/s² · Earth" on a world, the number alone between them.
    nonisolated static func gravityReadout(_ g: Double) -> String {
        let value = PhysicsFormat.measurement(g, "m/s²", decimals: 2)
        guard let world = KinematicsModel.gravityPresets
            .first(where: { abs($0.gravity - g) < 1e-9 }) else { return value }
        return value + " · " + world.name
    }

    /// The numbers the room does not already draw: what is being thrown,
    /// what the law of its flight predicts, and what the last throw
    /// measured. Angle and speed ride the protractor; g, wind and air are
    /// More's own controls.
    static func readings(appModel: AppModel) -> [Reading] {
        let model = appModel.kinematicsModel
        var rows: [Reading] = [
            .init("Projectile", model.kind.displayName),
            .init("Mass", PhysicsFormat.fixed(model.projectile.mass, decimals: 3), "kg"),
        ]
        rows.append(contentsOf: lawReadings(model))
        // The initial conditions your arm set, for the latest ball thrown by hand.
        if let release = model.latestThrow?.release {
            rows.append(.init("Release speed", PhysicsFormat.fixed(release.speed, decimals: 2), "m/s"))
            rows.append(.init("Release angle", PhysicsFormat.angle(release.elevationDegrees, decimals: 1),
                              formula: "θ = atan(v_y / v_h)"))
        }
        if let last = model.lastFlight {
            rows.append(.init("Measured range", PhysicsFormat.fixed(last.range, decimals: 3), "m"))
            rows.append(.init("Apex height", PhysicsFormat.fixed(last.apexHeight, decimals: 3), "m"))
            rows.append(.init("Flight time", PhysicsFormat.fixed(last.flightTime, decimals: 3), "s"))
        }
        return rows
    }

    /// The closed form the flight obeys. In a vacuum, the range of the
    /// current aim back to the height it leaves from; in air, the speed
    /// at which drag holds up the ball's weight, which is what makes a
    /// table tennis ball and a cannonball fly differently.
    static func lawReadings(_ model: KinematicsModel) -> [Reading] {
        let g = model.gravity
        if model.airResistance {
            let ball = model.projectile
            let speed = ProjectileMotion.terminalSpeed(projectile: ball, gravity: g)
            guard speed.isFinite, speed > 0 else { return [] }
            return [.init("Terminal speed", PhysicsFormat.fixed(speed, decimals: 1), "m/s",
                          formula: "mg = ½ρC_DAv², C_D = "
                            + PhysicsFormat.fixed(ball.dragCoefficient, decimals: 2))]
        }
        let elevation = asin(min(1, max(-1, model.aimDirection.y)))
        guard elevation > 0, g > 0 else { return [] }
        let range = ProjectileMotion.dragFreeRange(speed: model.launchSpeed, angle: elevation,
                                                   gravity: g)
        let v = PhysicsFormat.fixed(model.launchSpeed, decimals: 1)
        let doubled = PhysicsFormat.angle(2 * elevation * 180 / .pi)
        return [.init("Range to launch height", PhysicsFormat.fixed(range, decimals: 2), "m",
                      formula: "R = v² sin 2θ / g = \(v)² × sin \(doubled) ÷ "
                        + PhysicsFormat.fixed(g, decimals: 2))]
    }
}
