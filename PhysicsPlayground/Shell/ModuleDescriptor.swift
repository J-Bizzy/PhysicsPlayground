//
//  ModuleDescriptor.swift
//  Physics Playground — Shell
//
//  The module contract that makes this a *platform*: every physics module
//  is a ModuleDescriptor — a catalog card, its shared-shell content (hint,
//  legend, real-world story, reset), and two view factories, one for the
//  control window and one for the immersive scene. The hub lists the
//  catalog; picking a card swaps the active module.
//
//  The shell renders everything but makeControls/makeScene itself, so the
//  hint style, legend style, and real-world panel are identical in every
//  module by construction — a module physically can't restyle them, and
//  can't ship without a real-world story.
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
    /// One sentence, shown once per module until dismissed.
    let firstRunHint: String
    /// Rendered by the shell in the shared legend style.
    let legend: [LegendItem]
    /// The first-class "where this shows up in the real world" content.
    let realWorld: RealWorldStory
    let makeControls: () -> AnyView
    let makeScene: () -> AnyView
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

/// A module's real-world tie-in: a one-line tagline and 2–4 applications,
/// rendered by the shared RealWorldPanel.
struct RealWorldStory {
    struct Application: Identifiable {
        let id = UUID()
        let title: String
        /// SF Symbol shown beside the title.
        let icon: String
        let body: String
    }

    let tagline: String
    let applications: [Application]
}

@MainActor
enum ModuleCatalog {
    /// Every module in the playground, in display order. New modules
    /// register by adding one line here.
    static func all(appModel: AppModel) -> [ModuleDescriptor] {
        [
            ElectromagnetismModule.descriptor(appModel: appModel),
            KinematicsModule.descriptor(appModel: appModel),
            GravityLabModule.descriptor(appModel: appModel),
            WavesModule.descriptor(appModel: appModel),
            WindTunnelModule.descriptor(appModel: appModel),
        ]
    }
}
