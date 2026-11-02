//
//  Bloom.swift
//  Physics Playground — Design System
//
//  The object is the interface: tap a thing and its own controls unfold
//  around it in place. A continuous quantity is pulled straight out of
//  the object — a handle on a stalk that stretches as the value grows,
//  along a long calm track where the value spans decades (a charge, a
//  mass), or the object itself stretching (a cable lengthening) where the
//  lab says how; a discrete action gets a petal.
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

        /// For a petal that changes a state rather than doing a thing (a
        /// mass, a winding, a colour): what that state is now, read after
        /// the action and spoken to VoiceOver, which otherwise hears only
        /// the petal's own name.
        var announce: (() -> String)?

        init(name: String, symbol: String, tint: UIColor,
             isAvailable: @escaping () -> Bool = { true },
             confirms: Bool = false,
             announce: (() -> String)? = nil,
             action: @escaping () -> Void) {
            self.name = name
            self.symbol = symbol
            self.tint = tint
            self.isAvailable = isAvailable
            self.confirms = confirms
            self.announce = announce
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
        /// A long, calm track out to the viewer's right, for a value the
        /// object shows by its size (a charge's |q|, a body's mass).
        var track: Track? = nil

        /// The calm track. Until 2026-10-24 these values were set by a
        /// handle on the object's surface whose distance from the centre WAS
        /// the sphere's radius, so a charge's whole 0.2–6 µC took 3.7 cm of
        /// hand travel and 8 mm doubled it: hand tracking's own jitter moved
        /// the number (the owner: "very clunky"). Here the value moves by
        /// how far the hand travels along the track, never by where it first
        /// landed; a value spanning decades lies on it logarithmically, so
        /// equal travel multiplies it by equal factors; and round values
        /// click into place on the way past.
        struct Track {
            /// The values the bead clicks into, with the number each tick
            /// carries (nil: a tick alone).
            struct Detent {
                let value: Double
                let label: String?
            }

            var detents: [Detent] = []
            /// Equal travel multiplies the value by equal factors.
            var logarithmic = true
            /// Its length at one metre, scaled with distance like the
            /// rest of the ring.
            var length: Float = Bloom.calmTrackLength
            /// How far below the object the track runs, at one metre; 0
            /// starts it at the object's surface. For an object whose size
            /// is not its value (a circuit part, a bar magnet) the track
            /// starts straight under it instead, clear of the leads or poles
            /// that join it to its neighbours along its own axis.
            var drop: Float = 0
            /// For a dropped track, how far the object's own pinch targets
            /// reach below its centre as seen from the viewer's side, in the
            /// ring's parent frame, metres; handed the level unit vector
            /// toward the viewer. The rail then hangs `drop` (at one metre)
            /// below THAT, so the object's target never sits over the rail's
            /// start, at any distance or turn. Nil: `drop` below the centre.
            var clearsBelow: ((_ towardViewer: SIMD3<Float>) -> Float)? = nil

            /// Where along the rail the track starts, for an object of
            /// `radius`: its surface, or under its centre when dropped.
            func start(radius: Float) -> Float { drop > 0 ? 0 : radius }
        }

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

        }

        init(name: String, range: ClosedRange<Double>,
             read: @escaping () -> Double, write: @escaping (Double) -> Void,
             format: @escaping (Double) -> String,
             radius: @escaping () -> Float, stretch: Stretch? = nil, track: Track? = nil) {
            self.name = name
            self.range = range
            self.read = read
            self.write = write
            self.format = format
            self.radius = radius
            self.stretch = stretch
            self.track = track
        }

        /// How far along its track `value` lies, 0 at the low end and 1 at
        /// the high.
        func fraction(of value: Double) -> Double {
            let low = range.lowerBound, high = range.upperBound
            guard high > low else { return 0 }
            let clamped = min(max(value, low), high)
            if track?.logarithmic ?? false, low > 0 {
                return log(clamped / low) / log(high / low)
            }
            return (clamped - low) / (high - low)
        }

        /// The value at `fraction` of the way along the track.
        func value(at fraction: Double) -> Double {
            let low = range.lowerBound, high = range.upperBound
            let t = min(max(fraction, 0), 1)
            if track?.logarithmic ?? false, low > 0 {
                return low * pow(high / low, t)
            }
            return low + t * (high - low)
        }

        /// The detent a bead at `fraction` falls into, if it lies within
        /// `window` (a share of the track) of one.
        func detent(near fraction: Double, window: Double) -> Track.Detent? {
            guard let track else { return nil }
            return track.detents
                .map { ($0, abs(self.fraction(of: $0.value) - fraction)) }
                .filter { $0.1 <= window }
                .min { $0.1 < $1.1 }?.0
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
    /// The calm track's rail, ticks and numbers; a pinch anywhere on it
    /// takes the bead.
    private var trackEntity: Entity?
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
    /// `trackStart` is where the calm track began when the hand took it,
    /// held for the whole drag: the object swells under the hand, and a
    /// track that rode its surface would run the bead away from the finger.
    private var gripDrag: (startHand: SIMD3<Float>, startValue: Double, trackStart: Float)?
    /// The detent the bead last clicked into, so each click sounds once.
    private var lastDetent: Double?
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
    /// The calm track's length at one metre: about 15 cm at arm's length.
    static let calmTrackLength: Float = 0.19
    /// How far under an object a dropped track runs, at one metre: below a
    /// lying circuit part's body and leads, or a bar magnet's.
    static let calmTrackDrop: Float = 0.065
    /// How near a detent, as a share of the track, the bead falls into it:
    /// about 3 mm of hand travel at arm's length.
    static let detentWindow: Double = 0.018
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
        lastDetent = nil
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
        trackEntity?.removeFromParent()
        trackEntity = nil
        if let grip, let track = grip.track {
            let built = Self.makeTrack(track, for: grip)
            root.addChild(built)
            trackEntity = built
        }
        if let grip {
            let handle = Self.makeGrip(clearOfObject: grip.track?.clearsBelow != nil
                                       && (grip.track?.drop ?? 0) > 0)
            root.addChild(handle)
            gripEntity = handle
            // The handle is dragged, not pressed, so it needs VoiceOver
            // increment/decrement.
            SpatialActions.attach(
                to: handle, label: grip.name,
                value: PhysicsFormat.spoken(grip.format(grip.read())),
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
        } else if let track = grip.track {
            // Out of the object's surface (or from under it, when dropped) to
            // a bead on the calm track, which starts where the surface stood
            // when the hand took it.
            let surface = track.start(radius: grip.radius())
            let start = gripDrag?.trackStart ?? surface
            let t = Float(grip.fraction(of: grip.read()))
            // The ring only yaws, so its own down is the parent frame's, and
            // its +z is level toward the viewer.
            let clears = track.drop > 0
                ? max(track.clearsBelow?(root.orientation.act([0, 0, 1])) ?? 0, 0) : 0
            let below = SIMD3<Float>(0, -(track.drop * scale + clears), 0)
            origin = anchor + below + railAxis * surface
            handle = anchor + below
                + railAxis * (start + (Self.gripGap + track.length * t) * scale)
            if let trackEntity {
                // The ring's root is the anchor scaled by `scale` and turned
                // so its +x is the rail: the track's start, in its own units.
                trackEntity.position = [start / max(scale, 0.001) + Self.gripGap,
                                        -(track.drop + clears / max(scale, 0.001)), 0]
                trackEntity.scale = [max(reveal, 0.001), 1, 1]
                trackEntity.isEnabled = reveal > 0.02
                let interactive = reveal > 0.85
                if interactive, trackEntity.components[InputTargetComponent.self] == nil {
                    trackEntity.components.set(InputTargetComponent())
                } else if !interactive,
                          trackEntity.components[InputTargetComponent.self] != nil {
                    trackEntity.components.remove(InputTargetComponent.self)
                }
            }
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
            SpatialActions.republish(value: PhysicsFormat.spoken(reading), on: gripEntity)
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
        if let announce = petals[index].announce {
            AccessibilityNotification.Announcement(announce()).post()
        }
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
        // The bead, or anywhere on the calm track's rail: the bead is small,
        // and the rail says where it can go.
        let name = Self.ownName(of: entity, under: root)
        guard name == gripEntity.name || (trackEntity != nil && name == trackEntity?.name)
        else { return false }
        gripDrag = (hand, grip.read(), grip.track?.start(radius: grip.radius()) ?? grip.radius())
        lastDetent = grip.detent(near: grip.fraction(of: grip.read()), window: 1e-9)?.value
        // A bead already at an end has already stopped there: only pulling
        // past it again, after leaving it, sounds.
        let startFraction = grip.fraction(of: grip.read())
        lastStop = startFraction <= 0 ? .minus : startFraction >= 1 ? .plus : nil
        // Taken as anything in the room is taken: a tick under the glow.
        SoundPalette.play(.grabTick, on: gripEntity, volume: 0.2)
        return true
    }

    /// The end of the range the bead last stopped against, so the stop
    /// sounds once as it arrives there.
    private var lastStop: FloatingPointSign?

    /// A soft stop as the hand pulls past either end of the range: the
    /// bead stays put, and says why. `fraction` is where the hand asks for,
    /// unclamped.
    private func stop(at fraction: Double) {
        let end: FloatingPointSign? = fraction <= 0 ? .minus : fraction >= 1 ? .plus : nil
        if let end, end != lastStop, let gripEntity {
            SoundPalette.play(.thud, on: gripEntity, volume: 0.12)
        }
        lastStop = end
    }

    /// Pull the handle. A stretching object takes its value from where the
    /// hand is; the plain stalk and the calm track from how far the hand has
    /// travelled along the pull axis, so drift up, down or toward you moves
    /// nothing.
    func updateGrip(hand: SIMD3<Float>) -> Bool {
        guard let grip, let gripDrag else { return false }
        if let stretch = grip.stretch {
            grip.write(min(max(stretch.value(hand, railAxis),
                               grip.range.lowerBound), grip.range.upperBound))
            return true
        }
        let along = simd_dot(hand - gripDrag.startHand, railAxis)
        if let track = grip.track {
            let travel = Double(track.length * max(lastScale, 0.001))
            let fraction = grip.fraction(of: gripDrag.startValue) + Double(along) / travel
            stop(at: fraction)
            let detent = grip.detent(near: fraction, window: Self.detentWindow)
            grip.write(detent?.value ?? grip.value(at: fraction))
            // One click as the bead drops into a round value.
            if let detent, detent.value != lastDetent, let gripEntity {
                SoundPalette.play(.grabTick, on: gripEntity, volume: 0.12)
            }
            lastDetent = detent?.value
            return true
        }
        let span = grip.range.upperBound - grip.range.lowerBound
        let worldTrack = Double(Self.gripTrackLength * max(lastScale, 0.001))
        let delta = Double(along) / worldTrack * span
        stop(at: (gripDrag.startValue + delta - grip.range.lowerBound) / max(span, .leastNonzeroMagnitude))
        grip.write(min(max(gripDrag.startValue + delta,
                           grip.range.lowerBound), grip.range.upperBound))
        return true
    }

    /// One VoiceOver increment/decrement: on a calm track with detents,
    /// from one round value to the next (and on to the range's ends);
    /// otherwise a twentieth of the range per step, through the same clamp
    /// `updateGrip` uses.
    func nudgeGrip(by steps: Double) {
        guard let grip else { return }
        if let track = grip.track, !track.detents.isEmpty {
            let stops = Array(Set(track.detents.map(\.value)
                + [grip.range.lowerBound, grip.range.upperBound])).sorted()
            var value = grip.read()
            for _ in 0..<Int(abs(steps).rounded()) {
                let tolerance = 1e-9 * max(abs(value), 1)
                if steps > 0 {
                    value = stops.first { $0 > value + tolerance } ?? grip.range.upperBound
                } else {
                    value = stops.last { $0 < value - tolerance } ?? grip.range.lowerBound
                }
            }
            grip.write(value)
        } else {
            let span = grip.range.upperBound - grip.range.lowerBound
            let next = grip.read() + steps * span / 20
            grip.write(min(max(next, grip.range.lowerBound), grip.range.upperBound))
        }
        if let gripEntity {
            SpatialActions.republish(value: PhysicsFormat.spoken(grip.format(grip.read())),
                                     on: gripEntity)
        }
    }

    /// Lets go of the bead: a tick, as any release in the room ticks —
    /// only after a drag, so the views' cleanup calls stay silent.
    func endGrip() {
        if gripDrag != nil, let gripEntity {
            SoundPalette.play(.releaseTick, on: gripEntity, volume: 0.2)
        }
        gripDrag = nil
    }

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

    /// The calm track: a faint rail the length of the range along +x from
    /// its origin, a tick at each detent and its number above it. Built once
    /// per retarget (the numbers are cached glyphs); the layout only moves
    /// and unfolds it. The whole rail is a target, so a pinch anywhere on it
    /// takes the bead.
    static func makeTrack(_ track: Grip.Track, for grip: Grip) -> Entity {
        let container = Entity()
        container.name = "bloom-track"
        container.isEnabled = false
        let line = Primitives.cylinder(height: 1, radius: 1)

        let rail = ModelEntity(mesh: line, materials: [Materials.unlit(.white, opacity: 0.26)])
        rail.orientation = simd_quatf(angle: -.pi / 2, axis: [0, 0, 1])
        rail.scale = [0.0009, track.length, 0.0009]
        rail.position = [track.length / 2, 0, 0]
        container.addChild(rail)

        let tickMaterial = Materials.unlit(.white, opacity: 0.6)
        for detent in track.detents {
            let x = track.length * Float(grip.fraction(of: detent.value))
            let tick = ModelEntity(mesh: line, materials: [tickMaterial])
            tick.scale = [0.0007, 0.009, 0.0007]
            tick.position = [x, 0, 0]
            container.addChild(tick)
            if let label = detent.label {
                let number = GlyphRun(size: 0.0085, color: UIColor(white: 1, alpha: 0.72))
                number.set(label)
                number.root.position = [x, 0.0125, 0]
                container.addChild(number.root)
            }
        }
        // Thick enough to pinch, thin enough to leave the object to itself
        // (it was 24 × 20 mm until 2026-11-02, about half what a pinch
        // wants, and the owner found the sliders hard to grab). It lights
        // under the eye as the bead does, so a pinch knows it is on the rail
        // before it closes.
        container.components.set(CollisionComponent(shapes: [
            Primitives.collisionBox(size: [track.length, Self.trackTargetHeight,
                                           Self.trackTargetDepth],
                                    offset: [track.length / 2, 0, 0])]))
        container.components.set(HoverEffectComponent())
        return container
    }

    /// The rail's pinch target at one metre, across and through: within the
    /// collider rule's 15 mm per side of the ticks and numbers it carries.
    /// Only the height grew: the rail is drawn under 2 mm deep, and a deeper
    /// target breaks the rule once the ring is scaled past about a metre.
    static let trackTargetHeight: Float = 0.036
    static let trackTargetDepth: Float = 0.02
    /// The bead's pinch target at one metre. On a track that hangs clear of
    /// the object's own targets (`clearsBelow`), nothing of the object's
    /// competes for it and it takes most of the rule's reach; anywhere else
    /// it stays barely larger than the bead, or it would steal pinches meant
    /// for the object.
    static let beadTargetRadius: Float = 0.016
    static let clearBeadTargetRadius: Float = 0.022

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

    private static func makeGrip(clearOfObject: Bool = false) -> ModelEntity {
        // The bead stays bright and solid — the handle your fingers hunt
        // for; the glass language is for surfaces a control sits on.
        let bead = ModelEntity(
            mesh: Primitives.sphere(radius: 0.014),
            materials: [Materials.grip(roughness: 0.15,
                                       emissive: UIColor(white: 1, alpha: 1),
                                       glow: 0.35)])
        bead.name = "bloom-grip"
        bead.components.set(InputTargetComponent())
        bead.components.set(CollisionComponent(shapes: [Primitives.collisionSphere(
            radius: clearOfObject ? clearBeadTargetRadius : beadTargetRadius)]))
        bead.components.set(HoverEffectComponent())
        bead.components.set(GroundingShadowComponent(castsShadow: true))
        SpatialActions.describe(bead, label: "Pull to change")
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
