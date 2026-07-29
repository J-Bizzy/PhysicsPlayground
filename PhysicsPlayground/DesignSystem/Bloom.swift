//
//  Bloom.swift
//  Physics Playground — Design System
//
//  THE OBJECT IS THE INTERFACE.
//
//  This replaces every control pod, dial, and floating panel in the
//  app. Look at a thing and its own controls unfold around it, in
//  place; look away and they fold back. Nothing floats unattached,
//  nothing has to be hunted for, and the number of surfaces competing
//  for your attention is exactly one: whatever you are looking at.
//
//  Two kinds of control, and the split is a rule, not a preference:
//
//  · A quantity with a PHYSICAL EXTENT is manipulated by that extent.
//    A charge's magnitude is its size, so you take the grip on its
//    surface and pull. The sphere follows your hand, the field lines
//    multiply, and the number is a consequence you can watch rather
//    than a slider you set. No dial ever describes this well, which is
//    exactly why the dials are gone.
//
//  · Only what is genuinely DISCRETE gets a petal — flip a polarity,
//    delete a thing. Petals arc above the object, hold constant
//    angular size at any distance, and stagger in on spring curves.
//

import RealityKit
import SwiftUI
import RenderKit
import simd

@MainActor
final class Bloom {
    /// A discrete action. Two or three per object, never more — a ring
    /// of icons is a menu, and menus are what this replaces.
    struct Petal {
        let name: String
        let symbol: String
        let tint: UIColor
        let action: () -> Void
    }

    /// A continuous quantity you pull out of the object itself.
    /// `radius` reports how far from the centre the grip should sit,
    /// so the handle rides the object's own surface as it grows.
    struct Grip {
        let name: String
        let range: ClosedRange<Double>
        let read: () -> Double
        let write: (Double) -> Void
        let format: (Double) -> String
        let radius: () -> Float
    }

    let root = Entity()

    private var petals: [Petal] = []
    private var petalEntities: [ModelEntity] = []
    private var grip: Grip?
    private var gripEntity: ModelEntity?
    /// The rail the bead travels: track line, end ticks, −/+ glyphs.
    private var gripRig: Entity?
    /// The bright segment from the rail's start to the bead.
    private var gripFill: ModelEntity?
    private var label: Callout?
    /// The root's scale last applied by update() — world metres per
    /// bloom-local unit, needed to map a hand's world pull onto the
    /// rail's local length.
    private var lastScale: Float = 1

    /// 0 folded, 1 unfolded. Eased every frame.
    private var reveal: Float = 0
    /// Per-petal reveal, staggered behind the parent so the ring
    /// unfurls rather than appearing.
    private var petalReveals: [Float] = []

    /// The live drag on the grip, if any.
    private var gripDrag: (startHand: SIMD3<Float>, startValue: Double)?

    /// Where the bloom is anchored, world space (set every frame).
    private var anchor: SIMD3<Float> = .zero

    // MARK: Geometry
    //
    // Sizes are in metres AT ONE METRE, then scaled by distance so the
    // bloom holds constant angular size — a control you can read at
    // arm's length and across the room without ever resizing itself.
    // Sized and placed to CLEAR the physics, not to sit politely next
    // to it. The first version put 3 cm discs 11 cm from a charge —
    // behind a dozen field lines, on a bright wall. Everything was
    // enabled and correct and invisible. A control that has to be
    // hunted for has failed.
    private static let petalRadius: Float = 0.030
    private static let ringRadius: Float = 0.235
    /// The grip's track: the visible rail the bead travels, from the
    /// object's surface outward. The bead's POSITION on the rail is the
    /// value — min at the object, max at the far tick — so the mapping
    /// is something you see, not something you discover.
    private static let gripTrackLength: Float = 0.14
    /// Small standoff between the object's surface and the rail, so the
    /// rail never reads as part of the thing it measures.
    private static let gripTrackInset: Float = 0.018
    /// Nearly a horizontal row: petals sit ABOVE the object, spread
    /// just enough to separate, so the object itself is never behind
    /// its own controls.
    private static let ringArc: Float = 34 * .pi / 180

