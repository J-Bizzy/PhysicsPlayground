//
//  Well.swift
//  Physics Playground — Design System
//
//  Creation, as a physical act. Every lab has one or two of these: a
//  small source you reach into and PULL something out of. The new
//  object is born at your fingertips and follows your hand until you
//  let go of it, which means placing a charge and moving a charge are
//  the same gesture — you never learn a second one.
//
//  This replaces "Add +" and "Add −" buttons on a floating card. A
//  button tells you a thing exists somewhere; a well hands it to you.
//
//  THE GLASS CAME OFF (2026-08-01, owner's call). Every well in the app
//  used to be the same tinted glass sphere with a different letter
//  floating inside it — "+" in three modules, "N" in one, "q" in
//  another. So the one affordance whose entire job is to say WHAT YOU
//  ARE ABOUT TO MAKE said only "something comes out of here", and said
//  it identically in five places.
//
//  What you see now is the thing itself: a bar magnet with its red and
//  blue poles in Magnetism, a bob on a cable in Pendulums, a world in
//  Gravity Lab, a red or blue charge in Electric Fields — at the size it
//  will be when you have it, with its name written under it. The
//  metaphor survives the glass going: it still breathes, still recoils
//  when it gives something up, and still dims when the lab is full and
//  it has nothing to give.
//
//  Callers supply the miniature, because only the module knows what its
//  own object looks like. The rule for a good one: build it out of the
//  SAME materials and proportions the renderer uses, so the preview and
//  the thing you pull out are recognisably one object.
//

import RealityKit
import SwiftUI
import RenderKit
import simd

@MainActor
final class Well {
    /// One source: what it makes, and what it looks like beforehand.
    struct Spec {
        let name: String
        let tint: UIColor
        /// The words under the object — "Add magnet", "Add world".
        let label: String
        /// Builds the miniature that stands here. Called once, on the
        /// main actor, at construction.
        let preview: @MainActor () -> Entity
        let position: SIMD3<Float>
        /// Makes the object at a world point and returns its id, so the
        /// caller can hand the new thing straight to the drag it was
        /// born from.
        let spawn: (SIMD3<Double>) -> UUID?

        /// For a ONE-OF-A-KIND object that lives in the shelf rather
        /// than being manufactured by it.
        ///
        /// Circuit Workshop's multimeter is the case: there is exactly
        /// one, so pulling its slot must hand over the instrument that
        /// exists rather than mint a second. `spawn` cannot express that
        /// — returning nil there means "I could not", which dims the
        /// slot in refusal.
        ///
        /// When this is set the slot is a PARKING SPACE, and `pull`
        /// answers with the pop rather than the flinch.
        var handOver: (@MainActor (SIMD3<Double>) -> Void)?

        init(name: String, tint: UIColor, label: String,
             preview: @escaping @MainActor () -> Entity,
             position: SIMD3<Float>,
             spawn: @escaping (SIMD3<Double>) -> UUID?,
             handOver: (@MainActor (SIMD3<Double>) -> Void)? = nil) {
            self.name = name
            self.tint = tint
            self.label = label
            self.preview = preview
            self.position = position
            self.spawn = spawn
            self.handOver = handOver
        }
    }

    /// How many slots are on screen at once, or nil for all of them.
    ///
    /// A SHELF, NOT A WALL. Circuit Workshop stands twelve kinds of part
    /// and the owner's note was that twelve at once is a lot to look
    /// past; the other five modules have three or four and want none of
    /// this. Nil keeps their behaviour exactly as it was — the window is
    /// opt-in, so adding it could not change a module that did not ask.
    ///
    /// Setting this BUILDS the carets, because a caller sets it after
    /// `init` and the first version built them there — where
    /// `visibleCount` was still nil, the guard bailed, and the rack
    /// shipped with no affordance at all. The tests for the affordance
    /// caught it, which is the whole reason they exist.
    var visibleCount: Int? {
        didSet {
            guard visibleCount != oldValue else { return }
            buildCarets()
            applyWindow()
        }
    }

    /// Which slot is at the top of the window.
    private(set) var scrollIndex = 0

    let root = Entity()

