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
            title: "Ray Optics",
            blurb: "A laser bench in mid-air: slide lenses and mirrors along the rail and watch the thin-lens equation draw itself in light.",
            icon: "rays",
            accent: DesignTokens.Palette.opticsAccent,
            firstRunHint: "The beam is live — drag the lens along the rail and watch the focus chase it. Switch to a point source and the gold marker sits exactly where 1/f = 1/dₒ + 1/dᵢ predicts. Add mirrors and screens from the panel.",
            legend: legend,
            realWorld: story,
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
    ]

    private static let story = RealWorldStory(
        tagline: "Every camera, telescope, and eyeball is this bench, folded up.",
        applications: [
            .init(title: "Your own eye", icon: "eye.fill",
                  body: "The cornea and lens form a converging system imaging the world onto your retina — near- and far-sightedness are just the image landing off the screen, and glasses slide the focus back."),
            .init(title: "Cameras", icon: "camera.fill",
                  body: "Focusing a lens is exactly dragging it along this rail: changing dₒ and dᵢ so the image lands on the sensor. f-numbers, zoom, macro — all thin-lens arithmetic."),
            .init(title: "Telescopes & microscopes", icon: "binoculars.fill",
                  body: "Two lenses sharing a focal point: one forms a real image, the second magnifies it. Galileo's telescope was this bench with better mounts."),
            .init(title: "Fiber optics", icon: "network",
                  body: "Past the critical angle, glass becomes a perfect mirror — total internal reflection traps light inside a hair-thin fiber for thousands of kilometers of internet."),
        ])
}

/// Window panel: nothing beyond the in-space controls yet.
struct OpticsControlsView: View {
    @Environment(OpticsModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Panel.sectionSpacing) {
            if let prediction = model.imagePrediction {
                PanelSection("Thin lens, live") {
                    Text("dₒ = \(prediction.objectDistance * 100, specifier: "%.0f") cm   dᵢ = \(prediction.imageDistance * 100, specifier: "%+.0f") cm   m = \(prediction.magnification, specifier: "%+.2f")")
                        .font(DesignTokens.TypeScale.control.monospacedDigit())
                    Text("1/f = 1/dₒ + 1/dᵢ — the gold marker in the scene sits on the traced crossing, not on this formula. They agree because the physics is real.")
                        .font(DesignTokens.TypeScale.footnote)
                        .foregroundStyle(.secondary)
                }
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
