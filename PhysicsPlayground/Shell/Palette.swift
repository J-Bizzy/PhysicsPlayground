//
//  Palette.swift
//  Physics Playground — Shell
//
//  Navigation, as one object.
//
//  This replaces the four-bead rail that used to float at every user's
//  feet: back, grid, pause, dim, note, pods — six affordances, always
//  on, in every lab, whether or not you wanted any of them. One of
//  them (pods) controlled something that no longer exists.
//
//  In its place: a single bead. Pinch it and it unfolds into a ring of
//  the labs themselves — live miniatures, the same running physics the
//  home constellation shows, not icons of them — with six petals:
//  home, pause, capture, dim, settings, reset. Pinch a lab and the room
//  changes. Pinch the bead again and everything folds away.
//
//  SIX PETALS IS NOT SIX MORE OBJECTS. The original decision (2026-07-29)
//  allowed exactly two and every addition since has amended it, which is
//  the right amount of friction — but the bar it sets is about what
//  stands in the room, and a folded ring stands for nothing. The real
//  cost of a petal is the width of the row when it is open, and that is
//  now derived from the count (`petalRowSpan`) rather than hand-tuned,
//  so the next one cannot quietly overlap its neighbours.
//
//  The two newest close capabilities that had NO door at all: `home`
//  (the only route back to the gallery was a chevron in a 2-D window
//  you may have left behind you) and `dim` (`cycleDimming` had zero
//  callers while Gravity Lab darkens your real room by 85%).
//
//  The bead is the app's only permanent piece of interface.
//

import RealityKit
import SwiftUI
import RenderKit
import simd

@MainActor
final class Palette {
    let root = Entity()

    /// The per-frame subscription, held here so it can be cancelled.
    ///
    /// THIS LEAKED UNTIL 2026-08-03, in the one object that is on screen
    /// in every lab. `PaletteView` is remounted per module — it carries
    /// `.id("palette-\(module.id)")` — and the subscription was created
    /// with `_ =`, capturing the palette strongly and never cancelled.
    /// So every module switch built another palette, another
    /// subscription, and another closure animating an orphaned bead
    /// forever, in the background, for the life of the process.
    ///
    /// `HubSpaceView` documents this exact cycle in fourteen lines of
    /// comment and defends against it with `[weak scene]` plus an
    /// explicit cancel — and says "every module already knew it". The
    /// shell chrome next door did not.
    var subscription: EventSubscription?

    private let bead = ModelEntity()
    /// The gyroscope inside the bead: its rotor is ticked every frame,
    /// and it is told how far the ring has unfolded so the gimbals can
    /// lay flat into it.
    private var beadVignette: HubVignettes.Built?
    /// The "Labs" nameplate under the closed bead; fades as the ring
    /// opens and the slots' own labels take over.
    private var beadLabel: Entity?
    var beadEntity: Entity { bead }
    private var slots: [(id: String, holder: Entity, animate: (Double) -> Void)] = []
    private var petals: [ModelEntity] = []

    /// 0 folded, 1 open. Everything else is derived from this.
    private(set) var openness: Float = 0
    /// The bead label opacity last written. The label follows the fold,
    /// but the fold is parked at 0 for most of a session — and this is
    /// the one object present in every lab, so an ungated write here was
    /// a component set per frame, forever, carrying a constant.
    private var appliedBeadLabelOpacity: Float = -1
    private var isOpen = false
    private var time: Double = 0

    /// Set by the host each frame so the ring faces the reader.
    private var viewer: SIMD3<Float>?

    /// The system's Reduce Motion setting, pushed in by the host.
    var stillness = false

    // Ring geometry, in metres. The labs sit on a circle you can sweep
    // with one comfortable arm movement.
    // The radius was sized when seven slots shared the 150 degrees: at
    // 0.26 m the arc gave 11 cm between centres while the discs were
    // 13 cm wide, so the ring overlapped itself into a smear. 0.40 m
    // keeps the same clear air with the 20%-bigger slots the labels
    // asked for — today's six labs ride it with room to spare — and at
    // the old 0.06 m slot size the miniatures read as specks and their
    // thin lines shimmered.
    /// One petal's touch target, across. The DISC is 0.048 m; the target
    /// is deliberately wider, and it is the wider number that decides
    /// whether two petals can be aimed at separately.
    static let petalColliderSpan: Float = 0.068

