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
    @State private var bloom = Bloom()
    /// Which magnet's ring is open — shared by the tap gesture and the
    /// render loop (see RingState's header for why it's a reference).
    @State private var ring = RingState()
    @State private var wells: Well?
    /// Two-hand scale and turn: grow the dipole field from a desk demo
    /// to loops you stand inside, or turn the whole field to see it
    /// side-on. A pure view transform — the tesla stay honest.
    @State private var scaleRig = SpatialScaleRig(
        pivot: SIMD3<Float>(MagnetismModel.regionCenter), range: 0.5...4.0)
    /// What is drawn, and whether the magnets are free.
    ///
    /// FOUR plates — field lines, hand compass, Earth's field, and the
    /// dynamics switch. (The compass-grid plate came off with the grid
    /// on 2026-08-03; `-magLayers 0` reaches three of these four —
    /// `earthFieldOn` has no argument.)
    /// The top one is not a display layer: `dynamicsOn` decides whether
    /// the magnets glide together and swing into alignment at all, which
    /// is the difference between a field diagram and a physics lab. It
    /// takes the top plate and a label that says what it does, because a
    /// bank whose plates all mean "draw this" plus one that means "run
    /// the simulation" has to admit the difference somewhere.
    @State private var layers: SpatialLayerBank?

    /// Beside the magnets, at the region's own depth — on the LEFT,
    /// like every other module's switch bank (owner, 2026-08-04: the
    /// side buttons live on the left everywhere; this was the one bank
    /// off the right shoulder).
    ///
    /// NOT under `viewRoot`: the scale rig reaches 4×, and a switch bank
    /// that grew fourfold with the field would push its own plates out of
    /// reach exactly when you had zoomed in to look at something. The
    /// well and the blooms belong to the field and DO scale with it; an
    /// instrument belongs to the room.
    private static let bankAnchor = SIMD3<Float>(MagnetismModel.regionCenter)
        + SIMD3(-0.80, 0.10, 0.08)

    var body: some View {
        RealityView { content in
            let renderer = MagnetismRenderer()
            content.add(renderer.root)

            let sources = Well([
                .init(name: "Magnet",
                      tint: UIColor(DesignTokens.Palette.magnetismAccent),
                      label: "Add magnet",
                      preview: { MagnetismRenderer.magnetPreview() },
                      position: SIMD3<Float>(MagnetismModel.regionCenter)
                          + SIMD3(-0.72, -0.20, 0.34),
                      spawn: { point in model.addMagnet(at: point) }),
            ])
            renderer.viewRoot.addChild(sources.root)
            renderer.viewRoot.addChild(bloom.root)
            wells = sources

            let bank = SpatialLayerBank(
                accent: UIColor(DesignTokens.Palette.magnetismAccent),
                layers: [
                    .init(id: "dynamics", label: "Magnets move",
                          symbol: "arrow.triangle.merge",
                          isOn: { model.dynamicsOn },
                          toggle: { model.dynamicsOn.toggle() }),
                    .init(id: "lines", label: "Field lines", symbol: "scribble",
                          isOn: { model.showFieldLines },
                          toggle: { model.showFieldLines.toggle() }),
                    .init(id: "handCompass", label: "Hand compass",
                          symbol: "location.north.circle",
                          isOn: { model.compassOn },
                          toggle: { model.compassOn.toggle() }),
                    // The fifth: whether the room is standing on a
                    // planet. Switching it off is the comparison — the
                    // compasses stop knowing which way is north and go
                    // back to reading only the bench.
                    .init(id: "earth", label: "Earth's field",
                          symbol: "globe",
                          isOn: { model.earthFieldOn },
                          toggle: { model.earthFieldOn.toggle() }),
                ])
            renderer.root.addChild(bank.root)
            layers = bank

            renderer.subscriptions.append(
                content.subscribe(to: SceneEvents.Update.self) { [weak renderer] event in
                    if let renderer { scaleRig.apply(to: renderer.viewRoot) }
                    wells?.update(dt: event.deltaTime)
                    layers?.update(
                        anchor: Self.bankAnchor,
                        viewer: appModel.room.headPosition.map { SIMD3<Float>($0) },
                        dt: event.deltaTime)
                    if let renderer {
                        syncBloom(renderer: renderer, dt: event.deltaTime)
                    }
                    model.step(dt: event.deltaTime)
                    renderer?.tick(model, viewer: appModel.room.headPosition.map {
                        renderer?.displayPoint(fromWorld: SIMD3<Float>($0)) ?? $0
                    })
                    // The lab's placement in the user's room — a pure
                    // display offset, safe because every grab in this app
                    // moves a body by hand DISPLACEMENT, which a constant
                    // translation leaves untouched.
                    renderer?.root.position = appModel.labPlacement.offset
                    // …AND THE INSTRUMENTS GO WITH IT. Every bank, rail,
                    // well and ring in this module is a child of
                    // `renderer.root`, so they ride the same offset the
                    // apparatus does.
                    //
                    // This comment said the opposite until 2026-08-03 —
                    // "the control pods do NOT go with it: the user
                    // parked them where they wanted them" — in all four
                    // modules that carry it, and it was false in all
                    // four. There are no pods; the instruments were
                    // reparented onto the apparatus when the panels died,
                    // and travelling with it is the RIGHT behaviour: a
                    // rail belongs to the thing it sets. Left standing,
                    // the sentence would eventually persuade somebody to
                    // "fix" a counter-translation back in.
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
            #if DEBUG
            // `-magRing 1` opens the first magnet's control ring at
            // launch, so the ring can be screenshot from the CLI.
            if UserDefaults.standard.bool(forKey: "magRing"),
               let first = model.magnets.first {
                ring.openID = first.id
            }
            // `-magLayers 0` darkens every plate on the bank, so one shot
            // shows the lamps OFF against the labels — the only way to
            // check the dark state, since the scene opens with several
            // already lit and the simulator has no finger to flick them
            // with. (`earthFieldOn` still has no argument.)
            if UserDefaults.standard.object(forKey: "magLayers") != nil,
               !UserDefaults.standard.bool(forKey: "magLayers") {
                model.showFieldLines = false
                model.compassOn = false
                model.dynamicsOn = false
            }
            #endif
            renderer.tick(model, viewer: appModel.room.headPosition)
            self.renderer = renderer
        }
        .spatialScale(scaleRig)
        .simultaneousGesture(
            TapGesture()
                .targetedToAnyEntity()
                .onEnded { value in
                    // The bank gets first refusal, ahead of the
                    // fall-through that folds the ring away — otherwise
                    // flicking a switch would also close whichever
                    // magnet's ring was open.
                    if layers?.handleTap(value.entity) == true { return }
                    if bloom.handleTap(value.entity) { return }
                    // A tap on a magnet toggles its control ring; a tap
                    // on anything else folds it away.
                    var current: Entity? = value.entity
                    while let candidate = current {
                        if let id = UUID(uuidString: candidate.name),
                           model.magnets.contains(where: { $0.id == id }) {
                            if ring.openID == id {
                                ring.openID = nil
                            } else {
                                ring.openID = id
                                SoundPalette.play(.pop, on: value.entity, volume: 0.35)
                            }
                            return
                        }
                        current = candidate.parent
                    }
                    ring.openID = nil
                }
        )
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
                    if bloom.updateGrip(hand: SIMD3<Float>(hand)) { return }
                    if drag == nil {
                        if bloom.beginGrip(value.entity, hand: SIMD3<Float>(hand)) { return }
                        if let id = wells?.pull(value.entity, at: hand) {
                            drag = RelativeDrag(name: id.uuidString,
                                                target: hand, hand: hand)
                            return
                        }
                        drag = beginDrag(entity: value.entity, hand: hand)
                    }
                    guard let drag else { return }
                    if drag.name == MagnetismRenderer.handCompassName {
                        model.moveCompass(to: drag.position(forHand: hand))
                    } else if let id = UUID(uuidString: drag.name) {
                        model.move(id: id, to: drag.position(forHand: hand))
                    }
                }
                .onEnded { _ in
                    bloom.endGrip()
                    model.release()
                    drag = nil
                }
        )
    }

    /// Tap a magnet and it offers exactly what a magnet offers:
    /// reverse its poles, remove it, or pull its strength up — and the
    /// field loops thicken and reach further as you pull, which is the
    /// only readout that matters.
    private func syncBloom(renderer: MagnetismRenderer, dt: Double) {
        if let openID = ring.openID,
           !model.magnets.contains(where: { $0.id == openID }) {
            ring.openID = nil     // deleted out from under the ring
        }
        guard let uuid = ring.openID,
              let magnet = model.magnets.first(where: { $0.id == uuid }) else {
            bloom.update(anchor: .zero, viewer: nil, revealTarget: 0, dt: dt)
            bloom.clearTarget()
            return
        }

        bloom.retarget(
            uuid,
            petals: [
                .init(name: "Flip poles", symbol: "arrow.triangle.2.circlepath",
                      tint: UIColor(white: 0.45, alpha: 1)) {
                    model.flipMagnet(id: uuid)
                },
                .init(name: "Delete", symbol: "trash",
                      tint: UIColor(red: 0.85, green: 0.25, blue: 0.25, alpha: 1)) {
                    model.removeMagnet(id: uuid)
                },
            ],
            grip: .init(
                name: "Strength",
                range: MagnetismModel.strengthRange,
                read: { model.strength(id: uuid) },
                write: { model.setStrength(id: uuid, $0) },
                format: { String(format: "%.1f A\u{00B7}m\u{00B2}", $0) },
                radius: { Float(MagnetismModel.magnetLength) * 0.6 }))

        let viewer = appModel.room.headPosition.map {
            renderer.viewRoot.convert(position: SIMD3<Float>($0), from: nil)
        }
        bloom.update(anchor: SIMD3<Float>(magnet.position),
                     viewer: viewer, revealTarget: 1, dt: dt)
    }

    private func beginDrag(entity: Entity, hand: SIMD3<Double>) -> RelativeDrag? {
        var current: Entity? = entity
        while let candidate = current {
            if candidate.name == MagnetismRenderer.handCompassName {
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
