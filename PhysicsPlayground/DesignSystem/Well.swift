//
//  Well.swift
//  Physics Playground — Design System
//
//  A source you reach into and pull an object out of. The preview is the
//  object itself at final size, named underneath; the new object is born
//  at the fingertips and follows the hand that pulled it. With a window
//  set, the column shows that many slots and scrolls by its crown — a
//  knurled wheel beside the column that the parts ride one to one; a
//  drag on a slot is always a pull, never a scroll.
//

import RealityKit
import SwiftUI
import RenderKit
import simd

@MainActor
final class Well {
    /// One source: what it makes and what stands there beforehand.
    struct Spec {
        let name: String
        let tint: UIColor
        /// The words under the object — "Add magnet", "Add world".
        let label: String
        /// Builds the miniature. Called once, on the main actor.
        let preview: @MainActor () -> Entity
        let position: SIMD3<Float>
        /// Makes the object at a world point and returns its id, or nil to
        /// refuse (the lab is at its budget).
        let spawn: (SIMD3<Double>) -> UUID?
        /// For a one-of-a-kind object parked here rather than minted here:
        /// hands over the existing object instead of calling `spawn`.
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

    /// The scroll furniture of a windowed well: a hairline spine beside
    /// the column with a knurled crown standing in a gap at its middle,
    /// and the title above. Nothing stands behind the parts. Pure
    /// geometry, so a placement test can measure the crown without
    /// building it.
    enum Rack {
        /// The spine's offset from the slot line, across the shelf; the
        /// crown stands on it.
        static let trackOffset: Float = 0.078
        /// The spine runs this far past the window's first and last slot.
        static let trackOverhang: Float = 0.04
        static let spineWidth: Float = 0.003
        static let spineDepth: Float = 0.002
        /// The title's height above the first slot.
        static let headerLift: Float = 0.064
        /// The crown, as `Tools/shelfcrown.py` mills it: a 48 mm wheel,
        /// 14 mm wide, its axis across the shelf.
        static let crownRadius: Float = 0.024
        static let crownWidth: Float = 0.014
        /// How far the crown's centre stands proud of the spine, toward
        /// the viewer.
        static let crownLift: Float = 0.006
        /// The gap in the spine the crown sits in.
        static let crownGap: Float = 2 * crownRadius + 0.008
        /// The crown's pinch target: the axle plus 8 mm across, the rim
        /// plus 30 mm over — the collider rule's allowance, no more. The
        /// milled rim's crests are bevelled a hair under `crownRadius`.
        static let crownTarget = SIMD3<Float>(0.044, 0.077, 0.077)
        /// How far below its place the column arrives from, in pitches,
        /// and how quickly it closes on it.
        static let arrivalDrop: Float = 0.45
        static let arrivalRate: Float = 3.5
        /// A slot fades out over this fraction of a pitch past the window's ends.
        static let fadeSpan: Float = 0.6

        /// The spine: where it stands and how long it runs.
        struct Track: Equatable {
            var center: SIMD3<Float>
            /// Axis-aligned half extents of the yawed spine.
            var halfExtents: SIMD3<Float>
            var yaw: Float
            var length: Float
        }

        /// An axis-aligned box in world coordinates.
        struct Box: Equatable {
            var center: SIMD3<Float>
            var halfExtents: SIMD3<Float>
        }

        /// Yaw about +y that turns the shelf's face toward `facing`.
        static func yaw(from head: SIMD3<Float>, toward facing: SIMD3<Float>?) -> Float {
            guard let facing else { return 0 }
            let d = facing - head
            guard d.x * d.x + d.z * d.z > 1e-8 else { return 0 }
            return atan2(d.x, d.z)
        }

        /// Where the spine stands for a window of `visible` slots headed at `head`.
        static func track(head: SIMD3<Float>, pitch: Float, visible: Int,
                          facing: SIMD3<Float>?) -> Track {
            let span = Float(max(visible - 1, 0)) * pitch
            let length = span + 2 * trackOverhang
            let yaw = yaw(from: head, toward: facing)
            // The shelf's own +x after the yaw.
            let across = SIMD3<Float>(cos(yaw), 0, -sin(yaw))
            let center = SIMD3(head.x, head.y - span / 2, head.z) + across * trackOffset
            let c = abs(cos(yaw)), sn = abs(sin(yaw))
            let half = SIMD3(spineWidth / 2 * c + spineDepth / 2 * sn,
                             length / 2,
                             spineWidth / 2 * sn + spineDepth / 2 * c)
            return Track(center: center, halfExtents: half, yaw: yaw, length: length)
        }

