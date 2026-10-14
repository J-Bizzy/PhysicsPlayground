//
//  ModuleDescriptor.swift
//  Physics Playground — Shell
//
//  The module contract: every lab is a ModuleDescriptor — a catalog
//  card, shared-shell closures (pause, reset, readings, time scrub) and
//  one view factory for the immersive scene. There is no control
//  factory: every control stands on the apparatus, and
//  `PanelControlCriterionTests` keeps it that way.
//

import SwiftUI

@MainActor
struct ModuleDescriptor: Identifiable {
    let id: String
    let title: String
    /// A one-word name for tight spaces — the palette ring's labels.
    /// Nil falls back to the full title.
    var shortTitle: String? = nil
    /// SF Symbol for the card.
    let icon: String
    /// From DesignTokens.Palette — never an ad-hoc color.
    let accent: Color
    /// How the shared immersive space presents this module: .mixed keeps
    /// the room (default); .progressive lets the crown open into a full
    /// environment the module renders (Orbital Mechanics' starfield).
    var immersionStyle: ImmersionStyle = .mixed
    /// How far the dimming shell is closed when this module opens, 0…1 —
    /// for apparatus with no contrast against a sunlit wall.
    var preferredDimming: Double = 0
    /// How far out this module wants the dimming shell, metres; larger only
    /// when the apparatus is larger than the default.
    var preferredDimmingRadius: Float = RoomDimmerView.defaultRadius
    /// Rendered by the shell in the shared legend style.
    let legend: [LegendItem]
    /// Freeze-everything state, driving the shared in-space pause orb.
    let isPaused: () -> Bool
    let togglePause: () -> Void
    let makeScene: () -> AnyView
    /// The readings the notebook writes down when the user captures a
    /// moment, read live from the model.
    var captureReadings: () -> [NotebookEntry.Reading] = { [] }
    /// What the Physics box shows, when a module wants a shorter list than
    /// the notebook records; nil shows `captureReadings`.
    var physicsRows: (() -> [NotebookEntry.Reading])? = nil
    /// One line of disclosure under the numbers, or nil.
    var physicsNote: () -> String? = { nil }
    /// The quantities the Physics box lets you set, one rail each.
    var adjustables: [PhysicsAdjustable] = []
    /// The Time Capsule: scrubbing the module's recorded past while paused.
    /// `.inert` shows no Time Rail.
    let timeScrub: TimeScrubControls
    /// Returns the module's model to its freshly-entered state.
    let reset: () -> Void
}

/// A physics quantity the Physics box can set: read live from the
/// model, written back clamped to its range.
struct PhysicsAdjustable: Identifiable {
    let id: String
    let label: String
    let unit: String
    let range: ClosedRange<Double>
    let read: () -> Double
    let write: (Double) -> Void
    /// Digits after the point on the rail's own readout.
    var decimals: Int = 2

    init(id: String, label: String, unit: String, range: ClosedRange<Double>,
         decimals: Int = 2,
         read: @escaping () -> Double, write: @escaping (Double) -> Void) {
        self.id = id
        self.label = label
        self.unit = unit
        self.range = range
        self.decimals = decimals
        self.read = read
        // Clamped here, once, so no module's setter has to.
        self.write = { value in
            write(min(max(value, range.lowerBound), range.upperBound))
        }
    }
}

/// The descriptor's window onto a module's Time Capsule, as closures so
/// the shell's Time Rail serves every module without knowing its model.
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
    /// Un-pause from the scrubbed instant, truncating the rejected future.
    let resume: () -> Void

    /// Every call a no-op and `span` nil, so the Time Rail never appears.
    static let inert = TimeScrubControls(
        span: { nil }, scrubTime: { nil }, scrub: { _ in },
        stepFrames: { _ in }, resume: {})
}

/// One row of a module's legend. The swatch shapes match how the concept
/// is actually drawn in the scene, so the legend reads as a key, not prose.
struct LegendItem: Identifiable {
    enum Swatch {
        case fill(Color)
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
        // Six experiences behind two doors (`HubDomain`); each gets the room to
        // itself. Cut modules are archived and return with one line here plus a
        // HubDomains entry.
        registry.map { $0.make(appModel) }
    }

    /// One descriptor without building the other five — `activeModule` is
    /// read every frame. Built from the same `registry` as `all`, so a
    /// module cannot be in the catalog and unopenable by id.
    static func descriptor(id: String, appModel: AppModel) -> ModuleDescriptor? {
        registry.first { $0.id == id }?.make(appModel)
    }

    /// The one list. Ids are declared here so a lookup does not have to
    /// build a descriptor to find out what it is called.
    private static let registry: [(id: String, make: (AppModel) -> ModuleDescriptor)] = [
        (ElectromagnetismModule.id, ElectromagnetismModule.descriptor),
        (CircuitsModule.id, CircuitsModule.descriptor),
        (MagnetismModule.id, MagnetismModule.descriptor),
        (KinematicsModule.id, KinematicsModule.descriptor),
        (PendulumsModule.id, PendulumsModule.descriptor),
        (OrbitalMechanicsModule.id, OrbitalMechanicsModule.descriptor),
    ]

    /// Every module's id, without constructing anything.
    static var allIDs: [String] { registry.map(\.id) }
}
