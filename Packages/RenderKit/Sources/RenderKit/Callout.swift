//
//  Callout.swift
//  RenderKit
//
//  Spatial annotation done properly: a number that belongs to a place
//  in the room is anchored TO that place — a dot on the thing, a thin
//  leader line, and the text floating at the end of it, billboarded so
//  it always faces the reader.
//
//  Before this, every module billboarded bare text at some offset and
//  hoped: labels drifted away from what they described, collided with
//  the title bar, and read as free-floating index cards. A callout is
//  one entity you re-point each frame; the leader keeps the meaning
//  attached no matter where the reader is standing.
//
//  Text meshes are cached by (string, size) — generating them per frame
//  is the classic way to tank a scene, and several modules update their
//  readouts every frame.
//

import QuartzCore
import RealityKit
import UIKit
import simd

/// A billboarded label tethered to a point in space by a leader line.
@MainActor
public final class Callout {
    /// Add this to the scene. Positioned at the ANCHOR point; the label
    /// hangs at `offset` from it with the leader drawn between.
    public let root = Entity()

    private let dot = Entity()
    private let leader = Entity()
    private let labelPivot = Entity()
    private var labelEntity: ModelEntity?

    private let color: UIColor
    private let textSize: CGFloat
    private var offset: SIMD3<Float>
    private var lastText: String?
    private var lastTextTime: Double = -1

    /// Whether the text wears the house dark backing plate
    /// (`BackedLabel.backing`). OFF by default: the backing rollout is
    /// staged module by module and judged on device — a room full of
    /// pills is the failure mode being checked for. Takes effect on the
    /// next text change.
    public var showsBacking = false

    /// What VoiceOver calls this readout — the quantity, not the number.
    ///
    /// A `Callout` is a text MESH, and a mesh is invisible to VoiceOver
    /// unless something says otherwise. `ARCHITECTURE.md` names the
    /// callout as one of the app's two readout forms, and `DECISIONS.md`
    /// claimed on 2026-08-01 that "VoiceOver reach is preserved by
    /// `AccessibilityComponent` on every plate, petal, disc and card" —
    /// a callout is none of those four, so the claim stayed technically
    /// true while every tethered live number in the app went unread:
    /// flux, µT, catch speed, sweep area, the prediction countdown, the
    /// orbital chord.
    ///
    /// Fixed here rather than at the six call sites, because putting it
    /// in the shared type is what stops it being adopted by four of them.
    private var accessibilityName: String?

    /// - Parameters:
    ///   - color: accent for the dot, leader, and type. Saturated module
    ///     accents survive white walls; pale tints do not.
    ///   - textSize: glyph height in metres.
    ///   - offset: where the label sits relative to the anchor point.
    public init(color: UIColor,
                textSize: CGFloat = 0.035,
                offset: SIMD3<Float> = SIMD3(0, 0.11, 0)) {
        self.color = color
        self.textSize = textSize
        self.offset = offset

        // The anchor dot: small, bright, sits exactly on the subject.
        let dotMesh = MeshResource.generateSphere(radius: 0.006)
        let dotModel = ModelEntity(mesh: dotMesh,
                                   materials: [Materials.energized(color, glow: 0.8)])
        dot.addChild(dotModel)
        root.addChild(dot)

        root.addChild(leader)

        labelPivot.components.set(BillboardComponent())
        labelPivot.position = offset
        root.addChild(labelPivot)

        rebuildLeader()
    }

    /// Where the callout points. Set every frame if the subject moves.
    public func anchor(at worldPosition: SIMD3<Float>) {
        root.position = worldPosition
    }

    /// Moves the label relative to the anchor (to dodge other content).
    public func setOffset(_ newOffset: SIMD3<Float>) {
        guard simd_distance(newOffset, offset) > 1e-4 else { return }
        offset = newOffset
        labelPivot.position = offset
        rebuildLeader()
    }

