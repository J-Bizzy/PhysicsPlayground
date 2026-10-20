//
//  BackedLabel.swift
//  RenderKit
//
//  A dark rounded plate behind a live in-room numeral; padding and depth
//  scale with the type. The backing is decoration: no collider, no input
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
    /// Last text/colour kept separately, not as an interpolated key —
    /// the unchanged path runs every frame and must be genuinely free.
    private var lastText: String?
    private var lastColor: UIColor?
    private var lastTextTime: Double = 0
    /// The glyphs and the plate, kept across changes (`GlyphRun`): a new
    /// reading moves glyphs, it does not generate text.
    private var run: GlyphRun?
    private var card: ModelEntity?

    public init(size: CGFloat) {
        self.size = size
    }

    /// Rebuilds glyphs and backing. Free when unchanged; rate-limited
    /// (Callout.minimumLabelInterval) — a skipped value is not dropped,
    /// it lands on the first frame past the interval — provided the caller
    /// asks again, which is what the return value is for: false means held
    /// back, so a caller caching "what I last showed" must not record it.
    @discardableResult
    public func setText(_ text: String, color: UIColor) -> Bool {
        guard text != lastText || color != lastColor else { return true }
        // Clearing is never rate-limited: empty means the subject is
        // gone, and a stale reading over nothing is worse than the cost.
        if !text.isEmpty {
            let now = CACurrentMediaTime()
            guard now - lastTextTime >= Callout.minimumLabelInterval else { return false }
            lastTextTime = now
        }
        lastText = text
        lastColor = color
        guard !text.isEmpty else {
            // Gone from the room, kept for the next reading.
            card?.removeFromParent()
            run?.root.removeFromParent()
            return true
        }
        let run = self.run ?? GlyphRun(size: size, color: color)
        self.run = run
        run.setColor(color)
        let bounds = run.set(text)
        if let card {
            Self.reshape(card, behind: bounds, size: size)
        } else {
            card = Self.backing(behind: bounds, size: size)
        }
        // The plate first, then the glyphs, as they always stood.
        if let card, card.parent == nil { root.addChild(card) }
        if run.root.parent == nil { root.addChild(run.root) }
        return true
    }

    /// The plate alone, for callers composing their own glyphs — one
    /// copy of the inset/corner arithmetic keeps every backing identical.
    static func backing(behind bounds: BoundingBox,
                        size: CGFloat) -> ModelEntity {
        let material = Materials.unlit(UIColor(white: 0.02, alpha: 1), opacity: 0.58)
        let card = ModelEntity(mesh: plateMesh(behind: bounds, size: size),
                               materials: [material])
        card.position.z = -Float(size) * 0.17
        return card
    }

    /// Fits an existing plate to new text: a cached mesh swapped, nothing made.
    static func reshape(_ card: ModelEntity, behind bounds: BoundingBox, size: CGFloat) {
        let mesh = plateMesh(behind: bounds, size: size)
        if card.model?.mesh !== mesh { card.model?.mesh = mesh }
    }

    private static func plateMesh(behind bounds: BoundingBox, size: CGFloat) -> MeshResource {
        let padX = Float(size) * 0.5
        let padY = Float(size) * 0.44
        let width = (bounds.max.x - bounds.min.x) + padX * 2
        let height = (bounds.max.y - bounds.min.y) + padY * 2
        // Pill for a one-line badge; radius capped so a wrapped
        // paragraph gets an honest corner, not a lozenge eating end words.
        let radius = min(height / 2, Float(size) * 1.2)
        return plate(width: width, height: height, cornerRadius: radius)
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
        let mesh = Primitives.plane(
            width: width, height: height, cornerRadius: cornerRadius)
        if plates.count > 400 { plates.removeAll() }
        plates[key] = mesh
        return mesh
    }
}
