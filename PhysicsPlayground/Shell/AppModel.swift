//
//  AppModel.swift
//  Physics Playground — Shell
//
//  App-wide state: the active module, the shared immersive space, the
//  room and the atmosphere. Module models are created on
//  first entry and retained, so switching labs keeps their state. (The
//  catalog's `timeScrub` closures force every model the first time a
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
            // The lab's surroundings first: the immersion style reads them.
            adoptModuleAtmosphere()
            refreshImmersionStyle()
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

    /// The one door between labs, and between a lab and the home. A
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

    /// What stands around the wearer now (`Surroundings`): the lab's own
    /// for this visit when it has one, else the wearer's remembered choice.
    /// Deep space is full immersion; the room keeps each lab's own style.
    var surroundings: Surroundings {
        Surroundings.resolve(choice: settings.surroundings, labPrefers: labSurroundings)
    }

    /// The lab's surroundings for this visit: its descriptor's preference on
    /// entry, or what the wearer chose there since. Nil follows the choice.
    private(set) var labSurroundings: Surroundings?

    /// The wearer's choice, from More: remembered, and taken by the lab on
    /// screen too when it came with a preference of its own — choosing the
    /// room in Orbital Mechanics brings the room back now, not next visit.
    func choose(_ choice: Surroundings) {
        settings.surroundings = choice
        if labSurroundings != nil { labSurroundings = choice }
        refreshImmersionStyle()
    }

    /// The title bar's More: everything secondary in a lab, its live
    /// numbers included. Kept across labs, so a wearer who wants it open
    /// has it open in every room.
    var moreOpen = false

    /// The dimming target, 0…1: how far the shell is closed. Modules with no
    /// contrast against a sunlit wall open part-closed (`preferredDimming`);
    /// More's dimming slider sets it, and it sticks until another module is
    /// entered. `dimmingShown` is what the shell wears.
    var roomDimming: Double = AppModel.homeDimming

    /// The home's dimming: slight, so the portals and the opening's
    /// particles have contrast while the room stays the room.
    static let homeDimming: Double = 0.3

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

    private func adoptModuleAtmosphere() {
        // One descriptor build, not two — see `dimmingRadius`.
        let module = activeModule
        roomDimming = module?.preferredDimming ?? Self.homeDimming
        dimmingRadius = module?.preferredDimmingRadius ?? RoomDimmerView.defaultRadius
        labSurroundings = module?.preferredSurroundings
        if let id = activeModuleID { labPlacement.adopt(moduleID: id) }
    }

    private func refreshImmersionStyle() {
        immersionStyle = surroundings == .deepSpace
            ? .full : (activeModule?.immersionStyle ?? .mixed)
    }

    /// The user's real room — bounds, walls, furniture. Shared by every
    /// module; the ARKit session is reference-counted.
    let room = RoomModel()

    /// Where the active module's apparatus sits in the user's room.
    /// A pure display offset, remembered per module.
    let labPlacement = LabPlacement()

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
        // The app keeps no record of its wearer. Earlier builds kept a list of
        // every lab visited (for "New" badges), the Lab Notebook's captured
        // observations and the hoop best streak; an upgraded install forgets
        // all three.
        // The gallery's grab-bar placement went with the gallery.
        for retired in ["visited.modules", "notebook.entries.v1", "kinematics.bestStreak",
                        "hub.galleryOffset", "hub.galleryYaw"] {
            UserDefaults.standard.removeObject(forKey: retired)
        }
        // `-openModule <id>` jumps straight into a module; the simulator cannot
        // be gaze-pinched from the command line.
        #if DEBUG
        if let id = UserDefaults.standard.string(forKey: "openModule") {
            // An unknown id is refused by name rather than silently showing the
            // hub. `allIDs` validates without building every module's closures.
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
        // Observers do not fire in an initialiser, so a launch straight into
        // a lab adopts its atmosphere and surroundings here — or a cold
        // launch into Orbital Mechanics would open on .mixed, not in space.
        adoptModuleAtmosphere()
        #if DEBUG
        // `-surroundings space|room` holds for this launch over a lab's own
        // preference too (`AppSettings` takes it as the choice).
        if labSurroundings != nil,
           let argument = UserDefaults.standard.string(forKey: "surroundings"),
           let launch = Surroundings(argument: argument) {
            labSurroundings = launch
        }
        #endif
        refreshImmersionStyle()
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

    private var optics: OpticsModel?

    var opticsModel: OpticsModel {
        if let optics { return optics }
        let model = OpticsModel()
        optics = model
        return model
    }
}
