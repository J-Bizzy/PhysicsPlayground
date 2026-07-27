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
    /// True when the module's own pods already carry every control, so
    /// the shell should not mount a Controls pod at all — anything else
    /// would be a second place to do the same thing.
    var podsCoverControls: Bool = false
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
    let makeControls: () -> AnyView
    let makeScene: () -> AnyView
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
        // NINE modules, not eleven.
        //
        // Electric Fields and Magnetism were the same experience with
        // different math behind the line; Pendulums and Springs were one
        // chapter split in two. Merging each pair into a module with two
        // benches makes the comparison the point instead of hiding it —
        // and leaves every remaining entry with a reason to exist that
        // no other entry already covers.
        // EIGHT modules. Waves, Elastic Field, and Optics are BENCHED,
        // not deleted — each returns with one line here plus its
        // HubDomains entry. Everything else (hub arc, search, progress
        // totals, the challenge) derives from this list.
        //
        // The Fields and Oscillators MERGERS are undone. Each merged
        // module hid its second half behind a bench picker that lived
        // only in the window's control panel — and the app's controls
        // moved into spatial pods long ago, so Magnetism and Springs
        // were effectively unreachable. A module you cannot find is not
        // a module; four standalone entries put all four back on the
        // shelf where they can be seen.
        [
            ElectromagnetismModule.descriptor(appModel: appModel),
            MagnetismModule.descriptor(appModel: appModel),
            KinematicsModule.descriptor(appModel: appModel),
            GravityLabModule.descriptor(appModel: appModel),
            WindTunnelModule.descriptor(appModel: appModel),
            CircuitsModule.descriptor(appModel: appModel),
            PendulumsModule.descriptor(appModel: appModel),
            SpringsModule.descriptor(appModel: appModel),
        ]
    }
}