    /// The strip the sources ride, and the only thing that MOVES when
    /// the rack is scrolled.
    ///
    /// Separate from `root` because the carets must not slide with it —
    /// they mark the WINDOW, which stays where it was authored, and a
    /// caret that drifts up the room as you browse is worse than none.
    /// (The first version slid `root` itself and took the carets along.)
    private let rack = Entity()
    private var specs: [Spec] = []
    private var sources: [Entity] = []
    /// The preview model inside each source, scaled by the breath — kept
    /// separately from the source root so the LABEL does not breathe
    /// with it. A name that pulsed would read as an animation; a name
    /// should just be readable.
    private var previews: [Entity] = []
    private var dip: [Float] = []
    /// The refusal fade when a pull comes up empty — the lab is at its
    /// object budget and nothing came out, so the preview dims briefly
    /// instead of popping. (This comment said "dark pulse" long after
    /// the pulse became a fade — the doc-rot this project keeps
    /// catching.)
    private var refusal: [Float] = []
    private var time: Double = 0

    init(_ specs: [Spec]) {
        root.addChild(rack)
        self.specs = specs
        dip = Array(repeating: 0, count: specs.count)
        refusal = Array(repeating: 0, count: specs.count)
        for spec in specs {
            let (source, preview) = Self.makeSource(spec)
            source.position = spec.position
            rack.addChild(source)
            sources.append(source)
            previews.append(preview)
            // A well is PULLED FROM, and a pull needs a hand position
            // the activation does not have. It spawns just in front of
            // and above the well instead — the same place a short pull
            // would have put it — and then the object is an ordinary
            // one that every other route can reach. Refusal still
            // refuses: `pull` is the only path, so a lab at its budget
            // dims here exactly as it does for a hand.
            SpatialActions.attach(
                to: source, label: spec.label,
                activate: { [weak self, weak source] in
                    guard let self, let source else { return }
                    let origin = source.position(relativeTo: nil)
                        + SIMD3<Float>(0, 0.06, 0.10)
                    _ = self.pull(source, at: SIMD3<Double>(origin))
                })
        }
    }

    /// Per frame: the idle breath, the recoil after a spawn, and the
    /// recession.
    ///
    /// PER SOURCE, NOT PER ROOT, which is the one place this differs
    /// from every other primitive: a bank is one object at one anchor,
    /// but wells are spread along a bench, and fading the whole row on
    /// the nearest one would light up wells half a metre from your hand.
    func update(dt: Double, nearestHand: SIMD3<Float>? = nil) {
        time += dt
        applyWindow()
        for source in sources {
            Recession.apply(to: source,
                            anchor: source.position(relativeTo: nil),
                            nearestHand: nearestHand)
        }
        for (index, preview) in previews.enumerated() {
            dip[index] = max(0, dip[index] - Float(dt) * 2.6)
            refusal[index] = max(0, refusal[index] - Float(dt) * 2.2)
            // A PERPETUAL BREATH, IN EVERY LAB — which makes this the
            // single worst Reduce Motion omission in the app: the other
            // seven primitives animate when something happens, and this
            // one never stops. Someone who has asked the system for less
            // motion gets a still object.
            let breath = Motion.isReduced
                ? Float(1)
                : 1 + 0.035 * Float(sin(time * 1.4 + Double(index) * 1.1))
            // The dip is a recoil: it shrinks on giving, then swells back.
            preview.scale = SIMD3(repeating: breath * (1 - 0.42 * dip[index]))
            // Refusal used to darken a glass halo. With the glass gone
            // the object itself fades instead, which says the same thing
            // about the same object: nothing came out of here.
            let opacity = 1 - 0.6 * refusal[index]
            if opacity < 0.999 {
                preview.components.set(OpacityComponent(opacity: opacity))
            } else {
                preview.components.remove(OpacityComponent.self)
            }
        }
    }

    // MARK: The window

