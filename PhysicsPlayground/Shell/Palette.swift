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
//  home constellation shows, not icons of them — with pause, reset, and
//  settings as the only petals: the two controls you reach for without
//  breaking off what you are doing, plus the one door to the app's
//  preferences (the bead is the only interface that exists in every
//  lab, so the door has to live on it). Pinch a lab and
//  the room changes. Pinch the bead again and everything folds away.
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

    private let bead = ModelEntity()
    /// The "Labs" nameplate under the closed bead; fades as the ring
    /// opens and the slots' own labels take over.
    private var beadLabel: Entity?
    var beadEntity: Entity { bead }
    private var slots: [(id: String, holder: Entity, animate: (Double) -> Void)] = []
    private var petals: [ModelEntity] = []

    /// 0 folded, 1 open. Everything else is derived from this.
    private(set) var openness: Float = 0
    private var isOpen = false
    private var time: Double = 0

    /// Set by the host each frame so the ring faces the reader.
    private var viewer: SIMD3<Float>?

    // Ring geometry, in metres. The labs sit on a circle you can sweep
    // with one comfortable arm movement.
    // Seven slots across 150 degrees need room: at a 0.26 m radius the
    // arc gives 11 cm between centres while the discs were 13 cm wide,
    // so the ring overlapped itself into a smear. 0.40 m keeps the same
    // clear air with the 20%-bigger slots the labels asked for — at the
    // old 0.06 m the miniatures read as specks and their thin lines
    // shimmered.
    private static let ringRadius: Float = 0.40
    private static let slotSize: Float = 0.072
    private static let beadRadius: Float = 0.026

    var onSelect: ((String) -> Void)?
    var onPause: (() -> Void)?
    var onReset: (() -> Void)?
    var onSettings: (() -> Void)?
    var onCapture: (() -> Void)?

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
            holder.addChild(disc)
            if let rim = Self.rimRing(radius: Self.slotSize * 0.78,
                                      color: spec.accent) {
                rim.position.z = -Self.slotSize * 0.55
                holder.addChild(rim)
            }

            // The label: the house nameplate, small, in the lab's own
            // accent — the same treatment the gallery exhibits wear.
            let label = HubScene.namePlate(spec.title, accent: spec.accent,
                                           size: 0.014)
            label.position = [0, -Self.slotSize * 0.92, 0.01]
            holder.addChild(label)

            holder.components.set(InputTargetComponent())
            holder.components.set(CollisionComponent(
                shapes: [.generateSphere(radius: Self.slotSize * 0.8)]))
            holder.components.set(HoverEffectComponent())
            var accessibility = AccessibilityComponent()
            accessibility.isAccessibilityElement = true
            accessibility.label = LocalizedStringResource(
                stringLiteral: "Open \(spec.title)")
            holder.components.set(accessibility)
            holder.isEnabled = false
            root.addChild(holder)
            slots.append((spec.id, holder, built.animate))
        }

        // Pause and reset keep the outer spots hands have already
        // learned; capture and settings sit between them. (Each petal
        // past the original two amends the "exactly two petals"
        // decision — see DECISIONS.md 2026-07-29.)
        petals = [
            Self.makePetal(name: "pause", symbol: "pause.fill"),
            Self.makePetal(name: "capture", symbol: "square.and.pencil"),
            Self.makePetal(name: "settings", symbol: "gearshape.fill"),
            Self.makePetal(name: "reset", symbol: "arrow.counterclockwise"),
        ]
        petals.forEach { root.addChild($0) }
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
        let breath = 1 + 0.05 * Float(sin(time * 1.6))
        bead.scale = SIMD3(repeating: breath * (1 - 0.45 * openness))
        beadLabel?.components.set(OpacityComponent(opacity: 1 - openness))

        if let viewer {
            let flat = SIMD3<Float>(viewer.x - root.position.x, 0,
                                    viewer.z - root.position.z)
            if simd_length(flat) > 1e-4 {
                root.orientation = simd_quatf(from: [0, 0, 1],
                                              to: simd_normalize(flat))
            }
        }

        layoutRing(dt: dt)
    }

    private func layoutRing(dt: Double) {
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
            let x = (Float(index) / Float(max(petals.count - 1, 1)) - 0.5) * 0.22
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
        var glass = PhysicallyBasedMaterial()
        glass.baseColor = .init(tint: UIColor(white: 0.97, alpha: 1))
        glass.roughness = 0.12
        glass.clearcoat = .init(floatLiteral: 1.0)
        glass.blending = .transparent(opacity: .init(floatLiteral: 0.55))
        glass.emissiveColor = .init(color: .white)
        glass.emissiveIntensity = 0.3
        bead.model = ModelComponent(
            mesh: .generateSphere(radius: Self.beadRadius), materials: [glass])
        bead.name = "palette-bead"
        bead.components.set(InputTargetComponent())
        bead.components.set(CollisionComponent(
            shapes: [.generateSphere(radius: Self.beadRadius * 1.8)]))
        bead.components.set(HoverEffectComponent())
        var accessibility = AccessibilityComponent()
        accessibility.isAccessibilityElement = true
        accessibility.label = "Labs. Pinch to open."
        bead.components.set(accessibility)

        // The bead says what it IS: the module-switcher glyph floating
        // in the glass, the house nameplate beneath — an anonymous
        // sphere asked to be pinched on faith, and wasn't.
        if let texture = Bloom.symbolTexture("square.grid.3x3") {
            var iconMaterial = UnlitMaterial()
            iconMaterial.color = .init(tint: UIColor(white: 1, alpha: 0.92),
                                       texture: .init(texture))
            iconMaterial.blending = .transparent(opacity: .init(floatLiteral: 1))
            let icon = ModelEntity(
                mesh: .generatePlane(width: 0.021, height: 0.021),
                materials: [iconMaterial])
            icon.position = [0, 0, 0.009]
            bead.addChild(icon)
        }
        let label = HubScene.namePlate("Labs", accent: UIColor(white: 0.95, alpha: 1),
                                       size: 0.012)
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
                                       size: 0.010)
        plate.position = [0, 0.005, 0.047]
        plate.orientation = simd_quatf(angle: -.pi / 2, axis: [1, 0, 0])
        disc.addChild(plate)

        disc.components.set(InputTargetComponent())
        disc.components.set(CollisionComponent(
            shapes: [.generateSphere(radius: 0.034)]))
        disc.components.set(HoverEffectComponent())
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
            made.onReset = { module.reset() }
            made.onSettings = { openWindow(id: SettingsView.windowID) }
            made.onCapture = { appModel.captureNotebookEntry() }
            content.add(made.root)
            palette = made
            #if DEBUG
            // `-paletteOpen 1` unfolds it at launch: the simulator has
            // no hand to pinch the bead with.
            if UserDefaults.standard.double(forKey: "paletteOpen") > 0 {
                _ = made.handleTap(made.beadEntity)
            }
            #endif

            _ = content.subscribe(to: SceneEvents.Update.self) { event in
                made.update(dt: event.deltaTime,
                            viewer: appModel.room.headPosition.map { SIMD3<Float>($0) })
            }
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
