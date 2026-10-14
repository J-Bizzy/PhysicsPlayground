//
//  Bloom.swift
//  Physics Playground — Design System
//
//  The object is the interface: tap a thing and its own controls unfold
//  around it in place. A continuous quantity is pulled straight out of
//  the object — a handle on its surface, on a short stalk that stretches
//  as the value grows, or the object itself stretching (a charge swelling
//  with its charge, a cable lengthening) where the lab says how; a
//  discrete action gets a petal.
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
        /// the finger). A closure, not A BOOL: a Bool would be evaluated
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
    /// `radius` reports how far from the centre the object's surface is,
    /// so the handle rides it as it grows.
    struct Grip {
        let name: String
        let range: ClosedRange<Double>
        let read: () -> Double
        let write: (Double) -> Void
        let format: (Double) -> String
        let radius: () -> Float
        /// The object's own geometry, when the lab knows it: the value is
        /// then where the hand is, not how far it travelled.
        var stretch: Stretch? = nil

        /// How an object stretches, in the ring's parent frame — the frame
        /// its anchor and the hands arrive in. `axis` is the ring's pull
        /// direction (the viewer's right, level), handed in so an object
        /// without a natural axis of its own can use it.
        struct Stretch {
            /// Where the handle's stalk leaves the object.
            let origin: () -> SIMD3<Float>
            /// Where the handle stands for the current value.
            let handle: (_ axis: SIMD3<Float>) -> SIMD3<Float>
            /// The value a hand at this point asks for.
            let value: (_ hand: SIMD3<Float>, _ axis: SIMD3<Float>) -> Double

            /// For a sphere drawn with a radius that goes as the cube root
            /// of its value (a planet's mass, a charge's |q|): the handle
            /// sits just off the surface, and drawing it out to radius r
            /// asks for the value whose sphere is that big, so the object
            /// swells under the hand.
            static func surface(center: @escaping () -> SIMD3<Float>,
                                radius: @escaping () -> Float,
                                read: @escaping () -> Double) -> Stretch {
                let gap: Float = 0.02
                return Stretch(
                    origin: { center() },
                    handle: { axis in center() + axis * (radius() + gap) },
                    value: { hand, axis in
                        let reach = simd_dot(hand - center(), axis) - gap
                        let ratio = Double(max(reach, 0.004) / max(radius(), 1e-4))
                        return read() * ratio * ratio * ratio
                    })
            }
        }

        init(name: String, range: ClosedRange<Double>,
             read: @escaping () -> Double, write: @escaping (Double) -> Void,
             format: @escaping (Double) -> String,
             radius: @escaping () -> Float, stretch: Stretch? = nil) {
            self.name = name
            self.range = range
            self.read = read
            self.write = write
            self.format = format
            self.radius = radius
            self.stretch = stretch
        }
    }

    let root = Entity()

    private var petals: [Petal] = []
    private var petalEntities: [Entity] = []
    /// What each petal shows: armed, available.
    private var petalControls: [RoomControl] = []
    private var grip: Grip?
    private var gripEntity: ModelEntity?
    /// The stalk from the object's surface to the handle: the stretch.
    private var gripStalk: ModelEntity?
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

    /// Where the bloom is anchored, world space (set while open, held
    /// while it folds — see `update`).
    private var anchor: SIMD3<Float> = .zero
    /// The viewer's last known position, held for the same reason.
    private var lastViewer: SIMD3<Float>?
    /// The pull direction in world space, last frame: the viewer's right,
    /// level. A drag is projected onto it, so drift up, down or toward
    /// you moves nothing.
    private var railAxis = SIMD3<Float>(1, 0, 0)

    // MARK: Geometry
    //
    // Sizes are in metres at one metre, then scaled by distance so the
    // bloom holds constant angular size at any range. Sized and placed to
    // Clear the physics, not sit beside it.
    private static let ringRadius: Float = 0.235
    /// How far the handle travels from the low end of the range to the
    /// high, at one metre: the stalk's full stretch.
    private static let gripTrackLength: Float = 0.14
    /// Air between the object's surface and the handle at the low end.
    private static let gripGap: Float = 0.018
    /// Nearly a horizontal row: petals sit above the object, spread just
    /// enough to separate.
    private static let ringArc: Float = 34 * .pi / 180

    init() {
        root.isEnabled = false
    }

    /// What this bloom is currently pointed at. Tracked inside the class:
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
        // against the old grip, so a selection changing mid-drag would write
        // the old start value into the new object's range.
        gripDrag = nil
        self.petals = petals
        self.grip = grip
        petalEntities.forEach { $0.removeFromParent() }
        petalEntities = []
        petalControls = []
        petalReveals = Array(repeating: 0, count: petals.count)

        for petal in petals {
            let control = RoomControl(title: petal.name, systemImage: petal.symbol)
            // Through `press(named:)`, not straight at `petal.action`: that
            // path checks availability and arms a `confirms` petal instead of
            // firing. Found again by name: the view's closure must not hold
            // the entity that holds the view.
            let name = "bloom-\(petal.name)"
            let entity = ControlAttachment.control(
                control,
                kind: .button(Self.isDestructive(petal) ? .destructive : .standard,
                              iconOnly: true),
                name: name,
                press: { [weak self] in _ = self?.press(named: name) })
            entity.isEnabled = false
            root.addChild(entity)
            petalEntities.append(entity)
            petalControls.append(control)
        }

        gripEntity?.removeFromParent()
        gripStalk?.removeFromParent()
        if let grip {
            let handle = Self.makeGrip()
            root.addChild(handle)
            gripEntity = handle
            // The handle is dragged, not pressed, so it needs VoiceOver
            // increment/decrement.
            SpatialActions.attach(
                to: handle, label: grip.name, value: grip.format(grip.read()),
                adjust: { [weak self] delta in self?.nudgeGrip(by: delta) })
            let stalk = Self.makeStalk()
            root.addChild(stalk)
            gripStalk = stalk
        } else {
            gripEntity = nil
            gripStalk = nil
        }

        if label == nil {
            // Under the handle, where nothing of the object stands.
            let callout = Callout(color: UIColor(white: 0.97, alpha: 1),
                                  textSize: 0.019, offset: SIMD3(0, -0.040, 0))
            root.addChild(callout.root)
            label = callout
        }
        // Named on every retarget, not only when built: one ring serves every
        // object in a lab, and Electric Fields' probe "Charge" was announced
        // as the charge's "Strength" because that grip came first.
        label?.setAccessibilityName(grip?.name ?? "Value")
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

        // Where it folds is where it was, not where the caller says. A
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
        // The bead under a hand is live.
        if let gripEntity { LiveGlow.set(gripDrag != nil, on: gripEntity) }
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
            // Petals arc above the object, never in front of it.
            let lift = Self.ringRadius * r
            entity.position = SIMD3(sin(angle) * lift,
                                    cos(angle) * lift,
                                    0)
            // Overshoot slightly, then settle — the spring feel.
            let pop = 1 + 0.18 * sin(r * .pi)
            entity.scale = SIMD3(repeating: max(r, 0.001) * pop)
            entity.isEnabled = r > 0.02

            // Dim, never absent: the layout derives from the count, so
            // removing a petal would shift the rest under the finger.
            let available = index < petals.count ? petals[index].isAvailable() : true
            if index < petalControls.count { petalControls[index].setEnabled(available) }
        }
    }

    private func layoutGrip(scale: Float) {
        guard let grip, let gripEntity else { return }
        // Where the stalk leaves the object and where the handle stands,
        // in world space; the object's own geometry when the lab gave it,
        // else straight out of the surface toward the viewer's right, the
        // stalk as long as the value is far through its range.
        let origin: SIMD3<Float>
        let handle: SIMD3<Float>
        if let stretch = grip.stretch {
            origin = stretch.origin()
            handle = stretch.handle(railAxis)
        } else {
            let span = grip.range.upperBound - grip.range.lowerBound
            let t = Float(min(max((grip.read() - grip.range.lowerBound)
                                  / max(span, .leastNonzeroMagnitude), 0), 1))
            let surface = grip.radius()
            origin = anchor + railAxis * surface
            handle = anchor + railAxis * (surface + (Self.gripGap
                + Self.gripTrackLength * t) * scale)
        }
        // Everything above is in the ring's parent frame — the frame its
        // anchor and the hands arrive in — not world space: a lab's bench
        // may be zoomed.
        let localOrigin = root.convert(position: origin, from: root.parent)
        let localHandle = root.convert(position: handle, from: root.parent)

        gripEntity.position = localHandle
        gripEntity.scale = SIMD3(repeating: max(reveal, 0.001))
        // Visible for the whole fold, but only a hit target once nearly
        // fully open — a half-revealed grabbable handle steals grabs meant
        // for the object it decorates.
        gripEntity.isEnabled = reveal > 0.02
        let interactive = reveal > 0.85
        if interactive, gripEntity.components[InputTargetComponent.self] == nil {
            gripEntity.components.set(InputTargetComponent())
        } else if !interactive,
                  gripEntity.components[InputTargetComponent.self] != nil {
            gripEntity.components.remove(InputTargetComponent.self)
        }

        if let gripStalk {
            // A unit cylinder along +y, stretched from the surface to the handle.
            let run = localHandle - localOrigin
            let length = simd_length(run)
            gripStalk.isEnabled = reveal > 0.02 && length > 1e-4
            if length > 1e-4 {
                gripStalk.position = (localOrigin + localHandle) / 2
                gripStalk.orientation = simd_quatf(from: [0, 1, 0], to: run / length)
                gripStalk.scale = SIMD3(max(reveal, 0.001), length, max(reveal, 0.001))
            }
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
        guard let name = Self.ownName(of: entity, under: root) else { return false }
        return press(named: name)
    }

    /// One press on the petal of that name: the glass button's own action,
    /// and the end of every walk-up from a tapped entity.
    private func press(named name: String) -> Bool {
        guard root.isEnabled else { return false }
        guard let index = petalEntities.firstIndex(where: { $0.name == name }) else {
            return false
        }
        // An unavailable petal neither fires nor consumes — the tap must
        // fall through to whatever is behind it.
        guard petals[index].isAvailable() else { return false }

        // Acknowledge in place: a quick swell, then the action. Under Reduce
        // Motion the sound and the lamp acknowledge it; nothing swells.
        let petal = petalEntities[index]
        if !Motion.isReduced {
            petal.move(to: Self.swellTarget(for: petal),
                       relativeTo: root, duration: 0.09, timingFunction: .easeOut)
        }

        if petals[index].confirms, armedPetal?.index != index {
            // First tap: arm and wait. Arming consumes the tap.
            armedPetal = (index, 0)
            applyArmedLook(index: index, armed: true)
            SoundPalette.play(.pop, on: petal, volume: 0.25)
            return true
        }

        disarmPetal()
        // Heard as well as seen, as a fired action plate is: a petal used to
        // fire in silence, so Delete made no sound at all.
        SoundPalette.play(.pop, on: petal, volume: 0.35)
        petals[index].action()
        return true
    }

    /// The acknowledge-swell's target transform. The rotation must carry
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

    /// While armed the petal reads "Tap again" with a checkmark, filled in
    /// the destructive red — and says so to VoiceOver.
    private func applyArmedLook(index: Int, armed: Bool) {
        guard petalControls.indices.contains(index) else { return }
        petalControls[index].setArmed(armed)
    }

    /// What the named petal is showing — for tests, which cannot read the
    /// glass.
    func control(named name: String) -> RoomControl? {
        petalEntities.firstIndex { $0.name == "bloom-\(name)" }
            .flatMap { petalControls.indices.contains($0) ? petalControls[$0] : nil }
    }

    /// Whether a petal deletes or clears: its tint says so.
    private static func isDestructive(_ petal: Petal) -> Bool {
        petal.confirms || petal.tint.isEqual(DesignTokens.Palette.destructiveUI)
    }

    func beginGrip(_ entity: Entity, hand: SIMD3<Float>) -> Bool {
        guard root.isEnabled, reveal > 0.85, let grip, let gripEntity else { return false }
        guard Self.ownName(of: entity, under: root) == gripEntity.name else { return false }
        gripDrag = (hand, grip.read())
        return true
    }

    /// Pull the handle. A stretching object takes its value from where the
    /// hand is; the plain stalk from how far the hand has travelled along
    /// the pull axis, so drift up, down or toward you moves nothing.
    func updateGrip(hand: SIMD3<Float>) -> Bool {
        guard let grip, let gripDrag else { return false }
        if let stretch = grip.stretch {
            grip.write(min(max(stretch.value(hand, railAxis),
                               grip.range.lowerBound), grip.range.upperBound))
            return true
        }
        let along = simd_dot(hand - gripDrag.startHand, railAxis)
        let span = grip.range.upperBound - grip.range.lowerBound
        let worldTrack = Double(Self.gripTrackLength * max(lastScale, 0.001))
        let delta = Double(along) / worldTrack * span
        grip.write(min(max(gripDrag.startValue + delta,
                           grip.range.lowerBound), grip.range.upperBound))
        return true
    }

    /// One VoiceOver increment/decrement — a twentieth of the range per
    /// step, through the same clamp `updateGrip` uses.
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

    /// The bead's instrument: a translucent rail the length of the
    /// whole range, a tick at each end, a small − at the weak end and
    /// + at the strong end, and a bright fill that grows with the
    /// value. Origin at the rail's start; the fill is repositioned per
    /// frame as the value moves.
    /// The stalk: a thin bright line, the part of the object that
    /// stretches. Scaled along +y by the layout; never a target.
    private static func makeStalk() -> ModelEntity {
        let stalk = ModelEntity(
            mesh: Primitives.cylinder(height: 1, radius: 0.0018),
            materials: [Materials.unlit(UIColor(white: 1.0, alpha: 1), opacity: 0.8)])
        stalk.name = "bloom-stalk"
        stalk.isEnabled = false
        return stalk
    }

    private static func makeGrip() -> ModelEntity {
        // The bead stays bright and solid — the handle your fingers hunt
        // for; the glass language is for surfaces a control sits on.
        let bead = ModelEntity(
            mesh: Primitives.sphere(radius: 0.014),
            materials: [Materials.grip(roughness: 0.15,
                                       emissive: UIColor(white: 1, alpha: 1),
                                       glow: 0.35)])
        bead.name = "bloom-grip"
        bead.components.set(InputTargetComponent())
        // Barely larger than the bead: a generous collider steals grabs
        // meant for the object the bloom decorates.
        bead.components.set(CollisionComponent(
            shapes: [Primitives.collisionSphere(radius: 0.016)]))
        bead.components.set(HoverEffectComponent())
        bead.components.set(GroundingShadowComponent(castsShadow: true))
        var accessibility = AccessibilityComponent()
        accessibility.isAccessibilityElement = true
        accessibility.label = "Pull to change"
        bead.components.set(accessibility)
        bead.isEnabled = false
        return bead
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
