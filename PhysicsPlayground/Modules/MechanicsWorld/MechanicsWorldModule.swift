//
//  MechanicsWorldModule.swift
//  Physics Playground — Mechanics & Energy
//
//  Catalog registration for the merged Mechanics world.
//
//  Projectiles and Pendulums were two entries that teach one thing:
//  what a constant downward acceleration does to a moving body. One
//  lets the body go and the other keeps hold of it by a cable, and the
//  gravity control on each was the same number typed twice — set the
//  Moon on one bench and the other stayed on Earth, which made the
//  app's clearest comparison impossible to actually see.
//
//  One world, two benches, one gravity. Orbital mechanics is the third
//  and is not a bench at all: it is the volume the other two stand
//  inside. Its seat is reserved and its containment bounded here (see
//  `MechanicsStationLayout`) rather than discovered later.
//
//  Both modules keep their own files, models, renderers, panels and
//  legends; this composes them.
//

import SwiftUI
import PhysicsCore

@MainActor
enum MechanicsWorldModule {
    static let id = "mechanics"

    static func descriptor(appModel: AppModel) -> ModuleDescriptor {
        ModuleDescriptor(
            id: id,
            title: "Mechanics & Energy",
            shortTitle: "Mechanics",
            blurb: "Throw real balls across your room and watch them ricochet off your actual walls, then hang a pendulum beside them and set both to the Moon's gravity at once.",
            icon: "figure.golf",
            accent: DesignTokens.Palette.kinematicsAccent,
            firstRunHint: "Two benches, one room. STRAIGHT AHEAD, grab any ball and throw it — physics takes over the instant you let go, and it bounces off your real walls. On your LEFT, a bob is already swinging: grab it and throw it sideways. Whichever bench you touch comes forward and the other stands back.",
            legend: legend,
            // Freeze-everything means everything: the orb reads as
            // paused only when both benches are, and pressing it
            // commits both to whichever state that isn't.
            isPaused: {
                appModel.kinematicsModel.isPaused && appModel.pendulumsModel.isPaused
            },
            togglePause: {
                let paused = appModel.kinematicsModel.isPaused
                    && appModel.pendulumsModel.isPaused
                appModel.kinematicsModel.isPaused = !paused
                appModel.pendulumsModel.isPaused = !paused
            },
            makeScene: {
                AnyView(
                    MechanicsWorldSpaceView()
                        .environment(appModel.kinematicsModel)
                        .environment(appModel.pendulumsModel)
                )
            },
            makeControls: {
                AnyView(
                    MechanicsWorldControlsPanel()
                        .environment(appModel.kinematicsModel)
                        .environment(appModel.pendulumsModel)
                )
            },
            captureReadings: { readings(appModel: appModel) },
            reset: {
                appModel.kinematicsModel.reset()
                appModel.pendulumsModel.reset()
            }
        )
    }

    /// Both benches' readings, in the order the room reads.
    static func readings(appModel: AppModel) -> [NotebookEntry.Reading] {
        var rows = KinematicsModule.readings(appModel: appModel)
        rows.append(contentsOf: PendulumsModule.readings(appModel: appModel))
        return rows
    }

    /// Curated rather than concatenated: both benches have a full
    /// legend of their own and stacking them makes a wall.
    private static let legend: [LegendItem] = [
        LegendItem(
            swatch: .fill(DesignTokens.Palette.projectile),
            text: "Balls at their real sizes — grab and throw any of them, anywhere"),
        LegendItem(
            swatch: .line(DesignTokens.Palette.predictedArc),
            text: "The faint arc is where the throw you are holding will go"),
        LegendItem(
            swatch: .fill(DesignTokens.Palette.kinematicsAccent),
            text: "The launcher — drag it anywhere, pinch its bead to aim"),
        LegendItem(
            swatch: .fill(DesignTokens.Palette.pendulumsAccent),
            text: "Bobs swing on a taut cable — grab one and throw it sideways for a true 3-D orbit"),
        LegendItem(
            swatch: .symbol("arrow.down", DesignTokens.Palette.kinematicsAccent),
            text: "One gravity serves both benches: set the Moon and the arc flattens as the swing slows"),
    ]
}