    init() {
        root.isEnabled = false
    }

    /// What this bloom is currently pointed at. Tracked INSIDE the
    /// class on purpose: a SwiftUI @State read from a RealityKit update
    /// closure comes back stale, which made the first version rebuild
    /// itself every frame — the petals' unfold animation reset to zero
    /// sixty times a second (so they never appeared) while two fresh
    /// entities leaked per frame. State that a render loop reads must
    /// live where the render loop lives.
    private(set) var targetID: AnyHashable?

    /// Rebuilds only when the target actually changes.
    func retarget(_ id: AnyHashable,
                  petals: @autoclosure () -> [Petal],
                  grip: @autoclosure () -> Grip?) {
        guard targetID != id else { return }
        targetID = id
        configure(petals: petals(), grip: grip())
    }

    func clearTarget() { targetID = nil }

    func configure(petals: [Petal], grip: Grip?) {
        self.petals = petals
        self.grip = grip
        petalEntities.forEach { $0.removeFromParent() }
        petalEntities = []
        petalReveals = Array(repeating: 0, count: petals.count)

        for petal in petals {
            let entity = Self.makePetal(petal)
            root.addChild(entity)
            petalEntities.append(entity)
        }

        gripEntity?.removeFromParent()
        gripRig?.removeFromParent()
        if grip != nil {
            let handle = Self.makeGrip()
            root.addChild(handle)
            gripEntity = handle
            let rig = Self.makeGripRig()
            root.addChild(rig.root)
            gripRig = rig.root
            gripFill = rig.fill
        } else {
            gripEntity = nil
            gripRig = nil
            gripFill = nil
        }

        if label == nil {
            let callout = Callout(color: UIColor(white: 0.97, alpha: 1),
                                  textSize: 0.019, offset: SIMD3(0, 0.055, 0))
            root.addChild(callout.root)
            label = callout
        }
    }

    /// Per frame. `revealTarget` is 1 while the object is being looked
    /// at (or held), 0 otherwise; the fold is eased here so callers
    /// never animate anything themselves.
    func update(anchor: SIMD3<Float>,
                viewer: SIMD3<Float>?,
                revealTarget: Float,
                dt: Double) {
        self.anchor = anchor
        // A grip mid-drag pins the bloom open — you cannot be asked to
        // keep looking at something while you are pulling on it.
        let target = gripDrag != nil ? 1 : revealTarget
        let rate = Float(min(dt * 9, 1))
        reveal += (target - reveal) * rate
        if abs(reveal - target) < 0.004 { reveal = target }

        root.isEnabled = reveal > 0.01
        guard root.isEnabled else { return }
        root.position = anchor

        // Constant angular size: a bloom two metres away is drawn twice
        // as large, so it subtends the same angle and reads identically.
        var scale: Float = 1
        if let viewer {
            scale = max(simd_distance(viewer, anchor), 0.35)
        }
        root.scale = SIMD3(repeating: scale)
        lastScale = scale

        // Face the viewer without rolling — the ring stays level.
        if let viewer {
            let toViewer = viewer - anchor
            let flat = SIMD3<Float>(toViewer.x, 0, toViewer.z)
            if simd_length(flat) > 1e-4 {
                root.orientation = simd_quatf(from: [0, 0, 1],
                                              to: simd_normalize(flat))
            }
        }

        layoutPetals(dt: dt)
        layoutGrip(scale: scale)
    }

