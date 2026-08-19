//
//  BackedLabel.swift
//  RenderKit
//
//  A dark rounded plate behind a live in-room numeral; padding and depth
//  scale with the type. The backing is DECORATION: no collider, no input
//  target, ever.
//

import QuartzCore
import RealityKit
import UIKit

/// A billboard-ready label: centred glyphs over a dark rounded backing.
/// The caller owns position and billboarding; this owns the look.
@MainActor
public final class BackedLabel {
    /// Add this under the caller's (usually billboarded) pivot; the
    /// label is centred on it.
    public let root = Entity()

    private let size: CGFloat
    /// Last text/colour kept SEPARATELY, not as an interpolated key —
    /// the unchanged path runs every frame and must be genuinely free.
    private var lastText: String?
    private var lastColor: UIColor?
    private var lastTextTime: Double = 0

    public init(size: CGFloat) {
        self.size = size
    }

    /// Rebuilds glyphs and backing. Free when unchanged; rate-limited
    /// (Callout.minimumLabelInterval) — a skipped value is not dropped,
    /// it lands on the first frame past the interval.
    public func setText(_ text: String, color: UIColor) {
        guard text != lastText || color != lastColor else { return }
        // CLEARING IS NEVER RATE-LIMITED: empty means the subject is
        // gone, and a stale reading over nothing is worse than the cost.
        if !text.isEmpty {
            let now = CACurrentMediaTime()
            guard now - lastTextTime >= Callout.minimumLabelInterval else { return }
            lastTextTime = now
        }
        lastText = text
        lastColor = color
        // Snapshot first: `children` is live; removing while iterating
        // skips every other element.
        for child in Array(root.children) { child.removeFromParent() }
        guard !text.isEmpty else { return }

        let mesh = Callout.textMesh(text, size: size)
        var material = UnlitMaterial(color: color)
        material.blending = .opaque
        let glyphs = ModelEntity(mesh: mesh, materials: [material])
        let bounds = mesh.bounds
        glyphs.position = [-(bounds.min.x + bounds.max.x) / 2,
                           -(bounds.min.y + bounds.max.y) / 2, 0]

        root.addChild(Self.backing(behind: bounds, size: size))
        root.addChild(glyphs)
    }

    /// The plate alone, for callers composing their own glyphs — one
    /// copy of the inset/corner arithmetic keeps every backing identical.
    static func backing(behind bounds: BoundingBox,
                        size: CGFloat) -> ModelEntity {
        let padX = Float(size) * 0.5
        let padY = Float(size) * 0.44
        let width = (bounds.max.x - bounds.min.x) + padX * 2
        let height = (bounds.max.y - bounds.min.y) + padY * 2
        var material = UnlitMaterial(color: UIColor(white: 0.02, alpha: 1))
        material.blending = .transparent(opacity: 0.58)
        // Pill for a one-line badge; radius capped so a wrapped
        // paragraph gets an honest corner, not a lozenge eating end words.
        let radius = min(height / 2, Float(size) * 1.2)
        let card = ModelEntity(
            mesh: plate(width: width, height: height, cornerRadius: radius),
            materials: [material])
        card.position.z = -Float(size) * 0.17
        return card
    }

    /// Plate meshes cached by dimensions quantised to 0.1 mm — raw Float
    /// keys never match. Bounded, like Callout's glyph cache.
    private static var plates: [PlateKey: MeshResource] = [:]

    private struct PlateKey: Hashable {
        let width: Int32, height: Int32, radius: Int32
        init(_ width: Float, _ height: Float, _ radius: Float) {
            self.width = Int32((width * 10_000).rounded())
            self.height = Int32((height * 10_000).rounded())
            self.radius = Int32((radius * 10_000).rounded())
        }
    }

    private static func plate(width: Float, height: Float,
                              cornerRadius: Float) -> MeshResource {
        let key = PlateKey(width, height, cornerRadius)
        if let cached = plates[key] { return cached }
        let mesh = MeshResource.generatePlane(
            width: width, height: height, cornerRadius: cornerRadius)
        if plates.count > 400 { plates.removeAll() }
        plates[key] = mesh
        return mesh
    }
}
