//
//  PartsDrawer.swift
//  Physics Playground — Design System
//
//  THE COMPONENTS LIVE IN A DRAWER NOW.
//
//  Circuit Workshop stood eleven kinds of part in two columns of wells,
//  one on each flank, permanently — whether or not anybody was building
//  anything. Owner's call 2026-08-08: put them behind one object on the
//  right, the way the palette bead holds the labs and the reel holds the
//  Time Capsule. Closed until asked.
//
//  A DRAWER SPECIFICALLY, because of the scroll. There are more part
//  kinds than fit across one opening, and there will be more still — so
//  whatever holds them has to be longer than what you can see of it. A
//  drawer is the shape where that is already obvious: everyone knows a
//  drawer goes back further than its mouth. (`Tools/partsdrawer.py`
//  records the three shapes that lost.)
//
//  ── TWO GESTURES ON ONE OBJECT, AND HOW THEY ARE TOLD APART ──
//
//  Once it is open the strip does two things that both begin with a
//  pinch on a part: SCROLL it sideways to find something, and PULL a
//  part out to build with it. There is no mode switch and no second
//  handle, because the alternative — a scroll bar beside the drawer —
//  puts a control next to a control and is the clutter this replaces.
//
//  They are told apart by which way the hand actually goes.
//  `DrawerGesture` is that rule, and it is pure arithmetic so it can be
//  tested without a headset: travel mostly ACROSS the drawer scrolls,
//  travel mostly OUT of it spawns. The threshold is not 50/50 — a pull
//  has to beat the sideways component by a clear margin, because a hand
//  arcing out of a drawer naturally drifts along it, and a spurious
//  spawn puts an unwanted part on the bench while a spurious scroll
//  merely moves the strip somewhere you can see.
//

import Foundation
import RealityKit
import RenderKit
import SwiftUI
import simd

/// Which of the drawer's two drags this is.
///
/// Split out as a value type with no RealityKit in it, because the
/// interesting part is the decision and the decision is the thing no
/// automated test in this project can otherwise reach — `simctl` has no
/// tap verb and XCUITest has no entity API, so a rule embedded in a
/// gesture closure is a rule verified by hand forever.
enum DrawerGesture: Equatable {
    case undecided
    case scroll
    case pull

    /// How much further out than sideways a hand must travel before it
    /// counts as pulling a part rather than scrolling the strip.
    static let pullBias: Float = 1.6

    /// Below this the hand has not committed to anything yet, and
    /// deciding early is how a 2 mm tremor becomes a spawned component.
    static let deadZone: Float = 0.012

    /// `travel` is the hand's movement in the drawer's own frame: x
    /// across the strip, z out toward the reader.
    static func classify(travel: SIMD3<Float>) -> DrawerGesture {
        let across = abs(travel.x)
        let out = max(travel.z, 0)          // pushing IN is not a pull
        guard max(across, out) > deadZone else { return .undecided }
        return out > across * pullBias ? .pull : .scroll
    }
}

@MainActor
final class PartsDrawer {
    let root = Entity()

    /// Open enough to reach into.
    private(set) var isOpen = false

    /// How far the drawer rides out, metres.
    static let travel: Float = 0.155

    /// Centre-to-centre spacing of the parts along the strip.
    static let pitch: Float = 0.075

    /// The interior width a part has to be inside to be visible. Taken
    /// from the modelled carcass — see `Tools/partsdrawer.py`.
    static let mouthHalfWidth: Float = 0.155

    private let specs: [Well.Spec]
    private var carcass = Entity()
    private var drawer = Entity()
    /// The parts ride this, so scrolling moves one entity rather than
    /// eleven.
    private let strip = Entity()
    private var slots: [Entity] = []

    /// 0 shut, 1 fully out. Eased.
    private var slide: Float = 0
    /// How far the strip is scrolled, metres. 0 shows the first part.
    private var scroll: Float = 0
    private var scrollAtGrab: Float = 0
    private var gesture: DrawerGesture = .undecided
    private var grabHand: SIMD3<Float>?
    private var grabbedSlot: Int?