    private func layoutPetals(dt: Double) {
        let rate = Float(min(dt * 11, 1))
        for (index, entity) in petalEntities.enumerated() {
            // Stagger: each petal trails the one before it, so the ring
            // unfurls left to right instead of blinking into being.
            let delay = Float(index) * 0.16
            let own = max(0, min((reveal - delay) / max(1 - delay, 0.01), 1))
            petalReveals[index] += (own - petalReveals[index]) * rate
            let r = petalReveals[index]

            let count = max(petalEntities.count, 1)
            let spread = Self.ringArc * Float(count - 1)
            let angle = -spread / 2 + Self.ringArc * Float(index)
            // Petals arc ABOVE the object: up and around, never in
            // front of the thing they belong to.
            let lift = Self.ringRadius * r
            entity.position = SIMD3(sin(angle) * lift,
                                    cos(angle) * lift,
                                    0)
            // Overshoot slightly, then settle — the spring feel.
            let pop = 1 + 0.18 * sin(r * .pi)
            entity.scale = SIMD3(repeating: max(r, 0.001) * pop)
            entity.isEnabled = r > 0.02
        }
    }

    private func layoutGrip(scale: Float) {
        guard let grip, let gripEntity else { return }
        // The rail starts just off the object's surface, so growing the
        // thing pushes the whole instrument outward with it.
        let surface = grip.radius() / max(scale, 0.001)
        let start = surface + Self.gripTrackInset
        let span = grip.range.upperBound - grip.range.lowerBound
        let t = Float(min(max((grip.read() - grip.range.lowerBound)
                              / max(span, .leastNonzeroMagnitude), 0), 1))

        // The bead sits ON the rail at the value's position — weak at
        // the object, strong at the far tick.
        gripEntity.position = SIMD3(start + Self.gripTrackLength * t, 0, 0)
        gripEntity.scale = SIMD3(repeating: max(reveal, 0.001))
        // Interactive only once the bloom is essentially fully open —
        // a half-revealed bead must never intercept a grab.
        gripEntity.isEnabled = reveal > 0.85

        if let gripRig {
            gripRig.position = SIMD3(start, 0, 0)
            gripRig.scale = SIMD3(repeating: max(reveal, 0.001))
            gripRig.isEnabled = reveal > 0.05
        }
        if let gripFill {
            // The fill grows from the rail's start to the bead — the
            // "how much" you can read without the number.
            let length = max(Self.gripTrackLength * t, 0.001)
            gripFill.scale = SIMD3(1, length, 1)
            gripFill.position = SIMD3(length / 2, 0, 0)
        }

        // The value stays readable the whole time the ring is open —
        // brighter feedback while actually pulling.
        if reveal > 0.85 {
            label?.isEnabled = true
            label?.anchor(at: gripEntity.position)
            label?.setText(grip.format(grip.read()))
        } else {
            label?.isEnabled = false
        }
    }

    // MARK: Hit testing

    /// True if `entity` (or an ancestor) is one of this bloom's petals,
    /// in which case its action has been run.
    func handleTap(_ entity: Entity) -> Bool {
        guard root.isEnabled else { return false }
        guard let name = Self.ownName(of: entity, under: root) else { return false }
        guard let index = petalEntities.firstIndex(where: { $0.name == name }) else {
            return false
        }
        // Acknowledge in place: a quick swell, then the action.
        let petal = petalEntities[index]
        petal.move(to: Transform(scale: SIMD3(repeating: petal.scale.x * 1.35),
                                 translation: petal.position),
                   relativeTo: root, duration: 0.09, timingFunction: .easeOut)
        petals[index].action()
        return true
    }

    func beginGrip(_ entity: Entity, hand: SIMD3<Float>) -> Bool {
        guard root.isEnabled, reveal > 0.85, let grip, let gripEntity else { return false }
        guard Self.ownName(of: entity, under: root) == gripEntity.name else { return false }
        gripDrag = (hand, grip.read())
        return true
    }

    /// Radial pull: how far the hand moved AWAY from the object maps to
    /// the quantity. Pull out to grow, push in to shrink — the same
    /// gesture you would use on a real thing you were stretching. The
    /// mapping is the rail's own length, so the bead tracks the hand
    /// one-to-one along the visible track.
    func updateGrip(hand: SIMD3<Float>) -> Bool {
        guard let grip, let gripDrag else { return false }
        let startOut = simd_distance(gripDrag.startHand, anchor)
        let nowOut = simd_distance(hand, anchor)
        let span = grip.range.upperBound - grip.range.lowerBound
        let worldTrack = Double(Self.gripTrackLength * max(lastScale, 0.001))
        let delta = Double(nowOut - startOut) / worldTrack * span
        grip.write(min(max(gripDrag.startValue + delta,
                           grip.range.lowerBound), grip.range.upperBound))
        return true
    }