    /// Shows only `visibleCount` slots, starting at `scrollIndex`, and
    /// slides them up so the window always sits where the first slot
    /// was authored.
    ///
    /// The slots keep their AUTHORED positions and the whole rack moves,
    /// rather than each slot being re-placed. That way the layout stays
    /// the one thing that decides where parts stand — a scroll is the
    /// rack sliding past a hole, which is what it looks like.
    private func applyWindow() {
        guard let visibleCount, !specs.isEmpty else {
            for source in sources { source.isEnabled = true }
            rack.position.y = 0
            return
        }
        let last = max(specs.count - visibleCount, 0)
        scrollIndex = min(max(scrollIndex, 0), last)
        // Authored positions run DOWN the column, so scrolling forward
        // lifts the rack by the distance from the first slot to the one
        // that should now head the window.
        let head = specs[0].position.y
        rack.position.y = head - specs[min(scrollIndex, specs.count - 1)].position.y
        for (index, source) in sources.enumerated() {
            source.isEnabled = index >= scrollIndex
                && index < scrollIndex + visibleCount
        }
    }

    /// Scrolls by whole slots — a rack of discrete objects left between
    /// two positions is a rack with something half out of view.
    func scroll(by slots: Int) {
        guard let visibleCount, specs.count > visibleCount else { return }
        scrollIndex = min(max(scrollIndex + slots, 0), specs.count - visibleCount)
        applyWindow()
        refreshCarets()
    }

    /// True when there is more above or below the window.
    ///
    /// READ BY THE CARETS BELOW, not left for a caller to remember. The
    /// first version of this said "the caller draws whatever tells the
    /// user so" and no caller did — six of twelve parts on screen and
    /// nothing saying the other six existed, which is the same
    /// authored-but-dark defect this project keeps convicting, committed
    /// by the comment that promised otherwise.
    var canScrollUp: Bool { scrollIndex > 0 }
    var canScrollDown: Bool {
        guard let visibleCount else { return false }
        return scrollIndex + visibleCount < specs.count
    }

    // MARK: The carets

    /// The two marks that say the rack goes on.
    ///
    /// A DRAG IS INVISIBLE. A rack of six with no affordance is a rack of
    /// six as far as anyone can tell, and the parts they cannot see are
    /// the ones they will not build with. These say "more this way" by
    /// existing, and pressing one moves a whole page — so the feature is
    /// reachable without knowing the gesture, and reachable by VoiceOver,
    /// which cannot drag at all.
    ///
    /// A PAGE, not a slot: at six visible of twelve, one press reaches
    /// the end. Stepping one at a time would take six presses to learn
    /// what is down there.
    private let upCaret = ModelEntity()
    private let downCaret = ModelEntity()

    static let caretName = "well-caret"

    private func buildCarets() {
        // Idempotent: the window can be set more than once, and a second
        // pair of carets would sit exactly on the first.
        upCaret.removeFromParent()
        downCaret.removeFromParent()
        guard let visibleCount, specs.count > visibleCount else { return }
        let pitch = slotPitch
        let top = specs[0].position
        for (caret, direction) in [(upCaret, Float(1)), (downCaret, Float(-1))] {
            caret.name = "\(Self.caretName)-\(direction > 0 ? "up" : "down")"
            caret.model = ModelComponent(
                mesh: .generateCone(height: 0.016, radius: 0.013),
                materials: [Materials.machined(UIColor(white: 0.62, alpha: 1))])
            // Pointing the way it takes you.
            caret.orientation = simd_quatf(angle: direction > 0 ? 0 : .pi,
                                           axis: [0, 0, 1])
            let span = Float(visibleCount - 1) * pitch
            caret.position = SIMD3(top.x,
                                   direction > 0 ? top.y + 0.055
                                                 : top.y - span - 0.055,
                                   top.z)
            caret.components.set(InputTargetComponent())
            caret.components.set(CollisionComponent(
                shapes: [.generateSphere(radius: 0.020)]))
            caret.components.set(HoverEffectComponent())
            root.addChild(caret)
        }
        refreshCarets()
    }

