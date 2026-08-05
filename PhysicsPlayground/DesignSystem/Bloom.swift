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

        /// Read every frame. A petal whose condition is false goes dim
        /// and refuses the tap — it never disappears, because a ring
        /// whose petals come and go moves the others under your finger.
        ///
        /// A CLOSURE, NOT A BOOL, and that distinction has already cost
        /// this project a bug in the other direction. A `Bloom` is
        /// configured once when a ring opens, so a plain `Bool` would be
        /// evaluated on that one frame and then never again — the petal
        /// would be permanently live or permanently dim depending on
        /// what the room happened to look like when you tapped. The note
        /// in `KinematicsSpaceView` recording exactly that reasoning is
        /// why its Clear petal had no condition at all.
        var isAvailable: () -> Bool = { true }

        /// Two taps: the first arms the petal and swaps its glyph to a
        /// checkmark, the second fires. An armed petal disarms itself
        /// after `armWindow`, so one walked away from is safe.
        ///
        /// For destructive verbs that cannot be undone. The same
        /// semantics `SpatialActionBank` gives a standing plate, in the
        /// ring — Circuits' and Electric Fields' "Clear" both confirm,
        /// and Projectiles' identical verb did not, because a petal had
        /// no way to say so.
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

    /// How long an armed petal stays armed — the same window a standing
    /// verb plate uses, so the two feel like one mechanism.
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

    /// Where the bloom is anchored, world space (set every frame while
    /// it is open, and HELD while it folds — see `update`).
    private var anchor: SIMD3<Float> = .zero
    /// The viewer's last known position, held for the same reason.
    private var lastViewer: SIMD3<Float>?
    /// The rail's direction in world space, as of the last frame. The
    /// grip drag projects the hand onto this, so a pull along the rail
    /// is a pull along the rail and nothing else.
    private var railAxis = SIMD3<Float>(1, 0, 0)

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
    /// The glyph plane's entity name, so the armed checkmark can find it.
    private static let iconName = "bloom-petal-icon"
    private static let ringRadius: Float = 0.235
    /// The grip's track: the visible rail the bead travels, from the
    /// object's surface outward. The bead's POSITION on the rail is the
    /// value — min at the object, max at the far tick — so the mapping
    /// is something you see, not something you discover.
    private static let gripTrackLength: Float = 0.14
    /// How far BELOW the object's surface the rail hangs, so it never
    /// reads as part of the thing it measures — and, more to the point,
    /// so it never shares space with whatever that thing has bolted to
    /// its sides. See `layoutGrip`.
    private static let gripTrackDrop: Float = 0.048
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
        // Rebuilding the ring destroys the entity the armed index refers
        // to, so the arm cannot survive it. `SpatialActionBank` learned
        // the same thing — see `testSettingNewActionsDisarms`.
        armedPetal = nil
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
            // BELOW the bead. The rail moved under the object, so a
            // label 55 mm above its bead would now land between the
            // rail and the object it belongs to — the one gap in the
            // stack that has to stay clear.
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

        // WHERE IT FOLDS is where it was, not where the caller says.
        //
        // Every module closes this ring the same way: the moment nothing
        // is selected, it calls `update(anchor: .zero, viewer: nil,
        // revealTarget: 0)` and then `clearTarget()`. Which meant the
        // fold — a real half-second ease that has always been in this
        // file — ran at the scene ORIGIN, at 1× scale, unrotated. The
        // ring did not vanish; it teleported to the floor a metre and a
        // half away, shrank to a third of its size, and eased out down
        // there where nobody was looking. On device that is
        // indistinguishable from "the buttons just disappear," which is
        // exactly how it was reported.
        //
        // So a closing bloom keeps the last pose it was given. Only a
        // bloom that is open, or opening, adopts a new one.
        if target > 0.01 || reveal < 0.01 {
            self.anchor = anchor
            if let viewer { lastViewer = viewer }
        }
        let heldViewer = viewer ?? lastViewer

        let rate = Float(min(dt * 9, 1))
        reveal += (target - reveal) * rate
        if abs(reveal - target) < 0.004 { reveal = target }

        root.isEnabled = reveal > 0.01
        guard root.isEnabled else { return }
        root.position = self.anchor

        // Constant angular size: a bloom two metres away is drawn twice
        // as large, so it subtends the same angle and reads identically.
        var scale: Float = 1
        if let heldViewer {
            scale = max(simd_distance(heldViewer, self.anchor), 0.35)
        } else {
            scale = lastScale
        }
        root.scale = SIMD3(repeating: scale)
        lastScale = scale

        // Face the viewer without rolling — the ring stays level.
        if let heldViewer {
            let toViewer = heldViewer - self.anchor
            let flat = SIMD3<Float>(toViewer.x, 0, toViewer.z)
            if simd_length(flat) > 1e-4 {
                root.orientation = simd_quatf(from: [0, 0, 1],
                                              to: simd_normalize(flat))
            }
        }
        railAxis = root.orientation.act(SIMD3<Float>(1, 0, 0))

        layoutPetals(dt: dt)
        layoutGrip(scale: scale)
    }

    private func layoutPetals(dt: Double) {
        let rate = Float(min(dt * 11, 1))

        // An armed petal walked away from disarms itself, exactly as a
        // standing verb plate does. Without this a ring left open with a
        // Clear armed would still be one stray pinch from firing when the
        // user came back to it minutes later — which is the risk the
        // confirmation exists to remove, not to reschedule.
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

            // Dim, never absent. A petal that vanished when its condition
            // went false would shift every petal beside it out from under
            // the finger already reaching for one — the ring's layout is
            // derived from the COUNT, so removing one moves the rest.
            let available = index < petals.count ? petals[index].isAvailable() : true
            entity.components.set(OpacityComponent(opacity: available ? 1 : 0.35))
        }
    }

    private func layoutGrip(scale: Float) {
        guard let grip, let gripEntity else { return }
        // The rail hangs UNDER the object, centred on it, running level.
        //
        // It used to run radially outward from the object's surface
        // along the bloom's +X — straight through whatever that object
        // has attached to its sides. In Circuit Workshop that is a
        // copper terminal and its lead, sitting at 85 mm on the part's
        // own axis, and the bead's whole low-value half was behind it:
        // the one control that has to be visible while you pull it was
        // the one thing you could not see. Every module shares this
        // class, so the rail was in the same wrong place in all eight.
        //
        // Under is the free direction, and it is free by construction:
        // the petals arc ABOVE (`layoutPetals`), so the object gets a
        // clean stack — actions overhead, the thing itself, its rail
        // beneath, its number below that. Nothing overlaps anything.
        let surface = grip.radius() / max(scale, 0.001)
        let drop = -(surface + Self.gripTrackDrop)
        let start = -Self.gripTrackLength / 2
        let span = grip.range.upperBound - grip.range.lowerBound
        let t = Float(min(max((grip.read() - grip.range.lowerBound)
                              / max(span, .leastNonzeroMagnitude), 0), 1))

        // The bead sits ON the rail at the value's position — weak at
        // the left tick, strong at the right.
        gripEntity.position = SIMD3(start + Self.gripTrackLength * t, drop, 0)
        gripEntity.scale = SIMD3(repeating: max(reveal, 0.001))
        // Visible for the whole fold, so it eases out with everything
        // else — but only a HIT TARGET once the bloom is essentially
        // fully open. A half-revealed bead that can still be grabbed
        // steals grabs meant for the object it decorates, which is why
        // this used to be a plain isEnabled cutoff; the two concerns
        // just needed separating rather than conflating.
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
            // The fill grows from the rail's start to the bead — the
            // "how much" you can read without the number.
            let length = max(Self.gripTrackLength * t, 0.001)
            gripFill.scale = SIMD3(1, length, 1)
            gripFill.position = SIMD3(length / 2, 0, 0)
        }

        // The value stays readable the whole time the ring is open, and
        // fades WITH it rather than blinking off on the first fold
        // frame.
        label?.isEnabled = reveal > 0.02
        label?.anchor(at: gripEntity.position)
        label?.setText(grip.format(grip.read()))
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
        // An unavailable petal neither fires NOR consumes. Swallowing the
        // tap would make a dim petal a hole in the room — the gesture has
        // to fall through to whatever is behind it, which is the same rule
        // `SpatialActionBank` follows for a dim plate.
        guard petals[index].isAvailable() else { return false }

        // Acknowledge in place: a quick swell, then the action.
        let petal = petalEntities[index]
        petal.move(to: Self.swellTarget(for: petal),
                   relativeTo: root, duration: 0.09, timingFunction: .easeOut)

        if petals[index].confirms, armedPetal?.index != index {
            // First tap: arm and wait. Arming CONSUMES the tap — it is a
            // real response, and letting it fall through would run
            // whatever is behind the ring while the user was aiming here.
            armedPetal = (index, 0)
            applyArmedLook(index: index, armed: true)
            SoundPalette.play(.pop, on: petal, volume: 0.25)
            return true
        }

        disarmPetal()
        petals[index].action()
        return true
    }

    /// The acknowledge-swell's target transform. Scale and translation
    /// grow the petal in place; the rotation MUST carry the petal's own
    /// orientation — petals are built face-on at π/2 about X, and a
    /// `Transform` that omits rotation defaults to identity, so the
    /// swell used to tumble every petal 90° on tap.
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
        var accessibility = AccessibilityComponent()
        accessibility.isAccessibilityElement = true
        accessibility.label = LocalizedStringResource(stringLiteral: petal.name)
        accessibility.value = LocalizedStringResource(
            stringLiteral: armed ? "armed, tap again to confirm" : "")
        entity.components.set(accessibility)
    }

    func beginGrip(_ entity: Entity, hand: SIMD3<Float>) -> Bool {
        guard root.isEnabled, reveal > 0.85, let grip, let gripEntity else { return false }
        guard Self.ownName(of: entity, under: root) == gripEntity.name else { return false }
        gripDrag = (hand, grip.read())
        return true
    }

    /// Pull ALONG the rail: the hand's travel is projected onto the
    /// track's own direction, so the bead follows your fingers exactly
    /// down the line you can see, and a hand that drifts up, down or
    /// toward you while it slides does not move the number.
    ///
    /// This was a radial mapping — distance from the object's centre —
    /// which was congruent with the rail only for as long as the rail
    /// pointed straight away from the object. It no longer does (it
    /// hangs underneath), and a radial reading of a rail centred below
    /// its object is worse than wrong: it reads the SAME growing
    /// distance whichever way you slide, so half the track runs
    /// backwards.
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
            // Named so `applyArmedLook` can find it to swap in the
            // checkmark. Without a name it would have to guess by index,
            // which the accent rim already occupies.
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
        // The bead stays BRIGHT AND SOLID, and is the one control in this
        // file that does not become glass. It is the thing your fingers
        // are looking for on a rail a centimetre thick; a dark
        // translucent pea is a worse target than a lit one, and the
        // glass language is for the surfaces a control sits ON, not for
        // the handle itself.
        let bead = ModelEntity(
            mesh: .generateSphere(radius: 0.014),
            materials: [Materials.grip(roughness: 0.15,
                                       emissive: UIColor(white: 1, alpha: 1),
                                       glow: 0.35)])
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

    /// A petal's pane. Frosted glass, and slightly more solid than the
    /// banks' — a petal is a BUTTON with a glyph on it, and a glyph read
    /// through too much room is a glyph you have to hunt for.
    private static func casing() -> RealityKit.Material {
        Materials.frostedGlass(opacity: 0.66)
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