    func endGrip() { gripDrag = nil }

    var isGripping: Bool { gripDrag != nil }

    private static func ownName(of entity: Entity, under root: Entity) -> String? {
        var current: Entity? = entity
        while let candidate = current {
            if candidate.parent === root { return candidate.name }
            if candidate === root { return nil }
            current = candidate.parent
        }
        return nil
    }

    // MARK: Building

    private static func makePetal(_ petal: Petal) -> ModelEntity {
        // A DARK casing, not a tinted glass one. Tinted glass over a
        // bright room and a coloured field is a smudge; near-black with
        // a white glyph is legible over anything, which is the same
        // lesson the name plates and the control rail learned.
        let disc = ModelEntity(
            mesh: .generateCylinder(height: 0.005, radius: petalRadius),
            materials: [casing()])
        disc.name = "bloom-\(petal.name)"
        disc.orientation = simd_quatf(angle: .pi / 2, axis: [1, 0, 0])

        // A thin accent rim carries the meaning (red = destructive)
        // without staining the glyph.
        var rimMaterial = UnlitMaterial(color: petal.tint)
        rimMaterial.blending = .transparent(opacity: 0.95)
        let rim = ModelEntity(
            mesh: .generateCylinder(height: 0.0032, radius: petalRadius * 1.16),
            materials: [rimMaterial])
        rim.position = [0, -0.0012, 0]
        disc.addChild(rim)

        if let texture = symbolTexture(petal.symbol) {
            var iconMaterial = UnlitMaterial()
            iconMaterial.color = .init(tint: .white, texture: .init(texture))
            iconMaterial.blending = .transparent(opacity: .init(floatLiteral: 1))
            let icon = ModelEntity(
                mesh: .generatePlane(width: petalRadius * 1.15,
                                     height: petalRadius * 1.15),
                materials: [iconMaterial])
            icon.position = [0, 0.0045, 0]
            icon.orientation = simd_quatf(angle: -.pi / 2, axis: [1, 0, 0])
            disc.addChild(icon)
        }

        disc.components.set(InputTargetComponent())
        disc.components.set(CollisionComponent(
            shapes: [.generateSphere(radius: petalRadius * 1.4)]))
        disc.components.set(HoverEffectComponent())
        var accessibility = AccessibilityComponent()
        accessibility.isAccessibilityElement = true
        accessibility.label = LocalizedStringResource(stringLiteral: petal.name)
        disc.components.set(accessibility)
        disc.isEnabled = false
        return disc
    }