    /// How wide the petal row has to be to hold `count` of them.
    ///
    /// DERIVED, NOT TYPED, and the comment this replaces is the reason:
    /// it said the span was "widened from 0.17 when the fourth petal
    /// arrived, keeping clear air between neighbouring discs" — a number
    /// hand-tuned for a specific count, which is exactly how Gravity
    /// Lab's clock bank came to lay six discs out on geometry derived
    /// for four. At 0.22 m a FIFTH petal would already have pitched at
    /// 0.055 m against a 0.068 m target, and a sixth at 0.044 m: both
    /// unaimable, both looking fine.
    static func petalRowSpan(count: Int) -> Float {
        Float(max(count - 1, 1)) * petalColliderSpan * 1.1
    }

    private static let ringRadius: Float = 0.40
    private static let slotSize: Float = 0.072
    private static let beadRadius: Float = 0.026

    var onSelect: ((String) -> Void)?
    var onPause: (() -> Void)?
    var onReset: (() -> Void)?
    var onSettings: (() -> Void)?
    var onCapture: (() -> Void)?
    /// Back to the gallery. See the petal list for why this exists.
    var onHome: (() -> Void)?
    /// Steps the room dimmer off → half → full.
    var onDim: (() -> Void)?

    /// One ring slot's identity: the module, its short label, its color.
    struct Slot {
        let id: String
        let title: String
        let accent: UIColor
    }

    init(slots slotSpecs: [Slot]) {
        buildBead()
        for spec in slotSpecs {
            let holder = Entity()
            holder.name = "palette-\(spec.id)"

            // The lab's OWN miniature, running. The name beneath makes
            // it a labelled button; the miniature makes it a promise.
            let built = HubVignettes.make(for: spec.id)
            let bounds = built.entity.visualBounds(relativeTo: nil).extents
            let largest = max(bounds.x, max(bounds.y, 1e-4))
            built.entity.scale = SIMD3(repeating: Self.slotSize / largest)
            holder.addChild(built.entity)

            // The slot's puck: an accent disc with a lit rim, so each
            // lab reads as a designed button rather than a floating
            // speck. (The old 0.11-opacity disc barely registered.)
            var backing = UnlitMaterial(color: spec.accent)
            backing.blending = .transparent(opacity: 0.18)
            let disc = ModelEntity(
                mesh: .generateCylinder(height: 0.002, radius: Self.slotSize * 0.78),
                materials: [backing])
            disc.orientation = simd_quatf(angle: .pi / 2, axis: [1, 0, 0])
            disc.position.z = -Self.slotSize * 0.55
            disc.components.set(GroundingShadowComponent(castsShadow: true))
            holder.addChild(disc)
            if let rim = Self.rimRing(radius: Self.slotSize * 0.78,
                                      color: spec.accent) {
                rim.position.z = -Self.slotSize * 0.55
                holder.addChild(rim)
            }

            // The label: the house nameplate, small, in the lab's own
            // accent — the same treatment the gallery exhibits wear.
            let label = HubScene.namePlate(spec.title, accent: spec.accent,
                                           size: PlateStyle.labelSize)
            label.position = [0, -Self.slotSize * 0.92, 0.01]
            holder.addChild(label)

            holder.components.set(InputTargetComponent())
            // THE LABEL IS PART OF THE TARGET — the lab's name hangs
            // below the miniature, outside the sphere, so the words on
            // the one surface that opens a lab were unpinchable.
            let slotLabelSpan = min(
                HubScene.namePlateWidth(spec.title, size: PlateStyle.labelSize),
                Self.slotSize * 1.6)
            holder.components.set(CollisionComponent(shapes: [
                .generateSphere(radius: Self.slotSize * 0.8),
                .generateBox(size: [slotLabelSpan, 0.024, 0.020])
                    .offsetBy(translation: [0, -Self.slotSize * 0.92, 0.01]),
            ]))
            holder.components.set(HoverEffectComponent())
            SpatialActions.attach(
                to: holder, label: "Open \(spec.title)",
                activate: { [weak self, weak holder] in
                    guard let self, let holder else { return }
                    _ = self.handleTap(holder)
                })
            holder.isEnabled = false
            root.addChild(holder)
            slots.append((spec.id, holder, built.animate))
        }

        // Pause and reset keep the outer spots hands have already
        // learned; capture and settings sit between them. (Each petal
        // past the original two amends the "exactly two petals"
        // decision — see DECISIONS.md 2026-07-29.)
        // HOME and DIM arrive 2026-08-07, and both close a capability
        // with NO other door.
        //
        // · Home — `dismissImmersiveSpace` appeared zero times in the
        //   app target, and the only route from a lab back to the
        //   gallery was a chevron in a 2-D window the user may well have
        //   left behind them. A one-path capability, and the one path
        //   was not in the room.
        // · Dim — `AppModel.cycleDimming()` had zero callers. Entering
        //   Gravity Lab darkens the user's real room by 85% with no
        //   control in the window, none in the room and none in
        //   Settings. That is the rule's strongest form broken: not one
        //   path, none.
        //
        // They go on the RING rather than into the room because the ring
        // is the one container this app already has that costs nothing
        // at rest — six petals folded away are still zero standing
        // objects, which a plate on a bank would not be.
        petals = [
            Self.makePetal(name: "home", symbol: "square.grid.2x2.fill"),
            Self.makePetal(name: "pause", symbol: "pause.fill"),
            Self.makePetal(name: "capture", symbol: "square.and.pencil"),
            Self.makePetal(name: "dim", symbol: "circle.lefthalf.filled"),
            Self.makePetal(name: "settings", symbol: "gearshape.fill"),
            Self.makePetal(name: "reset", symbol: "arrow.counterclockwise"),
        ]
        petals.forEach { petal in
            root.addChild(petal)
            // Through `handleTap`, which is where the ring's own rules
            // live: pause and reset fold the ring, capture and dim keep
            // it open. Routing at the callbacks would lose that.
            SpatialActions.attach(
                to: petal, label: petal.name.replacingOccurrences(
                    of: "palette-", with: "").capitalized,
                activate: { [weak self, weak petal] in
                    guard let self, let petal else { return }
                    _ = self.handleTap(petal)
                })
        }
    }

