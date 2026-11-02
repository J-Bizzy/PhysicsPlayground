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

import RealityKit
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
        leavingScene = nil
        leavingFades = false
        activeModuleID = nil
    }

    // MARK: The door

    /// What the space shows: the home, or a lab by id.
    enum SceneKey: Hashable {
        case home
        case lab(String)
    }

    var currentScene: SceneKey { activeModuleID.map(SceneKey.lab) ?? .home }

    /// The scene still on screen while the one replacing it builds and
    /// settles out of sight (2026-11-02). Until then the room stood empty
    /// between them for a third of a second or more — black, in deep
    /// space — while the new scene took in its build (`Settle`); now the
    /// old one holds until the new one is ready, and the two cross-fade.
    private(set) var leavingScene: SceneKey?
    /// True once the replacement has settled and the leaving scene is
    /// fading out from under it.
    private(set) var leavingFades = false

    /// The scenes the space mounts: the leaving one, then the current one.
    var mountedScenes: [SceneKey] {
        guard let leavingScene, leavingScene != currentScene else { return [currentScene] }
        return [leavingScene, currentScene]
    }

    /// How long a scene takes to fade in or out; the cross-fade's length.
    static let departure: Double = 0.22
    /// The longest a leaving scene waits for its replacement to settle: a
    /// scene that never says so must not hold the door for ever.
    static let holdLimit: Double = 2.0

    /// The one door between labs, and between a lab and the home. The
    /// current scene stays while the next builds and settles behind it;
    /// then the next fades up as the old fades out (`sceneSettled`).
    func go(to id: String?) {
        guard id != activeModuleID else { return }
        // Nothing on screen to hold: straight through. Under Reduce Motion the
        // door still holds — the scenes cut rather than fade (`Fade.tick`,
        // the home's stillness), but the room never stands empty between them.
        guard isImmersiveSpaceOpen else {
            activeModuleID = id
            return
        }
        // One door at a time.
        guard leavingScene == nil else { return }
        leavingScene = currentScene
        leavingFades = false
        activeModuleID = id
        let incoming = currentScene
        #if DEBUG
        LaunchTrace.mark("[door] to \(id ?? "home"), holding the last scene")
        #endif
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(Self.holdLimit))
            self?.sceneSettled(incoming)
        }
    }

    /// A scene has taken in its build. If it is the one a door is waiting
    /// on, the scene it replaces starts fading out under it, and leaves the
    /// space once it has.
    func sceneSettled(_ scene: SceneKey) {
        guard scene == currentScene, let leaving = leavingScene, !leavingFades else { return }
        leavingFades = true
        #if DEBUG
        LaunchTrace.mark("[door] the new scene has settled; cross-fading")
        #endif
        Task { @MainActor [weak self] in
            // A frame past the fade, so the last frame drawn is a clear one.
            try? await Task.sleep(for: .seconds(Self.departure + 0.05))
            guard let self, self.leavingScene == leaving else { return }
            self.leavingScene = nil
            self.leavingFades = false
        }
    }

    /// Whether a mounted scene should be drawn: all of them are, but a
    /// leaving scene once its replacement is up.
    func isShown(_ scene: SceneKey) -> Bool {
        !(scene == leavingScene && leavingFades)
    }

    /// A lab's side of the door, every frame from its scene's update. Once
    /// its scene has settled it says so, and fades in — or, leaving, out.
    func doorTick(_ root: Entity, lab id: String, settled: Bool) {
        guard settled else { return }
        sceneSettled(.lab(id))
        Fade.tick(root, visible: isShown(.lab(id)), duration: Self.departure)
    }

    /// Where a lab stands: its placement while it is the one on screen.
    /// Nil for a lab on its way out, which holds where it stood while the
    /// next lab adopts its own placement.
    func placement(forLab id: String) -> SIMD3<Float>? {
        activeModuleID == id ? labPlacement.offset : nil
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

    /// Whether deep space's sky has fully come up (2026-11-02). Until it
    /// has, the space keeps the room's immersion and the room's dimmer, and
    /// the sky fades in over the room; full immersion came first before,
    /// which turned the room off and left black until the sky had settled
    /// and faded up.
    private(set) var isSkyUp = false

    /// The sky reports in: up once its fade has finished, down as it goes.
    func skyArrived(_ up: Bool) {
        guard up != isSkyUp else { return }
        isSkyUp = up
        refreshImmersionStyle()
    }

    private func refreshImmersionStyle() {
        immersionStyle = surroundings == .deepSpace && isSkyUp
            ? .full : (activeModule?.immersionStyle ?? .mixed)
        // The room is out of reach in deep space (`RoomModel.tangible`).
        let shown = surroundings == .room
        if room.isShown != shown { room.isShown = shown }
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
