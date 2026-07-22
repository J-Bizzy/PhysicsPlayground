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
            immersionStyle = activeModule?.immersionStyle ?? .mixed
        }
    }
    var isImmersiveSpaceOpen = false
    /// Cross-module challenge progress (persisted).
    let challenges = ChallengeProgress()
    /// Driven by the active module's descriptor; bound to the shared
    /// immersive space's style selection.
    var immersionStyle: ImmersionStyle = .mixed
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
            activeModuleID = id
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
}
