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
        }
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

    /// Which bench the merged Fields module is showing (electric or
    /// magnetic), and which the merged Oscillators module is showing.
    /// They live here rather than in either physics model because they
    /// choose BETWEEN models.
    var fieldsBench: FieldsBench = .electric
    var oscillatorBench: OscillatorBench = .pendulum

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
            activeModuleID = id
        }
        if UserDefaults.standard.bool(forKey: "studioMode") {
            studioMode = true
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

    private var waves: WavesModel?

    var wavesModel: WavesModel {
        if let waves { return waves }
        let model = WavesModel()
        waves = model
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

    private var optics: OpticsModel?

    var opticsModel: OpticsModel {
        if let optics { return optics }
        let model = OpticsModel()
        optics = model
        return model
    }

    private var springs: SpringsModel?

    var springsModel: SpringsModel {
        if let springs { return springs }
        let model = SpringsModel()
        springs = model
        return model
    }

    private var waveMedium: WaveMediumModel?

    var waveMediumModel: WaveMediumModel {
        if let waveMedium { return waveMedium }
        let model = WaveMediumModel()
        waveMedium = model
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
