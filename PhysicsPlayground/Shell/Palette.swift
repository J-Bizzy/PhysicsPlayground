//
//  Palette.swift
//  Physics Playground — Shell
//
//  Navigation, as one object: the app's only permanent piece of
//  interface. Pinch the bead and it unfolds into a ring of the labs
//  themselves — live miniatures — plus five petals: home, pause, dim,
//  settings, reset. The open row's width derives from the petal
//  count (`petalRowSpan`), so a new petal cannot overlap its neighbours.
//  Reset arms before it fires, like every destructive plate in the room.
//

import RealityKit
import SwiftUI
import RenderKit
import simd

@MainActor
final class Palette {
    let root = Entity()

    /// Held so it can be cancelled: the view is remounted per module, and a
    /// running subscription would keep animating an orphaned bead.
    var subscription: EventSubscription?

    private let bead = ModelEntity()
    /// The gyroscope inside the bead; ticked every frame and told how far
    /// the ring has unfolded so the gimbals lay flat into it.
    private var beadVignette: HubVignettes.Built?
    /// The "Labs" nameplate under the closed bead; fades as the ring
    /// opens and the slots' own labels take over.
    private var beadLabel: Entity?
    var beadEntity: Entity { bead }
    private var slots: [(id: String, holder: Entity, animate: (Double) -> Void)] = []
    private var petals: [ModelEntity] = []

    /// 0 folded, 1 open. Everything else is derived from this.
    private(set) var openness: Float = 0
    /// The bead label opacity last written, so a parked fold writes no
    /// component per frame.
    private var appliedBeadLabelOpacity: Float = -1
    private var isOpen = false
    private var time: Double = 0

    /// Set by the host each frame so the ring faces the reader.
    private var viewer: SIMD3<Float>?

    /// The system's Reduce Motion setting, pushed in by the host.
    var stillness = false

    // Ring geometry, in metres.
    /// One petal's touch target, across — wider than the 0.048 m disc, and
    /// the number that decides whether two petals can be aimed at separately.
    static let petalColliderSpan: Float = 0.068

    /// How wide the petal row must be to hold `count` petals. Derived, not
    /// typed: a span tuned for one count is how a fifth petal ends up
    /// unaimable.
    static func petalRowSpan(count: Int) -> Float {
        Float(max(count - 1, 1)) * petalColliderSpan * 1.1
    }

    private static let ringRadius: Float = 0.40
    private static let slotSize: Float = 0.072
    private static let beadRadius: Float = 0.026
    /// Where the bead stands in every lab, in the space's coordinates: to the
    /// right, at eye height, 33° off axis — in reach, clear of the physics,
    /// and the same in every lab. At y 1.50 it clears every Orbital Mechanics orbit
    /// and Circuits' shelf by 25 cm.
    static let defaultAnchor = SIMD3<Float>(0.62, 1.50, -0.95)

    var onSelect: ((String) -> Void)?
    var onPause: (() -> Void)?
    var onReset: (() -> Void)?
    var onSettings: (() -> Void)?
    /// Back to the gallery.
    var onHome: (() -> Void)?
    /// Steps the room dimmer off → half → full.
    var onDim: (() -> Void)?

    // MARK: Reset arms first

    /// Seconds the reset petal stays armed, nil when it is not. The title
    /// bar's Reset asks first and so does every Clear plate; a petal one
    /// pinch from wiping a bench that survives relaunch did not.
    private(set) var resetArmed: Double?
    private var resetPetal: ModelEntity?
    /// The petal's lit face and its two names, swapped by `isEnabled` —
    /// built once, never rebuilt on the per-frame path.
    private var resetLamp: Entity?
    private var resetRestLabel: Entity?
    private var resetArmedLabel: Entity?

    /// Read every frame so the pause petal says what it will do.
    var isPaused: (() -> Bool)?
    private var pausePetal: ModelEntity?
    private var pauseRest: [Entity] = []
    private var pauseResume: [Entity] = []
    private var shownPaused = false