    /// Where the strip can travel between: the last part must be able to
    /// reach the mouth, and the first must not scroll past it.
    private var scrollRange: ClosedRange<Float> {
        let span = Float(max(specs.count - 1, 0)) * Self.pitch
        let visible = Self.mouthHalfWidth * 2 - Self.pitch
        return -max(span - visible, 0)...0
    }

    init(_ specs: [Well.Spec]) {
        self.specs = specs
        root.isEnabled = true
        buildShell()
        buildParts()
    }

    // MARK: Per frame

    func update(dt: Double, nearestHand: SIMD3<Float>? = nil) {
        slide = Motion.ease(slide, toward: isOpen ? 1 : 0, dt: dt)
        drawer.position.z = slide * Self.travel

        // The parts only exist while there is somewhere for them to be.
        // A closed drawer with eleven components hanging in the space in
        // front of it is worse than the two columns this replaced.
        strip.isEnabled = slide > 0.35
        layoutParts()

        Recession.apply(to: root, anchor: root.position(relativeTo: nil),
                        nearestHand: nearestHand)
    }

    /// Hides whatever has scrolled past the cabinet's sides.
    ///
    /// RealityKit will not clip a child to its parent, so a part outside
    /// the mouth would otherwise hang in mid-air beside the cabinet with
    /// nothing holding it. Culling by position is the honest version of
    /// the clip the geometry implies.
    private func layoutParts() {
        strip.position.x = scroll
        for (index, slot) in slots.enumerated() {
            let x = Float(index) * Self.pitch - Self.mouthHalfWidth + Self.pitch / 2
            slot.position = SIMD3(x, 0, 0)
            let visible = abs(x + scroll) <= Self.mouthHalfWidth - Self.pitch * 0.35
            slot.isEnabled = visible && strip.isEnabled
        }
    }

    // MARK: Opening

    /// True if the tap belongs to this cabinet.
    func handleTap(_ entity: Entity) -> Bool {
        guard owns(entity) else { return false }
        // A tap on a PART while the drawer is open is not a request to
        // shut it — that is a miss on a pull, and closing the drawer
        // under someone reaching into it is the rudest possible answer.
        if isOpen, slotIndex(for: entity) != nil { return true }
        isOpen.toggle()
        SoundPalette.play(isOpen ? .pop : .releaseTick, on: drawer, volume: 0.45)
        return true
    }

    func close() { isOpen = false }

    // MARK: Scrolling and pulling

    /// Begins a drag. `hand` is in the drawer's own frame.
    func beginDrag(_ entity: Entity, hand: SIMD3<Float>) -> Bool {
        guard isOpen, slide > 0.9, owns(entity) else { return false }
        grabHand = hand
        scrollAtGrab = scroll
        gesture = .undecided
        grabbedSlot = slotIndex(for: entity)
        return true
    }

    /// Continues it. Returns the part to spawn, once, if the hand has
    /// committed to a pull.
    ///
    /// The spawn fires on the FIRST frame the gesture resolves, not on
    /// release: a part you are pulling out has to be in your hand while
    /// you are still moving, or the gesture reads as a failed grab and
    /// the object appears afterwards somewhere you are no longer
    /// looking. `Well.pull` has always worked this way.
    func updateDrag(hand: SIMD3<Float>) -> Well.Spec? {
        guard let grabHand else { return nil }
        let travel = hand - grabHand
        switch gesture {
        case .pull:
            return nil                       // already spent
        case .scroll:
            scroll = min(max(scrollAtGrab + travel.x, scrollRange.lowerBound),
                         scrollRange.upperBound)
            return nil
        case .undecided:
            gesture = DrawerGesture.classify(travel: travel)
            if gesture == .scroll {
                scroll = min(max(scrollAtGrab + travel.x, scrollRange.lowerBound),
                             scrollRange.upperBound)
            }
            guard gesture == .pull, let index = grabbedSlot,
                  specs.indices.contains(index) else { return nil }
            return specs[index]
        }
    }

    func endDrag() {
        grabHand = nil
        grabbedSlot = nil
        gesture = .undecided
    }

    var isDragging: Bool { grabHand != nil }

    // MARK: Stowage

