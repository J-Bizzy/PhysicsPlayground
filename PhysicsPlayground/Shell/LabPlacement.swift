//
//  LabPlacement.swift
//  Physics Playground — Shell
//
//  Put the lab where you have room: one grabbable anchor, one offset,
//  applied to the active module's display root. A pure display
//  translation, safe because every physics object is dragged by relative
//  hand displacement, which is invariant under a constant translation.
//  Remembered per module across launches.
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
        // Flush before switching: a pending debounced write would file the old
        // lab's offset under the new lab's key.
        persistNow()
        self.moduleID = moduleID
        isPlacing = false
        if let saved = UserDefaults.standard.array(forKey: Self.key(moduleID)) as? [Double],
           saved.count == 3 {
            offset = SIMD3(Float(saved[0]), Float(saved[1]), Float(saved[2]))
        } else {
            offset = .zero
        }
        #if DEBUG
        // `-labShift <metres>` slides the lab that far to the right for one
        // launch, unsaved, so what stands off the left shoulder — the wells —
        // comes into the simulator's view (positive only: a value starting
        // with "-" is read as the next key).
        let shift = UserDefaults.standard.double(forKey: "labShift")
        if shift > 0 { offset.x += Float(shift) }
        #endif
    }

    func move(to newOffset: SIMD3<Float>) {
        // Far enough to clear the furniture, not so far the apparatus ends up
        // next door.
        offset = simd_clamp(newOffset, SIMD3(-2, -0.9, -2.5), SIMD3(2, 0.9, 1.2))
        // Debounced: this runs once per frame for the length of a placement
        // drag.
        persistSoon()
    }

    /// The drag let go: write the final offset without waiting out the
    /// debounce, so quitting straight after a placement keeps it.
    func endMove() {
        persistNow()
    }

    func recentre() {
        offset = .zero
        persistNow()
    }

    @ObservationIgnored private var persistTask: Task<Void, Never>?

    /// Writes within a second of each other collapse into one.
    private func persistSoon() {
        persistTask?.cancel()
        persistTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            self?.persistNow()
        }
    }

    private func persistNow() {
        persistTask?.cancel()
        persistTask = nil
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
    /// How far this press has moved the anchor — a press that never
    /// moves it is a tap. See `onEnded`.
    @State private var travelled: Float = 0
    /// Whether the anchor has moved far enough to be carried, not tapped.
    @State private var carrying = false
    /// Held so it can be cancelled: the view is remounted per lab, and an
    /// uncancelled subscription accumulates one live closure per entry.
    @State private var subscription: EventSubscription?

    var body: some View {
        RealityView { content in
            let anchor = Self.makeAnchor(accent: UIColor(module.accent))
            root = anchor
            content.add(anchor)

            subscription = content.subscribe(
                to: SceneEvents.Update.self
            ) { [weak anchor] _ in
                guard let anchor else { return }
                anchor.isEnabled = appModel.labPlacement.isPlacing
                guard appModel.labPlacement.isPlacing else { return }
                anchor.position = Self.home + appModel.labPlacement.offset
            }
        }
        .onDisappear {
            subscription?.cancel()
            subscription = nil
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
                    let next = SIMD3<Float>(drag.position(forHand: hand))
                    // Against the drag's own start (`RelativeDrag.travel(forHand:)`), not
                    // `labPlacement.offset`, which the next line overwrites.
                    travelled = max(travelled, Float(drag.travel(forHand: hand)))
                    // Carried, not tapped, once it has moved: the glow and the
                    // tick every held thing answers a hand with.
                    if travelled >= Self.tapTravel, !carrying {
                        carrying = true
                        Grasp.take(root)
                    }
                    appModel.labPlacement.move(to: next)
                }
                // Recentre: a press on the cross-hair that never moves it. Folded into
                // this drag rather than a `TapGesture` because this view is a sibling
                // of every module's scene, and a tap recogniser here would win over
                // every module's own instrument taps.
                .onEnded { _ in
                    if carrying { Grasp.letGo(root) }
                    carrying = false
                    if drag != nil, travelled < Self.tapTravel {
                        appModel.labPlacement.recentre()
                        // The whole lab moves home: heard, not only seen.
                        SoundPalette.play(.pop, on: root, volume: 0.4)
                    } else if drag != nil {
                        // Final: write it now rather than leaving it in the debounce window.
                        appModel.labPlacement.endMove()
                    }
                    drag = nil
                    travelled = 0
                }
        )
    }

    /// How far a press may wander and still count as a tap, metres.
    /// A hand held still in mid-air drifts a few millimetres.
    private static let tapTravel: Float = 0.012

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

    /// Internal so `ColliderCriterionTests` can build the puck and measure it.
    static func makeAnchor(accent: UIColor) -> Entity {
        let anchor = Entity()
        anchor.name = "lab-anchor"
        anchor.position = home

        var glass = PhysicallyBasedMaterial()
        glass.baseColor = .init(tint: .white)
        glass.roughness = 0.1
        glass.clearcoat = .init(floatLiteral: 1.0)
        glass.blending = .transparent(opacity: .init(floatLiteral: 0.35))
        let puck = ModelEntity(
            mesh: Primitives.cylinder(height: 0.016, radius: 0.075),
            materials: [glass])
        anchor.addChild(puck)

        // A cross-hair in the module's accent: a placement tool, not a physics
        // object.
        for axis in [SIMD3<Float>(1, 0, 0), SIMD3<Float>(0, 0, 1)] {
            let bar = ModelEntity(
                mesh: Primitives.box(size: [0.13, 0.004, 0.007], cornerRadius: 0.002),
                materials: [Materials.energized(accent, glow: 0.5)])
            // The first bar aims [1,0,0] at itself, the degenerate parallel case.
            bar.orientation = rotation(from: [1, 0, 0], to: axis)
            bar.position.y = 0.011
            anchor.addChild(bar)
        }

        // A puck is a disc: the collider matches the visual, not a sphere stood
        // proud of it.
        Grabbable.configureTouchTarget(anchor, matchingVisualBoundsOf: anchor)
        // The default gaze highlight was invisible on device; an explicit bright
        // highlight says the pinch will land.
        anchor.components.set(HoverEffectComponent(.highlight(.init(
            color: accent, strength: 0.6))))
        SpatialActions.describe(
            anchor, label: "Lab anchor. Drag it to move the whole lab to where you have room.")
        anchor.isEnabled = false
        return anchor
    }
}
