//
//  WavesModule.swift
//  Physics Playground — Waves module
//
//  Catalog registration for the ripple tank: descriptor, legend, and
//

import SwiftUI
import PhysicsCore

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
            // Opens part-dimmed: the wavefront rings and silence sheets are translucent and wash out.
            preferredDimming: 0.45,
            legend: legend,
            isPaused: { appModel.wavesModel.isPaused },
            togglePause: { appModel.wavesModel.isPaused.toggle() },
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
            captureReadings: {
                let model = appModel.wavesModel
                let probe = model.probeReadout
                var rows: [NotebookEntry.Reading] = [
                    .init("Sources", "\(model.sources.count)"),
                    .init("Frequency", String(format: "%.3f", model.frequency), "Hz"),
                    .init("Wave speed", String(format: "%.3f", model.waveSpeed), "m/s"),
                    .init("Wavelength", String(format: "%.4f", model.wavelength), "m"),
                    .init("Amplitude at probe",
                          String(format: "%.4f", probe.amplitude * 1000), "mm"),
                ]
                if let difference = probe.pathDifference,
                   let inWavelengths = probe.pathDifferenceInWavelengths {
                    rows.append(.init("Path difference",
                                      String(format: "%.4f", difference), "m"))
                    rows.append(.init("Δr / λ", String(format: "%.3f", inWavelengths)))
                }
                if let interference = probe.interference {
                    rows.append(.init("Interference", "\(interference)"))
                }
                if let separation = model.sourceSeparation {
                    rows.append(.init("Source separation",
                                      String(format: "%.4f", separation), "m"))
                }
                if let count = model.silentSurfaceCount {
                    rows.append(.init("Silence surfaces", "\(count)"))
                }
                return rows
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
        LegendItem(
            swatch: .fill(DesignTokens.Palette.waveSource),
            text: "Sweep a source through the field (or switch on Doppler flyby) and its wavefronts bunch ahead, stretch behind — the Doppler effect"
        ),
    ]
}
