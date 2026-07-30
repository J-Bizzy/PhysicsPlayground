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
        // THREE entries, heading for two: Electricity & Magnetism, and
        // Mechanics & Energy. Everything else (hub arc, search, progress
        // totals, the challenge) derives from this list.
        //
        // Cut, in order: Springs (a block on a rail is a ONE-dimensional
        // oscillator), Elastic Field (a membrane is two-dimensional),
        // Optics (an optical bench is a line of elements in a row),
        // Waves (its dot lattice sampled below Nyquist and could not be
        // fixed at a workable budget), and Wind Tunnel (owner's call —
        // it belongs to neither of the two labs). None of it is deleted:
        // each sits in Archive/ with its tests, the physics stays in
        // PhysicsCore and stays tested, and each returns with one line
        // here plus its HubDomains entry.
        //
        // A WORD ON MERGERS, because this list has been burned twice.
        // Fields and Oscillators were once merged, and both mergers were
        // undone: each hid its second half behind a bench picker that
        // lived only in the window's control panel, and the app's
        // controls had moved into spatial pods long ago, so Magnetism
        // and Springs became unreachable. A module you cannot find is
        // not a module.
        //
        // The E&M world is a merger that does not do that. Its three
        // benches — circuits, magnets, charges — are not three modes of
        // one entry; they stand in the room AT THE SAME TIME, all three
        // solving, with a cable running from the circuit's inductor to a
        // coil in the magnetic field. One of them is FOCUSED at a time,
        // which is emphasis and not a picker: the others stay built,
        // live, and one tap from attention. See StationFocus for the
        // four properties that keep that distinction real, and
        // EMStationLayout for the geometry that keeps the benches out of
        // each other.
        [
            EMWorldModule.descriptor(appModel: appModel),
            MechanicsWorldModule.descriptor(appModel: appModel),
            GravityLabModule.descriptor(appModel: appModel),
        ]
    }
}