    private func refreshCarets() {
        upCaret.isEnabled = canScrollUp
        downCaret.isEnabled = canScrollDown
        // Announced with what pressing them DOES, and re-announced as the
        // window moves — a caret that still says "6 more below" at the
        // bottom of the rack is worse than a silent one.
        SpatialActions.attach(
            to: upCaret, label: "Earlier parts",
            value: "\(scrollIndex) above",
            activate: { [weak self] in self?.page(-1) })
        SpatialActions.attach(
            to: downCaret, label: "More parts",
            value: "\(max(specs.count - scrollIndex - (visibleCount ?? 0), 0)) below",
            activate: { [weak self] in self?.page(1) })
    }

    /// One window's worth, the direction the caret points.
    func page(_ direction: Int) {
        scroll(by: direction * (visibleCount ?? 1))
    }

    /// True if the tap hit a caret — the caller's other tap handling
    /// should not also run.
    @discardableResult
    func handleTap(_ entity: Entity) -> Bool {
        var current: Entity? = entity
        while let candidate = current {
            if candidate === upCaret { page(-1); return true }
            if candidate === downCaret { page(1); return true }
            if candidate === root { return false }
            current = candidate.parent
        }
        return false
    }

    // MARK: Dragging the rack

    private var dragStart: SIMD3<Float>?
    private var scrollAtGrab = 0
    private var gesture: ScrollGesture = .undecided
    private var draggedIndex: Int?

    /// How far a hand travels along the rack per slot scrolled. Matched
    /// to the authored pitch so the rack tracks the fingers.
    private var slotPitch: Float {
        guard specs.count > 1 else { return 0.105 }
        return abs(specs[1].position.y - specs[0].position.y)
    }

    /// Begins a drag on the rack. Returns false if the pinch missed it,
    /// or if there is nothing to scroll — in which case the caller's
    /// ordinary `pull` should handle it as it always did.
    func beginDrag(_ entity: Entity, hand: SIMD3<Float>) -> Bool {
        guard visibleCount != nil, specs.count > (visibleCount ?? 0),
              let name = Self.sourceName(of: entity, under: rack),
              let index = sources.firstIndex(where: { $0.name == name })
        else { return false }
        dragStart = hand
        scrollAtGrab = scrollIndex
        gesture = .undecided
        draggedIndex = index
        return true
    }

    /// Continues it. Returns the slot to pull, once, when the hand has
    /// committed to taking something rather than browsing.
    func updateDrag(hand: SIMD3<Float>) -> Int? {
        guard let dragStart else { return nil }
        let travel = hand - dragStart
        switch gesture {
        case .pull:
            return nil                              // already spent
        case .scroll:
            applyScroll(travel)
            return nil
        case .undecided:
            gesture = ScrollGesture.classify(travel: travel, axis: .vertical)
            if gesture == .scroll { applyScroll(travel) }
            return gesture == .pull ? draggedIndex : nil
        }
    }

    private func applyScroll(_ travel: SIMD3<Float>) {
        guard let visibleCount, slotPitch > 1e-6 else { return }
        // Drag DOWN to bring later slots up, the way a physical rack
        // behaves under a finger.
        let slots = Int((-travel.y / slotPitch).rounded())
        scrollIndex = min(max(scrollAtGrab + slots, 0),
                          max(specs.count - visibleCount, 0))
        applyWindow()
    }

    func endDrag() {
        dragStart = nil
        draggedIndex = nil
        gesture = .undecided
    }

    var isDragging: Bool { dragStart != nil }

    /// How many slots there are, window or no window.
    var slotCount: Int { specs.count }

    /// The slot at `index`, for a caller resolving a committed pull.
    func spec(at index: Int) -> Spec? {
        specs.indices.contains(index) ? specs[index] : nil
    }

    /// The entity standing in slot `index` — what a pull should be
    /// measured from.
    func source(at index: Int) -> Entity? {
        sources.indices.contains(index) ? sources[index] : nil
    }

