//
//  AppModel.swift
//  Physics Playground — Shell
//
//  App-wide state: which module is active and whether the shared immersive
//  space is on screen. Each module's model is created lazily on first entry
//  and retained, so switching modules preserves their state.
//
//  "LAZILY" IS ASPIRATIONAL, and worth knowing before you rely on it.
//  The getters below are lazy, but `ModuleDescriptor` evaluates
//  `timeScrub: .init(model: appModel.<x>Model)` eagerly, so building the
//  catalog forces all six models — plus six 2 700-frame Time Capsule ring
//  buffers, about 2 MB, whether or not the feature is switched on.
//
//  `activeModule` used to build the whole catalog on every read, which
//  meant every SwiftUI invalidation did it; since 2026-08-09 it asks
//  `ModuleCatalog.descriptor(id:appModel:)` for the one it wants, and the
//  `-openModule` validation reads `ModuleCatalog.allIDs` rather than
//  constructing anything. So the per-frame cost is gone and the launch
//  footprint is not: making it genuinely lazy means `TimeScrubControls`
//  taking an autoclosure, which is a change to all six descriptors.
//

import RenderKit
import SwiftUI
import Observation

@MainActor
@Observable
final class AppModel {
    /// `private(set)` since 2026-08-26: `go(to:)` below calls itself THE
    /// ONE DOOR, and it was one of five — four callers still assigned this
    /// directly and so skipped the departure fade the door exists to run.
    /// Compile-time enforcement was owed from the day the door was written
    /// (DECISIONS.md 2026-08-23); this is it. The only writer that is not
    /// the door is `closeForDismissal()`, which says why.
    private(set) var activeModuleID: String? {
        didSet {
            refreshImmersionStyle()
            adoptModuleAtmosphere()
            recordVisit()
        }
    }

    /// Clears the active module WITHOUT the departure fade, for the one
    /// caller that is closing the immersive space in the same breath:
    /// there is nothing to fade into, and `go(to:)`'s 0.22 s delay would
    /// land after `dismissImmersiveSpace()` had already torn the scene
    /// down — leaving a module marked active with no space to hold it.
    func closeForDismissal() {
        activeModuleID = nil
    }

    /// True while a lab is fading out and before its replacement mounts.
    /// Every module's scene root watches this and rides it down.
    private(set) var isDeparting = false

    /// How long a lab takes to leave. Matches the arrival ramp, so a
    /// switch is symmetric rather than lopsided.
    static let departure: Double = 0.22