        /// Where the crown's pinch target stands: on the spine at the
        /// window's middle, lifted toward the viewer.
        static func crown(head: SIMD3<Float>, pitch: Float, visible: Int,
                          facing: SIMD3<Float>?) -> Box {
            let span = Float(max(visible - 1, 0)) * pitch
            let yaw = yaw(from: head, toward: facing)
            let across = SIMD3<Float>(cos(yaw), 0, -sin(yaw))
            // The shelf's own +z after the yaw: toward the viewer.
            let outward = SIMD3<Float>(sin(yaw), 0, cos(yaw))
            let center = SIMD3(head.x, head.y - span / 2, head.z)
                + across * trackOffset + outward * crownLift
            let c = abs(cos(yaw)), sn = abs(sin(yaw))
            let target = crownTarget / 2
            let half = SIMD3(target.x * c + target.z * sn,
                             target.y,
                             target.x * sn + target.z * c)
            return Box(center: center, halfExtents: half)
        }
    }

    /// How many slots are on screen at once; nil shows them all with no
    /// shelf. Setting it builds the spine, the crown and the scroll.
    var visibleCount: Int? {
        didSet {
            guard visibleCount != oldValue else { return }
            scroll = RackScroll(pitch: slotPitch, count: specs.count,
                                visible: visibleCount ?? specs.count)
            rebuildShelf()
            applyWindow()
        }
    }

    /// The point the shelf faces (a standing viewer). Sources turn to face
    /// it, and the crown stands edge-on to it.
    var facing: SIMD3<Float>? {
        didSet {
            applyFacing()
            rebuildShelf()
        }
    }

    /// The word above the column, and what VoiceOver calls the shelf.
    var windowTitle: String? {
        didSet { rebuildShelf() }
    }

    let root = Entity()

    /// The strip the sources ride — the only thing that moves on a scroll.
    /// Always `root`'s first child.
    private let rack = Entity()
    private var specs: [Spec] = []
    private var sources: [Entity] = []
    /// The preview inside each source, scaled by the breath; the label
    /// hangs off the source so it does not breathe with it.
    private var previews: [Entity] = []
    private var dip: [Float] = []
    /// The refusal fade after a pull came up empty.
    private var refusal: [Float] = []
    private var time: Double = 0

    private var scroll = RackScroll(pitch: 0.105, count: 0, visible: 0)
    private var lastIndex = 0
    private var shelf: Entity?
    /// The crown's pinch target, and the pivot inside it that turns.
    private var crownMount: Entity?
    private var spindle: Entity?
    /// Whether the settle in progress came from a hand, so it lands with
    /// a click; an arrival lands silently.
    private var handMoved = false