    /// Where the bead lives, in the host's coordinates. A saved spot —
    /// the user carried it somewhere — wins over the default.
    func place(at position: SIMD3<Float>) {
        if let saved = UserDefaults.standard.array(forKey: "palette.position")
            as? [Double], saved.count == 3 {
            root.position = SIMD3(Float(saved[0]), Float(saved[1]), Float(saved[2]))
        } else {
            root.position = position
        }
    }

    // MARK: Carrying the bead

    private var carryOffset: SIMD3<Float>?

    /// Routes a drag. True while the palette owns it (the drag began
    /// on the bead); the whole assembly rides the hand.
    func handleDrag(entity: Entity, world: SIMD3<Float>) -> Bool {
        if carryOffset == nil {
            guard Self.ownName(of: entity, under: root) == bead.name else {
                return false
            }
            carryOffset = root.position - world
        }
        guard let carryOffset else { return false }
        root.position = world + carryOffset
        return true
    }

    func endDrag() {
        guard carryOffset != nil else { return }
        carryOffset = nil
        // The new spot is where hands will now learn it: keep it,
        // across labs and across launches.
        UserDefaults.standard.set(
            [Double(root.position.x), Double(root.position.y), Double(root.position.z)],
            forKey: "palette.position")
    }

    func update(dt: Double, viewer: SIMD3<Float>?) {
        time += dt
        self.viewer = viewer

        let target: Float = isOpen ? 1 : 0
        let rate = Float(min(dt * 8, 1))
        openness += (target - openness) * rate
        if abs(openness - target) < 0.004 { openness = target }

        // The bead breathes when closed and recedes when open — it has
        // handed its job to the ring, and its nameplate goes with it.
        //
        // STILL UNDER REDUCE MOTION. `DESIGN_SYSTEM.md` describes
        // stillness as if it were app-wide; until 2026-08-03 it was read
        // in exactly one place, `HubSpaceView`, so the bead went on
        // breathing in every lab — on the one object that is never off
        // screen. Unfolding is not suppressed: that is a response to a
        // pinch, and a control that does not answer reads as broken.
        // What stops is the idle life nobody asked for.
        let breath = stillness ? 1 : 1 + 0.05 * Float(sin(time * 1.6))
        bead.scale = SIMD3(repeating: breath * (1 - 0.45 * openness))
        // Written only while the fold is actually moving — see the note
        // on `appliedBeadLabelOpacity`.
        if abs((1 - openness) - appliedBeadLabelOpacity) > 0.0005 {
            appliedBeadLabelOpacity = 1 - openness
            beadLabel?.components.set(OpacityComponent(opacity: 1 - openness))
        }

        // The rotor spins whatever else is paused, and the gimbals need
        // to know how far the ring has come to lay flat into it.
        beadVignette?.animate(time)
        beadVignette?.setOpenness?(openness)

        if let viewer, let facing = yaw(facing: viewer, from: root.position) {
            root.orientation = facing
        }

        layoutRing(dt: dt)
    }

