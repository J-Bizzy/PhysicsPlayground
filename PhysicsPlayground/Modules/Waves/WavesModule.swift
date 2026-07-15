//
//  WavesModule.swift
//  Physics Playground — Waves module
//
//  Catalog registration for the ripple tank: descriptor, legend, and
//  first-run hint. The real-world story lives in WavesRealWorld.swift.
//

import SwiftUI

@MainActor
enum WavesModule {
    static let id = "waves"

    static func descriptor(appModel: AppModel) -> ModuleDescriptor {
        ModuleDescriptor(
            id: id,
            title: "Wave Interference",
            blurb: "A ripple tank at table height — drag wave sources around, flip one out of phase, and find the silent lines with your own hands.",
            icon: "water.waves",
            accent: DesignTokens.Palette.wavesAccent,
            firstRunHint: "Pinch a teal source and drag it across the pool — the pattern reorganizes live. Then flip 'Invert phase' and watch the loud midline go silent.",
            legend: legend,
            realWorld: WavesRealWorld.story,
            makeControls: {
                AnyView(
                    WavesControlsView()
                        .environment(appModel.wavesModel)
                )
            },
            makeScene: {
                AnyView(
                    WavesSpaceView()
                        .environment(appModel.wavesModel)
                )
            },
            reset: {
                appModel.wavesModel.reset()
            }
        )
    }

    private static let legend: [LegendItem] = [
        LegendItem(
            swatch: .fill(DesignTokens.Palette.waveSource),
            text: "Wave source — grab and drag it; all sources share one frequency, like a real ripple tank"
        ),
        LegendItem(
            swatch: .fill(DesignTokens.Palette.waveInverted),
            text: "Phase-inverted source (starts half a cycle late) — the active noise-cancelling trick"
        ),
        LegendItem(
            swatch: .stroke(DesignTokens.Palette.predictedArc),
            text: "Probe — park it anywhere for the local amplitude and path-difference math"
        ),
        LegendItem(
            swatch: .symbol("water.waves", DesignTokens.Palette.wavesAccent),
            text: "Surface heights are exaggerated ×6 for visibility; all panel numbers are true values"
        ),
    ]
}