    /// If `entity` belongs to a source, makes its object at `hand` and
    /// returns the new id — the caller then drags it like anything else.
    ///
    /// A slot with a `handOver` gives up the ONE object it parks and
    /// returns nil, which is a success rather than a refusal: the caller
    /// has nothing new to drag because the thing already existed and has
    /// its own drag.
    @discardableResult
    func pull(_ entity: Entity, at hand: SIMD3<Double>) -> UUID? {
        guard let name = Self.sourceName(of: entity, under: rack),
              let index = sources.firstIndex(where: { $0.name == name })
        else { return nil }
        if let handOver = specs[index].handOver {
            handOver(hand)
            dip[index] = 1
            SoundPalette.play(.pop, on: sources[index], volume: 0.5)
            return nil
        }
        // The recoil and the pop are the well SAYING it just gave
        // something up, so they only happen when it did. A lab at its
        // budget used to chirp and flinch and hand back nothing — the
        // gesture read as working and the object simply never arrived,
        // which is the worst of both answers.
        guard let id = specs[index].spawn(hand) else {
            refusal[index] = 1
            return nil
        }
        dip[index] = 1
        SoundPalette.play(.pop, on: sources[index], volume: 0.5)
        return id
    }

    private static func sourceName(of entity: Entity, under rack: Entity) -> String? {
        var current: Entity? = entity
        while let candidate = current {
            if candidate.parent === rack { return candidate.name }
            if candidate === rack { return nil }
            current = candidate.parent
        }
        return nil
    }

    private static func applyGroundingShadow(_ entity: Entity) {
        if entity is ModelEntity {
            entity.components.set(GroundingShadowComponent(castsShadow: true))
        }
        for child in entity.children { applyGroundingShadow(child) }
    }

    private static func makeSource(_ spec: Spec) -> (source: Entity, preview: Entity) {
        let source = Entity()
        source.name = "well-\(spec.name)"

        // The object, at the size it will be when you are holding it.
        // A pivot sits between it and the source so the breath can scale
        // the model without touching the label beneath.
        let preview = Entity()
        let model = spec.preview()
        // The preview is caller-supplied and arbitrarily nested, so the
        // contact shadow is applied to every model in it — the component
        // renders per mesh, not per subtree.
        applyGroundingShadow(model)
        preview.addChild(model)
        source.addChild(preview)

        // The name, below the object and NOT breathing with it.
        let plate = HubScene.namePlate(spec.label, accent: spec.tint, size: PlateStyle.labelSize)
        plate.components.set(BillboardComponent())
        source.addChild(plate)

        // The collider is sized to what is actually there, per the rule
        // that an input-targetable collider must never be larger than
        // the thing it represents (DECISIONS.md, 2026-07-29 — an
        // oversized one shields everything behind it from every pinch,
        // and these stand among the objects they make).
        //
        // Measured from the preview rather than assumed, because callers
        // build their own miniatures and a magnet is not a sphere.
        let bounds = preview.visualBounds(relativeTo: source)
        // A small generous margin so a near miss still counts — the well
        // is a target you reach for, not one you have to hit.
        let padded = bounds.extents + SIMD3<Float>(repeating: 0.028)
        // THE LABEL IS PART OF THE TARGET. "Add magnet" hangs 34 mm below
        // the miniature — well outside the padded box — so the words
        // telling you what the well makes were the one part of it you
        // could not pull from.
        //
        // Not widened LATERALLY beyond the padded box: wells stand in a
        // column and a label-width target would reach across the bench
        // toward whatever the well is drawn in front of. The box covers
        // the label's own height and depth at the well's width, which is
        // where a hand aiming at the word actually arrives.
        let plateDrop = bounds.min.y - 0.034
        source.components.set(InputTargetComponent())
        source.components.set(CollisionComponent(shapes: [
            .generateBox(size: padded).offsetBy(translation: bounds.center),
            .generateBox(size: [padded.x, 0.030, 0.020])
                .offsetBy(translation: [bounds.center.x, plateDrop, 0]),
        ]))
        source.components.set(HoverEffectComponent())

        plate.position = [0, bounds.min.y - 0.034, 0]

        // The label is set here and the ACTION in `init`, because a
        // static builder has no `self` to call `pull` on. `attach`
        // overwrites this label with the same words.
        var accessibility = AccessibilityComponent()
        accessibility.isAccessibilityElement = true
        accessibility.label = LocalizedStringResource(
            stringLiteral: "\(spec.label). Pinch and pull to make one.")
        source.components.set(accessibility)
        return (source, preview)
    }
}