    /// Puts a carried instrument inside the drawer.
    ///
    /// The multimeter used to stand beside the bench at all times, which
    /// the owner's word for was "intruding". It lives here now and comes
    /// out the way a part does — except that it is one object rather than
    /// a source, so the caller re-parents it rather than spawning a copy.
    func stow(_ entity: Entity, at slot: Int = 0) {
        entity.position = SIMD3(Float(slot) * Self.pitch - Self.mouthHalfWidth
                                + Self.pitch / 2, 0.028, 0)
        strip.addChild(entity)
    }

    // MARK: Build

    private func buildShell() {
        // `PartsDrawer.usdz`, built by `Tools/partsdrawer.py`. The
        // fallback is a plain box rather than nothing: an asset that
        // fails to load should leave a cabinet you can still open, not
        // an invisible one whose collider eats every pinch on this
        // flank. (`TimeRail` learned the same lesson for the reel.)
        if let loaded = try? Entity.load(named: "PartsDrawer") {
            carcass = loaded.findEntity(named: "Carcass") ?? loaded
            drawer = loaded.findEntity(named: "Drawer") ?? Entity()
            root.addChild(loaded)
        } else {
            let stock = Materials.machined(UIColor(white: 0.13, alpha: 1))
            carcass = ModelEntity(
                mesh: .generateBox(width: 0.34, height: 0.22, depth: 0.20,
                                   cornerRadius: 0.004),
                materials: [stock])
            drawer = ModelEntity(
                mesh: .generateBox(width: 0.32, height: 0.05, depth: 0.18,
                                   cornerRadius: 0.003),
                materials: [stock])
            root.addChild(carcass)
            root.addChild(drawer)
        }
        drawer.name = "parts-drawer"
        strip.position = SIMD3(0, 0.026, 0)
        drawer.addChild(strip)

        // The whole cabinet is the handle when shut. Sized to the
        // modelled carcass and no larger, per the standing rule.
        Grabbable.configureTouchTarget(root, box: SIMD3(0.34, 0.22, 0.20))
        SpatialActions.attach(
            to: root, label: "Parts drawer",
            value: isOpen ? "open" : "closed",
            activate: { [weak self] in
                guard let self else { return }
                _ = self.handleTap(self.root)
            },
            adjust: { [weak self] steps in
                // Hands-free scrolling: one part per step, which is the
                // only sensible quantum here — a continuous nudge on a
                // strip of discrete objects would leave it between two.
                guard let self, self.isOpen else { return }
                let next = self.scroll - Float(steps) * Self.pitch
                self.scroll = min(max(next, self.scrollRange.lowerBound),
                                  self.scrollRange.upperBound)
            })
    }

    private func buildParts() {
        for spec in specs {
            let slot = Entity()
            slot.name = "drawer-\(spec.name)"
            let model = spec.preview()
            slot.addChild(model)

            let plate = HubScene.namePlate(spec.label, accent: spec.tint,
                                           size: 0.0088)
            plate.position = [0, -0.026, 0]
            plate.components.set(BillboardComponent())
            slot.addChild(plate)

            // Measured from the miniature, and the LABEL is inside the
            // target — see `LabelTargetCriterionTests`, which exists
            // because five primitives placed a name outside the thing it
            // names and left the word unpinchable.
            let bounds = model.visualBounds(relativeTo: slot)
            let span = max(bounds.extents.x, 0.03) + 0.014
            slot.components.set(InputTargetComponent())
            slot.components.set(CollisionComponent(shapes: [
                .generateBox(size: [span, bounds.extents.y + 0.014,
                                    bounds.extents.z + 0.014])
                    .offsetBy(translation: bounds.center),
                .generateBox(size: [span, 0.016, 0.014])
                    .offsetBy(translation: [0, -0.026, 0]),
            ]))
            slot.components.set(HoverEffectComponent())
            slot.isEnabled = false
            strip.addChild(slot)
            slots.append(slot)
        }
    }

    // MARK: Hit testing

    private func owns(_ entity: Entity) -> Bool {
        var current: Entity? = entity
        while let candidate = current {
            if candidate === root { return true }
            current = candidate.parent
        }
        return false
    }

    private func slotIndex(for entity: Entity) -> Int? {
        var current: Entity? = entity
        while let candidate = current {
            if let index = slots.firstIndex(where: { $0 === candidate }) {
                return index
            }
            if candidate === root { return nil }
            current = candidate.parent
        }
        return nil
    }
}
