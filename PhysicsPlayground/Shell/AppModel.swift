//
//  AppModel.swift
//  Physics Playground — Shell
//
//  App-wide state: the active module, the shared immersive space, the
//  room, the notebook and the atmosphere. Module models are created on
//  first entry and retained, so switching labs keeps their state. (The
//  catalog's `timeScrub` closures force all six models the first time a
//  descriptor is built.)
//

import RenderKit
import SwiftUI
import Observation

@MainActor
@Observable
final class AppModel {
    /// Written only by `go(to:)`, the one door with its departure fade, and
    /// by `closeForDismissal()`.
    private(set) var activeModuleID: String? {
        didSet {
            refreshImmersionStyle()
            adoptModuleAtmosphere()
        }
    }

    /// Clears the active module without the departure fade, for the caller
    /// that is dismissing the space in the same breath: the fade's delay
    /// would land after the scene was torn down.
    func closeForDismissal() {
        activeModuleID = nil
    }

    /// True while a lab is fading out and before its replacement mounts.
    /// Every module's scene root watches this and rides it down.
    private(set) var isDeparting = false

    /// How long a lab takes to leave; matches the arrival ramp.
    static let departure: Double = 0.22

    /// The one door between labs, and between a lab and the gallery. A
    /// dissolve through passthrough: the old lab fades, the room stands
    /// alone for a beat, the new lab fades up.
    func go(to id: String?) {
        guard id != activeModuleID else { return }
        // Nothing to fade from, nothing that would render a fade, or Reduce
        // Motion: go straight through.
        guard activeModuleID != nil, isImmersiveSpaceOpen, !Motion.isReduced else {
            activeModuleID = id
            return
        }
        guard !isDeparting else { return }
        isDeparting = true
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(Self.departure))
            guard let self else { return }
            // Cleared before the swap: the incoming scene mounts on the next line
            // and must not be born invisible. `AppModelDoorTests` pins the order.
            self.isDeparting = false
            self.activeModuleID = id
        }
    }

    /// Every user preference, persisted; the one instance the hub, the
    /// modules and Settings share.
    let settings = AppSettings()

    /// Bumped on every reset of the active module (title bar or palette
    /// petal). A reset reaches the model; a SpaceView compares this each
    /// frame to disarm what it keeps itself, such as an armed Clear plate.
    private(set) var resetNonce = 0

    /// Resets the active module and tells the room about it.
    func resetActiveModule(_ module: ModuleDescriptor) {
        module.reset()
        resetNonce &+= 1
    }

    /// Whether the hub's arrival choreography has run this session. A fresh
    /// launch is an arrival; a walk back from a lab is not.
    var hasPlayedArrival = false

    /// Writes the active module's live readings into the notebook. Returns
    /// false when no module is open or it has nothing to say.
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
    /// physics in a dark gallery. Overrides every module's immersion
    /// preference until switched off.
    var studioMode = false {
        didSet { refreshImmersionStyle() }
    }

    /// The Physics box, opened by the title bar's ƒ button; kept across
    /// labs, so a wearer who wants the numbers has them in every room.
    var physicsBoardOpen = false

    /// The dimming target, 0…1: how far the shell is closed. Modules with no
    /// contrast against a sunlit wall open part-closed (`preferredDimming`);
    /// the palette bead's dim petal steps off → half → full and sticks until
    /// another module is entered. `dimmingShown` is what the shell wears.
    var roomDimming: Double = 0

    /// What the shell wears this frame, eased toward `roomDimming` so a lab
    /// switch never changes the room's brightness in one frame.
    /// `@ObservationIgnored` because it changes at 90 Hz while a ramp runs;
    /// on the model so it survives the view being rebuilt.
    @ObservationIgnored var dimmingShown: Double = 0

    /// How far out the shell stands, metres — the active module's
    /// `preferredDimmingRadius`. Kept here because the ramp runs at 90 Hz
    /// and `activeModule` builds a descriptor on every read.
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

    /// The user's real room — bounds, walls, furniture. Shared by every
    /// module; the ARKit session is reference-counted.
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
    /// How many main windows are on screen. A value-less `WindowGroup` opens
    /// a new window on every `openWindow(id:)`, and three places ask for it,
    /// so every opener checks `wantsMainWindow` first.
    var mainWindowCount = 0
    /// True when opening the main window would show one rather than add one.
    var wantsMainWindow: Bool { mainWindowCount == 0 }
    /// Driven by the active module's descriptor; bound to the shared
    /// immersive space's style selection.
    var immersionStyle: ImmersionStyle = .mixed


    var activeModule: ModuleDescriptor? {
        guard let activeModuleID else { return nil }
        return ModuleCatalog.descriptor(id: activeModuleID, appModel: self)
    }

    init() {
        // The app tracks nothing about its wearer. Builds before 2026-10-14
        // kept a list of every lab visited for "New" badges that no longer
        // exist; an upgraded install forgets it.
        UserDefaults.standard.removeObject(forKey: "visited.modules")
        // `-openModule <id>` jumps straight into a module; the simulator cannot
        // be gaze-pinched from the command line.
        #if DEBUG
        if let id = UserDefaults.standard.string(forKey: "openModule") {
            // An unknown id is refused by name rather than silently showing the
            // hub. `allIDs` validates without building six modules' closures.
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
        // `-startPaused 1` opens the module frozen.
        if UserDefaults.standard.bool(forKey: "startPaused") {
            activeModule?.togglePause()
        }
        // `-pauseAfter <s>` lets the simulation run and then freezes it. Staged
        // here, fired from the lab's scene: the space builds only once the prop
        // cache is warm, so a clock started at launch paused a room that had
        // never run.
        let pauseAfter = UserDefaults.standard.double(forKey: "pauseAfter")
        if pauseAfter > 0 {
            pauseAfterSeconds = pauseAfter
        }
        #endif
    }

    #if DEBUG
    /// Seconds of simulation to allow before `-pauseAfter` freezes the
    /// active lab; consumed by the first scene that mounts.
    var pauseAfterSeconds: Double?

    /// The staged pause, counted from the moment a lab's scene is on
    /// screen. Cancelled with the scene, so leaving the lab first is
    /// simply no pause.
    func runStagedPause(for module: ModuleDescriptor) async {
        guard let seconds = pauseAfterSeconds else { return }
        pauseAfterSeconds = nil
        try? await Task.sleep(for: .seconds(seconds))
        guard !Task.isCancelled, activeModuleID == module.id else { return }
        module.togglePause()
    }
    #endif

    // MARK: Per-module models — created on first entry and retained

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

    private var orbitalMechanics: OrbitalMechanicsModel?

    var orbitalMechanicsModel: OrbitalMechanicsModel {
        if let orbitalMechanics { return orbitalMechanics }
        let model = OrbitalMechanicsModel()
        orbitalMechanics = model
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
