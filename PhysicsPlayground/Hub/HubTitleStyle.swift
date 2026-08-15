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
        //
        // ANODISED DARK since 2026-08-13, matching `milled` — the same
        // legibility finding, applied to the fallback so a missing asset
        // degrades in tone rather than in voice. The generated prism has
        // no rim mesh to cut bright, so this path leans entirely on the
        // dark face.
        let stock = accent.map {
            blend($0, toward: .black, by: 0.32)
        } ?? graphite
        var metal = Materials.machined(stock)
        // An emissive floor so the letters never fall to pure black in
        // the shaded parts of the extrusion — the anodised colour stays
        // legible all the way round the bevel.
        //
        // 0.16 UNTIL 2026-08-08, and the owner's word for what it needed
        // was "pop". The problem this solves is specific to a headset:
        // the plaque is machined metal, so most of what you see is
        // REFLECTED light, and the gallery is drawn over whatever room
        // the wearer is standing in. Against a bright wall the highlights
        // and the passthrough behind them land at nearly the same
        // luminance and the mark goes soft — the same failure the colour
        // it replaced had, one step further along.
        //
        // Lifting the floor to 0.34 makes the letterform carry its own
        // light rather than borrowing the room's, so the shape holds at
        // any wall brightness. It stays a floor, not a glow: the
        // specular highlight is still what shapes the bevel, which is
        // what keeps it reading as metal rather than as a lit sign.
        metal.emissiveColor = .init(color: stock)
        // BACK TO 0.16 ON 2026-08-08. I pushed this to 0.34 to make the
        // wordmark "pop" and a screenshot showed it had not: the mark
        // was still a ghost on a cream wall, because light-on-light has
        // no contrast and a brighter light does not create any. What
        // fixed it was giving the letters something dark to be ivory
        // against — first a backing plate, and since 2026-08-09 the
        // keyline below — and with that in place the original floor is
        // the right one again.
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

    /// ONE LINE OF DISPLAY TYPE, MILLED RATHER THAN GENERATED — same
    /// contract as `keylined`, and nil when there is no asset for these
    /// words.
    ///
    /// WHAT THE ASSET BUYS, IN ONE WORD: THE CHAMFER.
    /// `MeshResource.generateText` extrudes a flat prism — a face,
    /// straight sides, and a sharp ninety-degree edge between them. The
    /// note on `line` says the plaque's depth cue is its extruded sides
    /// catching the light at a different angle from its face, and that
    /// is true, but a square edge catches it in a hard line, which is
    /// what a stamped part looks like. `blenderprops.bevel` states the
    /// house position: a machined part has no sharp corners, and the
    /// highlight running along a bevel is most of what makes a shape
    /// read as a solid object rather than as a box. This is the plaque
    /// finally being milled instead of claiming to be.
    ///
    /// THE TYPEFACE DID NOT CHANGE. Blender cannot read SF Pro's Bold —
    /// `SFNS.ttf` is a variable font and its default instance is
    /// Regular — so `Tools/hubtitles.py` snapshots it at wght 700 with
    /// fontTools before building. It also pins the optical size to SF
    /// Pro's DISPLAY cut, which is the right face for type set this
    /// large and which `.systemFont(ofSize:weight:)` cannot ask for.
    ///
    /// THE COLOUR IS STILL SWIFT'S. The asset carries two meshes named
    /// for their role and nothing else; the alloy, the accent blend and
    /// the casing are assigned here, so `Materials.machined` and
    /// `DesignTokens.Palette` remain the one authority on what the home
    /// is coloured. Bake geometry, never bake the design system.
    @MainActor
    static func milled(_ text: String, size: CGFloat,
                       accent: UIColor?) -> (entity: Entity,
                                             extents: SIMD3<Float>)? {
        guard let asset = milledAssets[text] else { return nil }
        guard let prototype = PropCache.prototype(named: asset) else { return nil }
        // THE RETURNED ENTITY'S OWN SCALE MUST STAY 1, and this wrapper
        // is the whole reason for it. Both lockups above finish with
        //
        //     item.entity.scale = SIMD3(repeating: scale)
        //
        // — an ASSIGNMENT, not a multiply, because `keylined` hands back
        // a line whose size is already in its geometry. Putting `size`
        // on the entity here instead means that assignment silently
        // throws it away, the asset reverts to its nominal point size of
        // ONE METRE, and the wordmark comes up about six times too big
        // and swallows the room.
        //
        // Which is exactly what it did. Every test still passed —
        // they inspect what this function returns, and what it returns
        // was correct; the defect only exists once the caller composes
        // with it. A screenshot found it in one frame.
        //
        // So `size` goes on a CHILD and the wrapper stays free for the
        // caller to scale.
        let group = Entity()
        let model = prototype.clone(recursive: true)
        group.addChild(model)

        // ANODISED DARK, CUT BRIGHT (2026-08-13). Three generations of
        // this sign chased legibility with LIGHT — ivory letters, a
        // raised emissive floor, a keyline, a backing plate — and every
        // one ran into the same wall: the gallery is drawn over the
        // wearer's own room, and light-on-light has no edge. This build
        // goes the other way round. The faces and extrusion walls are
        // anodised dark — the wordmark in graphite, a door sign in its
        // accent pulled a third toward black, which keeps the hue that
        // does the wayfinding while giving the letters real weight —
        // and the chamfer band is a SEPARATE mesh left bright champagne
        // alloy, the way a diamond-cut badge shows bare metal exactly
        // where the tool touched the stock. A dark face holds the mark
        // against a bright wall; the bright rim holds it against a dark
        // one; and the rake finally has a real edge to walk light along.
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

    /// A slow turn, so the light walks across the letterforms.
    ///
    /// THIS IS AN ANIMATION THAT ONLY WORKS BECAUSE THE TYPE IS MILLED,
    /// which is why it is the one that got built. The letters carry a
    /// real chamfer around every stroke; turning the line a degree and a
    /// half moves where that chamfer catches the key light, so the
    /// highlight travels along the edge of each glyph and the mark reads
    /// as a metal object sitting in a lit room. Flat extruded type doing
    /// the same thing just looks like a sign wobbling — there is no edge
    /// for the light to run along.
    ///
    /// So nothing here is animating an EFFECT. It moves the geometry a
    /// little and lets the material do what a material does, which is
    /// also why it costs one transform per line and no per-frame
    /// material work.
    ///
    /// DELIBERATELY NOT A KINETIC BODY. An electron lapped the E&M sign
    /// and a ball crossed the Mechanics rule through two full redesigns,
    /// and the owner cut both on 2026-08-04 — "still is pretty bad".
    /// Those put a PROP next to the type. This animates the type.
    ///
    /// Yaw and pitch run at rates that do not divide into each other, so
    /// the pair never repeats on a short cycle and the motion has no
    /// findable beat — the fastest way to make slow movement look
    /// mechanical is to let the reader catch its period.
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