    /// Whether the folded (openness == 0) layout has been applied, so a
    /// closed, settled palette writes no transforms at all per frame.
    private var appliedFoldedLayout = false

    private func layoutRing(dt: Double) {
        // Early out when folded and settled — this used to write
        // positions, scales and isEnabled for every slot and petal,
        // ninety times a second, to hold a closed fan closed. The zero
        // state must still be applied ONCE, or a palette that opens in
        // frame one shows a fan nobody laid out.
        if openness == 0 {
            if appliedFoldedLayout { return }
            appliedFoldedLayout = true
        } else {
            appliedFoldedLayout = false
        }
        let count = max(slots.count, 1)
        // A fan opening UPWARD from the bead — 150 degrees, so even the
        // outermost slots stay above it. Two hundred degrees swept the
        // ends back down below the bead, where they fall off the bottom
        // of a seated user's view.
        let span: Float = 150 * .pi / 180
        for (index, slot) in slots.enumerated() {
            let delay = Float(index) * 0.07
            let own = max(0, min((openness - delay) / max(1 - delay, 0.01), 1))
            let angle = -span / 2 + span * Float(index) / Float(max(count - 1, 1))
            let reach = Self.ringRadius * own
            slot.holder.position = SIMD3(sin(angle) * reach,
                                         cos(angle) * reach * 0.78 + 0.03,
                                         0)
            let pop = 1 + 0.16 * sin(own * .pi)
            slot.holder.scale = SIMD3(repeating: max(own, 0.001) * pop)
            slot.holder.isEnabled = own > 0.02
            if own > 0.2 { slot.animate(time) }
        }

        for (index, petal) in petals.enumerated() {
            let delay = 0.5 + Float(index) * 0.08
            let own = max(0, min((openness - delay) / max(1 - delay, 0.01), 1))
            // Petals fan across a constant 0.22 m span below the bead —
            // widened from 0.17 when the fourth petal arrived, keeping
            // clear air between neighbouring discs.
            let x = (Float(index) / Float(max(petals.count - 1, 1)) - 0.5)
                * Self.petalRowSpan(count: petals.count)
            petal.position = SIMD3(x * own, -0.135 * own, 0)
            petal.scale = SIMD3(repeating: max(own, 0.001))
            petal.isEnabled = own > 0.02
        }
    }

    /// Routes a tap. Returns true if the palette consumed it.
    func handleTap(_ entity: Entity) -> Bool {
        guard let name = Self.ownName(of: entity, under: root) else { return false }
        if name == bead.name {
            isOpen.toggle()
            SoundPalette.play(.pop, on: bead, volume: 0.5)
            SpatialActions.republish(value: isOpen ? "open" : "closed", on: bead)
            return true
        }
        guard isOpen else { return false }
        if name == "palette-pause" { onPause?(); isOpen = false; return true }
        if name == "palette-capture" {
            // Capture stays OPEN: writing down a run of moments is one
            // errand, and refolding after each note would make three
            // captures cost three unfoldings.
            onCapture?()
            SoundPalette.play(.chime, on: bead, volume: 0.5)
            return true
        }
        if name == "palette-home" { onHome?(); isOpen = false; return true }
        if name == "palette-dim" {
            // Stays OPEN, like capture: dimming is a thing you tune by
            // looking at the result, and off → half → full is three
            // taps. Refolding after each would cost three unfoldings.
            onDim?()
            SoundPalette.play(.pop, on: bead, volume: 0.35)
            return true
        }
        if name == "palette-settings" { onSettings?(); isOpen = false; return true }
        if name == "palette-reset" { onReset?(); isOpen = false; return true }
        if let slot = slots.first(where: { $0.holder.name == name }) {
            SoundPalette.play(.chime, on: slot.holder, volume: 0.6)
            isOpen = false
            onSelect?(slot.id)
            return true
        }
        return false
    }

    func close() { isOpen = false }

    private static func ownName(of entity: Entity, under root: Entity) -> String? {
        var current: Entity? = entity
        while let candidate = current {
            if candidate.parent === root { return candidate.name }
            if candidate === root { return nil }
            current = candidate.parent
        }
        return nil
    }

