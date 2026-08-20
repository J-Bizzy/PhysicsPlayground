//
//  HubTitleStyle.swift
//  Physics Playground — Hub
//
//  The typographic voice of the home's three display texts — the wordmark
//  and the two door signs. One voice, no alternatives: widetracked
//  uppercase bold, deeply extruded, milled from the labs' own alloy.
//
//  A NAMESPACE, not a taxonomy — `HubTitleStyle.line`, not
//  `.current.line`, because there is no current. Deliberately NOT the
//  style of every text in the hub: exhibit nameplates and Well glyphs keep
//  `HubScene.bubbleText`, since those are labels on objects.
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
        mesh(text, size: size, extrusion: Float(size) * extrusionFactor)
    }

    /// The same type at a chosen depth — the keyline's shell is a deeper
    /// solid than the letter it backs, so the letter is contained rather
    /// than merely near it.
    static func mesh(_ text: String, size: CGFloat,
                     extrusion: Float) -> MeshResource {
        MeshResource.generateText(
            display(text), extrusionDepth: extrusion,
            font: font(size: size), alignment: .center)
    }

    /// Measured extents — case, face and depth included, so the
    /// flush-width lockup math is measuring what it will actually build.
    static func extents(_ text: String, size: CGFloat) -> SIMD3<Float> {
        mesh(text, size: size).bounds.extents
    }

    /// One line of display type, centred on its own origin. `accent` nil is
    /// the wordmark's neutral role; a colour is a door sign in its domain's
    /// voice.
    ///
    /// ONE solid, one material — never a shadow copy behind it. This type is
    /// deeply extruded, so any offset small enough to read as a shadow is
    /// small enough to interpenetrate the faces; the extruded sides catching
    /// the light at their own angle ARE the depth cue.
    @MainActor
    static func line(_ text: String, size: CGFloat, accent: UIColor?) -> Entity {
        let group = Entity()
        let mesh = mesh(text, size: size)
        let bounds = mesh.bounds

        // Anodised dark, matching `milled`: the generated prism has no rim
        // mesh to cut bright, so this fallback leans on the dark face.
        let stock = accent.map {
            blend($0, toward: .black, by: 0.32)
        } ?? graphite
        var metal = Materials.machined(stock)
        // An emissive FLOOR (not a glow) so the letters never fall to pure
        // black in the shaded parts of the extrusion. Kept low: raising it
        // does not fix legibility on a bright wall — light-on-light has no
        // contrast — and the specular highlight must stay what shapes the
        // bevel, or the plaque reads as a lit sign rather than as metal.
        metal.emissiveColor = .init(color: stock)
        metal.emissiveIntensity = 0.16

        let model = ModelEntity(mesh: mesh, materials: [metal])
        model.position = SIMD3(-(bounds.min.x + bounds.max.x) / 2,
                               -(bounds.min.y + bounds.max.y) / 2, 0)
        group.addChild(model)
        return group
    }

    /// A generated line and its extents — the shape `milled` returns,
    /// for the words it has no asset for.
    ///
    /// This is what is left of `keylined`, which was deleted on
    /// 2026-08-11 along with the casing it existed to build. That
    /// builder laid a line out glyph by glyph for one reason: a shell
    /// scaled about a whole STRING lands each letter's swell between
    /// its neighbours, so it had to swell each glyph about its own
    /// centre instead. With no shell there is nothing to misregister,
    /// and a line of text is one mesh again — which is what `line` has
    /// always made.
    @MainActor
    static func generated(_ text: String, size: CGFloat,
                          accent: UIColor?) -> (entity: Entity,
                                                extents: SIMD3<Float>) {
        (line(text, size: size, accent: accent), extents(text, size: size))
    }

    // MARK: The milled line

    /// The lines that were milled in Blender, and the asset each became.
    ///
    /// A BAKED ASSET ONLY KNOWS THE WORDS IT WAS BAKED WITH, which is
    /// the one real cost of this route and the reason `milled` returns
    /// an optional rather than trusting a lookup. The home says exactly
    /// these six things and has since the two doors landed; anything
    /// else falls through to `keylined` and is merely generated, which
    /// is what every line was until now.
    private static let milledAssets: [String: String] = [
        "Physics": "HubTitle_Physics",
        "Playground": "HubTitle_Playground",
        "Electricity": "HubTitle_Electricity",
        "& Magnetism": "HubTitle_Magnetism",
        "Mechanics": "HubTitle_Mechanics",
        "& Energy": "HubTitle_Energy",
    ]

    // The local `milledCache` went with the shared `PropCache`
    // (2026-08-15): one prototype cache for the whole app, warmed
    // off-main before the space opens.

    /// One line of display type, MILLED rather than generated; nil when
    /// there is no asset for these words.
    ///
    /// What the asset buys is THE CHAMFER: `generateText` extrudes a flat
    /// prism with a sharp ninety-degree edge, and the highlight running
    /// along a bevel is most of what makes a shape read as a solid object.
    /// The typeface is unchanged — `Tools/hubtitles.py` snapshots SF Pro at
    /// wght 700 (Blender cannot read the variable font's Bold) and pins the
    /// DISPLAY optical cut. BAKE GEOMETRY, NEVER THE DESIGN SYSTEM: the
    /// asset's meshes are named for their role and coloured here.
    @MainActor
    static func milled(_ text: String, size: CGFloat,
                       accent: UIColor?) -> (entity: Entity,
                                             extents: SIMD3<Float>)? {
        guard let asset = milledAssets[text] else { return nil }
        guard let prototype = PropCache.prototype(named: asset) else { return nil }
        // THE RETURNED ENTITY'S SCALE MUST STAY 1: callers finish with
        // `entity.scale = ...`, an ASSIGNMENT, so a scale set here would be
        // thrown away and the asset would revert to its nominal ONE METRE.
        // `size` therefore goes on a CHILD, leaving the wrapper free.
        let group = Entity()
        let model = prototype.clone(recursive: true)
        group.addChild(model)

        // ANODISED DARK, CUT BRIGHT. Chasing legibility with light fails —
        // the gallery draws over the wearer's room and light-on-light has
        // no edge — so faces and extrusion walls are dark (graphite, or an
        // accent pulled a third toward black to keep the wayfinding hue)
        // while the chamfer band stays a SEPARATE bright alloy mesh. Dark
        // face holds against a bright wall, bright rim against a dark one.
        let stock = accent.map {
            blend($0, toward: .black, by: 0.32)
        } ?? graphite
        // A small emissive floor so the anodise never crushes to pure
        // black in the shaded parts of the extrusion.
        var metal = Materials.machined(stock)
        metal.emissiveColor = .init(color: stock)
        metal.emissiveIntensity = 0.16

        // The cut edge. A higher floor than the face on purpose: the rim
        // is a thin line doing the silhouette's work, and it must not
        // die in shade — while staying a floor, not a glow, so the
        // specular walk of the rake still shapes it.
        var rimMetal = Materials.machined(champagne)
        rimMetal.emissiveColor = .init(color: champagne)
        rimMetal.emissiveIntensity = 0.30

        // Found by the MESH's name, which is what the USD exporter
        // writes the prim from — naming only the Blender object ships a
        // file whose part comes back as `Text_007`, and that file loads
        // and renders perfectly while quietly defeating this lookup.
        // `Tools/hubtitles.py` names both object and mesh.
        //
        // Read off ModelComponent rather than casting to ModelEntity:
        // `Entity.load` is under no obligation to hand back that
        // subclass, and a cast that quietly fails would paint nothing
        // and look like a missing asset.
        var paintedLetters = false
        var paintedRim = false
        func paint(_ entity: Entity) {
            if var model = entity.components[ModelComponent.self] {
                if entity.name.contains("Rim") {
                    model.materials = [rimMetal]
                    entity.components.set(model)
                    paintedRim = true
                } else if entity.name.contains("Letters") {
                    model.materials = [metal]
                    entity.components.set(model)
                    paintedLetters = true
                }
            }
            for child in entity.children { paint(child) }
        }
        paint(group)
        // An unrecognised asset would render in Blender's preview greys
        // — near enough to shippable to go unnoticed, and wrong. And an
        // asset carrying only `Letters` is from before the rim split:
        // its chamfer would anodise dark along with the face and the
        // silhouette would go with it. Rather than show a mark this app
        // does not own the look of, fall back to the generated line,
        // which is always current.
        guard paintedLetters && paintedRim else { return nil }

        // Built at a nominal point size of 1, so `size` IS the scale.
        // On the child, per the note above.
        model.scale = SIMD3(repeating: Float(size))
        // Measured in the WRAPPER's space, which is where the caller
        // will read it — so these extents describe the object that
        // actually gets stacked.
        let built = group.visualBounds(relativeTo: group)
        // Centred on its own origin, the same contract `line` and
        // `keylined` offer, so the lockup stacking above is unchanged.
        // The child moves; the wrapper stays at the origin with an
        // untouched transform.
        model.position -= built.center
        return (group, built.extents)
    }

    // MARK: The rake

    /// A slow turn, so the light walks across the letterforms — an
    /// animation that only works because the type is MILLED: the chamfer
    /// gives the highlight an edge to travel along. Nothing here animates
    /// an effect; it moves the geometry and lets the material do the rest,
    /// so it costs one transform per line and no per-frame material work.
    ///
    /// Yaw and pitch run at rates that do not divide into each other, so
    /// the motion never repeats on a findable beat.
    static func rake(time: Double, phase: Double) -> simd_quatf {
        let yaw = rakeAmplitude * Float(sin(time * rakeRate + phase))
        let pitch = rakeAmplitude * 0.34
            * Float(sin(time * rakeRate * 0.61 + phase * 1.7))
        return simd_quatf(angle: yaw, axis: [0, 1, 0])
            * simd_quatf(angle: pitch, axis: [1, 0, 0])
    }

    /// About 1.6 degrees. Small enough that nobody catches the sign
    /// moving; large enough that the highlight does. On a 0.6 m line
    /// this swings the ends by roughly 8 mm in depth.
    static let rakeAmplitude: Float = 0.028
    /// Roughly a twelve-second cycle. Slower than the wordmark's bob so
    /// the two never lock into one motion.
    static let rakeRate: Double = 0.52

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
    /// The anodise the faces wear since 2026-08-13 — dark enough to hold
    /// against a lit wall, warm enough to stay in the ivory/champagne
    /// family rather than reading as printer black. The champagne now
    /// lives on the CUT: the rim mesh is the one place the bare alloy
    /// shows, which is what ties the dark plaque back to the podium rim
    /// and the title rule.
    static let graphite = UIColor(red: 0.155, green: 0.150, blue: 0.140,
                                  alpha: 1)

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
