//
//  EMWorldSpaceView.swift
//  Physics Playground — Electricity & Magnetism
//
//  The merged E&M world: a circuit bench on your left, a magnetic
//  field on your right, and a cable between them carrying the bench's
//  current to a coil standing in the field.
//
//  ONE RealityView, ONE update tick, and gestures ROUTED by whichever
//  station owns the entity the hands landed on. That routing is the
//  whole trick, and the reason this is a merge rather than a picker.
//  The catalog still carries the scar of the last attempt (see
//  ModuleDescriptor's header): Fields and Oscillators were merged once
//  before, each hiding its second bench behind a picker that lived only
//  in the window's control panel — and by then the app's controls had
//  moved into spatial pods, so the second half of each module was
//  effectively unreachable and both mergers were undone.
//
//  So there is no picker here and nothing to switch between. Both
//  benches are in the room, both are live, both are running their own
//  solver every frame. Turn your head.
//

import PhysicsCore
import SwiftUI
import RealityKit
import RenderKit

struct EMWorldSpaceView: View {
    @Environment(CircuitsModel.self) private var circuits
    @Environment(MagnetismModel.self) private var magnetism
    @Environment(AppModel.self) private var appModel

    @State private var bench: EMBenchStation?
    @State private var field: EMFieldStation?
    @State private var feed: EMFeedLine?
    @State private var subscription: EventSubscription?

    var body: some View {
        RealityView { content in
            let bench = EMBenchStation(model: circuits)
            let field = EMFieldStation(model: magnetism)
            let feed = EMFeedLine()

            bench.install(into: content)
            field.install(into: content)
            // The cable belongs to neither station's frame, so it hangs
            // at the scene root and is given scene-space endpoints.
            content.add(feed.root)

            #if DEBUG
            // `-emLink 1` stages the world's whole point — a driven
            // coil with the cable running to it — at launch. The
            // simulator has no hands to wire an inductor with, so
            // without this the one thing worth looking at in this
            // module cannot be screenshot from the CLI at all.
            if UserDefaults.standard.bool(forKey: "emLink") {
                Self.stageDrivenCoil(circuits: circuits, magnetism: magnetism)
            }
            #endif

            subscription = content.subscribe(to: SceneEvents.Update.self) { event in
                Self.tick(dt: event.deltaTime, bench: bench, field: field,
                          feed: feed, appModel: appModel)
            }

            self.bench = bench
            self.field = field
            self.feed = feed
        }
        // Routed, not stacked: `spatialScale(_:)` targets any entity, so
        // two of them here would zoom the bench and the magnets together
        // on every two-handed pinch.
        .spatialScale(rigs: rigs, routing: rig(forEntity:))
        .simultaneousGesture(
            TapGesture()
                .targetedToAnyEntity()
                .onEnded { value in
                    switch station(owning: value.entity) {
                    case .bench: _ = bench?.handleTap(value.entity)
                    case .field: _ = field?.handleTap(value.entity)
                    // A tap on the cable, the room, or nothing at all
                    // folds both benches' rings away — the same "you
                    // tapped elsewhere" each module meant on its own.
                    case nil:
                        _ = bench?.handleTap(value.entity)
                        _ = field?.handleTap(value.entity)
                    }
                }
        )
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .targetedToAnyEntity()
                .onChanged { value in
                    switch station(owning: value.entity) {
                    case .bench: bench?.dragChanged(value)
                    case .field: field?.dragChanged(value)
                    case nil: break
                    }
                }
                .onEnded { value in
                    // Ended goes to BOTH regardless of where the hand
                    // finished. A drag that begins on a magnet and ends
                    // over the bench must still release the magnet, and
                    // each station's end-handler is a no-op when it has
                    // no drag in flight.
                    bench?.dragEnded(value)
                    field?.dragEnded(value)
                }
        )
    }

    // MARK: Routing

    private enum Which { case bench, field }

    /// Every rig in the scene — the sweep a finished gesture is ended
    /// on, so none is left stuck mid-pinch.
    private var rigs: [SpatialScaleRig] {
        [bench?.scaleRig, field?.scaleRig].compactMap { $0 }
    }

    /// Which station owns the entity a gesture landed on, found by
    /// walking up to whichever station root it sits beneath.
    private func station(owning entity: Entity) -> Which? {
        if let bench, entity.isDescendant(of: bench.root) { return .bench }
        if let field, entity.isDescendant(of: field.root) { return .field }
        return nil
    }

    private func rig(forEntity entity: Entity) -> SpatialScaleRig? {
        switch station(owning: entity) {
        case .bench: bench?.scaleRig
        case .field: field?.scaleRig
        case nil: nil
        }
    }

    #if DEBUG
    /// Builds a battery–switch–inductor–bulb loop and switches the
    /// electromagnet on, so the feed line has both ends it needs.
    private static func stageDrivenCoil(
        circuits: CircuitsModel, magnetism: MagnetismModel
    ) {
        circuits.clearBench()
        circuits.add(.battery)
        circuits.add(.switcher)
        circuits.add(.inductor)
        circuits.add(.bulb)
        let parts = circuits.components
        guard parts.count == 4 else { return }
        // Tap terminal-to-terminal round the ring, closing on the
        // battery it started from.
        let ring = [(0, 1), (1, 0), (1, 1), (2, 0), (2, 1), (3, 0), (3, 1), (0, 0)]
        for (part, end) in ring {
            circuits.tapTerminal(.init(componentID: parts[part].id, end: end))
        }
        magnetism.electromagnetOn = true
    }
    #endif

    // MARK: The single tick

    /// Both solvers, the cable, and the link between them — in one
    /// place, in a fixed order, once per frame.
    private static func tick(
        dt: Double, bench: EMBenchStation, field: EMFieldStation,
        feed: EMFeedLine, appModel: AppModel
    ) {
        bench.tick(dt: dt, appModel: appModel)
        // The bench solves BEFORE the coil reads it, so the current the
        // electromagnet gets is this frame's, not last frame's. Across
        // a module boundary that ordering was unknowable; here it is
        // just two lines in the right order.
        let current = bench.model.inductorCurrent
        field.tick(dt: dt, appModel: appModel, coilCurrent: current)
        feed.update(
            benchLeads: bench.inductorLeads,
            coilLeads: field.coilLeads,
            current: current,
            speed: CircuitsRenderer.electronDisplaySpeed(
                current: current, model: bench.model),
            isPaused: bench.model.isPaused,
            dt: dt)
    }
}
