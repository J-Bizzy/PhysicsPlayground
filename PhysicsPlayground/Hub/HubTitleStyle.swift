//
//  HubTitleStyle.swift
//  Physics Playground — Hub
//
//  The typographic voice of the home's three display texts — the
//  wordmark and the two door signs: widetracked uppercase bold, deeply
//  extruded, milled from the labs' own alloy. A namespace, not a
//  taxonomy. Exhibit nameplates and well glyphs keep `HubScene.bubbleText`.
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

    /// Leading multiplier. Capitals on both lines and a flush lockup that
    /// scales the shorter word up need air between them.
    static let leadingFactor: Float = 0.62

    /// Extrusion as a fraction of point size. Milled from stock, and the
    /// depth is load-bearing — see `line`.
    static let extrusionFactor: Float = 0.55

    // MARK: Building

    static func mesh(_ text: String, size: CGFloat) -> MeshResource {
        mesh(text, size: size, extrusion: Float(size) * extrusionFactor)
    }

    /// The same type at a chosen depth.
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
    /// the wordmark's neutral role; a colour is a door sign. One solid, one
    /// material — never a shadow copy: the extruded sides catching the light
    /// are the depth cue.
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
        // An emissive floor (not a glow) so the letters never crush to black in
        // the shaded parts of the extrusion; the specular highlight must stay
        // what shapes the bevel.
        metal.emissiveColor = .init(color: stock)
        metal.emissiveIntensity = 0.16

        let model = ModelEntity(mesh: mesh, materials: [metal])
        model.position = SIMD3(-(bounds.min.x + bounds.max.x) / 2,
                               -(bounds.min.y + bounds.max.y) / 2, 0)
        group.addChild(model)
        return group
    }

    /// A generated line and its extents — the shape `milled` returns, for
    /// words it has no asset for.
    @MainActor
    static func generated(_ text: String, size: CGFloat,
                          accent: UIColor?) -> (entity: Entity,
                                                extents: SIMD3<Float>) {
        (line(text, size: size, accent: accent), extents(text, size: size))
    }

    // MARK: The milled line

    /// The lines milled in Blender and the asset each became. A baked asset
    /// only knows the words it was baked with, so `milled` is optional.
    private static let milledAssets: [String: String] = [
        "Physics": "HubTitle_Physics",
        "Playground": "HubTitle_Playground",
    ]

    /// One line of display type, milled rather than generated; nil when
    /// there is no asset for these words. The asset buys the chamfer:
    /// `generateText` extrudes a sharp-edged prism, and the highlight along
    /// a bevel is what makes a solid read as one. `Tools/hubtitles.py`
    /// snapshots SF Pro Display at wght 700; the meshes are named for their
    /// role and coloured here.
    @MainActor
    static func milled(_ text: String, size: CGFloat,
                       accent: UIColor?) -> (entity: Entity,
                                             extents: SIMD3<Float>)? {
        guard let asset = milledAssets[text] else { return nil }
        guard let prototype = PropCache.prototype(named: asset) else { return nil }
        // The returned entity's scale must stay 1: callers assign
        // `entity.scale`, so `size` goes on a child.
        let group = Entity()
        let model = prototype.clone(recursive: true)
        group.addChild(model)

        // Anodised dark, cut bright: faces and extrusion walls are dark
        // (graphite, or the accent pulled toward black) and the chamfer band is
        // a separate bright alloy mesh. A dark face holds against a bright wall,
        // a bright rim against a dark one.
        let stock = accent.map {
            blend($0, toward: .black, by: 0.32)
        } ?? graphite
        // Anodise, not lacquer, and not `Materials.machined`: its clearcoat's
        // Fresnel term blows the extrusion walls (seen at grazing incidence by
        // definition) out to a pale slab. No clearcoat, metal down, roughness
        // up, so a wall answers its own dark base colour at every angle.
        var metal = PhysicallyBasedMaterial()
        metal.baseColor = .init(tint: stock)
        metal.metallic = .init(floatLiteral: 0.20)
        metal.roughness = .init(floatLiteral: 0.62)
        metal.clearcoat = .init(floatLiteral: 0.0)
        // A small emissive floor so the anodise never crushes to pure
        // black in the shaded parts of the extrusion.
        metal.emissiveColor = .init(color: stock)
        metal.emissiveIntensity = 0.16

        // The keyline must read at every rake, so it is not a specular effect:
        // a chamfer a fortieth of cap height lit only where a facet bisected
        // eye and light, aliasing into dashes. The emissive floor carries the
        // band; the raised roughness spreads what specular remains across both
        // facets.
        var rimMetal = PhysicallyBasedMaterial()
        rimMetal.baseColor = .init(tint: champagne)
        rimMetal.metallic = .init(floatLiteral: 0.30)
        rimMetal.roughness = .init(floatLiteral: 0.55)
        rimMetal.clearcoat = .init(floatLiteral: 0.0)
        rimMetal.emissiveColor = .init(color: champagne)
        rimMetal.emissiveIntensity = 0.55

        // Found by the mesh's name, which is what the USD exporter writes the
        // prim from; `Tools/hubtitles.py` names both object and mesh. Read off
        // ModelComponent rather than casting to ModelEntity, which `Entity.load`
        // need not return.
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
        // An unrecognised asset would render in Blender's preview greys, and
        // one without a rim mesh would anodise its chamfer dark; fall back to
        // the generated line rather than ship either.
        guard paintedLetters && paintedRim else { return nil }

        // Built at a nominal point size of 1, so `size` is the scale — on the
        // child.
        model.scale = SIMD3(repeating: Float(size))
        // Measured in the wrapper's space, which is what the caller stacks.
        let built = group.visualBounds(relativeTo: group)
        // Centred on its own origin, like `line`; the child moves, the wrapper
        // stays put.
        model.position -= built.center
        return (group, built.extents)
    }

    // MARK: The rake

    /// A slow turn so the light walks along the chamfer — geometry moves,
    /// the material does the rest. Yaw and pitch run at rates that do not
    /// divide, so the motion never repeats on a findable beat.
    static func rake(time: Double, phase: Double) -> simd_quatf {
        let yaw = rakeAmplitude * Float(sin(time * rakeRate + phase))
        let pitch = rakeAmplitude * 0.34
            * Float(sin(time * rakeRate * 0.61 + phase * 1.7))
        return simd_quatf(angle: yaw, axis: [0, 1, 0])
            * simd_quatf(angle: pitch, axis: [1, 0, 0])
    }

    /// About 1.6°: small enough that nobody catches the sign moving, large
    /// enough that the highlight does.
    static let rakeAmplitude: Float = 0.028
    /// Roughly a twelve-second cycle. Slower than the wordmark's bob so
    /// the two never lock into one motion.
    static let rakeRate: Double = 0.52

    // MARK: Shared tones

    /// Deliberately outside `DesignTokens.Palette`: these two are the
    /// in-space brand voice — signage, not wayfinding. The wordmark's
    /// neutral letters and its champagne, which the podium rim and the
    /// title rule also wear.
    static let ivory = UIColor(red: 0.99, green: 0.98, blue: 0.95, alpha: 1)
    static let champagne = UIColor(red: 1.0, green: 0.88, blue: 0.70, alpha: 1)
    /// The anodise the faces wear: dark enough to hold against a lit wall,
    /// warm enough to stay in the ivory/champagne family. The champagne
    /// lives on the cut.
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
