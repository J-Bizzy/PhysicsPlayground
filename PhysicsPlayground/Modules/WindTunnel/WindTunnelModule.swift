//
//  WindTunnelModule.swift
//  Physics Playground — Wind Tunnel module
//
//  Catalog registration for the wind tunnel: descriptor, legend, and
//  first-run hint. The real-world story lives in WindTunnelRealWorld.swift.
//

import SwiftUI

@MainActor
enum WindTunnelModule {
    static let id = "windtunnel"

    static func descriptor(appModel: AppModel) -> ModuleDescriptor {
        ModuleDescriptor(
            id: id,
            title: "Wind Tunnel",
            blurb: "An air-resistance lab: race a teardrop against a flat disc, spin the exact-flow cylinder for lift — and on device the wind bends around your own hands.",
            icon: "wind",
            accent: DesignTokens.Palette.windAccent,
            firstRunHint: "Pick a test body — the teardrop slips through the wind while the flat disc fights it 30 times harder at the same size. The cylinder keeps the exact ideal-flow exhibit: drag it, spin it, watch the lift arrow. On device, the air also bends around your hands and real objects in the room.",
            legend: legend,
            realWorld: WindTunnelRealWorld.story,
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
            swatch: .line(Color(uiColor: DesignTokens.Palette.streamlineUI)),
            text: "Streamlines — the paths the air actually follows (exact solution, not simulated)"
        ),
        LegendItem(
            swatch: .fill(DesignTokens.Palette.predictedArc),
            text: "Air particles riding the flow at true speed — watch them rush over the shoulders"
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
