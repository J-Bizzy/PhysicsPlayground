//
//  OpticsModule.swift
//  Physics Playground — Ray Optics module
//
//  Catalog registration and the real-world story.
//

import PhysicsCore
import SwiftUI

@MainActor
enum OpticsModule {
    static let id = "optics"

    static func descriptor(appModel: AppModel) -> ModuleDescriptor {
        ModuleDescriptor(
            id: id,
            title: "Optics Studio",
            blurb: "One room, three light stations: the lens bench dead ahead, a prism spilling spectra on your left, and a laser you carry in your hand on the right — where you hold it IS the angle of incidence.",
            icon: "rays",
            accent: DesignTokens.Palette.opticsAccent,
            firstRunHint: "Look around — three stations. AHEAD: drag lenses along the rail. LEFT: rotate the prism until the exit face locks into total internal reflection. RIGHT: grab the little laser and carry it around the glass block — Snell's law follows your hand; sneak up on the block edge-on and the beam gets trapped inside.",
            legend: legend,
            isPaused: { false },
            togglePause: { },
            makeControls: {
                AnyView(
                    OpticsControlsView()
                        .environment(appModel.opticsModel)
                )
            },
            makeScene: {
                AnyView(
                    OpticsSpaceView()
                        .environment(appModel.opticsModel)
                )
            },
            reset: {
                appModel.opticsModel.reset()
            }
        )
    }

    private static let legend: [LegendItem] = [
        LegendItem(swatch: .line(Color(red: 1, green: 0.32, blue: 0.26)),
                   text: "Red beams — traced exactly through every lens (bend y/f) and mirror (fold)"),
        LegendItem(swatch: .fill(Color(red: 1, green: 0.85, blue: 0.3)),
                   text: "Gold marker — the image point the thin-lens equation predicts; the rays cross right on it"),
        LegendItem(swatch: .fill(Color(red: 0.3, green: 0.75, blue: 1)),
                   text: "Blue-rimmed lens converges; orange-rimmed diverges (virtual focus behind it)"),
        LegendItem(swatch: .line(Color(red: 0.55, green: 0.25, blue: 1)),
                   text: "The spectrum fan — seven wavelengths, each solving Snell's law with its own refractive index (Cauchy dispersion)"),
    ]

}

/// Window panel: the readouts and the physics prose. In-space the
/// room holds only instruments (the twist dials, the carried laser)
/// and short labels — the paragraphs live here, the flat/VoiceOver
/// path, so the room never fills with boxes of text.
struct OpticsControlsView: View {
    @Environment(OpticsModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Panel.sectionSpacing) {
            if let prediction = model.imagePrediction {
                PanelSection("Thin lens, live") {
                    Text("dₒ = \(prediction.objectDistance * 100, specifier: "%.0f") cm   dᵢ = \(prediction.imageDistance * 100, specifier: "%+.0f") cm   m = \(prediction.magnification, specifier: "%+.2f")")
                        .font(DesignTokens.TypeScale.control.monospacedDigit())
                    Text("1/f = 1/dₒ + 1/dᵢ — the gold marker in the scene sits on the traced crossing, not on this formula. They agree because the physics is real. Twist the blue dial above the lens to change f.")
                        .font(DesignTokens.TypeScale.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            PanelSection("Prism, on your left") {
                Text("Rotation θ = \(model.prismRotationDegrees, specifier: "%.0f")° — twist the coral dial under the prism.")
                    .font(DesignTokens.TypeScale.control.monospacedDigit())
                Text(model.prismShowsTIR
                     ? "The exit face is past the critical angle: it's a mirror now, and the spectrum reflects instead of leaving. Total internal reflection — the trick inside every optical fiber."
                     : "Blue light sees a higher refractive index than red (Cauchy dispersion), so it bends more — white light fans into a spectrum. Rotate toward +15° to lock the exit face into total internal reflection.")
                    .font(DesignTokens.TypeScale.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            PanelSection("Glass block, on your right") {
                if let entry = model.blockEntry {
                    Text("sin \(entry.incidence * 180 / .pi, specifier: "%.0f")° = n · sin \(entry.refraction * 180 / .pi, specifier: "%.0f")°   (n = \(model.blockIndex, specifier: "%.2f"))")
                        .font(DesignTokens.TypeScale.control.monospacedDigit())
                }
                Text(model.blockShowsTIR
                     ? "The beam is trapped inside — bouncing off the walls like light in a fiber. Ease the laser back toward face-on to release it."
                     : "Grab the laser and carry it: it always aims at the block, so your hand position IS the angle of incidence. Twist the blue dial to change n. Sneak the laser toward the block's edge-on side until the beam gets trapped.")
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
