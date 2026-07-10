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
    var activeModuleID: String?
    var isImmersiveSpaceOpen = false

    var activeModule: ModuleDescriptor? {
        guard let activeModuleID else { return nil }
        return ModuleCatalog.all(appModel: self).first { $0.id == activeModuleID }
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
}
