//
//  AppModel.swift
//  Physics Playground — Shell
//
//  App-wide state: which module is active and whether the shared immersive
//  space is on screen. Each module's model is created lazily on first entry
//  and retained, so switching modules preserves their state.
//

import SwiftUI
import Observation

@MainActor
@Observable
final class AppModel {
    var activeModuleID: String? {
        didSet {
            refreshImmersionStyle()
            adoptModuleAtmosphere()
            recordVisit()
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

    // MARK: Visit history — powers "New" badges and "last played".

    private(set) var visitedModuleIDs: Set<String> =
        Set(UserDefaults.standard.stringArray(forKey: "visited.modules") ?? [])

    func lastPlayed(_ moduleID: String) -> Date? {
        UserDefaults.standard.object(forKey: "lastPlayed.\(moduleID)") as? Date
    }

    private func recordVisit() {
        guard let id = activeModuleID else { return }
        UserDefaults.standard.set(Date(), forKey: "lastPlayed.\(id)")
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
    var roomDimming: Double = 0

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
        roomDimming = activeModule?.preferredDimming ?? 0
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
    /// Completed-experiment bookkeeping, shared app-wide and persisted.
    let experiments = ExperimentProgress()

    // `controlPodsVisible` was deleted here on 2026-08-03. A GRAVE: it
    // had zero readers anywhere in the app, and its doc comment
    // described two things that no longer exist — "the pods orb" (gone
    // with the four-bead rail) and "the 2D window remains the full
    // fallback" (gone with `makeControls` on 2026-08-01). A dead flag
    // whose comment describes a dead world is the doc-rot this project
    // keeps catching, in its most concentrated form.


    var activeModule: ModuleDescriptor? {
        guard let activeModuleID else { return nil }
        return ModuleCatalog.all(appModel: self).first { $0.id == activeModuleID }
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
            let known = ModuleCatalog.all(appModel: self).map(\.id)
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
