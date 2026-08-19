//  HubDomainTitle.swift — 3-D door signage: the domain's name in the domain accent over a lit rule.
//  Type comes from `HubTitleStyle` (same engine as the wordmark, so the home's display texts
//  cannot disagree); the lockup is the wordmark's flush-both-sides two-line math.

import RealityKit
import RenderKit
import SwiftUI
import simd

@MainActor
final class HubDomainTitle {
    let root = Entity()

    private let domain: HubDomain
    /// The rule under the lockup — shimmerable, like the slab hairline below it.
    private let rule: ModelEntity
    /// The two lines, held so the rake can turn them.
    private var lines: [Entity] = []

    /// The signage face, built at this size and scaled per line.
    private static let reference: CGFloat = 0.12

    /// Rule width as a multiple of the lockup's — an overhanging rule reads as a bar the words rest on.
    nonisolated static let ruleOverhang: Float = 1.16

    /// Two lines per domain — near-equal character counts, so the flush-width lockup
    /// scales the pair to almost the same letter size.
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

        // Wordmark lockup math: measure both lines, scale to common width, stack with
        // cap-height leading, centre on the anchor. Milled if the asset exists; `generated`
        // is a FALLBACK, not an equal — square-edged generateText loses its silhouette against
        // a lit room, the milled chamfer carries its own rim. Accent applies either way.
        let built = texts.map { text -> (entity: Entity, extents: SIMD3<Float>) in
            HubTitleStyle.milled(text, size: Self.reference, accent: accent)
                ?? HubTitleStyle.generated(text, size: Self.reference,
                                           accent: accent)
        }
        let scales = built.map { width / max($0.extents.x, 1e-4) }
        let heights = zip(built, scales).map { $0.0.extents.y * $0.1 }
        // Leading off the TALLEST line, not the average — the flush lockup scales a short
        // line up, and an average-derived gap lets the tall line collide with its neighbour.
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

        // The rule, in the domain accent — same lit line as the slab hairline below it.
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

    /// Drive the sign: rule shimmer (same clock as the slab hairlines) and the type's rake.
    /// `stillness` (reduce-motion, or room asleep) parks both at composed rest.
    func animate(time: Double, stillness: Bool) {
        // ~1.5° rake walks the chamfer's highlight along every stroke — see `HubTitleStyle.rake`.
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
