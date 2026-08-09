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
        let stock = accent.map {
            blend($0, toward: UIColor(white: 0.72, alpha: 1), by: 0.30)
        } ?? UIColor(white: 0.78, alpha: 1)
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

    // MARK: The keyline

    /// A LINE OF DISPLAY TYPE WITH A DARK SHELL HUGGING EVERY GLYPH,
    /// and its measured extents, because the lockup math must measure
    /// what it will actually build.
    ///
    /// WHY THIS SHAPE, AND NOT THE TWO OBVIOUS ONES.
    ///
    /// The problem is fixed and specific: the mark is ivory machined
    /// metal drawn over whatever wall the wearer is standing in front
    /// of, and light-on-light has no contrast. Raising the emissive
    /// floor was tried on 2026-08-08 and did nothing — a brighter light
    /// against a bright wall is still no edge. DECISIONS.md settled the
    /// principle on 2026-07-26 in four words: CASINGS BEAT GLOWS.
    ///
    /// The first casing was a rectangular backing plate, and it worked.
    /// It was also a black slab hanging in the room behind the words,
    /// which the owner cut on 2026-08-09: the contrast is wanted, the
    /// panel is not.
    ///
    /// So the casing follows the letterforms. Two ways to build that
    /// have already failed here and both are worth naming:
    ///
    /// · A DARK COPY OFFSET BACK — tried when this file was written.
    ///   The type is deeply extruded, so any offset small enough to read
    ///   as a shadow is smaller than the extrusion is deep, and the two
    ///   solids share a volume: letters looked doubled, lines looked
    ///   like they had collided.
    /// · A DARK COPY SCALED UP — `HubScene.namePlate` records why it
    ///   cannot work. Scaling a whole STRING moves every glyph outward
    ///   from the string's centre, so the shell letters land between
    ///   their own neighbours and the word reads as if printed twice.
    ///
    /// Both fail for the same underlying reason: they treat a line of
    /// text as one object. This builds it as glyphs. Each letter is
    /// generated, placed, and given its own shell scaled about ITS OWN
    /// centre — so the swell is a thicker stroke rather than a wider
    /// word, and shell and letter cannot misregister because the same
    /// transform places both.
    ///
    /// The shell is also DEEPER and set back, so the letter is contained
    /// inside it rather than intersecting it. Nothing is coplanar, which
    /// is what the first attempt's doubling actually was.
    @MainActor
    static func keylined(_ text: String, size: CGFloat,
                         accent: UIColor?) -> (entity: Entity,
                                               extents: SIMD3<Float>) {
        let group = Entity()
        let characters = Array(display(text))

        // WHERE EACH GLYPH GOES, asked of the font rather than guessed.
        //
        // `advance[i]` is the inked width of the first i characters laid
        // out together, so kerning is in the number by construction —
        // "PL" is measured as a pair, and whatever the face does between
        // that pair is what comes back. The right edge of glyph i is the
        // right edge of the prefix ending at glyph i, which makes the
        // placement exact rather than an accumulation of guessed
        // advances.
        var advance: [Float] = [0]
        for index in characters.indices {
            advance.append(extents(String(characters[0...index]), size: size).x)
        }
        let total = advance.last ?? 0

        let stock = accent.map {
            blend($0, toward: UIColor(white: 0.72, alpha: 1), by: 0.30)
        } ?? ivory
        var metal = Materials.machined(stock)
        metal.emissiveColor = .init(color: stock)
        // BRIGHTER THAN `line`'s 0.16, and this is the one place raising
        // it is not the mistake it was on 2026-08-08.
        //
        // That day's failure was lifting the floor to 0.34 with nothing
        // behind the letters: light-on-light has no contrast, and a
        // brighter light against a bright wall is still no edge. The
        // keyline supplies the edge. What is left is a separate
        // complaint the first screenshot of this build showed plainly —
        // the faces read GREY, because machined metal is mostly
        // reflected light and the gallery's lighting is composed for
        // instruments sitting in a room, not for signage two metres up.
        // With a dark casing holding the silhouette, the face is free to
        // carry its own light and land where ivory should.
        metal.emissiveIntensity = 0.32
        // MATTE AND UNLIT-DARK, deliberately. The shell is the thing the
        // letter is read against, so it must not catch a highlight of
        // its own — a glossy casing under a metal letter is two
        // specular objects competing at the same edge, which is the
        // contrast problem again one layer in.
        let casing = Materials.machined(Self.keylineStock)

        let depth = Float(size) * extrusionFactor
        let recess = Float(size) * keylineRecess

        for (index, character) in characters.enumerated() {
            guard !character.isWhitespace else { continue }
            let glyph = String(character)
            let letterMesh = mesh(glyph, size: size)
            let bounds = letterMesh.bounds
            // Placed by its RIGHT edge, and vertically not at all: every
            // glyph is generated the same way, so they already share a
            // baseline. Re-centring each one on its own ink is how "O"
            // and "S" — which overshoot the cap line — end up sitting a
            // millimetre off it.
            let x = advance[index + 1] - total / 2 - bounds.max.x

            let letter = ModelEntity(mesh: letterMesh, materials: [metal])
            letter.position.x = x
            group.addChild(letter)

            let shellMesh = mesh(glyph, size: size,
                                 extrusion: depth + recess * 2)
            let shellBounds = shellMesh.bounds
            let shell = ModelEntity(mesh: shellMesh, materials: [casing])
            // Swollen in the PLANE only. A uniform scale would deepen it
            // too, and the depth is already chosen.
            let swell = 1 + keylineSwell
            shell.scale = SIMD3(swell, swell, 1)
            // About the glyph's own centre, so the outline is even all
            // the way round rather than growing off one corner.
            let centre = SIMD3(x, 0, 0) + bounds.center
            shell.position = SIMD3(
                centre.x - shellBounds.center.x * swell,
                centre.y - shellBounds.center.y * swell,
                // Face set back behind the letter's face: the keyline is
                // seen past the letter's edge, never in front of it.
                (bounds.max.z - recess) - shellBounds.max.z)
            group.addChild(shell)
        }

        // Centred on its own origin, from what was built — the same
        // contract `line` offers, so the lockup stacking above is
        // unchanged.
        let built = group.visualBounds(relativeTo: nil)
        for child in group.children {
            child.position.y -= built.center.y
            child.position.x -= built.center.x
        }
        return (group, built.extents)
    }

    /// How much wider the shell's strokes are than the letter's, as a
    /// fraction.
    ///
    /// 0.12 IN THE FIRST BUILD, AND IT WAS TOO TIMID. On a face this
    /// bold, a 12% swell puts barely a pixel of casing past the letter's
    /// own extruded side, so the two merged and read as a drop shadow
    /// falling bottom-right rather than as an outline holding the shape.
    /// A drop shadow is a direction; a keyline is a silhouette, and the
    /// silhouette is the whole point on a wall of unknown brightness.
    ///
    /// Still a keyline and not a slab: at 0.22 the casing is visible all
    /// the way round and stops well short of closing the counters — the
    /// holes in P, R, O and D stay open, which is what keeps this
    /// reading as set type rather than as a stencil.
    static let keylineSwell: Float = 0.22

    /// How far the shell's face sits behind the letter's, and how much
    /// deeper it runs, in fractions of point size.
    static let keylineRecess: Float = 0.05

    /// The casing's stock. Near-black rather than black: the labs'
    /// instruments are dark machined metal and the signage is the same
    /// alloy, so a true black would be the one object in the room that
    /// is not made of anything.
    static let keylineStock = UIColor(white: 0.08, alpha: 1)

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
