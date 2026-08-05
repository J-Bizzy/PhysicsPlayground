//
//  BackedLabel.swift
//  RenderKit
//
//  A live in-room number, built to survive the room behind it.
//
//  The hub's nameplates solved this on 2026-08-01: bright type over
//  passthrough has no floor under its contrast — cyan on a white wall,
//  white on a sunlit one — and the fix that survives every wall is a
//  small near-black plate sized to the words it carries. The gallery got
//  that treatment; the modules' live numerals (circuit values, tower
//  volts, ring scores) stayed naked unlit text, which is the same defect
//  the nameplate was built for, one meter further into the room.
//
//  This is that plate, for numbers. The geometry is the nameplate's,
//  imported not imitated: padding scales WITH the type (fixed padding
//  authored at one size made a small label wear a plate three
//  text-heights wide), the corner radius is half the height, and the
//  backing sits behind the glyphs by a distance that also scales, so a
//  20 mm label is not floating 6 mm off its own card.
//
//  The backing is DECORATION: no collider, no input target, ever — a
//  readout that intercepts a pinch is `SpatialScaleHandle` again.
//

import RealityKit
import UIKit

/// A billboard-ready label: centred glyphs over a dark rounded backing.
/// The caller owns position and any billboarding pivot; this owns what
/// the label looks like.
@MainActor
public final class BackedLabel {
    /// Add this under the caller's (usually billboarded) pivot. The
    /// label is centred on it, horizontally and vertically.
    public let root = Entity()

    private let size: CGFloat
    private var lastKey: String?

    public init(size: CGFloat) {
        self.size = size
    }

    /// Rebuilds the glyphs and their backing. Free when nothing changed;
    /// glyph meshes come from `Callout`'s shared cache, so repeated
    /// values ("9.0 V") cost a dictionary lookup.
    public func setText(_ text: String, color: UIColor) {
        let key = "\(text)|\(color.description)"
        guard key != lastKey else { return }
        lastKey = key
        // Snapshot first: `children` is a live collection, and removing
        // while iterating it skips every other element — the test for
        // "empty text leaves nothing" caught exactly one orphaned plate.
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

    /// The plate alone — for a caller composing its own glyphs (the
    /// callout) that still wants the one house backing.
    static func backing(behind bounds: BoundingBox, size: CGFloat) -> ModelEntity {
        let padX = Float(size) * 0.5
        let padY = Float(size) * 0.44
        let width = (bounds.max.x - bounds.min.x) + padX * 2
        let height = (bounds.max.y - bounds.min.y) + padY * 2
        var material = UnlitMaterial(color: UIColor(white: 0.02, alpha: 1))
        material.blending = .transparent(opacity: 0.58)
        let card = ModelEntity(
            mesh: .generatePlane(width: width, height: height,
                                 cornerRadius: height / 2),
            materials: [material])
        card.position.z = -Float(size) * 0.17
        return card
    }
}
