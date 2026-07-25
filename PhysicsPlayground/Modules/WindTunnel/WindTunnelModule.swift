//
//  WindTunnelModule.swift
//  Physics Playground — Wind Tunnel module
//
//  Catalog registration for the wind tunnel: descriptor, legend, and
//

import SwiftUI

@MainActor
enum WindTunnelModule {
    static let id = "windtunnel"

    static func descriptor(appModel: AppModel) -> ModuleDescriptor {
        ModuleDescriptor(
            id: id,
            title: "Wind Tunnel",
            blurb: "A real wind tunnel: a live incompressible flow solve routes the air around whatever you put in the stream, wraps it over the shoulders, and sheds a wake behind — and on device it does the same around your own hands and the furniture in your room.",
            icon: "wind",
            accent: DesignTokens.Palette.windAccent,
            firstRunHint: "Watch the smoke: it splits at the nose, races over the shoulders, and tumbles into a wake behind. Swap bodies to see shape decide everything — a box truck shoves the whole tunnel aside, an airliner barely creases it. On device, reach into the stream and the air breaks around your hand too.",
            legend: legend,
            isPaused: { appModel.windTunnelModel.isPaused },
            togglePause: { appModel.windTunnelModel.isPaused.toggle() },
            makeControls: {
                AnyView(
                    WindTunnelControlsView()
                        .environment(appModel.windTunnelModel)
                )
            },
            makeScene: {
                AnyView(
                    WindTunnelSpaceView()
                        .environment(appModel.windTunnelModel)
                )
            },
            reset: {
                appModel.windTunnelModel.reset()
            }
        )
    }

    private static let legend: [LegendItem] = [
        LegendItem(
            swatch: .fill(Color(uiColor: DesignTokens.Palette.launcherUI)),
            text: "Cylinder — grab and drag it; it visibly spins at the rate its circulation implies"
        ),
        LegendItem(
            swatch: .line(.white),
            text: "Smoke filaments — streamlines of a live incompressible flow solve, so they bend around any shape the way real air does. Warm where the air piles up and slows, cool where it accelerates past a shoulder"
        ),
        LegendItem(
            swatch: .fill(DesignTokens.Palette.predictedArc),
            text: "Smoke motes carried by that same solved field — they churn in the wake behind a bluff body and stay smooth behind a streamlined one"
        ),
        LegendItem(
            swatch: .fill(DesignTokens.Palette.forceVector),
            text: "Red dots: stagnation points where air comes to rest. Red arrow: Kutta–Joukowski lift when the cylinder spins"
        ),
        LegendItem(
            swatch: .stroke(DesignTokens.Palette.predictedArc),
            text: "Probe — park it anywhere for local speed and pressure coefficient"
        ),
    ]
}
