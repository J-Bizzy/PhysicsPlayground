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
    /// How the shared immersive space presents this module in the room:
    /// .mixed keeps it (default); .progressive lets the crown close it
    /// down. Deep space is always .full (`AppModel.surroundings`).
    var immersionStyle: ImmersionStyle = .mixed
    /// How far the dimming shell is closed when this module opens, 0…1 —
    /// for apparatus with no contrast against a sunlit wall.
    var preferredDimming: Double = 0
    /// How far out this module wants the dimming shell, metres; larger only
    /// when the apparatus is larger than the default.
    var preferredDimmingRadius: Float = RoomDimmerView.defaultRadius
    /// The surroundings this lab opens in for a visit, whatever the wearer
    /// last chose; nil follows the choice. The atmosphere above applies
    /// whenever the wearer is in the room.
    var preferredSurroundings: Surroundings? = nil
    /// True when the lab draws a Sun of its own, so deep space puts its
    /// distant one away rather than show two.
    var drawsItsOwnSun = false
    /// Freeze-everything state, driving the shared in-space pause orb.
    let isPaused: () -> Bool
    let togglePause: () -> Void
    let makeScene: () -> AnyView
    /// The lab's live numbers, read from the model, for the Physics box.
    var readings: () -> [Reading] = { [] }
    /// One line of disclosure under the numbers, or nil.
    var physicsNote: () -> String? = { nil }
    /// The quantities with no object to stretch, one slider each in More.
    var adjustables: [PhysicsAdjustable] = []
    /// Everything secondary the lab offers — display layers, modes, verbs
    /// — behind the title bar's More. The room holds only the apparatus.
    var more: [MoreItem] = []
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
    /// The readout, when the number alone does not say enough (gravity
    /// names the world it matches). Nil reads value and unit.
    var format: ((Double) -> String)?

    init(id: String, label: String, unit: String, range: ClosedRange<Double>,
         decimals: Int = 2,
         format: ((Double) -> String)? = nil,
         read: @escaping () -> Double, write: @escaping (Double) -> Void) {
        self.id = id
        self.label = label
        self.unit = unit
        self.range = range
        self.decimals = decimals
        self.format = format
        self.read = read
        // Clamped here, once, so no module's setter has to.
        self.write = { value in
            write(min(max(value, range.lowerBound), range.upperBound))
        }
    }
}

/// One secondary control a lab offers behind More. Drawn by the shell in
/// the one control language; the lab only says what it is.
enum MoreItem: Identifiable {
    /// A display layer or a mode: on or off.
    case toggle(id: String, title: String, symbol: String,
                isOn: () -> Bool, set: (Bool) -> Void,
                isEnabled: () -> Bool = { true })
    /// A verb. `confirms` arms first ("Tap again"), for anything that
    /// throws work away; `destructive` paints it red, for the one verb
    /// whose whole point is to throw it away (Clear).
    case action(id: String, title: String, symbol: String,
                confirms: Bool = false, destructive: Bool = false,
                isEnabled: () -> Bool = { true },
                run: () -> Void)
    /// One of a few named choices, the current one selected.
    case choice(id: String, title: String,
                options: [(id: String, label: String)],
                selected: () -> String?, select: (String) -> Void)
    /// A quantity with no object to stretch.
    case slider(PhysicsAdjustable, isEnabled: () -> Bool = { true })
    /// A set of like verbs — things you could add — as one wrapping grid.
    case verbs(id: String, title: String,
               items: [(id: String, label: String, symbol: String)],
               run: (String) -> Void)

    var id: String {
        switch self {
        case .toggle(let id, _, _, _, _, _): id
        case .action(let id, _, _, _, _, _, _): id
        case .choice(let id, _, _, _, _): id
        case .slider(let adjustable, _): adjustable.id
        case .verbs(let id, _, _, _): id
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

/// One live number: a name, a formatted value and its unit, and the law
/// it obeys when there is one.
struct Reading: Equatable {
    var name: String
    var value: String
    var unit: String
    /// The equation behind the number, drawn under its name in More and
    /// nowhere in the room. Where the law is one product or quotient of
    /// quantities the lab can name, the live values follow it:
    /// "T = 2π√(L/g) = 2π√(0.800 m ÷ 9.81 m/s²)". `_x` and `_{xy}` set a
    /// subscript (`Formula`), for the ones Unicode has no glyph for.
    var formula: String?

    init(_ name: String, _ value: String, _ unit: String = "", formula: String? = nil) {
        self.name = name
        self.value = value
        self.unit = unit
        self.formula = formula
    }
}

@MainActor
enum ModuleCatalog {
    /// Every module in the playground, in display order. New modules
    /// register by adding one line here.
    static func all(appModel: AppModel) -> [ModuleDescriptor] {
        // Seven experiences behind two doors (`HubDomain`); each gets the room to
        // itself. Cut modules are archived and return with one line here plus a
        // HubDomains entry.
        registry.map { $0.make(appModel) }
    }

    /// One descriptor without building the others — `activeModule` is
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
        (OpticsModule.id, OpticsModule.descriptor),
        (KinematicsModule.id, KinematicsModule.descriptor),
        (PendulumsModule.id, PendulumsModule.descriptor),
        (OrbitalMechanicsModule.id, OrbitalMechanicsModule.descriptor),
    ]

    /// Every module's id, without constructing anything.
    static var allIDs: [String] { registry.map(\.id) }
}
