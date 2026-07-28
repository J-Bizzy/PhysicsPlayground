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
//  home constellation shows, not icons of them — with pause and reset
//  as the only two petals, because those are the only two controls you
//  reach for without breaking off what you are doing. Pinch a lab and
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
    // so the ring overlapped itself into a smear. 0.36 m and smaller
    // slots leave clear air between neighbours.
    private static let ringRadius: Float = 0.36
    private static let slotSize: Float = 0.060
    private static let beadRadius: Float = 0.026

    var onSelect: ((String) -> Void)?
    var onPause: (() -> Void)?
    var onReset: (() -> Void)?

    init(moduleIDs: [String], accents: [String: UIColor]) {
        buildBead()
        for id in moduleIDs {
            let holder = Entity()
            holder.name = "palette-\(id)"

            // The lab's OWN miniature, running. A switcher that shows
            // the physics is a switcher you can read without labels.
            let built = HubVignettes.make(for: id)
            let bounds = built.entity.visualBounds(relativeTo: nil).extents
            let largest = max(bounds.x, max(bounds.y, 1e-4))
            built.entity.scale = SIMD3(repeating: Self.slotSize / largest)
            holder.addChild(built.entity)

            // A faint accent disc behind it, so a slot reads as a target.
            var backing = UnlitMaterial(color: accents[id] ?? .white)
            backing.blending = .transparent(opacity: 0.11)
            let disc = ModelEntity(
                mesh: .generateCylinder(height: 0.002, radius: Self.slotSize * 0.78),
                materials: [backing])
            disc.orientation = simd_quatf(angle: .pi / 2, axis: [1, 0, 0])
            disc.position.z = -Self.slotSize * 0.55
            holder.addChild(disc)

            holder.components.set(InputTargetComponent())
            holder.components.set(CollisionComponent(
                shapes: [.generateSphere(radius: Self.slotSize * 0.8)]))
            holder.components.set(HoverEffectComponent())
            var accessibility = AccessibilityComponent()
            accessibility.isAccessibilityElement = true
            accessibility.label = LocalizedStringResource(stringLiteral: "Open \(id)")
            holder.components.set(accessibility)
            holder.isEnabled = false
            root.addChild(holder)
            slots.append((id, holder, built.animate))
        }

        petals = [
            Self.makePetal(name: "pause", symbol: "pause.fill"),
            Self.makePetal(name: "reset", symbol: "arrow.counterclockwise"),
        ]
        petals.forEach { root.addChild($0) }
    }

    /// Where the bead lives, in the host's coordinates.
    func place(at position: SIMD3<Float>) {
        root.position = position
    }

    func update(dt: Double, viewer: SIMD3<Float>?) {
        time += dt
        self.viewer = viewer

        let target: Float = isOpen ? 1 : 0
        let rate = Float(min(dt * 8, 1))
        openness += (target - openness) * rate
        if abs(openness - target) < 0.004 { openness = target }

        // The bead breathes when closed and recedes when open — it has
        // handed its job to the ring.
        let breath = 1 + 0.05 * Float(sin(time * 1.6))
        bead.scale = SIMD3(repeating: breath * (1 - 0.45 * openness))

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
            let side: Float = index == 0 ? -1 : 1
            petal.position = SIMD3(side * 0.085 * own, -0.135 * own, 0)
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
        root.addChild(bead)
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
    @State private var palette: Palette?

    var body: some View {
        RealityView { content in
            let modules = ModuleCatalog.all(appModel: appModel)
            var accents: [String: UIColor] = [:]
            for entry in modules { accents[entry.id] = UIColor(entry.accent) }
            let made = Palette(moduleIDs: modules.map(\.id), accents: accents)
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
    }
}
