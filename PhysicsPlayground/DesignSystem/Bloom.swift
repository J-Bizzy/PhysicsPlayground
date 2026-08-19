//
//  Bloom.swift
//  Physics Playground — Design System
//
//  The object is the interface: look at a thing and its own controls
//  unfold around it in place. A continuous quantity is pulled by a grip
//  on the object's surface; a discrete action gets a petal.
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

        /// Read every frame; a false condition dims the petal and refuses
        /// the tap rather than removing it (removal shifts neighbours under
        /// the finger). A CLOSURE, NOT A BOOL: a Bool would be evaluated
        /// once at configure time and never re-checked.
        var isAvailable: () -> Bool = { true }

        /// Two taps for a destructive verb: the first arms and swaps the
        /// glyph to a checkmark, the second fires; disarms after
        /// `armWindow`.
        var confirms: Bool = false

        init(name: String, symbol: String, tint: UIColor,
             isAvailable: @escaping () -> Bool = { true },
             confirms: Bool = false,
             action: @escaping () -> Void) {
            self.name = name
            self.symbol = symbol
            self.tint = tint
            self.isAvailable = isAvailable
            self.confirms = confirms
            self.action = action
        }
    }

    /// How long an armed petal stays armed — same window as a verb plate.
    static let armWindow: Double = SpatialActionBank.armWindow

    /// The armed petal's index and how long it has been armed.
    private var armedPetal: (index: Int, elapsed: Double)?

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
    /// World metres per bloom-local unit, from the last update(); maps a
    /// hand's world pull onto the rail's local length.
    private var lastScale: Float = 1

    /// 0 folded, 1 unfolded. Eased every frame.
    private var reveal: Float = 0
    /// Per-petal reveal, staggered behind the parent so the ring
    /// unfurls rather than appearing.
    private var petalReveals: [Float] = []

    /// The live drag on the grip, if any.
    private var gripDrag: (startHand: SIMD3<Float>, startValue: Double)?
    /// The last value spoken for the bead, so the component is only
    /// rewritten when the number actually changes.
    private var lastGripSpoken: String?

    /// Where the bloom is anchored, world space (set while open, HELD
    /// while it folds — see `update`).
    private var anchor: SIMD3<Float> = .zero
    /// The viewer's last known position, held for the same reason.
    private var lastViewer: SIMD3<Float>?
    /// The rail's world-space direction, last frame. The grip drag
    /// projects the hand onto this so a pull along the rail moves nothing else.
    private var railAxis = SIMD3<Float>(1, 0, 0)

    // MARK: Geometry
    //
    // Sizes are in metres AT ONE METRE, then scaled by distance so the
    // bloom holds constant angular size at any range. Sized and placed to
    // CLEAR the physics, not sit beside it.
    private static let petalRadius: Float = 0.030
    /// The glyph plane's entity name, so the armed checkmark can find it.
    private static let iconName = "bloom-petal-icon"
    private static let ringRadius: Float = 0.235
    /// The visible rail the bead travels; the bead's position IS the value
    /// — min at the object, max at the far tick.
    private static let gripTrackLength: Float = 0.14
    /// How far BELOW the object's surface the rail hangs, so it never
    /// shares space with whatever is bolted to the object's sides. See `layoutGrip`.
    private static let gripTrackDrop: Float = 0.048
    /// Nearly a horizontal row: petals sit ABOVE the object, spread just
    /// enough to separate.
    private static let ringArc: Float = 34 * .pi / 180

    init() {
        root.isEnabled = false
    }

    /// What this bloom is currently pointed at. Tracked INSIDE the class:
    /// a SwiftUI @State read from a RealityKit update closure comes back
    /// stale. State a render loop reads must live where the render loop lives.
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
        // Rebuilding the ring destroys the entity the armed index refers to,
        // so the arm cannot survive it.
        armedPetal = nil
        // Nor can the grip drag: it holds (startHand, startValue) captured
        // against the OLD grip, so a selection changing mid-drag would write
        // the old start value into the new object's range.
        gripDrag = nil
        self.petals = petals
        self.grip = grip
        petalEntities.forEach { $0.removeFromParent() }
        petalEntities = []
        petalReveals = Array(repeating: 0, count: petals.count)

        for petal in petals {
            let entity = Self.makePetal(petal)
            root.addChild(entity)
            petalEntities.append(entity)
            // Through `handleTap`, NOT straight at `petal.action`: the tap
            // path checks availability and arms a `confirms` petal instead
            // of firing.
            SpatialActions.attach(
                to: entity, label: petal.name,
                activate: { [weak self, weak entity] in
                    guard let self, let entity else { return }
                    _ = self.handleTap(entity)
                })
        }

        gripEntity?.removeFromParent()
        gripRig?.removeFromParent()
        if let grip {
            let handle = Self.makeGrip()
            root.addChild(handle)
            gripEntity = handle
            // The bead is dragged, not pressed, so it needs VoiceOver
            // increment/decrement.
            SpatialActions.attach(
                to: handle, label: grip.name, value: grip.format(grip.read()),
                adjust: { [weak self] delta in self?.nudgeGrip(by: delta) })
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
            // BELOW the bead: the rail hangs under the object, so a label
            // above the bead would land in the gap that must stay clear.
            let callout = Callout(color: UIColor(white: 0.97, alpha: 1),
                                  textSize: 0.019, offset: SIMD3(0, -0.046, 0))
            callout.setAccessibilityName(grip?.name ?? "Value")
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
        // A grip mid-drag pins the bloom open — you cannot be asked to
        // keep looking at something while you are pulling on it.
        let target = gripDrag != nil ? 1 : revealTarget

        // WHERE IT FOLDS is where it was, not where the caller says. A
        // closing bloom keeps its last pose; only an open/opening one
        // adopts a new one — modules close by passing anchor .zero, and
        // folding there would teleport the ring to the scene origin.
        if target > 0.01 || reveal < 0.01 {
            self.anchor = anchor
            if let viewer { lastViewer = viewer }
        }
        let heldViewer = viewer ?? lastViewer

        reveal = Motion.ease(reveal, toward: target, dt: dt)

        root.isEnabled = reveal > 0.01
        guard root.isEnabled else { return }
        root.position = self.anchor

        // Constant angular size: scale with distance so it reads the same
        // at any range.
        var scale: Float = 1
        if let heldViewer {
            scale = max(simd_distance(heldViewer, self.anchor), 0.35)
        } else {
            scale = lastScale
        }
        root.scale = SIMD3(repeating: scale)
        lastScale = scale

        // Face the viewer without rolling — the ring stays level.
        if let heldViewer, let facing = yaw(facing: heldViewer, from: self.anchor) {
            root.orientation = facing
        }
        railAxis = root.orientation.act(SIMD3<Float>(1, 0, 0))

        layoutPetals(dt: dt)
        layoutGrip(scale: scale)
    }

    private func layoutPetals(dt: Double) {
        let rate = Motion.rate(dt: dt, 11)

        // An armed petal walked away from disarms itself, so a ring left
        // open with Clear armed isn't one stray pinch from firing later.
        if var armed = armedPetal {
            armed.elapsed += dt
            if armed.elapsed >= Self.armWindow {
                disarmPetal()
            } else {
                armedPetal = armed
            }
        }

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
            // Petals arc ABOVE the object, never in front of it.
            let lift = Self.ringRadius * r
            entity.position = SIMD3(sin(angle) * lift,
                                    cos(angle) * lift,
                                    0)
            // Overshoot slightly, then settle — the spring feel.
            let pop = 1 + 0.18 * sin(r * .pi)
            entity.scale = SIMD3(repeating: max(r, 0.001) * pop)
            entity.isEnabled = r > 0.02

            // Dim, never absent: the layout derives from the COUNT, so
            // removing a petal would shift the rest under the finger.
            let available = index < petals.count ? petals[index].isAvailable() : true
            entity.components.set(OpacityComponent(opacity: available ? 1 : 0.35))
        }
    }

    private func layoutGrip(scale: Float) {
        guard let grip, let gripEntity else { return }
        // The rail hangs UNDER the object, centred and level. Under is the
        // free direction: petals arc ABOVE (`layoutPetals`), giving a clean
        // stack — actions overhead, the object, its rail, its number.
        let surface = grip.radius() / max(scale, 0.001)
        let drop = -(surface + Self.gripTrackDrop)
        let start = -Self.gripTrackLength / 2
        let span = grip.range.upperBound - grip.range.lowerBound
        let t = Float(min(max((grip.read() - grip.range.lowerBound)
                              / max(span, .leastNonzeroMagnitude), 0), 1))

        // The bead sits ON the rail at the value's position.
        gripEntity.position = SIMD3(start + Self.gripTrackLength * t, drop, 0)
        gripEntity.scale = SIMD3(repeating: max(reveal, 0.001))
        // Visible for the whole fold, but only a HIT TARGET once nearly
        // fully open — a half-revealed grabbable bead steals grabs meant
        // for the object it decorates.
        gripEntity.isEnabled = reveal > 0.02
        let interactive = reveal > 0.85
        if interactive, gripEntity.components[InputTargetComponent.self] == nil {
            gripEntity.components.set(InputTargetComponent())
        } else if !interactive,
                  gripEntity.components[InputTargetComponent.self] != nil {
            gripEntity.components.remove(InputTargetComponent.self)
        }

        if let gripRig {
            gripRig.position = SIMD3(start, drop, 0)
            gripRig.scale = SIMD3(repeating: max(reveal, 0.001))
            gripRig.isEnabled = reveal > 0.02
        }
        if let gripFill {
            // The fill grows from the rail's start to the bead.
            let length = max(Self.gripTrackLength * t, 0.001)
            gripFill.scale = SIMD3(1, length, 1)
            gripFill.position = SIMD3(length / 2, 0, 0)
        }

        label?.isEnabled = reveal > 0.02
        label?.anchor(at: gripEntity.position)
        let reading = grip.format(grip.read())
        label?.setText(reading)
        // Spoken and seen from the same string. Guarded on change: a
        // component write per frame per bead is a cost this app refuses.
        if reading != lastGripSpoken {
            lastGripSpoken = reading
            SpatialActions.republish(value: reading, on: gripEntity)
        }
        label?.root.components.set(OpacityComponent(
            opacity: max(0, min((reveal - 0.35) / 0.5, 1))))
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
        // An unavailable petal neither fires NOR consumes — the tap must
        // fall through to whatever is behind it.
        guard petals[index].isAvailable() else { return false }

        // Acknowledge in place: a quick swell, then the action.
        let petal = petalEntities[index]
        petal.move(to: Self.swellTarget(for: petal),
                   relativeTo: root, duration: 0.09, timingFunction: .easeOut)

        if petals[index].confirms, armedPetal?.index != index {
            // First tap: arm and wait. Arming CONSUMES the tap.
            armedPetal = (index, 0)
            applyArmedLook(index: index, armed: true)
            SoundPalette.play(.pop, on: petal, volume: 0.25)
            return true
        }

        disarmPetal()
        petals[index].action()
        return true
    }

    /// The acknowledge-swell's target transform. The rotation MUST carry
    /// the petal's own orientation (built face-on at π/2 about X): an
    /// omitted rotation defaults to identity and tumbles the petal 90°.
    static func swellTarget(for petal: Entity) -> Transform {
        Transform(scale: SIMD3(repeating: petal.scale.x * 1.35),
                  rotation: petal.orientation,
                  translation: petal.position)
    }

    /// Clears any armed petal and restores its glyph.
    func disarmPetal() {
        guard let armed = armedPetal else { return }
        armedPetal = nil
        applyArmedLook(index: armed.index, armed: false)
    }

    /// Swap the glyph to a checkmark while armed, and light the casing so
    /// the change is legible without reading the icon.
    private func applyArmedLook(index: Int, armed: Bool) {
        guard petalEntities.indices.contains(index) else { return }
        let petal = petals[index]
        let entity = petalEntities[index]
        let symbol = armed ? "checkmark" : petal.symbol
        if let texture = Self.symbolTexture(symbol),
           let icon = entity.children.first(where: { $0.name == Self.iconName })
            as? ModelEntity {
            var material = UnlitMaterial()
            material.color = .init(tint: .white, texture: .init(texture))
            material.blending = .transparent(opacity: .init(floatLiteral: 1))
            icon.model?.materials = [material]
        }
        // REPUBLISH, DO NOT REBUILD: a fresh AccessibilityComponent would
        // carry empty systemActions and strip Activate, stranding a
        // VoiceOver user mid-confirmation.
        SpatialActions.republish(
            value: armed ? "armed, tap again to confirm" : "", on: entity)
    }

    func beginGrip(_ entity: Entity, hand: SIMD3<Float>) -> Bool {
        guard root.isEnabled, reveal > 0.85, let grip, let gripEntity else { return false }
        guard Self.ownName(of: entity, under: root) == gripEntity.name else { return false }
        gripDrag = (hand, grip.read())
        return true
    }

    /// Pull ALONG the rail: the hand's travel is projected onto the
    /// track's direction, so drift up/down/toward-you doesn't move the
    /// number. A radial mapping would run half the track backwards now
    /// that the rail hangs under the object rather than out from it.
    func updateGrip(hand: SIMD3<Float>) -> Bool {
        guard let grip, let gripDrag else { return false }
        let along = simd_dot(hand - gripDrag.startHand, railAxis)
        let span = grip.range.upperBound - grip.range.lowerBound
        let worldTrack = Double(Self.gripTrackLength * max(lastScale, 0.001))
        let delta = Double(along) / worldTrack * span
        grip.write(min(max(gripDrag.startValue + delta,
                           grip.range.lowerBound), grip.range.upperBound))
        return true
    }

    /// One VoiceOver increment/decrement — a twentieth of the range per
    /// step, through the SAME clamp `updateGrip` uses.
    func nudgeGrip(by steps: Double) {
        guard let grip else { return }
        let span = grip.range.upperBound - grip.range.lowerBound
        let next = grip.read() + steps * span / 20
        grip.write(min(max(next, grip.range.lowerBound), grip.range.upperBound))
        if let gripEntity {
            SpatialActions.republish(value: grip.format(grip.read()), on: gripEntity)
        }
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
        // A DARK casing with a white glyph: legible over a bright room and
        // a coloured field, where tinted glass reads as a smudge.
        let disc = ModelEntity(
            mesh: .generateCylinder(height: 0.005, radius: petalRadius),
            materials: [casing()])
        disc.name = "bloom-\(petal.name)"
        disc.orientation = simd_quatf(angle: .pi / 2, axis: [1, 0, 0])
        disc.components.set(GroundingShadowComponent(castsShadow: true))

        // A thin accent rim carries the meaning (red = destructive).
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
            // Named so `applyArmedLook` can find it to swap in the checkmark.
            icon.name = iconName
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
        // The bead stays BRIGHT AND SOLID — the handle your fingers hunt
        // for; the glass language is for surfaces a control sits ON.
        let bead = ModelEntity(
            mesh: .generateSphere(radius: 0.014),
            materials: [Materials.grip(roughness: 0.15,
                                       emissive: UIColor(white: 1, alpha: 1),
                                       glow: 0.35)])
        bead.name = "bloom-grip"
        bead.components.set(InputTargetComponent())
        // Barely larger than the bead: a generous collider steals grabs
        // meant for the object the bloom decorates.
        bead.components.set(CollisionComponent(
            shapes: [.generateSphere(radius: 0.016)]))
        bead.components.set(HoverEffectComponent())
        bead.components.set(GroundingShadowComponent(castsShadow: true))
        var accessibility = AccessibilityComponent()
        accessibility.isAccessibilityElement = true
        accessibility.label = "Pull to change"
        bead.components.set(accessibility)
        bead.isEnabled = false
        return bead
    }

    /// A petal's pane. Frosted glass, more solid than the banks' — a petal
    /// is a button and its glyph must stay legible.
    private static func casing() -> RealityKit.Material {
        Materials.frostedGlass(opacity: 0.66)
    }

    /// SF Symbols as textures.
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