    /// How often a changing readout may regenerate its glyphs.
    ///
    /// `MeshResource.generateText` builds a whole mesh, on the main
    /// thread. "Skip when unchanged" is no protection at all for a
    /// LIVE number — 12.3 µT becomes 12.4 µT becomes 12.2 µT, so the
    /// text differs every single frame and every single frame paid for
    /// a new mesh. At 90 Hz that is ninety text meshes a second, per
    /// callout, and it is the kind of cost that shows up as the whole
    /// app hitching rather than as one slow thing.
    ///
    /// Eight updates a second is faster than anyone can read a changing
    /// number and a tenth of the work.
    private static let minimumInterval: Double = 1.0 / 8

    /// Updates the text. Free when unchanged, and rate-limited when it
    /// changes, because generating glyphs is not free.
    public func setText(_ text: String) {
        guard text != lastText else { return }
        let now = CACurrentMediaTime()
        guard now - lastTextTime >= Self.minimumInterval else { return }
        lastTextTime = now
        lastText = text
        labelEntity?.removeFromParent()
        guard !text.isEmpty else {
            labelEntity = nil
            return
        }
        let mesh = Self.textMesh(text, size: textSize)
        var material = UnlitMaterial(color: color)
        material.blending = .opaque
        let model = ModelEntity(mesh: mesh, materials: [material])
        // Centre the glyph run on the pivot.
        let bounds = mesh.bounds
        model.position = [-(bounds.min.x + bounds.max.x) / 2,
                          -(bounds.min.y + bounds.max.y) / 2, 0]
        if showsBacking {
            model.addChild(BackedLabel.backing(behind: bounds, size: textSize))
        }
        labelPivot.addChild(model)
        labelEntity = model
        publishAccessibility()
    }

    /// Names the quantity this callout reports, for VoiceOver. The VALUE
    /// is whatever `setText` last wrote, so a caller sets this once and
    /// the reading follows by itself.
    public func setAccessibilityName(_ name: String) {
        guard name != accessibilityName else { return }
        accessibilityName = name
        publishAccessibility()
    }

    private func publishAccessibility() {
        // Label and value BOTH, which is the omission `SpatialTrackControl`
        // was caught making on its first flight: a control VoiceOver can
        // name but not read is not reachable, it is merely listed.
        guard let text = lastText, !text.isEmpty else {
            root.components.remove(AccessibilityComponent.self)
            return
        }
        var accessibility = AccessibilityComponent()
        accessibility.isAccessibilityElement = true
        accessibility.label = LocalizedStringResource(
            stringLiteral: accessibilityName ?? "Reading")
        accessibility.value = LocalizedStringResource(stringLiteral: text)
        root.components.set(accessibility)
    }

    public var isEnabled: Bool {
        get { root.isEnabled }
        set { root.isEnabled = newValue }
    }

    // MARK: Leader

    private func rebuildLeader() {
        leader.children.forEach { $0.removeFromParent() }
        let length = simd_length(offset)
        guard length > 1e-4 else { return }
        var material = UnlitMaterial(color: color)
        material.blending = .transparent(opacity: 0.7)
        let rod = ModelEntity(
            mesh: .generateCylinder(height: length, radius: 0.0011),
            materials: [material])
        // generateCylinder runs along +Y; aim it down the offset.
        rod.orientation = simd_quatf(from: [0, 1, 0], to: offset / length)
        rod.position = offset / 2
        leader.addChild(rod)
    }

    // MARK: Text mesh cache

    private static var cache: [String: MeshResource] = [:]

    /// Generated text meshes are expensive; modules re-request the same
    /// strings constantly ("9.0 V", "45°"). Cache keyed by content+size.
    public static func textMesh(_ text: String, size: CGFloat) -> MeshResource {
        let key = "\(size)|\(text)"
        if let cached = cache[key] { return cached }
        let mesh = MeshResource.generateText(
            text,
            extrusionDepth: Float(size) * 0.06,
            font: .systemFont(ofSize: size, weight: .semibold),
            alignment: .center)
        // Bounded so a module that formats a continuously-varying number
        // can't grow the cache without limit.
        if cache.count > 400 { cache.removeAll(keepingCapacity: true) }
        cache[key] = mesh
        return mesh
    }
}
