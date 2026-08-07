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
            // The blurb names what the bench ACTUALLY opens with. It
            // promised "five-pendulum resonance" for a day after the
            // plate that built it was removed — and this string is not
            // only the catalog hook, it is the hub exhibit's VoiceOver
            // label, so a stale one is read aloud.
            blurb: "Hang a pendulum anywhere in the room, then grab the steel bob and throw it — a Newton's cradle to break apart, a double pendulum that never repeats itself, and full nonlinear swings in true 3-D.",
            icon: "metronome.fill",
            accent: DesignTokens.Palette.pendulumsAccent,
            // The hint names controls that EXIST. The line it replaces
            // ended "To your right, tap a world", and the world discs
            // were removed on 2026-08-02 — leaving the app's one
            // onboarding surface pointing at an empty wall.
            firstRunHint: "Five steel balls, touching, with one drawn back — let it go and watch which of them move. Grab any bob and throw it sideways; press a pendulum's top collar for a bead that pays out its cable, or drag that collar to re-hang the whole rig. visionOS will ask to use your room so the rig can hang in it.",
            legend: legendItems,
            isPaused: { appModel.pendulumsModel.isPaused },
            togglePause: { appModel.pendulumsModel.togglePauseRespectingScrub() },
            makeScene: {
                AnyView(PendulumsSpaceView().environment(appModel.pendulumsModel))
            },
            captureReadings: { readings(appModel: appModel) },
            timeScrub: .init(model: appModel.pendulumsModel),
            reset: { appModel.pendulumsModel.reset() }
        )
    }

    /// The readings this bench writes into the lab notebook.
    static func readings(appModel: AppModel) -> [NotebookEntry.Reading] {
        let model = appModel.pendulumsModel
        var rows: [NotebookEntry.Reading] = [
            .init("Pendulums", "\(model.pendulums.count)"),
            .init("Gravity", PhysicsFormat.fixed(model.gravity, decimals: 2), "m/s²"),
            .init("Friction", PhysicsFormat.state(model.frictionOn)),
        ]
        if let selected = model.selected {
            rows.append(.init("Length", PhysicsFormat.fixed(selected.length, decimals: 3), "m"))
            rows.append(.init("Mass", PhysicsFormat.fixed(selected.mass, decimals: 3), "kg"))
            rows.append(.init("Period 2π√(L/g)",
                              PhysicsFormat.fixed(selected.period(gravity: model.gravity),
                                                  decimals: 3), "s"))
            rows.append(.init("Speed",
                              PhysicsFormat.fixed(simd_length(selected.state.velocity),
                                                  decimals: 3), "m/s"))
        }
        return rows
    }

    static let legendItems: [LegendItem] = [
        LegendItem(swatch: .fill(DesignTokens.Palette.velocityVector),
                   text: "Blue arrow — velocity; the trail runs blue (slow) to orange (fast), so the swing colours its own speed"),
        LegendItem(swatch: .fill(Color(red: 0.95, green: 0.85, blue: 0.2)),
                   text: "Force arrows — purple gravity, yellow cable tension, red net force"),
        LegendItem(swatch: .line(.white),
                   text: "White ghost line while holding a bob — the exact swing a release right now would launch"),
    ]

}

// `PendulumsControlsView` was deleted here (2026-07-29): a window panel
// of six per-pendulum sliders — length, mass, damping, bob size, cable
// thickness, start angle — plus a Remove button, never instantiated by
// anything since it was written.
//
// It is the clearest specimen in the app of what the interaction law now
// forbids (DECISIONS.md, 2026-07-29): every quantity in it has physical
// extent and three of them are already manipulated BY that extent on the
// object itself — the bob's Bloom carries a Length grip you pull to pay
// out cable, a Mass petal, and a Delete petal. The panel was a second,
// worse way to do what the pendulum already does.
//
// A grave, not a missing door: `setBobRadius`, `setCableThickness`,
// `setInitialAngle` and `removeSelected` went with it. Bob size and cable
// thickness are cosmetics, not physics; a start angle is what grabbing
// the bob and letting go already sets, more honestly; and deletion is a
// petal. `setLength`, `setMass` and `setDamping` stay — the Bloom and the
// module panel use those.
