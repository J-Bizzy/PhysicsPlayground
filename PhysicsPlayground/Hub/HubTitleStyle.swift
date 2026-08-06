//
//  HubTitleStyle.swift
//  Physics Playground — Hub
//
//  The typographic voice of the home's three display texts — the
//  wordmark and the two door signs. One voice, no alternatives, no
//  switch: widetracked uppercase bold, deeply extruded, milled from the
//  same alloy as the labs' instruments. Museum plaque, flight hardware.
//
//  THE PLAQUE SHIPS (owner's call, 2026-07-30), chosen off a specimen
//  wall that hung four candidates side by side in the room. On
//  2026-07-31 the wall and the Settings picker behind it both came out:
//  the decision had been made, and a made decision offered back as a
//  menu is not a feature, it is an unfinished argument.
//
//  The three losing voices stayed in this file for a while after that,
//  unreferenced, on the reasoning that deleting them would leave the
//  survivor looking arbitrary. That reasoning does not survive contact
//  with the file: an enum with four cases, a `shipping` constant, a
//  `current` global and a `switch` in every method is a CHOICE
//  mechanism, and a choice mechanism with one live option is just an
//  elaborate way of writing one option. The argument the specimen wall
//  settled lives in the git history and in DECISIONS.md, which is where
//  a settled argument belongs — not in three unreachable branches that
//  every future reader has to rule out.
//
//  So this is a namespace, not a taxonomy. It reads `HubTitleStyle.line`
//  rather than `HubTitleStyle.current.line`, because there is no current.
//
//  DELIBERATELY NOT the style of every text in the hub. The exhibit
//  nameplates and the Well glyphs keep `HubScene.bubbleText`: they are
//  labels on objects, this is display type, and restyling forty labels
//  because the marquee changed would be the tail wagging the dog.
//

import RealityKit
import RenderKit
import SwiftUI
import UIKit

enum HubTitleStyle {

    // MARK: The voice's parameters

    /// How the words are cased. The plaque speaks in capitals.
    static func display(_ text: String) -> String {
        text.uppercased()
    }

    /// The face. The system family, so dynamic content never falls back
    /// mid-word; the VOICE lives in weight and case.
    static func font(size: CGFloat) -> MeshResource.Font {
        .systemFont(ofSize: size, weight: .bold)
    }

    /// Leading multiplier. The plaque needs air: it is set in CAPITALS,
    /// so both lines are cap-height tall, and the flush lockup scales the
    /// shorter word up hard — two full-cap lines at different scales
    /// close the gap from both sides at once.
    static let leadingFactor: Float = 0.62

    /// Extrusion as a fraction of point size. Milled from stock, and the
    /// depth is load-bearing — see `line`.
    static let extrusionFactor: Float = 0.55

    // MARK: Building

    static func mesh(_ text: String, size: CGFloat) -> MeshResource {
        MeshResource.generateText(
            display(text), extrusionDepth: Float(size) * extrusionFactor,
            font: font(size: size), alignment: .center)
    }

    /// Measured extents — case, face and depth included, so the
    /// flush-width lockup math is measuring what it will actually build.
    static func extents(_ text: String, size: CGFloat) -> SIMD3<Float> {
        mesh(text, size: size).bounds.extents
    }

    /// One line of display type, centred on its own origin.
    /// `accent` nil is the wordmark's neutral role; a colour is a door
    /// sign speaking in its domain's voice.
    ///
    /// ONE solid, one material. It was three passes and they fought: a
    /// dark copy behind the metal has to sit further back than the
    /// extrusion is deep or the two meshes interpenetrate, and this type
    /// is deep — so any offset small enough to read as a shadow was small
    /// enough to punch through the faces. The symptom was letters that
    /// looked doubled and lines that looked like they collided; the cause
    /// was two solids sharing a volume.
    ///
    /// A real plaque does not need a drop shadow. It is a thick object,
    /// and its own extruded sides catch the light at a different angle
    /// from its face. That IS the depth cue, and it holds from every
    /// viewing angle, which a fixed offset never does.
    @MainActor
    static func line(_ text: String, size: CGFloat, accent: UIColor?) -> Entity {
        let group = Entity()
        let mesh = mesh(text, size: size)
        let bounds = mesh.bounds

        // These values were derived here, on the specimen wall, and then
        // promoted: `Materials.machined` IS this recipe, and the
        // reasoning behind every number lives on it now. The labs' metal
        // is the same alloy as the signage.
        let stock = accent.map {
            blend($0, toward: UIColor(white: 0.72, alpha: 1), by: 0.30)
        } ?? UIColor(white: 0.78, alpha: 1)
        var metal = Materials.machined(stock)
        // A low emissive floor so the letters never fall to pure black in
        // the shaded parts of the extrusion — the anodised colour stays
        // legible all the way round the bevel.
        metal.emissiveColor = .init(color: stock)
        metal.emissiveIntensity = 0.16

        let model = ModelEntity(mesh: mesh, materials: [metal])
        model.position = SIMD3(-(bounds.min.x + bounds.max.x) / 2,
                               -(bounds.min.y + bounds.max.y) / 2, 0)
        group.addChild(model)
        return group
    }

    // MARK: Shared tones

    /// Deliberately OUTSIDE `DesignTokens.Palette`'s accent system,
    /// which became the one authority for module and domain hues on
    /// 2026-08-06: these two are the in-space brand voice — signage,
    /// not wayfinding — and folding them into the accent table would
    /// invite exactly the borrowing it exists to prevent.
    /// The wordmark's neutral letters and its champagne — the same two
    /// tones the home has always spoken its neutral role in, so the
    /// podium rim and the title rule (also champagne) keep matching.
    static let ivory = UIColor(red: 0.99, green: 0.98, blue: 0.95, alpha: 1)
    static let champagne = UIColor(red: 1.0, green: 0.88, blue: 0.70, alpha: 1)

    /// A derived tint of a canonical colour, never a new hue.
    static func blend(_ color: UIColor, toward target: UIColor,
                      by fraction: CGFloat) -> UIColor {
        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
        var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
        color.getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        target.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        return UIColor(red: r1 + (r2 - r1) * fraction,
                       green: g1 + (g2 - g1) * fraction,
                       blue: b1 + (b2 - b1) * fraction,
                       alpha: a1)
    }
}
