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
    /// A manual change sticks for as long as the user stays in the
    /// module; entering a different one adopts that module's preference.
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
    var isImmersiveSpaceOpen = false
    /// Driven by the active module's descriptor; bound to the shared
    /// immersive space's style selection.
    var immersionStyle: ImmersionStyle = .mixed
    /// Completed-experiment bookkeeping, shared app-wide and persisted.
    let experiments = ExperimentProgress()

    /// Whether the floating control pods are shown. The pods orb
    /// toggles this to clear the space for an unobstructed look at
    /// the physics; the 2D window remains the full fallback.
    var controlPodsVisible = true


    var activeModule: ModuleDescriptor? {
        guard let activeModuleID else { return nil }
        return ModuleCatalog.all(appModel: self).first { $0.id == activeModuleID }
    }

    init() {
        // Debug hook: `simctl launch <udid> <bundle> -openModule circuits`
        // jumps straight into a module, since the simulator can't be
        // gaze-pinched from the command line.
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
        // freezes it. Some labs have nothing to freeze at t=0 — the wind
        // tunnel has no flow field until its first solve lands — so
        // freezing from launch shows an empty room and proves nothing.
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



    private var windTunnel: WindTunnelModel?

    var windTunnelModel: WindTunnelModel {
        if let windTunnel { return windTunnel }
        let model = WindTunnelModel()
        windTunnel = model
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