    /// Arms the reset petal without a pinch and holds it there — for the
    /// debug screenshot, which cannot pinch at all.
    func armResetForDebug() {
        resetArmed = .infinity
        paintReset()
    }

    private func paintReset() {
        let armed = resetArmed != nil
        resetLamp?.isEnabled = armed
        resetRestLabel?.isEnabled = !armed
        resetArmedLabel?.isEnabled = armed
        if let resetPetal {
            SpatialActions.republish(
                value: armed ? "armed — tap again to confirm" : "button",
                on: resetPetal)
        }
    }

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

            // The lab's own miniature, running.
            let built = HubVignettes.make(for: spec.id)
            let bounds = built.entity.visualBounds(relativeTo: nil).extents
            let largest = max(bounds.x, max(bounds.y, 1e-4))
            built.entity.scale = SIMD3(repeating: Self.slotSize / largest)
            holder.addChild(built.entity)

            // The slot's puck: an accent disc with a lit rim, so each lab reads as
            // a button.
            let disc = ModelEntity(
                mesh: Primitives.cylinder(height: 0.002, radius: Self.slotSize * 0.78),
                materials: [Materials.unlit(spec.accent, opacity: 0.18)])
            disc.orientation = simd_quatf(angle: .pi / 2, axis: [1, 0, 0])
            disc.position.z = -Self.slotSize * 0.55
            disc.components.set(GroundingShadowComponent(castsShadow: true))
            holder.addChild(disc)
            if let rim = Self.rimRing(radius: Self.slotSize * 0.78,
                                      color: spec.accent) {
                rim.position.z = -Self.slotSize * 0.55
                holder.addChild(rim)
            }

            // The house nameplate in the lab's accent, as the gallery exhibits wear.
            let label = HubScene.namePlate(spec.title, accent: spec.accent,
                                           size: PlateStyle.labelSize)
            label.position = [0, -Self.slotSize * 0.92, 0.01]
            holder.addChild(label)