    /// The bead's instrument: a translucent rail the length of the
    /// whole range, a tick at each end, a small − at the weak end and
    /// + at the strong end, and a bright fill that grows with the
    /// value. Origin at the rail's start; the fill is repositioned per
    /// frame as the value moves.
    private static func makeGripRig() -> (root: Entity, fill: ModelEntity) {
        let rig = Entity()
        let alongX = simd_quatf(angle: -.pi / 2, axis: [0, 0, 1])

        var trackMaterial = UnlitMaterial(color: UIColor(white: 0.95, alpha: 1))
        trackMaterial.blending = .transparent(opacity: 0.28)
        let track = ModelEntity(
            mesh: .generateCylinder(height: gripTrackLength, radius: 0.0012),
            materials: [trackMaterial])
        track.orientation = alongX
        track.position = SIMD3(gripTrackLength / 2, 0, 0)
        rig.addChild(track)

        var fillMaterial = UnlitMaterial(color: UIColor(white: 1.0, alpha: 1))
        fillMaterial.blending = .transparent(opacity: 0.85)
        let fill = ModelEntity(
            mesh: .generateCylinder(height: 1, radius: 0.0022),
            materials: [fillMaterial])
        fill.orientation = alongX
        rig.addChild(fill)

        var tickMaterial = UnlitMaterial(color: UIColor(white: 0.95, alpha: 1))
        tickMaterial.blending = .transparent(opacity: 0.55)
        for x in [Float(0), gripTrackLength] {
            let tick = ModelEntity(
                mesh: .generateBox(width: 0.002, height: 0.014, depth: 0.002,
                                   cornerRadius: 0.001),
                materials: [tickMaterial])
            tick.position = SIMD3(x, 0, 0)
            rig.addChild(tick)
        }

        for (symbol, x) in [("minus", Float(0)), ("plus", gripTrackLength)] {
            guard let texture = symbolTexture(symbol) else { continue }
            var glyphMaterial = UnlitMaterial()
            glyphMaterial.color = .init(tint: UIColor(white: 1, alpha: 0.8),
                                        texture: .init(texture))
            glyphMaterial.blending = .transparent(opacity: .init(floatLiteral: 1))
            let glyph = ModelEntity(
                mesh: .generatePlane(width: 0.013, height: 0.013),
                materials: [glyphMaterial])
            glyph.position = SIMD3(x, -0.021, 0)
            rig.addChild(glyph)
        }

        return (rig, fill)
    }

    private static func makeGrip() -> ModelEntity {
        var material = PhysicallyBasedMaterial()
        material.baseColor = .init(tint: UIColor(white: 0.98, alpha: 1))
        material.roughness = 0.15
        material.metallic = 0.0
        material.emissiveColor = .init(color: UIColor(white: 1, alpha: 1))
        material.emissiveIntensity = 0.35
        let bead = ModelEntity(mesh: .generateSphere(radius: 0.014),
                               materials: [material])
        bead.name = "bloom-grip"
        bead.components.set(InputTargetComponent())
        // Barely larger than the bead itself: this collider competes
        // with the touch target of the object the bloom decorates, and
        // a generous one stole grabs meant for the object.
        bead.components.set(CollisionComponent(
            shapes: [.generateSphere(radius: 0.016)]))
        bead.components.set(HoverEffectComponent())
        var accessibility = AccessibilityComponent()
        accessibility.isAccessibilityElement = true
        accessibility.label = "Pull to change"
        bead.components.set(accessibility)
        bead.isEnabled = false
        return bead
    }

    private static func casing() -> RealityKit.Material {
        var material = PhysicallyBasedMaterial()
        material.baseColor = .init(tint: UIColor(white: 0.06, alpha: 1))
        material.roughness = 0.28
        material.metallic = 0.0
        material.clearcoat = .init(floatLiteral: 1.0)
        material.clearcoatRoughness = .init(floatLiteral: 0.12)
        material.blending = .transparent(opacity: .init(floatLiteral: 0.94))
        return material
    }

    /// SF Symbols as textures — the system's own icon language, so a
    /// petal reads the way every other Apple control does.
    private static var symbolCache: [String: TextureResource] = [:]
    static func symbolTexture(_ name: String) -> TextureResource? {
        if let cached = symbolCache[name] { return cached }
        let config = UIImage.SymbolConfiguration(pointSize: 96, weight: .semibold)
        guard let image = UIImage(systemName: name, withConfiguration: config)?
            .withTintColor(.white, renderingMode: .alwaysOriginal) else { return nil }
        let size = CGSize(width: 128, height: 128)
        let renderer = UIGraphicsImageRenderer(size: size)
        let padded = renderer.image { _ in
            let rect = CGRect(
                x: (size.width - image.size.width) / 2,
                y: (size.height - image.size.height) / 2,
                width: image.size.width, height: image.size.height)
            image.draw(in: rect)
        }
        guard let cgImage = padded.cgImage,
              let texture = try? TextureResource(
                image: cgImage, options: .init(semantic: .color)) else { return nil }
        symbolCache[name] = texture
        return texture
    }
}
