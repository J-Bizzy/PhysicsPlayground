//
//  WindTunnelModule.swift
//  Physics Playground — Wind Tunnel module
//
//  Catalog registration for the wind tunnel: descriptor, legend, and
//

import SwiftUI
import PhysicsCore

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
            // Opens part-dimmed: smoke is near-white and disappeared entirely into white walls.
            preferredDimming: 0.3,
            legend: legend,
            isPaused: { appModel.windTunnelModel.isPaused },
            togglePause: { appModel.windTunnelModel.isPaused.toggle() },
            makeScene: {
                AnyView(
                    WindTunnelSpaceView()
                        .environment(appModel.windTunnelModel)
                )
            },
            captureReadings: {
                let model = appModel.windTunnelModel
                let probe = model.probeReadout
                var rows: [NotebookEntry.Reading] = [
                    .init("Test body", model.testBody.displayName),
                    .init("Drag coefficient",
                          String(format: "%.3f", model.testBody.dragCoefficient)),
                    .init("Wind speed", String(format: "%.2f", model.windSpeed), "m/s"),
                    .init("Drag force", String(format: "%.4f", model.dragForce), "N"),
                    .init("Speed at probe", String(format: "%.3f", probe.speed), "m/s"),
                    .init("Pressure coefficient", String(format: "%.3f", probe.pressureCoefficient)),
                ]
                if model.testBody == .cylinder {
                    rows.append(.init("Circulation", String(format: "%.3f", model.circulation), "m²/s"))
                    rows.append(.init("Spin", String(format: "%.0f", model.spinRPM), "rpm"))
                    rows.append(.init("Lift per span",
                                      String(format: "%.4f", model.liftPerSpan), "N/m"))
                }
                return rows
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
            swatch: .fill(Color(red: 0.92, green: 0.13, blue: 0.10)),
            text: "The body's PRESSURE SKIN — Cp read off the solved flow just outside the surface. Red is air piling up and pushing back (that is where drag comes from); blue is air accelerated past, at lower pressure (that is where lift comes from). Grey means free-stream: nothing happening"
        ),
        LegendItem(
            swatch: .line(Color(red: 0.85, green: 0.24, blue: 0.10)),
            text: "Red filament — air piled up and slowed. Because the flow is incompressible, Cp = 1 − (v/U)², so slow means HIGH PRESSURE: the red band across a nose is the pressure that becomes drag"
        ),
        LegendItem(
            swatch: .line(Color(red: 0.11, green: 0.78, blue: 0.92)),
            text: "Cyan filament — air accelerated past a shoulder, and so at LOW pressure. Over a wing that is exactly where lift comes from"
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