    /// THE ONE DOOR between labs — and between a lab and the gallery.
    ///
    /// There were three ways to change the active module and all three
    /// were a bare assignment, so the scene swapped in one frame: the
    /// gallery's Load button, the palette's slot ring (lab→lab, the move
    /// a demo makes constantly), and the window's back chevron. Routing
    /// them through here is what lets all three run the same curve.
    ///
    /// The transition is a DISSOLVE THROUGH PASSTHROUGH, not a
    /// cross-dissolve: the old lab fades, the wearer's real room is
    /// briefly just the room, the new one fades up. A true cross-fade
    /// would need both scenes alive at once, and the room never leaving
    /// the frame is what makes this read as continuous anyway.
    func go(to id: String?) {
        guard id != activeModuleID else { return }
        // Nothing to fade FROM (arriving from the gallery, or from
        // `-openModule` during init), or nothing that would render a
        // fade, or the wearer has asked for no motion. Go straight
        // through — a delay nobody can see is just latency.
        guard activeModuleID != nil, isImmersiveSpaceOpen, !Motion.isReduced else {
            activeModuleID = id
            return
        }
        guard !isDeparting else { return }
        isDeparting = true
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(Self.departure))
            guard let self else { return }
            // BEFORE the swap, and this ordering is the whole thing.
            // The incoming scene mounts on the next line; if the flag
            // were still true it would be born invisible with nothing
            // left to turn it back on, and an invisible lab looks
            // exactly like a crash. `AppModelDoorTests` asserts it.
            self.isDeparting = false
            self.activeModuleID = id
        }
    }

    /// Every user preference, persisted. Lives on the app model so the
    /// hub, the modules, and the settings window all read the same one.
    let settings = AppSettings()

    /// Bumped every time the user resets the active module, from either
    /// of the two places that can do it — the title bar's Reset and the
    /// palette bead's reset petal.
    ///
    /// WHY THIS EXISTS. `ModuleDescriptor.reset` is `{ model.reset() }`
    /// in all six modules, so a reset reaches the MODEL and nothing
    /// else. That is right for everything a module keeps on its model
    /// and wrong for the one piece of state a module keeps in its
    /// SpaceView: a `SpatialActionBank`'s armed plate. `disarm()` was
    /// written for exactly this — its own header says "`disarm()` exists
    /// so `reset()` can clear it. An armed Clear plate that outlived a
    /// reset would be the same defect that has now bitten four modules
    /// in a different costume" — and it had no caller anywhere in the
    /// app, so a "Clear bench" armed and then reset came back still lit
    /// and still reading "Tap again".
    ///
    /// A nonce rather than a callback because the banks already tick
    /// every frame: a SpaceView compares this against what it last saw
    /// and disarms on the change, which costs one integer compare and
    /// cannot get out of sync the way a registration list can.
    private(set) var resetNonce = 0

    /// Resets the active module and tells the room about it.
    func resetActiveModule(_ module: ModuleDescriptor) {
        module.reset()
        resetNonce &+= 1
    }

    /// Whether the hub's arrival choreography has run this SESSION.
    /// The ceremony is for arriving; the hub scene is rebuilt on every
    /// return from a lab, and before this flag each return replayed
    /// the full title flight, cascade and chime — a 2.6 s toll on the
    /// most-travelled path in the app. Session-lived on purpose: a
    /// fresh launch is an arrival, a walk back from Circuits is not.
    var hasPlayedArrival = false

    // MARK: Visit history — powers "New" badges.

    private(set) var visitedModuleIDs: Set<String> =
        Set(UserDefaults.standard.stringArray(forKey: "visited.modules") ?? [])

    // `lastPlayed(_:)` AND ITS "lastPlayed.<id>" WRITE went with the
    // experiments (2026-08-09). Its only reader was
    // `ExperimentCatalog.modulesByRecency`, which ordered the experiment
    // list by the lab you were last in. Left behind, the write would be
    // exactly the defect the recency tests were written to catch: a
    // timestamp recorded on every visit, forever, that nothing asks for.

    private func recordVisit() {
        guard let id = activeModuleID else { return }
        if !visitedModuleIDs.contains(id) {
            visitedModuleIDs.insert(id)
            UserDefaults.standard.set(visitedModuleIDs.sorted(), forKey: "visited.modules")
        }
    }

    /// Writes the active module's live readings into the notebook —
    /// the moment's numbers, exactly as the physics reported them.
    /// Returns false when no module is open or it has nothing to say.
    @discardableResult
    func captureNotebookEntry() -> Bool {
        guard let module = activeModule else { return false }
        let readings = module.captureReadings()
        guard !readings.isEmpty else { return false }
        let count = notebook.entries(forModule: module.id).count
        notebook.record(moduleID: module.id, moduleTitle: module.title,
                        title: "Observation \(count + 1)", readings: readings)
        return true
    }

    /// Studio Mode: full immersion that shuts the room out and stages the
    /// physics in a dark gallery (StudioEnvironmentView). Overrides every
    /// module's own immersion preference until switched off.
    var studioMode = false {
        didSet { refreshImmersionStyle() }
    }

    /// How far the dimming shell is closed, 0…1. The middle setting
    /// between "bright room" and "no room": the physics gets its
    /// contrast back while the user keeps their furniture and their
    /// feet. Modules that can't be read in a sunlit room open with it
    /// already part-closed (ModuleDescriptor.preferredDimming).
    /// A manual change — the palette bead's `dim` petal, which steps
    /// off → half → full — sticks for as long as the user stays in the
    /// module; entering a different one adopts that module's preference.
    ///
    /// The sentence above described that manual change from the day it
    /// was written until 2026-08-07, and there was no manual change:
    /// `cycleDimming` and `setDimming` had ZERO callers anywhere, so
    /// entering Gravity Lab darkened the user's real room by 85% with no
    /// control in the window, none in the room and none in Settings.
    /// Not one path to a capability — none — which reads as a bug rather
    /// than as a feature.
    /// THE TARGET, not what is on screen. `dimmingShown` below is what the
    /// shell actually wears; this is where it is heading.
    var roomDimming: Double = 0

    /// What the shell is wearing this frame, eased toward `roomDimming`.
    ///
    /// WHY THE SPLIT. Until 2026-08-23 there was one number, assigned in
    /// `adoptModuleAtmosphere` and written straight into an
    /// `OpacityComponent` — so the wearer's real room changed brightness in
    /// ONE FRAME, twice per lab visit, six times in a demo that cuts between
    /// labs. `AtmosphereCriterionTests` already named that as the loudest
    /// difference between two rooms meant to feel like one place; it fixed
    /// the values and could not reach the transition between them.
    ///
    /// `@ObservationIgnored` is load-bearing: this changes every frame while
    /// a ramp runs, and an observed property would invalidate the whole
    /// shell view hierarchy at 90 Hz. It lives on the model rather than in
    /// the view because it has to survive the view being rebuilt — which it
    /// is, whenever the dimming radius changes.
    @ObservationIgnored var dimmingShown: Double = 0

    /// How far out the shell should stand, metres — the active module's
    /// `preferredDimmingRadius`, or the house 3.4.
    ///
    /// ON THE MODEL, not read from `activeModule` in the ramp, because
    /// `activeModule` builds a whole `ModuleDescriptor` (six closures) on
    /// every access and the ramp runs at 90 Hz. Set once when the module
    /// changes, which is the only time it can move.
    @ObservationIgnored var dimmingRadius: Float = RoomDimmerView.defaultRadius

    func setDimming(_ level: Double) {
        roomDimming = min(max(level, 0), 1)
    }

    /// Steps the shell through off → half → full, for the nav bead.
    func cycleDimming() {
        let next: Double
        switch roomDimming {
        case ..<0.05: next = 0.55
        case ..<0.8: next = 1.0
        default: next = 0
        }
        setDimming(next)
    }

    private func adoptModuleAtmosphere() {
        // One descriptor build, not two — see `dimmingRadius`.
        let module = activeModule
        roomDimming = module?.preferredDimming ?? 0
        dimmingRadius = module?.preferredDimmingRadius ?? RoomDimmerView.defaultRadius
        if let id = activeModuleID { labPlacement.adopt(moduleID: id) }
    }

    private func refreshImmersionStyle() {
        immersionStyle = studioMode ? .full : (activeModule?.immersionStyle ?? .mixed)
    }

    /// One shared understanding of the user's real room — bounds to clip
    /// against, walls to bounce off, furniture to be occluded by. Every
    /// module reads it; the ARKit session is reference-counted.
    let room = RoomModel()

    /// The lab notebook: captured moments with their parameters.
    let notebook = LabNotebook()

    /// Where the active module's apparatus sits in the user's room.
    /// A pure display offset, remembered per module.
    let labPlacement = LabPlacement()

    /// Where the hub gallery stands — dragged by its bar, remembered
    /// across launches.
    let galleryPlacement = GalleryPlacement()
    var isImmersiveSpaceOpen = false
    /// Driven by the active module's descriptor; bound to the shared
    /// immersive space's style selection.
    var immersionStyle: ImmersionStyle = .mixed

    // `controlPodsVisible` was deleted here on 2026-08-03. A GRAVE: it
    // had zero readers anywhere in the app, and its doc comment
    // described two things that no longer exist — "the pods orb" (gone
    // with the four-bead rail) and "the 2D window remains the full
    // fallback" (gone with `makeControls` on 2026-08-01). A dead flag
    // whose comment describes a dead world is the doc-rot this project
    // keeps catching, in its most concentrated form.


    var activeModule: ModuleDescriptor? {
        guard let activeModuleID else { return nil }
        return ModuleCatalog.descriptor(id: activeModuleID, appModel: self)
    }

    init() {
        // Debug hook: `simctl launch <udid> <bundle> -openModule circuits`
        // jumps straight into a module, since the simulator can't be
        // gaze-pinched from the command line. Valid ids are the ones
        // `ModuleCatalog.all` declares; anything else is refused by name
        // below.
        #if DEBUG
        if let id = UserDefaults.standard.string(forKey: "openModule") {
            // Validate it. An id that matches nothing used to be applied
            // anyway, and `activeModule` then found no descriptor for it,
            // so the app quietly showed the HUB — indistinguishable from
            // a module that opened and rendered nothing. Chasing that
            // through a profiler is a bad afternoon; say so instead.
            // `allIDs`, not `all(appModel:).map(\.id)` — validating a
            // name should not construct six modules' worth of closures,
            // and during `init` it is the difference between reading a
            // launch argument and standing up every model in the app.
            let known = ModuleCatalog.allIDs
            if known.contains(id) {
                activeModuleID = id
            } else {
                print("""
                      -openModule \(id): no such module. Staying on the hub.
                      Known ids: \(known.joined(separator: ", "))
                      """)
            }
        }
        if UserDefaults.standard.bool(forKey: "studioMode") {
            studioMode = true
        }
        // `-resetHints 1` clears the dismissed-hint set, so the
        // first-run hint row can be screenshot from the CLI.
        if UserDefaults.standard.bool(forKey: "resetHints") {
            settings.resetOnboardingTips()
        }
        // `-startPaused 1` opens the module frozen, so the frozen-vector
        // treatment can be screenshot-verified from the CLI.
        if UserDefaults.standard.bool(forKey: "startPaused") {
            activeModule?.togglePause()
        }
        // `-pauseAfter 12` lets the simulation RUN for a while and then
        // freezes it. Some labs have nothing to freeze at t=0 — a thrown
        // bob is still in the hand, an orbit has not swept — so freezing
        // from launch shows a room at rest and proves nothing.
        let pauseAfter = UserDefaults.standard.double(forKey: "pauseAfter")
        if pauseAfter > 0 {
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(pauseAfter))
                self?.activeModule?.togglePause()
            }
        }
        #endif
    }

    // MARK: Per-module models — created on first entry, retained so a
    // module's state survives leaving and re-entering it.

    private var electromagnetism: FieldModel?

    var electromagnetismModel: FieldModel {
        if let electromagnetism { return electromagnetism }
        let model = FieldModel()
        electromagnetism = model
        return model
    }

    private var kinematics: KinematicsModel?

    var kinematicsModel: KinematicsModel {
        if let kinematics { return kinematics }
        let model = KinematicsModel()
        kinematics = model
        return model
    }

    private var gravityLab: GravityLabModel?

    var gravityLabModel: GravityLabModel {
        if let gravityLab { return gravityLab }
        let model = GravityLabModel()
        gravityLab = model
        return model
    }



    private var circuits: CircuitsModel?

    var circuitsModel: CircuitsModel {
        if let circuits { return circuits }
        let model = CircuitsModel(restoreSaved: true)
        circuits = model
        return model
    }

    private var pendulums: PendulumsModel?

    var pendulumsModel: PendulumsModel {
        if let pendulums { return pendulums }
        let model = PendulumsModel()
        pendulums = model
        return model
    }







    private var magnetism: MagnetismModel?

    var magnetismModel: MagnetismModel {
        if let magnetism { return magnetism }
        let model = MagnetismModel()
        magnetism = model
        return model
    }
}
