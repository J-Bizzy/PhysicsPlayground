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
//  Both benches are therefore always in the room, always live, always
//  running their own solver every frame. What changed is that one of
//  them is FOCUSED: lit, with its panel section open, while the other
//  stands back at StationEmphasis.dimFloor. That is emphasis, not a
//  picker, and the difference is four properties enforced elsewhere —
//  see StationFocus's header, which is where the contract lives.
//
//  The routing below is where two of those four are kept: focus follows
//  the hands and NEVER consumes the gesture that moved it, so a drag
//  beginning on a dim magnet moves the magnet rather than merely
//  brightening it; and the tick runs both solvers regardless of which
//  one you are looking at.
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
            let focus = appModel.emFocus

            bench.install(into: content)
            field.install(into: content)
            // The cable belongs to neither station's frame, so it hangs
            // at the scene root and is given scene-space endpoints.
            content.add(feed.root)

            focus.register(.bench)
            focus.register(.field)

            #if DEBUG
            // `-emLink 1` stages the world's whole point — a driven
            // coil with the cable running to it — at launch. The
            // simulator has no hands to wire an inductor with, so
            // without this the one thing worth looking at in this
            // module cannot be screenshot from the CLI at all.
            if UserDefaults.standard.bool(forKey: "emLink") {
                Self.stageDrivenCoil(circuits: circuits, magnetism: magnetism)
            }
            // `-focusStation field` commits the focus at launch, for the
            // same reason: the simulator has no hands to attend with,
            // and `snap()` lands on the settled emphasis so the frame
            // that gets captured is not mid-fade.
            if let name = UserDefaults.standard.string(forKey: "focusStation"),
               let station = EMStation(rawValue: name) {
                focus.focus(station)
                focus.snap()
            }
            #endif

            subscription = content.subscribe(to: SceneEvents.Update.self) { event in
                Self.tick(dt: event.deltaTime, bench: bench, field: field,
                          feed: feed, focus: focus, appModel: appModel)
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
                    case .bench:
                        attend(.bench)
                        _ = bench?.handleTap(value.entity)
                    case .field:
                        attend(.field)
                        _ = field?.handleTap(value.entity)
                    // A tap on the cable, the room, or nothing at all
                    // folds both benches' rings away — the same "you
                    // tapped elsewhere" each module meant on its own.
                    // It does NOT move focus: attention should follow
                    // what you touched, and you touched neither.
                    case nil:
                        _ = bench?.handleTap(value.entity)
                        _ = field?.handleTap(value.entity)
                    default: break
                    }
                }
        )
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .targetedToAnyEntity()
                .onChanged { value in
                    switch station(owning: value.entity) {
                    // Focused AND forwarded, in that order and in the
                    // same event. Focusing without forwarding would
                    // make a dim station cost an extra gesture to use,
                    // and a station that is harder to use is a picker
                    // wearing a dimmer's clothes.
                    case .bench:
                        attend(.bench)
                        bench?.dragChanged(value)
                    case .field:
                        attend(.field)
                        field?.dragChanged(value)
                    case nil: break
                    default: break
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

    // MARK: Focus

    /// Attend to a station because the hands went there. Idempotent, so
    /// the sixty of these a drag sends per second cost nothing.
    private func attend(_ station: EMStation) {
        appModel.emFocus.focus(station)
    }

    // MARK: Routing

    /// Every rig in the scene — the sweep a finished gesture is ended
    /// on, so none is left stuck mid-pinch.
    private var rigs: [SpatialScaleRig] {
        [bench?.scaleRig, field?.scaleRig].compactMap { $0 ?? nil }
    }

    /// Which station owns the entity a gesture landed on, found by
    /// walking up to whichever station root it sits beneath.
    private func station(owning entity: Entity) -> EMStation? {
        if let bench, entity.isDescendant(of: bench.root) { return .bench }
        if let field, entity.isDescendant(of: field.root) { return .field }
        return nil
    }

    private func rig(forEntity entity: Entity) -> SpatialScaleRig? {
        switch station(owning: entity) {
        case .bench: bench?.scaleRig ?? nil
        case .field: field?.scaleRig ?? nil
        default: nil
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
        feed: EMFeedLine, focus: StationFocus<EMStation>, appModel: AppModel
    ) {
        // PROPERTY 1 of the focus contract: both stations solve every
        // frame, whichever one is being attended to. Skipping the dim
        // one's solver is forbidden — it is the cheap performance fix
        // that would quietly turn this back into a picker. If frames
        // get tight, cut an unfocused station's VISUAL work instead.
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

        // Emphasis last, so it lands on this frame's scene. Opacity
        // only — never a transform: a station receding mid-drag would
        // slide the held body out from under the fingers.
        focus.tick(dt: dt)
        focus.apply(.bench, to: bench.root)
        focus.apply(.field, to: field.root)
    }
}
