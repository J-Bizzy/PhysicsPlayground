//
//  ModuleDescriptor.swift
//  Physics Playground — Shell
//
//  The module contract that makes this a *platform*: every physics module
//  is a ModuleDescriptor — a catalog card, its shared-shell content (hint,
//  legend, reset), and two view factories, one for the pod controls and
//  one for the immersive scene. The hub lists the catalog; picking a
//  card swaps the active module. The shell renders everything but
//  makeControls/makeScene itself, so the hint, legend, and experiments
//  presentation are identical in every module by construction.
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
    /// Rendered by the shell in the shared legend style.
    let legend: [LegendItem]
    /// Freeze-everything state, driving the shared in-space pause orb.
    let isPaused: () -> Bool
    let togglePause: () -> Void
    let makeScene: () -> AnyView
    /// Optional flat control panel, rendered by the shell in the module
    /// window beneath the title bar. Nil means the module's spatial
    /// affordances carry every control on their own. A module supplies
    /// this when some of its controls need to be *discoverable* — a
    /// panel of labelled buttons and sliders is also the simulator and
    /// accessibility path, where gaze-revealed spatial controls barely
    /// exist.
    var makeControls: (() -> AnyView)? = nil
    /// The readings the notebook writes down when the user captures a
    /// moment in this module. Read live from the module's model, so a
    /// captured row is exactly what the physics said at that instant.
    var captureReadings: () -> [NotebookEntry.Reading] = { [] }
    /// Returns the module's model to its freshly-entered state.
    let reset: () -> Void
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
        // The one exception is wiring, not layout: an experience may
        // bring a partner bench it is physically cabled to (Circuit
        // Workshop's inductor drives a coil standing in a magnetic
        // field). Co-presence survives exactly where a demonstration
        // cannot exist without it, and nowhere else.
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
