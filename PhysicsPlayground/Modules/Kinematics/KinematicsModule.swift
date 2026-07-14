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
            blurb: "Throw real balls across your room — slow time, hang hoops in mid-air, and try every gravity from zero-g to Jupiter.",
            icon: "paperplane.fill",
            accent: DesignTokens.Palette.kinematicsAccent,
            firstRunHint: "Grab any ball and throw it — physics takes over the instant you let go. For precise launches, drag the launcher anywhere and pinch its orange bead to aim.",
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
            swatch: .fill(DesignTokens.Palette.projectile),
            text: "Balls at their real sizes — grab and throw any of them, anywhere"
        ),
        LegendItem(
            swatch: .stroke(DesignTokens.Palette.kinematicsAccent),
            text: "Aim bead — pinch and drag to point the launcher; grab the launcher body to move it"
        ),
        LegendItem(
            swatch: .line(DesignTokens.Palette.predictedArc),
            text: "Predicted arc from the launcher, bounces included"
        ),
        LegendItem(
            swatch: .fill(DesignTokens.Palette.projectile),
            text: "Strobe dots — one per 1/15 s of simulated time, so wider spacing means faster (honest even in slow motion)"
        ),
        LegendItem(
            swatch: .stroke(DesignTokens.Palette.target),
            text: "Hoop — anything passing down through it scores; the dark disc under each ball marks the spot below it"
        ),
    ]
}