            holder.components.set(InputTargetComponent())
            // The label is part of the target: the name hangs below the miniature,
            // outside the sphere.
            let slotLabelSpan = min(
                HubScene.namePlateWidth(spec.title, size: PlateStyle.labelSize),
                Self.slotSize * 1.6)
            holder.components.set(CollisionComponent(shapes: [
                Primitives.collisionSphere(radius: Self.slotSize * 0.8),
                Primitives.collisionBox(size: [slotLabelSpan, 0.024, 0.020],
                                        offset: [0, -Self.slotSize * 0.92, 0.01]),
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

        // Pause and reset keep the outer spots hands have learned; home and dim
        // ride the ring because folded petals cost nothing at rest.
        petals = [
            Self.makePetal(name: "home", symbol: "square.grid.2x2.fill"),
            Self.makePetal(name: "pause", symbol: "pause.fill"),
            Self.makePetal(name: "dim", symbol: "circle.lefthalf.filled"),
            Self.makePetal(name: "settings", symbol: "gearshape.fill"),
            Self.makePetal(name: "reset", symbol: "arrow.counterclockwise"),
        ]
        if let reset = petals.last {
            resetPetal = reset
            decorateReset(reset)
        }
        if let pause = petals.first(where: { $0.name == "palette-pause" }) {
            decoratePause(pause)
        }
        petals.forEach { petal in
            root.addChild(petal)
            // Through `handleTap`, where the ring's own fold rules live.
            SpatialActions.attach(
                to: petal, label: petal.name.replacingOccurrences(
                    of: "palette-", with: "").capitalized,
                activate: { [weak self, weak petal] in
                    guard let self, let petal else { return }
                    _ = self.handleTap(petal)
                })
        }
    }

    /// Where the bead lives, in the host's coordinates. A saved spot wins
    /// over the default.
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
        // Kept across labs and launches.
        UserDefaults.standard.set(
            [Double(root.position.x), Double(root.position.y), Double(root.position.z)],
            forKey: "palette.position")
    }

    func update(dt: Double, viewer: SIMD3<Float>?) {
        time += dt
        self.viewer = viewer

        showPaused(isPaused?() ?? false)

        // Armed only while it can be seen: folding the ring or letting the
        // window run out disarms.
        if let remaining = resetArmed {
            let next = remaining - dt
            if !isOpen || next <= 0 {
                resetArmed = nil
                paintReset()
            } else {
                resetArmed = next
            }
        }

        let target: Float = isOpen ? 1 : 0
        let rate = Float(min(dt * 8, 1))
        openness += (target - openness) * rate
        if abs(openness - target) < 0.004 { openness = target }

        // The bead breathes when closed and recedes when open. Still under
        // Reduce Motion; unfolding answers a pinch and is never suppressed.
        let breath = stillness ? 1 : 1 + 0.05 * Float(sin(time * 1.6))
        bead.scale = SIMD3(repeating: breath * (1 - 0.45 * openness))
        // Written only while the fold is moving.
        if abs((1 - openness) - appliedBeadLabelOpacity) > 0.0005 {
            appliedBeadLabelOpacity = 1 - openness
            beadLabel?.components.set(OpacityComponent(opacity: 1 - openness))
        }

        // The rotor spins whatever else is paused.
        beadVignette?.animate(time)
        beadVignette?.setOpenness?(openness)

        if let viewer, let facing = yaw(facing: viewer, from: root.position) {
            root.orientation = facing
        }

        layoutRing(dt: dt)
    }

    /// Whether the folded layout has been applied, so a closed, settled
    /// palette writes no transforms per frame.
    private var appliedFoldedLayout = false

    private func layoutRing(dt: Double) {
        // Early out when folded and settled; the zero state must still be
        // applied once.
        if openness == 0 {
            if appliedFoldedLayout { return }
            appliedFoldedLayout = true
        } else {
            appliedFoldedLayout = false
        }
        let count = max(slots.count, 1)
        // A fan opening upward from the bead, 150°, so the outermost slots stay
        // above it.
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
            // Petals fan across `petalRowSpan` below the bead.
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
        if name == "palette-home" { onHome?(); isOpen = false; return true }
        if name == "palette-dim" {
            // Stays open: dimming is tuned by looking at the result.
            onDim?()
            SoundPalette.play(.pop, on: bead, volume: 0.35)
            return true
        }
        if name == "palette-settings" { onSettings?(); isOpen = false; return true }
        if name == "palette-reset" {
            // First pinch arms; the second, inside the window, fires.
            guard resetArmed != nil else {
                resetArmed = SpatialActionBank.armWindow
                paintReset()
                SoundPalette.play(.pop, on: bead, volume: 0.25)
                return true
            }
            resetArmed = nil
            paintReset()
            onReset?()
            isOpen = false
            return true
        }
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
        // The label is part of the target. It is a sibling of the bead (added to
        // `root` so it does not inherit the spin), so this offset mirrors
        // `buildBead`; keep them together.
        bead.components.set(CollisionComponent(shapes: [
            Primitives.collisionSphere(radius: Self.beadRadius * 1.8),
            Primitives.collisionBox(size: [0.052, 0.024, 0.020], offset: [0, -(Self.beadRadius + 0.026), 0]),
        ]))
        bead.components.set(HoverEffectComponent())
        bead.components.set(GroundingShadowComponent(castsShadow: true))
        SpatialActions.attach(
            to: bead, label: "Labs", value: isOpen ? "open" : "closed",
            activate: { [weak self] in
                guard let self else { return }
                _ = self.handleTap(self.bead)
            })

        // The bead is a gyroscope from the same system that builds every lab's
        // miniature, fitted like the ring slots.
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

    /// A thin lit circle marking a slot's edge.
    private static func rimRing(radius: Float, color: UIColor) -> ModelEntity? {
        let points = (0...48).map { step -> SIMD3<Float> in
            let angle = Float(step) / 48 * 2 * .pi
            return SIMD3(cos(angle) * radius, sin(angle) * radius, 0)
        }
        guard let mesh = TubeMesh.tube(lines: [points], radius: 0.0012, sides: 4)
        else { return nil }
        return ModelEntity(mesh: mesh, materials: [Materials.unlit(color, opacity: 0.55)])
    }

    private static let petalLabelName = "petal-label"
    private static let petalLabelPosition = SIMD3<Float>(0, 0.005, 0.047)
    private static let petalLabelOrientation = simd_quatf(angle: -.pi / 2, axis: [1, 0, 0])

    /// The reset petal's armed state: a face in the destructive red over the
    /// casing (red is the one tinted petal colour — `destructiveUI`), and
    /// "Tap again" in place of its name, as an armed Clear plate reads.
    private func decorateReset(_ petal: ModelEntity) {
        let lamp = ModelEntity(
            mesh: Primitives.cylinder(height: 0.0055, radius: 0.0242),
            materials: [Materials.unlit(DesignTokens.Palette.destructiveUI, opacity: 0.9)])
        lamp.isEnabled = false
        petal.addChild(lamp)
        resetLamp = lamp

        resetRestLabel = petal.children.first { $0.name == Self.petalLabelName }
        let armed = HubScene.namePlate(SpatialActionBank.armedLabel,
                                       accent: UIColor(white: 0.95, alpha: 1),
                                       size: PlateStyle.labelSize)
        armed.name = Self.petalLabelName + "-armed"
        armed.position = Self.petalLabelPosition
        armed.orientation = Self.petalLabelOrientation
        armed.isEnabled = false
        petal.addChild(armed)
        resetArmedLabel = armed
    }

    private static let petalIconName = "petal-icon"

    /// A petal's glyph, lying on its face.
    private static func makePetalIcon(_ symbol: String) -> ModelEntity? {
        guard let texture = Bloom.symbolTexture(symbol) else { return nil }
        var iconMaterial = UnlitMaterial()
        iconMaterial.color = .init(tint: .white, texture: .init(texture))
        iconMaterial.blending = .transparent(opacity: .init(floatLiteral: 1))
        let icon = ModelEntity(
            mesh: Primitives.plane(width: 0.026, height: 0.026),
            materials: [iconMaterial])
        icon.name = petalIconName
        icon.position = [0, 0.004, 0]
        icon.orientation = simd_quatf(angle: -.pi / 2, axis: [1, 0, 0])
        return icon
    }

    /// The pause petal's other face: a play glyph and "Resume", shown while
    /// the lab is paused. It said "Pause" either way until 2026-10-14, so
    /// the petal that resumes a paused room offered to pause it.
    private func decoratePause(_ petal: ModelEntity) {
        pauseRest = petal.children.filter {
            $0.name == Self.petalIconName || $0.name == Self.petalLabelName
        }
        var resume: [Entity] = []
        if let icon = Self.makePetalIcon("play.fill") {
            icon.isEnabled = false
            petal.addChild(icon)
            resume.append(icon)
        }
        let plate = HubScene.namePlate("Resume", accent: UIColor(white: 0.95, alpha: 1),
                                       size: PlateStyle.labelSize)
        plate.position = Self.petalLabelPosition
        plate.orientation = Self.petalLabelOrientation
        plate.isEnabled = false
        petal.addChild(plate)
        resume.append(plate)
        pauseResume = resume
        pausePetal = petal
    }

    private func showPaused(_ paused: Bool) {
        guard paused != shownPaused else { return }
        shownPaused = paused
        pauseRest.forEach { $0.isEnabled = !paused }
        pauseResume.forEach { $0.isEnabled = paused }
        if let pausePetal,
           var accessibility = pausePetal.components[AccessibilityComponent.self] {
            accessibility.label = LocalizedStringResource(
                stringLiteral: paused ? "Resume" : "Pause")
            pausePetal.components.set(accessibility)
        }
    }

    private static func makePetal(name: String, symbol: String) -> ModelEntity {
        var casing = PhysicallyBasedMaterial()
        casing.baseColor = .init(tint: UIColor(white: 0.06, alpha: 1))
        casing.roughness = 0.28
        casing.clearcoat = .init(floatLiteral: 1.0)
        casing.blending = .transparent(opacity: .init(floatLiteral: 0.92))
        let disc = ModelEntity(
            mesh: Primitives.cylinder(height: 0.005, radius: 0.024),
            materials: [casing])
        disc.name = "palette-\(name)"
        disc.orientation = simd_quatf(angle: .pi / 2, axis: [1, 0, 0])
        disc.components.set(GroundingShadowComponent(castsShadow: true))
        if let icon = makePetalIcon(symbol) {
            disc.addChild(icon)
        }
        // The petal's name beneath it. The disc is rotated π/2 about X, so
        // "below, facing the viewer" is local +Z with the icon's counter-rotation.
        let plate = HubScene.namePlate(name.capitalized,
                                       accent: UIColor(white: 0.95, alpha: 1),
                                       size: PlateStyle.labelSize)
        plate.name = petalLabelName
        plate.position = petalLabelPosition
        plate.orientation = petalLabelOrientation
        disc.addChild(plate)

        disc.components.set(InputTargetComponent())
        // The label is part of the target, clamped to the petal pitch so it
        // never overlaps the petal beside it.
        let petalLabelSpan = min(
            HubScene.namePlateWidth(name.capitalized, size: PlateStyle.labelSize),
            Self.petalColliderSpan)
        disc.components.set(CollisionComponent(shapes: [
            Primitives.collisionSphere(radius: 0.034),
            Primitives.collisionBox(size: [petalLabelSpan, 0.020, 0.024], offset: [0, 0.005, 0.047]),
        ]))
        disc.components.set(HoverEffectComponent())
        // Label only; the action is attached in `init`, where there is a `self`.
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
    /// The system setting; there is no in-app duplicate.
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @State private var palette: Palette?

    var body: some View {
        RealityView { content in
            let made = Palette(slots: ModuleCatalog.all(appModel: appModel).map {
                .init(id: $0.id, title: $0.shortTitle ?? $0.title,
                      accent: UIColor($0.accent))
            })
            made.place(at: Palette.defaultAnchor)
            // The lab→lab switch, through the one door so it gets the transition.
            made.onSelect = { id in appModel.go(to: id) }
            made.onPause = { module.togglePause() }
            made.isPaused = { module.isPaused() }
            made.onReset = { appModel.resetActiveModule(module) }
            made.onSettings = { openWindow(id: SettingsView.windowID) }
            // Home clears the active module, which swaps the module scene for
            // `HubSpaceView` inside the same immersive space.
            made.onHome = { appModel.go(to: nil) }
            made.onDim = { appModel.cycleDimming() }
            content.add(made.root)
            palette = made
            #if DEBUG
            // `-paletteOpen 1` unfolds it at launch.
            let armReset = UserDefaults.standard.double(forKey: "paletteReset") > 0
            if UserDefaults.standard.double(forKey: "paletteOpen") > 0 || armReset {
                _ = made.handleTap(made.beadEntity)
            }
            // `-paletteReset 1` opens the ring with the reset petal ARMED and
            // held there — photographed armed, never fired, like `-circClear`.
            if armReset { made.armResetForDebug() }
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
        // Carry the bead: a real drag on it moves the whole palette, and the
        // spot sticks. The minimum distance keeps taps and carries apart.
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
