//
//  KinematicsModule.swift
//  Physics Playground — Kinematics module
//
//  Catalog registration for projectile motion: descriptor, legend, and
//  first-run hint. The real-world story lives in KinematicsRealWorld.swift.
//

import SwiftUI

@MainActor
enum KinematicsModule {
    static let id = "kinematics"

    static func descriptor(appModel: AppModel) -> ModuleDescriptor {
        ModuleDescriptor(
            id: id,
            title: "Projectile Motion",
            blurb: "Aim, fire, and walk around real trajectories — then flip on air resistance and see why golf balls have dimples.",
            icon: "paperplane.fill",
            accent: DesignTokens.Palette.kinematicsAccent,
            firstRunHint: "Pinch the orange bead in front of the launcher and drag to aim — the white arc previews the flight. Fire when it looks right.",
            legend: legend,
            realWorld: KinematicsRealWorld.story,
            makeControls: {
                AnyView(
                    KinematicsControlsView()
                        .environment(appModel.kinematicsModel)
                )
            },
            makeScene: {
                AnyView(
                    KinematicsSpaceView()
                        .environment(appModel.kinematicsModel)
                )
            },
            reset: {
                appModel.kinematicsModel.reset()
            }
        )
    }

    private static let legend: [LegendItem] = [
        LegendItem(
            swatch: .stroke(DesignTokens.Palette.kinematicsAccent),
            text: "Aim bead — pinch and drag it to point the launcher"
        ),
        LegendItem(
            swatch: .line(DesignTokens.Palette.predictedArc),
            text: "Predicted arc for the current aim, speed, and air setting"
        ),
        LegendItem(
            swatch: .fill(DesignTokens.Palette.projectile),
            text: "Projectile and its strobe dots — one dot per 1/15 s, so wider spacing means faster"
        ),
        LegendItem(
            swatch: .symbol("ruler", .secondary),
            text: "The scene is a 1:10 diorama; plate lines are 1 real meter apart. Panel numbers are true values. (Small balls are drawn enlarged to stay visible.)"
        ),
    ]
}