    private func buildBead() {
        bead.name = "palette-bead"
        bead.components.set(InputTargetComponent())
        // THE LABEL IS PART OF THE TARGET, and this one is a SIBLING of
        // the bead rather than a child — added to `root` so it does not
        // inherit the bead's spin. That makes it invisible to the
        // parent-walking criterion, which is exactly why it survived
        // while the picker's and the petals' were being found: nothing
        // could attribute it to the control it names. The offset below
        // mirrors the label's placement in `buildBead`; keep them
        // together.
        bead.components.set(CollisionComponent(shapes: [
            .generateSphere(radius: Self.beadRadius * 1.8),
            .generateBox(size: [0.052, 0.024, 0.020])
                .offsetBy(translation: [0, -(Self.beadRadius + 0.026), 0]),
        ]))
        bead.components.set(HoverEffectComponent())
        // The one permanent object in every lab missed the 2026-08-05
        // grounding-shadow pass; presence, not decoration.
        bead.components.set(GroundingShadowComponent(castsShadow: true))
        SpatialActions.attach(
            to: bead, label: "Labs", value: isOpen ? "open" : "closed",
            activate: { [weak self] in
                guard let self else { return }
                _ = self.handleTap(self.bead)
            })

        // The bead is a gyroscope, built by the same system that builds
        // every lab's miniature — `HubVignettes.make(for: "labs")`.
        //
        // It was a white glass sphere with an SF Symbol grid floating
        // inside it: iOS chrome on the one object in this app that is
        // never not on screen. The glyph was there because an anonymous
        // sphere asked to be pinched on faith and wasn't — but the answer
        // to "say what you are" is to BE something, and every other
        // object in the room is an instrument. A gyroscope belongs to no
        // single lab, and holding still while everything turns is exactly
        // the bead's job.
        //
        // Fitted the same way the ring slots are: the miniature arrives
        // normalised to the common square and is scaled to the bead.
        let built = HubVignettes.make(for: "labs")
        built.entity.scale = SIMD3(
            repeating: Self.beadRadius * 2 / (HubVignettes.frameHalf * 2))
        bead.addChild(built.entity)
        beadVignette = built

        let label = HubScene.namePlate("Labs", accent: UIColor(white: 0.95, alpha: 1),
                                       size: PlateStyle.labelSize)
        label.position = [0, -(Self.beadRadius + 0.026), 0]
        beadLabel = label
        root.addChild(label)

        root.addChild(bead)
    }

    /// A thin lit circle marking a slot's edge — the rim that turns a
    /// faint disc into a button.
    private static func rimRing(radius: Float, color: UIColor) -> ModelEntity? {
        let points = (0...48).map { step -> SIMD3<Float> in
            let angle = Float(step) / 48 * 2 * .pi
            return SIMD3(cos(angle) * radius, sin(angle) * radius, 0)
        }
        guard let mesh = TubeMesh.tube(lines: [points], radius: 0.0012, sides: 4)
        else { return nil }
        var material = UnlitMaterial(color: color)
        material.blending = .transparent(opacity: 0.55)
        return ModelEntity(mesh: mesh, materials: [material])
    }

    private static func makePetal(name: String, symbol: String) -> ModelEntity {
        var casing = PhysicallyBasedMaterial()
        casing.baseColor = .init(tint: UIColor(white: 0.06, alpha: 1))
        casing.roughness = 0.28
        casing.clearcoat = .init(floatLiteral: 1.0)
        casing.blending = .transparent(opacity: .init(floatLiteral: 0.92))
        let disc = ModelEntity(
            mesh: .generateCylinder(height: 0.005, radius: 0.024),
            materials: [casing])
        disc.name = "palette-\(name)"
        disc.orientation = simd_quatf(angle: .pi / 2, axis: [1, 0, 0])
        disc.components.set(GroundingShadowComponent(castsShadow: true))
        if let texture = Bloom.symbolTexture(symbol) {
            var iconMaterial = UnlitMaterial()
            iconMaterial.color = .init(tint: .white, texture: .init(texture))
            iconMaterial.blending = .transparent(opacity: .init(floatLiteral: 1))
            let icon = ModelEntity(
                mesh: .generatePlane(width: 0.026, height: 0.026),
                materials: [iconMaterial])
            icon.position = [0, 0.004, 0]
            icon.orientation = simd_quatf(angle: -.pi / 2, axis: [1, 0, 0])
            disc.addChild(icon)
        }
        // The petal's name, in the small house nameplate beneath it —
        // four icon-only discs asked to be memorised; labels don't.
        // (The disc is rotated π/2 about X, so "below, facing the
        // viewer" is local +Z with the icon's counter-rotation.)
        let plate = HubScene.namePlate(name.capitalized,
                                       accent: UIColor(white: 0.95, alpha: 1),
                                       size: PlateStyle.labelSize)
        plate.position = [0, 0.005, 0.047]
        plate.orientation = simd_quatf(angle: -.pi / 2, axis: [1, 0, 0])
        disc.addChild(plate)

        disc.components.set(InputTargetComponent())
        // THE LABEL IS PART OF THE TARGET. Clamped to the petal pitch for
        // the reason the picker's is — `petalRowSpan` spaces the ring by
        // `petalColliderSpan`, and a wider target would overlap the petal
        // beside it.
        let petalLabelSpan = min(
            HubScene.namePlateWidth(name.capitalized, size: PlateStyle.labelSize),
            Self.petalColliderSpan)
        disc.components.set(CollisionComponent(shapes: [
            .generateSphere(radius: 0.034),
            .generateBox(size: [petalLabelSpan, 0.020, 0.024])
                .offsetBy(translation: [0, 0.005, 0.047]),
        ]))
        disc.components.set(HoverEffectComponent())
        // Label only — the ACTION is attached in `init`, where there is
        // a `self` to route the tap through.
        var accessibility = AccessibilityComponent()
        accessibility.isAccessibilityElement = true
        accessibility.label = LocalizedStringResource(stringLiteral: name)
        disc.components.set(accessibility)
        disc.isEnabled = false
        return disc
    }
}

