//
//  HubDomainTitle.swift
//  Physics Playground — Hub
//
//  The three-dimensional signage over each door: the domain's name in
//  the app's signature bubble type, set in the domain's own colour,
//  over a lit rule.
//
//  Owner's call, 2026-07-30 — and it reverses an earlier doctrine, so
//  the reversal is worth a word. The Gallery shipped with "no floating
//  text headers": four terraces of two modules each were legible as a
//  crescent, and colour alone could carry the grouping. Two terraces of
//  three are a different room. The terraces ARE the app's two doors
//  now, the domain IS the choice the Home Screen exists to offer, and a
//  door without a name over it reads as someone's shelf — the same
//  argument that brought the wordmark back (DECISIONS.md, 2026-07-29),
//  one level down.
//
//  THE KINETIC BODIES ARE GONE (owner, 2026-08-04: "still is pretty
//  bad. Remove this for now, can revisit later if needed"). An electron
//  lapped the E&M sign and a ball crossed the Mechanics rule through
//  two full redesigns — a tanh depth-swap ellipse, then a tilted orbit;
//  a letter-clipping lob, then a travelling bounce — and neither ever
//  read as convincing in a real room. The signs are still signage: the
//  measured flush lockup, the domain accent, the overhanging rule with
//  its slow shimmer. Git history holds both generations of the motion
//  if it is ever revisited.
//
//  The design language is inherited, not invented:
//  · The TYPE comes from `HubTitleStyle` — the same engine the wordmark
//    uses, so the home's three display texts cannot disagree. What
//    changes per sign is the colour: the letters carry the DOMAIN
//    accent, which appears in each slab's hairline, the progress rings,
//    and now the signage.
//  · The LOCKUP is the wordmark's flush-both-sides two-line math:
//    lines measured, scaled to a common width, stacked with leading
//    derived from their real cap height.
//

import RealityKit
import RenderKit
import SwiftUI
import simd

@MainActor
final class HubDomainTitle {
    let root = Entity()

    private let domain: HubDomain
    /// The rule under the lockup — shimmerable, like the hairline
    /// below it on the slab.
    private let rule: ModelEntity
    /// The two lines, held so the rake can turn them.
    private var lines: [Entity] = []

    /// The signage face, built at this size and scaled per line.
    private static let reference: CGFloat = 0.12

    /// The rule's width as a multiple of the lockup's. Wider than the
    /// type it underlines: a rule that overhangs reads as a bar the
    /// words rest on rather than a shy dash trapped beneath them.
    nonisolated static let ruleOverhang: Float = 1.16

    /// The two lines per domain — near-equal character counts, so the
    /// flush-width lockup scales them to almost the same letter size
    /// and the pair reads as set type rather than an accident.
    private static func lines(for domain: HubDomain) -> [String] {
        switch domain {
        case .electricity: ["Electricity", "& Magnetism"]
        case .mechanics: ["Mechanics", "& Energy"]
        }
    }

    init(domain: HubDomain, width: Float) {
        self.domain = domain

        let accent = UIColor(domain.color)
        let texts = Self.lines(for: domain)

        // The wordmark's lockup math: measure both lines, scale each to
        // the common width, stack with cap-height leading, centre the
        // block on the anchor.
        // KEYLINED FROM 2026-08-10 TO 2026-08-11, AND NO LONGER.
        //
        // These two signs were the last display type in the app drawn as
        // bare machined metal, and they had a real failure: metal is
        // mostly REFLECTED light, the gallery is drawn over whatever
        // room the wearer is standing in, and light-on-light has no
        // edge. A photograph made it plain — the floor lamp's pole read
        // straight through the I and the S of MAGNETISM, and MECHANICS &
        // ENERGY dissolved into a bookshelf. A dark shell round every
        // glyph fixed it, and the owner removed it the next day.
        //
        // What makes that removal survivable is that the signs are
        // MILLED now. The shell was compensating for a letterform with a
        // square edge, which is all `generateText` can extrude; a
        // chamfered edge carries its own bright rim all the way round
        // every stroke, at every angle, so the silhouette is in the
        // letter rather than behind it. Put the generated type back and
        // the bookshelf wins again — which is what `generated` below is,
        // and why it is a fallback and not an equal.
        //
        // MILLED IF THE ASSET IS THERE — see `HubTitleStyle.milled`.
        // The signs take the accent either way: only the geometry came
        // out of Blender, so a door still speaks in its domain's colour
        // and `DesignTokens.Palette` is still the one place that decides
        // what that colour is.
        let built = texts.map { text -> (entity: Entity, extents: SIMD3<Float>) in
            HubTitleStyle.milled(text, size: Self.reference, accent: accent)
                ?? HubTitleStyle.generated(text, size: Self.reference,
                                           accent: accent)
        }
        let scales = built.map { width / max($0.extents.x, 1e-4) }
        let heights = zip(built, scales).map { $0.0.extents.y * $0.1 }
        // Leading off the TALLEST line, not the average. The flush
        // lockup scales a short line up (7-character "Physics" against
        // 10-character "Playground"), so its cap height can far exceed
        // the mean — and an average-derived gap then lets the tall line
        // collide with its neighbour. Uppercase makes it worse, which
        // is how the plaque exposed it.
        let gap = (heights.max() ?? 0) * HubTitleStyle.leadingFactor
        let blockHeight = heights.reduce(0, +) + gap * Float(heights.count - 1)

        var cursor = blockHeight / 2
        for (index, item) in built.enumerated() {
            item.entity.scale = SIMD3(repeating: scales[index])
            item.entity.position.y = cursor - heights[index] / 2
            root.addChild(item.entity)
            cursor -= heights[index] + gap
        }
        lines = built.map(\.entity)

        // The rule, in the domain accent — the same lit line as the
        // slab hairline below it, so sign and shelf read as one lamp.
        var ruleMaterial = UnlitMaterial(color: accent)
        ruleMaterial.blending = .transparent(opacity: 0.7)
        rule = ModelEntity(
            mesh: .generateBox(width: width * Self.ruleOverhang, height: 0.0035,
                               depth: 0.0035, cornerRadius: 0.0017),
            materials: [ruleMaterial])
        rule.position = SIMD3(0, -blockHeight / 2 - 0.055, 0)
        root.addChild(rule)

        var accessibility = AccessibilityComponent()
        accessibility.isAccessibilityElement = true
        accessibility.label = LocalizedStringResource(stringLiteral: domain.title)
        root.components.set(accessibility)
    }

    // MARK: Per-frame

    /// Drive the sign: the rule's slow shimmer, on the same clock as the
    /// slab hairlines so lamp and lamp agree, and the type's rake.
    /// `stillness` (reduce-motion, or the room asleep) parks both at
    /// their composed rest — square to the reader, at rest opacity.
    func animate(time: Double, stillness: Bool) {
        // The type turns a degree and a half so the chamfer walks its
        // highlight along every stroke — see `HubTitleStyle.rake`. This
        // is the door sign's only motion now that the kinetic bodies are
        // gone, and it is a different KIND of motion: those animated a
        // prop beside the words, this animates the words.
        for (index, line) in lines.enumerated() {
            line.orientation = stillness ? simd_quatf(angle: 0, axis: [0, 1, 0])
                : HubTitleStyle.rake(time: time, phase: Double(index) * 1.3)
        }
        guard !stillness else {
            rule.components.set(OpacityComponent(opacity: 0.7))
            return
        }
        let shimmer = 0.62 + 0.18 * Float(sin(time * 0.5 + Double(domain.hashValue % 5)))
        rule.components.set(OpacityComponent(opacity: shimmer))
    }
}
