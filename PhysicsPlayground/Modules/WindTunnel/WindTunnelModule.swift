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
            blurb: "Drag a cylinder through an exact airflow, spin it, and watch lift appear — the Magnus effect, with the math on display.",
            icon: "wind",
            accent: DesignTokens.Palette.windAccent,
            firstRunHint: "Pinch the cylinder and drag it through the flow — the streamlines re-form instantly. Then add spin and watch the red lift arrow appear.",
            legend: legend,
            realWorld: WindTunnelRealWorld.story,
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