/// Mounts the palette bead in whatever lab is on screen.
struct PaletteView: View {
    let module: ModuleDescriptor
    @Environment(AppModel.self) private var appModel
    @Environment(\.openWindow) private var openWindow
    /// The SYSTEM setting, not an in-app duplicate — the in-app one was
    /// deleted on 2026-07-31 and must not come back.
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @State private var palette: Palette?

    var body: some View {
        RealityView { content in
            let made = Palette(slots: ModuleCatalog.all(appModel: appModel).map {
                .init(id: $0.id, title: $0.shortTitle ?? $0.title,
                      accent: UIColor($0.accent))
            })
            // Low and to the RIGHT, at about fifteen degrees below the
            // eye line: in reach, clear of where every lab puts its
            // physics (which is centred), and in the same place in every
            // lab so it is somewhere your hands learn. Directly under
            // the chin — the first choice — is comfortable to reach and
            // never noticed, the same mistake the wells made.
            made.place(at: [0.72, 1.32, -0.95])
            made.onSelect = { id in appModel.activeModuleID = id }
            made.onPause = { module.togglePause() }
            made.onReset = { appModel.resetActiveModule(module) }
            made.onSettings = { openWindow(id: SettingsView.windowID) }
            made.onCapture = { appModel.captureNotebookEntry() }
            // Home clears the active module, which swaps the module
            // scene for `HubSpaceView` inside the SAME immersive space —
            // the gallery is not a separate space, so this is a
            // one-line answer to "let me out of this lab".
            made.onHome = { appModel.activeModuleID = nil }
            made.onDim = { appModel.cycleDimming() }
            content.add(made.root)
            palette = made
            #if DEBUG
            // `-paletteOpen 1` unfolds it at launch: the simulator has
            // no hand to pinch the bead with.
            if UserDefaults.standard.double(forKey: "paletteOpen") > 0 {
                _ = made.handleTap(made.beadEntity)
            }
            #endif

            made.stillness = systemReduceMotion
            made.subscription = content.subscribe(
                to: SceneEvents.Update.self
            ) { [weak made] event in
                made?.update(dt: event.deltaTime,
                             viewer: appModel.room.headPosition.map { SIMD3<Float>($0) })
            }
        } update: { _ in
            palette?.stillness = systemReduceMotion
        }
        .onDisappear {
            palette?.subscription?.cancel()
            palette?.subscription = nil
        }
        .simultaneousGesture(
            TapGesture()
                .targetedToAnyEntity()
                .onEnded { value in _ = palette?.handleTap(value.entity) }
        )
        // Carry the bead: a real drag (not a pinch-tap) on the bead
        // moves the whole palette, and the spot sticks. The minimum
        // distance keeps taps and carries from fighting.
        .simultaneousGesture(
            DragGesture(minimumDistance: 0.02)
                .targetedToAnyEntity()
                .onChanged { value in
                    let world = SIMD3<Float>(value.convert(
                        value.location3D, from: .local, to: .scene))
                    _ = palette?.handleDrag(entity: value.entity, world: world)
                }
                .onEnded { _ in palette?.endDrag() }
        )
    }
}