    init(_ specs: [Spec]) {
        root.addChild(rack)
        self.specs = specs
        dip = Array(repeating: 0, count: specs.count)
        refusal = Array(repeating: 0, count: specs.count)
        scroll = RackScroll(pitch: slotPitch, count: specs.count, visible: specs.count)
        for spec in specs {
            let (source, preview) = Self.makeSource(spec)
            source.position = spec.position
            rack.addChild(source)
            sources.append(source)
            previews.append(preview)
            // VoiceOver has no hand position, so an activation spawns just
            // in front of and above the source, where a short pull would.
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

    /// Per frame: the scroll, the window fade, recession per source (wells
    /// are spread along a bench, so the row never fades as one), the idle
    /// breath and the recoil after a spawn.
    func update(dt: Double, nearestHand: SIMD3<Float>? = nil) {
        time += dt
        let reduced = Motion.isReduced
        let wasMoving = scroll.isMoving
        scroll.step(dt: dt, reduceMotion: reduced)
        if scroll.index != lastIndex {
            // A detent per slot as the column passes it.
            if scroll.isMoving, let crownMount {
                SoundPalette.play(.grabTick, on: crownMount, volume: 0.12)
            }
            lastIndex = scroll.index
            refreshVoice()
        }
        // And the landing, when the settle a hand started closes.
        if wasMoving, !scroll.isMoving {
            if handMoved, let crownMount {
                SoundPalette.play(.releaseTick, on: crownMount, volume: 0.15)
            }
            handMoved = false
        }
        applyWindow()
        for (index, source) in sources.enumerated() {
            let fade = windowOpacity(at: index)
            source.isEnabled = fade > 0.02
            let recede = reduced
                ? 1
                : Recession.opacity(anchor: source.position(relativeTo: nil),
                                    nearestHand: nearestHand)
            Self.setOpacity(recede * fade, on: source)
        }
        if let shelf {
            Recession.apply(to: shelf, anchor: shelf.position(relativeTo: nil),
                            nearestHand: nearestHand)
        }
        for (index, preview) in previews.enumerated() {
            dip[index] = max(0, dip[index] - Float(dt) * 2.6)
            refusal[index] = max(0, refusal[index] - Float(dt) * 2.2)
            let breath = reduced
                ? Float(1)
                : 1 + 0.035 * Float(sin(time * 1.4 + Double(index) * 1.1))
            preview.scale = SIMD3(repeating: breath * (1 - 0.42 * dip[index]))
            Self.setOpacity(1 - 0.6 * refusal[index], on: preview)
        }
    }

    private static func setOpacity(_ opacity: Float, on entity: Entity) {
        if opacity > 0.995 {
            entity.components.remove(OpacityComponent.self)
        } else {
            entity.components.set(OpacityComponent(opacity: opacity))
        }
    }

    // MARK: The window

    /// Slots keep their authored positions and the strip slides, so the
    /// window always sits where the first slot was authored.
    private func applyWindow() {
        guard visibleCount != nil else {
            rack.position.y = 0
            return
        }
        rack.position.y = scroll.offset
        turnCrown()
    }

    /// 1 inside the window, fading to 0 over `Rack.fadeSpan` of a pitch
    /// past either end; 1 everywhere for a well with no window.
    func windowOpacity(at index: Int) -> Float {
        guard let visibleCount, specs.indices.contains(index) else { return 1 }
        let head = specs[0].position.y
        let below = head - specs[index].position.y - scroll.offset
        let span = Float(max(visibleCount - 1, 0)) * slotPitch
        let outside = max(-below, below - span, 0)
        return 1 - min(outside / (Rack.fadeSpan * slotPitch), 1)
    }

    /// Scrolls by whole slots, at once — the debug arguments and
    /// VoiceOver paging.
    func scroll(by slots: Int) {
        guard scroll.canScroll else { return }
        scroll.jump(toIndex: scroll.index + slots)
        lastIndex = scroll.index
        handMoved = false
        applyWindow()
        refreshVoice()
    }

    /// One window's worth in `direction`.
    func page(_ direction: Int) {
        scroll(by: direction * (visibleCount ?? 1))
    }

    /// The column arrives coasting up into its place, the crown rolling
    /// with it: the apparatus saying that it moves and what moves it.
    /// From wherever the window already stands, so a debug scroll holds.
    /// Nothing under Reduce Motion.
    func arrive() {
        guard visibleCount != nil, scroll.canScroll, !Motion.isReduced else { return }
        scroll.coast(from: scroll.offset - Rack.arrivalDrop * slotPitch,
                     rate: Rack.arrivalRate)
        handMoved = false
        applyWindow()
    }

    var canScrollUp: Bool { scroll.index > 0 }
    var canScrollDown: Bool {
        guard let visibleCount else { return false }
        return scroll.index + visibleCount < specs.count
    }
    /// Which slot heads the window.
    var scrollIndex: Int { scroll.index }
    /// How far the strip is lifted, metres.
    var scrollOffset: Float { scroll.offset }
    var isSettled: Bool { !scroll.isMoving }

    /// True if the tap landed on the shelf's furniture, which swallows it.
    @discardableResult
    func handleTap(_ entity: Entity) -> Bool {
        guard let shelf else { return false }
        return entity === shelf || entity.isDescendant(of: shelf)
    }

    // MARK: The shelf

    /// The title, spine and crown of a windowed well, for a test or a
    /// placement check.
    var shelfEntity: Entity? { shelf }
    /// The crown: the one handle that scrolls, present only when there is
    /// more than the window shows.
    var crown: Entity? { crownMount }
    /// The pivot inside the crown that turns with the column.
    var crownSpindle: Entity? { spindle }
    /// How far the crown has turned, radians about the shelf's +x: arc
    /// over radius, its front face rolling with the strip.
    var crownAngle: Float { -scroll.offset / Rack.crownRadius }

    private var track: Rack.Track? {
        guard let visibleCount, let head = specs.first?.position else { return nil }
        return Rack.track(head: head, pitch: slotPitch, visible: visibleCount,
                          facing: facing)
    }

    private func applyFacing() {
        let yaw = Rack.yaw(from: specs.first?.position ?? .zero, toward: facing)
        let turn = simd_quatf(angle: yaw, axis: [0, 1, 0])
        for source in sources { source.orientation = turn }
    }

    private func rebuildShelf() {
        shelf?.removeFromParent()
        shelf = nil
        crownMount = nil
        spindle = nil
        guard visibleCount != nil, let head = specs.first?.position, let track else { return }

        // The shelf's own frame: on the first slot, turned to face the viewer.
        let shelf = Entity()
        shelf.name = "well-shelf"
        shelf.position = head
        shelf.orientation = simd_quatf(angle: track.yaw, axis: [0, 1, 0])

        if let title = windowTitle {
            let header = HubScene.namePlate(title, accent: UIColor(white: 0.95, alpha: 1),
                                            size: PlateStyle.labelSize)
            header.position = [0, Rack.headerLift, 0]
            shelf.addChild(header)
        }

        if scroll.canScroll {
            let span = track.length - 2 * Rack.trackOverhang
            let holder = Entity()
            holder.position = [Rack.trackOffset, -span / 2, 0]

            // The spine, in two lengths with the crown's gap between them.
            let segment = (track.length - Rack.crownGap) / 2
            for sign: Float in [1, -1] {
                let rail = ModelEntity(
                    mesh: Primitives.box(size: [Rack.spineWidth, segment, Rack.spineDepth],
                                         cornerRadius: 0.001),
                    materials: [Materials.glassEdge(opacity: 0.30)])
                rail.position.y = sign * (Rack.crownGap + segment) / 2
                holder.addChild(rail)
            }

            // The crown: `ShelfCrown.usdz` from `Tools/shelfcrown.py`, with a
            // machined wheel of the same size standing in if it fails to load.
            let mount = Entity()
            mount.name = "well-crown"
            mount.position.z = Rack.crownLift
            mount.components.set(InputTargetComponent())
            mount.components.set(CollisionComponent(shapes: [
                Primitives.collisionBox(size: Rack.crownTarget),
            ]))
            mount.components.set(HoverEffectComponent())
            mount.components.set(GroundingShadowComponent(castsShadow: true))
            let spindle = Entity()
            spindle.name = "well-crown-spindle"
            if let milled = PropCache.instance(named: "ShelfCrown") {
                spindle.addChild(milled)
            } else {
                let fallback = ModelEntity(
                    mesh: Primitives.cylinder(height: Rack.crownWidth,
                                              radius: Rack.crownRadius),
                    materials: [Materials.machined(UIColor(white: 0.55, alpha: 1))])
                // A cylinder stands on y; the crown lies along x.
                fallback.orientation = simd_quatf(angle: .pi / 2, axis: [0, 0, 1])
                spindle.addChild(fallback)
            }
            mount.addChild(spindle)
            holder.addChild(mount)
            shelf.addChild(holder)
            self.crownMount = mount
            self.spindle = spindle
        }

        root.addChild(shelf)
        self.shelf = shelf
        turnCrown()
        refreshVoice()
    }

    /// The crown turns for the column's travel — arc over radius — so a
    /// crown at rest is a readout of where the shelf is.
    private func turnCrown() {
        spindle?.orientation = simd_quatf(angle: crownAngle, axis: [1, 0, 0])
    }

    /// VoiceOver reads the crown as the shelf and pages it by adjusting.
    private func refreshVoice() {
        guard let crownMount, let visibleCount else { return }
        let first = scroll.index + 1
        let last = min(scroll.index + visibleCount, specs.count)
        let value = "\(first) to \(last) of \(specs.count)"
        SpatialActions.attach(
            to: crownMount, label: windowTitle ?? "Shelf", value: value,
            adjust: { [weak self] delta in self?.page(delta > 0 ? 1 : -1) })
    }

    // MARK: Scrolling by the crown

    private var dragStart: SIMD3<Float>?

    /// The authored spacing between the first two slots.
    private var slotPitch: Float {
        guard specs.count > 1 else { return 0.105 }
        return abs(specs[1].position.y - specs[0].position.y)
    }

    /// Begins a drag on the crown, the only thing on a well that scrolls.
    /// False for anything else — a drag on a slot is the caller's pull.
    /// The first press wins: a scene's one drag gesture reports the same
    /// entity every frame, and re-pressing would move the anchor under
    /// the hand so the crown never turned.
    func beginDrag(_ entity: Entity, hand: SIMD3<Float>) -> Bool {
        guard scroll.canScroll, let crownMount,
              entity === crownMount || entity.isDescendant(of: crownMount) else { return false }
        if dragStart == nil {
            dragStart = hand
            scroll.beginDrag()
        }
        return true
    }

    /// The column rides the hand one to one: roll the crown's rim up and
    /// the later slots come up. Read along the column, which is world y
    /// whatever the shelf's yaw.
    func updateDrag(hand: SIMD3<Float>) {
        guard let dragStart else { return }
        scroll.drag(travel: (hand - dragStart).y)
    }

    func endDrag() {
        guard dragStart != nil else { return }
        dragStart = nil
        handMoved = true
        scroll.endDrag(reduceMotion: Motion.isReduced)
    }

    var isDragging: Bool { dragStart != nil }

    /// The slot `entity` belongs to, for a caller about to pull from it.
    func sourceIndex(of entity: Entity) -> Int? {
        guard let name = Self.sourceName(of: entity, under: rack) else { return nil }
        return sources.firstIndex { $0.name == name }
    }

    var slotCount: Int { specs.count }

    func spec(at index: Int) -> Spec? {
        specs.indices.contains(index) ? specs[index] : nil
    }

    /// The entity standing in slot `index`.
    func source(at index: Int) -> Entity? {
        sources.indices.contains(index) ? sources[index] : nil
    }

    /// If `entity` belongs to a source, makes its object at `hand` and
    /// returns the new id. A `handOver` slot gives up its one object and
    /// returns nil, which is a success: there is nothing new to drag.
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
        // The recoil and the pop only happen when something came out.
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

        // A pivot between the model and the source, so the breath scales
        // the model without touching the label.
        let preview = Entity()
        let model = spec.preview()
        applyGroundingShadow(model)
        preview.addChild(model)
        source.addChild(preview)

        let plate = HubScene.namePlate(spec.label, accent: spec.tint, size: PlateStyle.labelSize)
        plate.components.set(BillboardComponent())
        source.addChild(plate)

        // Collider measured from the preview, padded a little for a near
        // miss, plus a second box over the label so the word is part of
        // the target. Never wider than the preview: wells stand in a
        // column in front of the apparatus they make for.
        let bounds = preview.visualBounds(relativeTo: source)
        let padded = bounds.extents + SIMD3<Float>(repeating: 0.028)
        let plateDrop = bounds.min.y - 0.034
        source.components.set(InputTargetComponent())
        source.components.set(CollisionComponent(shapes: [
            Primitives.collisionBox(size: padded, offset: bounds.center),
            Primitives.collisionBox(size: [padded.x, 0.030, 0.020], offset: [bounds.center.x, plateDrop, 0]),
        ]))
        source.components.set(HoverEffectComponent())

        plate.position = [0, bounds.min.y - 0.034, 0]

        var accessibility = AccessibilityComponent()
        accessibility.isAccessibilityElement = true
        accessibility.label = LocalizedStringResource(
            stringLiteral: "\(spec.label). Pinch and pull to make one.")
        source.components.set(accessibility)
        return (source, preview)
    }
}
