//
//  LabPlacement.swift
//  Physics Playground — Shell
//
//  Put the lab where you actually have room.
//
//  Every module's apparatus is pinned to hard-coded immersive-space
//  coordinates — the beam at (0, 2.1, −1.1), the spring rail at
//  (0, 1.15, −0.85), the wave region at (0, 1.4, −0.6). Those numbers
//  were chosen in front of a desk, and in a real room they land the
//  apparatus in the sofa, through the coffee table, or half inside a
//  wall. The app had no way to say "not there, HERE".
//
//  So: one grabbable anchor, one offset, applied to the active module's
//  display root. It is a pure display translation, which is exactly why
//  it is safe: every physics object in this app is dragged by RELATIVE
//  hand displacement (RenderKit's RelativeDrag moves a body by how far
//  the hand moved, never by where the hand is), and a relative
//  displacement is invariant under a constant translation. So the lab
//  can sit anywhere without a single line of grab-handling code
//  changing, and without the simulation knowing it moved.
//
//  Per module, remembered across launches, because where the wave field
//  belongs in your room is not where the circuit bench belongs.
//

import RealityKit
import RenderKit
import SwiftUI
import simd

@MainActor
@Observable
final class LabPlacement {
    /// The live offset for the active module.
    private(set) var offset: SIMD3<Float> = .zero
    /// True while the anchor is on screen and being positioned.
    var isPlacing = false

    private var moduleID: String?

    private static func key(_ moduleID: String) -> String { "labOffset.\(moduleID)" }

    /// Loads the saved offset when a module opens.
    func adopt(moduleID: String) {
        guard moduleID != self.moduleID else { return }
        self.moduleID = moduleID
        isPlacing = false
        if let saved = UserDefaults.standard.array(forKey: Self.key(moduleID)) as? [Double],
           saved.count == 3 {
            offset = SIMD3(Float(saved[0]), Float(saved[1]), Float(saved[2]))
        } else {
            offset = .zero
        }
    }

    func move(to newOffset: SIMD3<Float>) {
        // A generous but bounded reach: far enough to clear the
        // furniture, not so far the apparatus ends up in next door.
        offset = simd_clamp(newOffset, SIMD3(-2, -0.9, -2.5), SIMD3(2, 0.9, 1.2))
        persist()
    }

    func recentre() {
        offset = .zero
        persist()
    }

    private func persist() {
        guard let moduleID else { return }
        UserDefaults.standard.set(
            [Double(offset.x), Double(offset.y), Double(offset.z)],
            forKey: Self.key(moduleID))
    }
}

/// The anchor: a glass puck with a cross-hair that appears while
/// placing, and the one thing the user drags to move the whole lab.
struct LabAnchorView: View {
    let module: ModuleDescriptor

    @Environment(AppModel.self) private var appModel
    @State private var root = Entity()
    @State private var drag: RelativeDrag?

    var body: some View {
        RealityView { content in
            let anchor = Self.makeAnchor(accent: UIColor(module.accent))
            root = anchor
            content.add(anchor)

            _ = content.subscribe(to: SceneEvents.Update.self) { _ in
                anchor.isEnabled = appModel.labPlacement.isPlacing
                guard appModel.labPlacement.isPlacing else { return }
                anchor.position = Self.home + appModel.labPlacement.offset
            }
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .targetedToAnyEntity()
                .onChanged { value in
                    guard appModel.labPlacement.isPlacing else { return }
                    guard Self.isAnchor(value.entity) else { return }
                    let hand = SIMD3<Double>(SIMD3<Float>(value.convert(
                        value.location3D, from: .local, to: .scene)))
                    if drag == nil {
                        drag = RelativeDrag(
                            name: "lab-anchor",
                            target: SIMD3<Double>(appModel.labPlacement.offset),
                            hand: hand)
                    }
                    guard let drag else { return }
                    appModel.labPlacement.move(
                        to: SIMD3<Float>(drag.position(forHand: hand)))
                }
                .onEnded { _ in drag = nil }
        )
        // RECENTRE, which used to be a button on a strip under the
        // module's title bar. That strip is gone with the rest of the
        // window's furniture (DECISIONS.md, 2026-08-01), and its other
        // button — "Done" — went with it as pure duplication: the
        // title-bar control TOGGLES `isPlacing`, so pressing it again
        // has always been Done.
        //
        // Recentre was not duplicated anywhere, so it lands on the
        // object it acts on. The cross-hair only exists while you are
        // placing the lab, which makes it the one affordance that is
        // present exactly when this verb is meaningful.
        .simultaneousGesture(
            TapGesture()
                .targetedToAnyEntity()
                .onEnded { value in
                    guard appModel.labPlacement.isPlacing,
                          Self.isAnchor(value.entity) else { return }
                    appModel.labPlacement.recentre()
                }
        )
    }

    /// Where the anchor sits when the lab has not been moved — roughly
    /// where the apparatus lives, at a comfortable reaching height.
    static let home = SIMD3<Float>(0, 1.1, -0.8)

    private static func isAnchor(_ entity: Entity) -> Bool {
        var current: Entity? = entity
        while let candidate = current {
            if candidate.name == "lab-anchor" { return true }
            current = candidate.parent
        }
        return false
    }

    private static func makeAnchor(accent: UIColor) -> Entity {
        let anchor = Entity()
        anchor.name = "lab-anchor"
        anchor.position = home

        var glass = PhysicallyBasedMaterial()
        glass.baseColor = .init(tint: .white)
        glass.roughness = 0.1
        glass.clearcoat = .init(floatLiteral: 1.0)
        glass.blending = .transparent(opacity: .init(floatLiteral: 0.35))
        let puck = ModelEntity(
            mesh: .generateCylinder(height: 0.016, radius: 0.075),
            materials: [glass])
        anchor.addChild(puck)

        // A cross-hair in the module's accent: this is a PLACEMENT tool,
        // not another physics object.
        for axis in [SIMD3<Float>(1, 0, 0), SIMD3<Float>(0, 0, 1)] {
            let bar = ModelEntity(
                mesh: .generateBox(size: [0.13, 0.004, 0.007], cornerRadius: 0.002),
                materials: [Materials.energized(accent, glow: 0.5)])
            bar.orientation = simd_quatf(from: [1, 0, 0], to: axis)
            bar.position.y = 0.011
            anchor.addChild(bar)
        }

        Grabbable.configureTouchTarget(anchor, collisionRadius: 0.1)
        var accessibility = AccessibilityComponent()
        accessibility.isAccessibilityElement = true
        accessibility.label = "Lab anchor. Drag it to move the whole experiment to where you have room."
        anchor.components.set(accessibility)
        anchor.isEnabled = false
        return anchor
    }
}
