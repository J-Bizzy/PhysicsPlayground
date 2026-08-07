//
//  ModuleDescriptor.swift
//  Physics Playground — Shell
//
//  The module contract that makes this a *platform*: every physics module
//  is a ModuleDescriptor — a catalog card, its shared-shell content (hint,
//  legend, reset), and ONE view factory, for the immersive scene. The hub
//  lists the catalog; picking a card swaps the active module.
//
//  There is no `makeControls`. It existed from 2026-07-29 to 2026-08-01,
//  and it is gone because a module has no flat control surface at all
//  now: every control and every readout stands on the apparatus in the
//  room, and the module window is a title bar. `PanelControlCriterionTests`
//  fails the build if one grows back. See DECISIONS.md for what that
//  costs, which is stated there plainly rather than glossed.
//

import SwiftUI

@MainActor
struct ModuleDescriptor: Identifiable {
    let id: String
    let title: String
    /// A one-word name for tight spaces — the palette ring's labels.
    /// Nil falls back to the full title.
    var shortTitle: String? = nil
    /// One-line hook shown on the catalog card.
    let blurb: String
    /// SF Symbol for the card.
    let icon: String
    /// From DesignTokens.Palette — never an ad-hoc color.
    let accent: Color
    /// How the shared immersive space presents this module: .mixed keeps
    /// the room (default); .progressive lets the crown open into a full
    /// environment the module renders (Gravity Lab's starfield).
    var immersionStyle: ImmersionStyle = .mixed
    /// One sentence, shown once per module until dismissed.
    let firstRunHint: String
    /// How far the dimming shell should be closed when this module
    /// opens, 0…1. Passthrough is a bright medium and several modules
    /// (a pale Sun, white smoke, red rays) have no contrast against a
    /// sunlit wall — those open part-dimmed rather than asking the user
    /// to discover a toggle before the module looks like anything.
    var preferredDimming: Double = 0
    /// How far out this module wants the dimming shell, metres. Bigger
    /// than the default only when the apparatus itself is bigger than
    /// the default — see `RoomDimmerView.radius`.
    var preferredDimmingRadius: Float = RoomDimmerView.defaultRadius
    /// Rendered by the shell in the shared legend style.
    let legend: [LegendItem]
    /// Freeze-everything state, driving the shared in-space pause orb.
    let isPaused: () -> Bool
    let togglePause: () -> Void
    let makeScene: () -> AnyView
    /// The readings the notebook writes down when the user captures a
    /// moment in this module. Read live from the module's model, so a
    /// captured row is exactly what the physics said at that instant.
    var captureReadings: () -> [NotebookEntry.Reading] = { [] }
    /// The Time Capsule: scrubbing the module's recorded past while
    /// paused. Wired to the model's `TimeCapsuleRecording` conformance;
    /// `.inert` only while a module has not adopted it yet — the shared
    /// Time Rail shows nothing over an inert capsule.
    let timeScrub: TimeScrubControls
    /// Returns the module's model to its freshly-entered state.
    let reset: () -> Void
}

/// The descriptor's window onto a module's Time Capsule — the same
/// closure pattern as `isPaused`/`togglePause`, so the shell's Time Rail
/// serves every module without knowing any model type.
struct TimeScrubControls {
    /// The recorded window (capsule clock), nil while nothing is recorded.
    let span: () -> ClosedRange<Double>?
    /// nil = live; non-nil = frozen at this recorded capsule time.
    let scrubTime: () -> Double?
    /// Scrub to `seconds` behind the newest recorded frame (≥ 0), pausing
    /// first if the module was live. Clamped to the recording.
    let scrub: (Double) -> Void
    /// Step by whole recorded physics ticks (negative = earlier).
    let stepFrames: (Int) -> Void
    /// Un-pause FROM the scrubbed instant, truncating the rejected future.
    let resume: () -> Void

    /// A module that has not adopted `TimeCapsuleRecording` yet. Every
    /// call is a no-op and `span` stays nil, so the Time Rail never
    /// appears — replaced module by module as the capsule rolls out.
    static let inert = TimeScrubControls(
        span: { nil }, scrubTime: { nil }, scrub: { _ in },
        stepFrames: { _ in }, resume: {})
}

/// One row of a module's legend. The swatch shapes match how the concept
/// is actually drawn in the scene, so the legend reads as a key, not prose.
struct LegendItem: Identifiable {
    enum Swatch {
        case fill(Color)
        case translucent(Color)
        case stroke(Color)
        case line(Color)
        case symbol(String, Color)
    }

    let id = UUID()
    let swatch: Swatch
    let text: String
}

@MainActor
enum ModuleCatalog {
    /// Every module in the playground, in display order. New modules
    /// register by adding one line here.
    static func all(appModel: AppModel) -> [ModuleDescriptor] {
        // SIX experiences behind TWO doors. The Home Screen shows two
        // domains — Electricity & Magnetism, Mechanics & Energy — and
        // each door opens onto its three experiences. An experience
        // gets the room to ITSELF: no arcs, no seats, no shared space.
        // Everything else (hub terraces, search, progress totals)
        // derives from this list, grouped by HubDomain.
        //
        // This list has now been burned THREE times, and the third burn
        // taught the real lesson. Fields and Oscillators died as
        // pickers (a segmented control hidden in the window panel made
        // each second half unreachable). The 2026-07-30 worlds died of
        // GEOMETRY: standing three benches in one room pushed every
        // bench a step out of reach, and the orrery proved outright
        // impossible — the pendulum station's diagonal (2.65 m) is
        // wider than the whole Mars–Jupiter shell (1.84 m), so no Sun
        // position existed anywhere. See DECISIONS.md. The rule that
        // survives all three: choosing belongs at the FRONT DOOR, the
        // most discoverable surface in the app — never in a module's
        // window panel, and not by cramming apparatus into one room.
        //
        // Cut and archived, each returning with one line here plus its
        // HubDomains entry: Springs, Elastic Field, Optics, Waves,
        // Wind Tunnel. Physics stays in PhysicsCore, tested.
        [
            ElectromagnetismModule.descriptor(appModel: appModel),
            CircuitsModule.descriptor(appModel: appModel),
            MagnetismModule.descriptor(appModel: appModel),
            KinematicsModule.descriptor(appModel: appModel),
            PendulumsModule.descriptor(appModel: appModel),
            GravityLabModule.descriptor(appModel: appModel),
        ]
    }
}
