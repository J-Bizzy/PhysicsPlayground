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
            blurb: "A wave field filling the space around you — float sources anywhere, flip one out of phase, and walk through the surfaces of silence.",
            icon: "water.waves",
            accent: DesignTokens.Palette.wavesAccent,
            firstRunHint: "Pinch a teal source and float it anywhere — the whole field reorganizes live. Flip 'Invert phase' and a silence sheet appears between the sources.",
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
            text: "Wave source — float it anywhere; all sources share one frequency, and waves spread as real spheres (1/r)"
        ),
        LegendItem(
            swatch: .fill(DesignTokens.Palette.waveInverted),
            text: "Phase-inverted source (starts half a cycle late) — the active noise-cancelling trick"
        ),
        LegendItem(
            swatch: .translucent(DesignTokens.Palette.wavesAccent),
            text: "Lattice dots — size pulses with the live field, brightness marks where it ever gets loud"
        ),
        LegendItem(
            swatch: .translucent(DesignTokens.Palette.forceVector),
            text: "Silence surfaces — the 3D sheets where crest always meets trough; nothing oscillates there"
        ),
        LegendItem(
            swatch: .stroke(DesignTokens.Palette.predictedArc),
            text: "Probe — park it anywhere for the local amplitude and path-difference math"
        ),
    ]
}
