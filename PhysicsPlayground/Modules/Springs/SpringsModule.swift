//
//  SpringsModule.swift
//  Physics Playground — Springs module
//
//  Catalog registration, window controls, and the real-world story.
//

import PhysicsCore
import SwiftUI

@MainActor
enum SpringsModule {
    static let id = "springs"

    static func descriptor(appModel: AppModel) -> ModuleDescriptor {
        ModuleDescriptor(
            id: id,
            title: "Elastic Field",
            blurb: "A membrane of coupled springs floating in your room — the real 2-D wave equation. Reach in, pull any point, and let go: waves ripple out, reflect off the rim, and ring the drumhead's modes.",
            icon: "waveform",
            accent: DesignTokens.Palette.springsAccent,
            firstRunHint: "Reach into the sheet, pinch a point, and pull it up — then let go. A wave spreads at speed c, bounces off the edges, and settles into standing patterns. Walk around it, duck underneath, ring a pure mode, or free the rim and watch the whole sheet heave.",
            legend: legend,
            realWorld: story,
            isPaused: { appModel.waveMediumModel.isPaused },
            togglePause: { appModel.waveMediumModel.isPaused.toggle() },
            makeControls: {
                AnyView(
                    WaveMediumControlsView()
                        .environment(appModel.waveMediumModel)
                )
            },
            makeScene: {
                AnyView(
                    WaveMediumSpaceView()
                        .environment(appModel.waveMediumModel)
                )
            },
            reset: {
                appModel.waveMediumModel.reset()
            }
        )
    }

    private static let legend: [LegendItem] = [
        LegendItem(swatch: .fill(Color(red: 1.0, green: 0.4, blue: 0.32)),
                   text: "Crests glow warm, troughs cool — the sheet's height IS the wave, shaded by real light so its 3-D shape reads from any side"),
        LegendItem(swatch: .fill(Color(red: 0.3, green: 0.85, blue: 0.85)),
                   text: "The rim traces the boundary — clamped (a drumhead) or free, changing how waves reflect"),
        LegendItem(swatch: .fill(.white),
                   text: "The halo marks the point in your hand; release it and the stored tension launches the wave"),
    ]

    private static let story = RealWorldStory(
        tagline: "Every wave — sound, water, a guitar string — is a medium of coupled springs doing exactly this.",
        applications: [
            .init(title: "Drums & speakers", icon: "speaker.wave.3.fill",
                  body: "A drumhead and a speaker cone are clamped membranes; the (m,p) modes you ring here are the timbres they make. Bigger or looser skins ring lower."),
            .init(title: "Earthquakes", icon: "waveform.path",
                  body: "Seismic waves travel through rock as this same wave equation — faster through stiff granite, slower through soft soil, reflecting off layer boundaries exactly like your rim."),
            .init(title: "Guitar & piano", icon: "guitars.fill",
                  body: "A plucked string is the 1-D version: pull it aside, release, and standing waves set the pitch. Tighter strings — higher c — sound higher; your wave-speed slider is the tuning peg."),
            .init(title: "Why instruments differ", icon: "music.note",
                  body: "A violin and a flute on the same note sound different because of the MIX of modes each excites — the standing patterns on this sheet, superposed."),
        ])
}

/// Window panel: the medium's parameters and the physics prose. The
/// room holds the sheet and two small pods; the paragraphs live here.
struct WaveMediumControlsView: View {
    @Environment(WaveMediumModel.self) private var model

    var body: some View {
        @Bindable var model = model

        VStack(alignment: .leading, spacing: DesignTokens.Panel.sectionSpacing) {
            PanelSection("The medium") {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Wave speed c = \(model.waveSpeed, specifier: "%.1f") m/s")
                        .font(DesignTokens.TypeScale.control.monospacedDigit())
                    Slider(value: $model.waveSpeed, in: WaveMediumModel.waveSpeedRange)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Damping: \(model.damping, specifier: "%.2f")")
                        .font(DesignTokens.TypeScale.control.monospacedDigit())
                    Slider(value: $model.damping, in: WaveMediumModel.dampingRange)
                }
                Toggle("Clamped rim (drumhead)", isOn: $model.boundaryFixed)
                    .font(DesignTokens.TypeScale.control)
            }

            PanelSection("What you're seeing") {
                Text("The sheet is a grid of masses joined by springs. In the small-displacement limit that IS the wave equation ∂²u/∂t² = c²∇²u: pull one point and the springs pull its neighbours, which pull theirs — a wave. Clamped edges reflect it inverted; the whole thing rings the drumhead's standing modes, the same shapes a real drum makes.")
                    .font(DesignTokens.TypeScale.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !model.insightText.isEmpty {
                Text(model.insightText)
                    .font(DesignTokens.TypeScale.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
