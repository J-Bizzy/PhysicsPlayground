//
//  MagnetismSpaceView.swift
//  Physics Playground — Magnetism module
//
//  The magnetism immersive scene. RealityView installs the renderer and
//  the control pods; from then on the model steps and the renderer ticks
//  every frame from SceneEvents.Update. A magnet is grabbed by its UUID
//  name and moved by the hand's displacement (relative drag) — while it's
//  held the model freezes it and lets every other magnet respond.
//

import PhysicsCore
import SwiftUI
import RealityKit
import RenderKit

struct MagnetismSpaceView: View {
    @Environment(MagnetismModel.self) private var model
    @Environment(AppModel.self) private var appModel
    @State private var renderer: MagnetismRenderer?
    @State private var drag: RelativeDrag?
    /// Two-hand scale and turn: grow the dipole field from a desk demo
    /// to loops you stand inside, or turn the whole field to see it
    /// side-on. A pure view transform — the tesla stay honest.
    @State private var scaleRig = SpatialScaleRig(
        pivot: SIMD3<Float>(MagnetismModel.regionCenter), range: 0.5...4.0)

    var body: some View {
        RealityView { content in
            let renderer = MagnetismRenderer()
            content.add(renderer.root)

            renderer.subscriptions.append(
                content.subscribe(to: SceneEvents.Update.self) { [weak renderer] event in
                    if let renderer { scaleRig.apply(to: renderer.viewRoot) }
                    model.step(dt: event.deltaTime)
                    // The cross-module link: whatever current the
                    // CIRCUIT bench's inductor is carrying right now is
                    // the current in this coil. Build a loop over there,
                    // open its switch, and the electromagnet here dies.
                    if model.electromagnetOn {
                        model.setCoilCurrent(appModel.circuitsModel.inductorCurrent)
                    }
                    renderer?.tick(model, viewer: appModel.room.headPosition.map {
                        renderer?.displayPoint(fromWorld: SIMD3<Float>($0)) ?? $0
                    }, lookRay: appModel.room.lookRay)
                    // The lab's placement in the user's room — a pure
                    // display offset, safe because every grab in this app
                    // moves a body by hand DISPLACEMENT, which a constant
                    // translation leaves untouched.
                    renderer?.root.position = appModel.labPlacement.offset
                    // …but the control pods do NOT go with it: the user
                    // parked them where they wanted them, and moving the
                    // apparatus is not a request to move the controls.
                }
            )
            #if DEBUG
            // `-viewScale 2.5` bakes a committed scale in at launch, so
            // the scaled view can be screenshot-verified from the CLI —
            // the simulator has no second hand to pinch with.
            // double(forKey:) coerces the string the launch-argument
            // domain actually stores; `object as? Double` does not.
            let forced = UserDefaults.standard.double(forKey: "viewScale")
            if forced > 0 {
                scaleRig.updateMagnification(Float(forced))
                scaleRig.endGesture()
            }
            #endif
            renderer.tick(model, viewer: appModel.room.headPosition)
            self.renderer = renderer
        }
        .spatialScale(scaleRig)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .targetedToAnyEntity()
                .onChanged { value in
                    guard let renderer else { return }
                    // Through the scaled root: at 3× a hand moving a
                    // metre moves a magnet a third of one, so what you
                    // hold stays under your fingers at every scale.
                    let hand = renderer.displayPoint(fromWorld: SIMD3<Float>(value.convert(
                        value.location3D, from: .local, to: .scene)))
                    if drag == nil {
                        drag = beginDrag(entity: value.entity, hand: hand)
                    }
                    guard let drag else { return }
                    if drag.name == MagnetismRenderer.electromagnetName {
                        model.moveElectromagnet(to: drag.position(forHand: hand))
                    } else if drag.name == MagnetismRenderer.handCompassName {
                        model.moveCompass(to: drag.position(forHand: hand))
                    } else if let id = UUID(uuidString: drag.name) {
                        model.move(id: id, to: drag.position(forHand: hand))
                    }
                }
                .onEnded { _ in
                    model.release()
                    renderer?.isCarryingCompass = false
                    renderer?.isCarryingCoil = false
                    drag = nil
                }
        )
    }

    private func beginDrag(entity: Entity, hand: SIMD3<Double>) -> RelativeDrag? {
        var current: Entity? = entity
        while let candidate = current {
            if candidate.name == MagnetismRenderer.electromagnetName {
                renderer?.isCarryingCoil = true
                return RelativeDrag(name: candidate.name,
                                    target: model.electromagnetPosition, hand: hand)
            }
            if candidate.name == MagnetismRenderer.handCompassName {
                renderer?.isCarryingCompass = true
                return RelativeDrag(name: candidate.name,
                                    target: model.compassPosition, hand: hand)
            }
            if let id = UUID(uuidString: candidate.name),
               let magnet = model.magnets.first(where: { $0.id == id }) {
                model.grab(id: id)
                return RelativeDrag(name: candidate.name, target: magnet.position, hand: hand)
            }
            current = candidate.parent
        }
        return nil
    }
}
