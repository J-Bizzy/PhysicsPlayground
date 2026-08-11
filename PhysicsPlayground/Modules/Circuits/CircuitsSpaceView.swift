//
//  CircuitsSpaceView.swift
//  Physics Playground — Circuits module
//
//  The circuit lab immersive scene. Component bodies are carried by a
//  `RelativeDrag` — the part moves by the hand's displacement, and the
//  model owns where it ends up. Terminals, wires and switch levers are
//  tap targets: pinch a terminal, then another, and they're wired;
//  pinch a wire to remove it; pinch a lever to flip it. The solver
//  clock is SceneEvents.Update.
//
//  (This said "route through RenderKit's ManipulationRouter" until
//  2026-08-03. They never did — nothing in the app ever used the
//  router, and it is deleted. See `Grabbable.swift` for why the system
//  component is the wrong shape here.)
//

import PhysicsCore
import SwiftUI
import RealityKit
import RenderKit

struct CircuitsSpaceView: View {
    @Environment(CircuitsModel.self) private var model
    @State private var renderer: CircuitsRenderer?
    @State private var bloom = Bloom()
    /// Which component's ring is open — shared by the tap gesture and
    /// the render loop (see RingState's header).
    @State private var ring = RingState()
    @State private var wireDragFrom: CircuitsModel.Terminal?
    @State private var partDrag: RelativeDrag?
    /// The part a pull off the palette just made, so the drag that made
    /// it can go on moving it. It outlives the `RelativeDrag`'s name,
    /// which for a new part is the well's, not a UUID.
    @State private var spawnedPartID: UUID?
    /// The parts palette: two blocks of sources on the flanks, one per
    /// component kind. See `CircuitsPartsLayout` for the geometry and
    /// for what it replaced.
    /// THE PARTS, VISIBLE AND ON THE RIGHT — see
    /// `CircuitsPartsLayout.rightSlot(index:)` for the geometry and for
    /// why the cabinet that briefly held them is gone.
    @State private var palette: Well?

    /// Which probe a hand is carrying, if either.
    @State private var probeDrag: CircuitsModel.ProbeSlot?
    /// Carrying the meter itself: where its case was when the hand closed
    /// on it, and where the hand was, both in the renderer's frame.
    @State private var meterDrag: (start: SIMD3<Float>, hand: SIMD3<Float>)?
    @State private var gripDrag: (grip: CircuitsModel.Terminal, pivot: SIMD3<Double>)?
    @Environment(AppModel.self) private var appModel
    /// Two-handed zoom on the bench. Electron View is now a FLOOR under
    /// this same number rather than a competing 1x/4x flip, so "get in
    /// among the electrons" and "pull the bench open with both hands"
    /// are one continuous control.
    @State private var scaleRig = SpatialScaleRig(
        pivot: CircuitsRenderer.benchPivot, range: 0.6...8.0, allowsTurn: false)
    /// The layers bank: which views of the current are switched on.
    ///
    /// It also finally gives ELECTRON VIEW a door. `model.electronView`
    /// has existed since the bench was written — it raises the zoom floor
    /// to 4x so the wires swell around you and the drifting electrons
    /// become things you stand among — and NOTHING in the app ever set it.
    /// It was reachable only by happening to pinch the bench open with two
    /// hands past 4x. The one view that kills the misconception this module
    /// exists to kill was hidden behind an accident.
    @State private var layers: SpatialLayerBank?
    /// The bench's meter — a tool, not a layer. See `Multimeter`.
    @State private var meter: Multimeter?
    /// The bench's one standing verb: clear it. See `clearAnchor`.
    @State private var verbs: SpatialActionBank?

    /// FIVE AUTHORED CIRCUITS THAT NOBODY COULD LOAD.
    ///
    /// `CircuitsModel.Preset` has five cases and `loadPreset` had ZERO
    /// callers — series bulbs, parallel bulbs, a voltage divider, an RC
    /// charger and a dead short, all compiled and unreachable. They were
    /// built for the window panel that was deleted on 2026-08-01 and
    /// never given a surface in the room. (Each also carried an authored
    /// paragraph explaining itself; those went with the insight card on
    /// 2026-08-09. The CIRCUITS are the teaching now — five real
    /// arrangements you can take apart.)
    ///
    /// Behind a `SummonHandle` because that type's own header names this
    /// exact case — "the things a room accumulates … a ten-preset fan" —
    /// and because five more standing plates in a lab the owner already
    /// called cluttered is not the trade. Folded it is one tab that
    /// reads out the last circuit loaded.
    @State private var presetsHandle = SummonHandle(
        title: "Presets", symbol: "square.grid.2x2",
        accent: UIColor(DesignTokens.Palette.circuitsAccent))
    @State private var presets: SpatialActionBank?
    /// What the handle reads out when folded.
    @State private var lastPreset: CircuitsModel.Preset?

    /// Identifies the floating readout above the selected part.
    private static let readoutCardID = "circuit-readout"

    /// Right of the bench, mirroring the layers bank on the left —
    /// where the meter STARTS. Where it ends up is the meter's own
    /// business once a hand has moved it (`Multimeter.anchor`). The
    /// two swapped flanks on 2026-08-04: the owner wants the side
    /// BUTTONS on the left in every module, and this bench was one of
    /// two that kept its bank off the right shoulder. The mirror
    /// layout survives, just handed.
    private static let meterAnchor = CircuitsRenderer.benchPivot
        + SIMD3<Float>(0.62, -0.03, 0.16)
    /// The Clear plate, on the bench's far left flank.
    ///
    /// It went beside the TRAY first, on the reasoning that the tray is
    /// where every part came from — the pairing Electric Fields makes
    /// between its wells and its Clear plate. A screenshot killed that
    /// twice over. The tray slab is not 0.63 m wide but 0.93: eleven
    /// component kinds make six columns, so `slabWidth` is `5 * 0.15 +
    /// 0.18`, and x = 0.42 was INSIDE it, with the slab's own glass
    /// between the plate and the reader. And tray height is the bottom
    /// of the frame — the plate sat half out of shot, which is
    /// `FieldInstrumentLayout`'s "reachable by the arithmetic, invisible
    /// in practice" in a second module.
    ///
    /// So it takes the far end of the buttons flank instead, at the
    /// furniture's own height. The bench's furniture reads as a row at
    /// one height — layers, bench, meter since the 2026-08-04 handing —
    /// with this beyond the bank, rather than one stray plate down
    /// among the parts.
    ///
    /// This is the most dangerous of the seven verbs that left the
    /// window. Circuit Workshop's bench PERSISTS ACROSS LAUNCHES
    /// (`CircuitsModel(restoreSaved:)`), so this plate can destroy work
    /// from a previous session — which is why the panel guarded it with
    /// a `confirmationDialog` and why the plate `confirms`.
    private static let clearAnchor = CircuitsRenderer.benchPivot
        + SIMD3<Float>(-1.02, -0.02, 0.10)

    /// The layers bank, on the bench's left flank. Named since
    /// 2026-08-09 so the reach criterion can measure it; the value is
    /// unchanged.
    static let bankAnchor = CircuitsRenderer.benchPivot
        + SIMD3<Float>(-0.62, -0.06, 0.16)

    /// BESIDE THE CLEAR PLATE, and unfolding UPWARD — moved down from
    /// y 1.73 on 2026-08-08 after a screenshot showed what the owner had
    /// already said in words: at that height it read "on its own",
    /// floating over the wall a long way from anything it belongs to.
    ///
    /// The constraint that shapes this is that the presets column and
    /// the layers bank are BOTH five plates, and two five-plate columns
    /// do not fit stacked inside the 0.70…1.80 working band. So they
    /// cannot share the bank's x, and the far-left flank is where the
    /// Clear plate already lives.
    ///
    /// Grouping them is the fix: the tab sits 0.06 above the Clear
    /// plate's top edge, which reads as one small stack of verbs rather
    /// than two strays, and the column unfolds UP into the empty band
    /// instead of down through the plate. Unfolded it spans y
    /// 1.483…1.797, inside the ceiling by 3 mm — tight, and checked by
    /// `CircuitsInstrumentClearanceTests` rather than by eye.
    private static let presetsAnchor = CircuitsRenderer.benchPivot
        + SIMD3<Float>(-1.02, 0.15, 0.10)
    /// The column hangs below the tab, centred on this point — a bank
    /// centres its plates on its anchor rather than stacking down from
    /// it, which is how the first attempt put the tab inside its own
    /// column.
    private static let presetsBankAnchor = CircuitsRenderer.benchPivot
        + SIMD3<Float>(-1.02, 0.39, 0.10)

    var body: some View {
        RealityView { content, attachments in
            let renderer = CircuitsRenderer()
            renderer.onTap = { handleTap(on: $0) }
            content.add(renderer.root)

            // What the selected part is doing, on the part. The anchor
            // has been repositioned above it every frame since the
            // renderer was written and carried nothing; the card was in
            // the window panel's "Selected part" dropdown.
            if let card = attachments.entity(for: Self.readoutCardID) {
                stripInput(from: card)
                renderer.selectedAnchor.addChild(card)
            }
            renderer.viewRoot.addChild(bloom.root)

            let bank = SpatialLayerBank(
                accent: UIColor(DesignTokens.Palette.circuitsAccent),
                layers: [
                    .init(id: "flow", label: "Electron flow", symbol: "circle.dotted",
                          isOn: { model.showElectronFlow },
                          toggle: { model.showElectronFlow.toggle() }),
                    .init(id: "truespeed", label: "True speed", symbol: "tortoise",
                          isOn: { model.trueSpeedMode },
                          toggle: { model.trueSpeedMode.toggle() }),
                    // The bench's own field. It replaces the
                    // electromagnet annex, and it makes the smaller,
                    // truer claim: EVERY wire here has a field around
                    // it, not just one wound into a coil.
                    .init(id: "bfield", label: "Magnetic field",
                          symbol: "circle.hexagongrid",
                          isOn: { model.showMagneticField },
                          toggle: { model.showMagneticField.toggle() }),
                    .init(id: "skyline", label: "Voltage skyline", symbol: "building.2",
                          isOn: { model.showVoltageHeights },
                          toggle: { model.showVoltageHeights.toggle() }),
                    .init(id: "electron", label: "Electron view", symbol: "arrow.down.left.and.arrow.up.right",
                          isOn: { model.electronView },
                          toggle: { model.electronView.toggle() }),
                ])
            // Under `root`, NOT `viewRoot`: the zoom reaches 8x, and a
            // control that grew with the bench would be a metre wide —
            // and Electron View's own switch would swell out of reach the
            // moment you used it.
            renderer.root.addChild(bank.root)
            self.layers = bank

            // Both under `root` for the same reason the layers bank is:
            // the zoom reaches 8×, and an instrument that grew with the
            // bench would put itself out of reach exactly when you had
            // zoomed in to use it.
            let multimeter = Multimeter(
                accent: UIColor(DesignTokens.Palette.circuitsAccent),
                anchor: Self.meterAnchor)
            renderer.root.addChild(multimeter.root)
            multimeter.onTap = { [weak multimeter] entity in
                _ = multimeter?.handleTap(entity, model: model)
            }
            self.meter = multimeter

            // Clearing the bench, off the window panel. Same parenting
            // rule as everything above: under `root`, so an 8× zoom
            // cannot carry it away.
            let benchVerbs = SpatialActionBank(
                accent: UIColor(DesignTokens.Palette.circuitsAccent),
                actions: [
                    .init(id: "clear", label: "Clear bench",
                          symbol: "trash.slash",
                          isAvailable: { !model.components.isEmpty },
                          confirms: true,
                          fire: { model.clearBench() }),
                ])
            renderer.root.addChild(benchVerbs.root)
            self.verbs = benchVerbs

            // EVERY PRESET CONFIRMS, and that is not caution for its own
            // sake: `loadPreset` opens with `clearBench()`, and this
            // bench PERSISTS ACROSS LAUNCHES (`CircuitsModel(restoreSaved:)`).
            // A single tap here would destroy work from a previous
            // session — the same reason the Clear plate beside it
            // confirms, and the reason its comment calls it the most
            // dangerous of the seven verbs that left the window. Adding
            // five more one-tap ways to do the same thing would have
            // undone that decision by accident.
            let presetBank = SpatialActionBank(
                accent: UIColor(DesignTokens.Palette.circuitsAccent),
                actions: CircuitsModel.Preset.allCases.map { preset in
                    .init(id: preset.rawValue, label: preset.displayName,
                          symbol: "bolt.horizontal",
                          confirms: true,
                          fire: {
                              model.loadPreset(preset)
                              lastPreset = preset
                              presetsHandle.close()
                          })
                })
            presetBank.root.isEnabled = false
            renderer.root.addChild(presetBank.root)
            self.presets = presetBank

            // The handle is a READOUT as well as a door — the half that
            // makes folding legitimate. It says which circuit is on the
            // bench, or that the bench is the user's own.
            presetsHandle.summary = { lastPreset?.displayName ?? "your bench" }
            renderer.root.addChild(presetsHandle.root)

            // THE PARTS, IN ONE BLOCK ON THE RIGHT.
            //
            // Two flanks until 2026-08-08, then a cabinet for a few
            // hours, now this — and the cabinet is the interesting one to
            // record. It was a correct answer to "eleven components stand
            // in the room whether or not anybody is building", and the
            // wrong answer to what a workshop bench is FOR. Parts behind
            // a door are parts you reach for less. The owner's verdict
            // was to bring them back visible, on the right of the
            // starting circuit, in the opening view.
            //
            // `CircuitsPartsLayout` still says WHICH parts and in what
            // order — sources, then passives, then the things that do
            // something — and now says where again, via `rightSlot`.
            // The two `kinds(on:)` lists are concatenated rather than
            // merged: that grouping is the one part of the old layout
            // that was about the COMPONENTS rather than the room, and it
            // is the order the block should read in.
            //
            // GRAVE: `slot`, `rowPitch`, `reach` and `offAxisAngle`
            // described the two-flank arrangement and have no callers.
            // They keep their tests — the reasoning in them about what a
            // reach and an off-axis angle cost is the material for
            // whatever this bench does next.
            let partSpecs: [Well.Spec] = CircuitsPartsLayout.Flank.allCases
                .flatMap { CircuitsPartsLayout.kinds(on: $0) }
                .enumerated()
                .map { index, kind in
                    Well.Spec(
                        name: kind.rawValue,
                        tint: UIColor(DesignTokens.Palette.circuitsAccent),
                        label: kind.displayName,
                        preview: { CircuitsRenderer.partPreview(for: kind) },
                        position: CircuitsPartsLayout.rightSlot(index: index),
                        spawn: { model.add(kind, at: $0) })
                }
            // THE METER IS THE TWELFTH SLOT. It stood beside the bench
            // at all times and the owner's word was "intruding"; the
            // cabinet that briefly swallowed it is gone, so it parks in
            // the rack with everything else instead. `handOver` rather
            // than `spawn` because there is exactly ONE multimeter —
            // minting a second on every pull would be the opposite of an
            // instrument.
            let meterSlot = Well.Spec(
                name: "multimeter",
                tint: UIColor(DesignTokens.Palette.circuitsAccent),
                label: "Multimeter",
                preview: { Multimeter.miniature() },
                position: CircuitsPartsLayout.rightSlot(index: partSpecs.count),
                spawn: { _ in nil },
                // CAPTURING THE INSTRUMENT, NOT THE VIEW: a SwiftUI
                // `View` is a struct, so there is no `self` to hold
                // weakly — and the meter is the only thing this closure
                // actually needs.
                handOver: { [weak multimeter] hand in
                    // Out of the rack and into the hand — and VISIBLE,
                    // which is the half that was missing. The instrument
                    // starts hidden so the rack's slot is the only
                    // multimeter in the room until somebody asks for it.
                    multimeter?.place(at: SIMD3<Float>(hand))
                    multimeter?.root.isEnabled = true
                })

            // HIDDEN UNTIL PULLED. The slot above shows a miniature; the
            // real instrument is one object with its own transform, its
            // dial and two probes, and leaving it standing beside the
            // bench as well put TWO multimeters in the room — the
            // miniature in the rack and the original still intruding
            // exactly where the owner objected to it. Caught in the
            // first CLI screenshot of the rack, which is the whole
            // reason the launch arguments above exist.
            multimeter.root.isEnabled = false

            let parts = Well(partSpecs + [meterSlot])
            // A WINDOW, NOT A WALL: six of the twelve, the rest a drag
            // away. Opt-in, so the five modules with three or four
            // sources are untouched.
            parts.visibleCount = CircuitsPartsLayout.rightVisibleRows
            renderer.root.addChild(parts.root)
            self.palette = parts

            renderer.subscriptions.append(
                content.subscribe(to: SceneEvents.Update.self) { [weak renderer] event in
                    // The lab's placement in the user's room — a pure
                    // display offset, safe because every grab in this app
                    // moves a body by hand DISPLACEMENT, which a constant
                    // translation leaves untouched.
                    renderer?.root.position = appModel.labPlacement.offset
                    // …AND THE INSTRUMENTS GO WITH IT. The bank, the
                    // meter and the verb plate are all children of
                    // `renderer.root` (see the three `addChild` calls in
                    // the setup above), so they ride the offset.
                    //
                    // This said they "hang off the scene content rather
                    // than the renderer root, so they never inherited the
                    // offset" until 2026-08-03. They always did. The
                    // three sibling modules carried the same false claim
                    // in different words.
                    model.step(dt: event.deltaTime)
                    // The bank stands beside the bench, at the bench's own
                    // depth so it sits in the same ~15 deg band as the
                    // apparatus rather than dropping out of view — on the
                    // LEFT, like every module's bank (2026-08-04).
                    let viewer = appModel.room.headPosition.map { SIMD3<Float>($0) }
                    layers?.update(
                        // x −0.62 IS INSIDE THE BUILD VOLUME, which spans
                        // ±0.70. Measured 2026-08-09, and left alone
                        // deliberately — the number is not the problem.
                        //
                        // The bank is 0.15 half-wide, so clearing the
                        // volume by `InstrumentClearance.stationMargin`
                        // needs its centre at |x| ≥ 0.97. Searched x
                        // 0.82…1.30 against z 0.60…1.20: NO position
                        // satisfies margin, reach and off-axis angle at
                        // once. The closest is x 0.97, z −0.73 — reach
                        // 1.253 m against a 1.25 limit and 53.0° against
                        // 48°. The bench is simply too wide for its own
                        // flanking furniture.
                        //
                        // It becomes feasible the moment the bench
                        // narrows: at `buildHalfExtents.x` = 0.60 the
                        // bank fits at x 0.87, z −0.79 (reach 1.215,
                        // 47.8°). That is a one-number change with a
                        // real cost — every saved circuit with a part
                        // between 0.60 and 0.70 is then outside its own
                        // bench — so it is the owner's, not a tidy-up.
                        // The multimeter's rest position (+0.62) is
                        // inside the volume for the same reason.
                        anchor: Self.bankAnchor,
                        viewer: viewer,
                        dt: event.deltaTime)
                    meter?.update(viewer: viewer, model: model)
                    // The palette's idle breath, its recoil when it gives
                    // a part up, and its refusal fade when the bench is
                    // at its sixteen-component budget. That last one is
                    // new capability, not decoration: at the budget the
                    // tray's pinch did nothing at all and said nothing
                    // about it.
                    palette?.update(
                        dt: event.deltaTime,
                        nearestHand: appModel.room.nearestFingertip(
                            to: CircuitsPartsLayout.rightSlot(index: 0)))
                    verbs?.update(anchor: Self.clearAnchor, viewer: viewer,
                                  dt: event.deltaTime,
                                  resetNonce: appModel.resetNonce,
                                  nearestHand: appModel.room.nearestFingertip(
                                    to: Self.clearAnchor))
                    presetsHandle.update(
                        anchor: Self.presetsAnchor, viewer: viewer,
                        dt: event.deltaTime,
                        nearestHand: appModel.room.nearestFingertip(
                            to: Self.presetsAnchor))
                    presets?.root.isEnabled = presetsHandle.isOpen
                    if presetsHandle.isOpen {
                        presets?.update(anchor: Self.presetsBankAnchor,
                                        viewer: viewer, dt: event.deltaTime,
                                        resetNonce: appModel.resetNonce,
                                        nearestHand: appModel.room.nearestFingertip(
                                            to: Self.presetsBankAnchor))
                    }
                    // Rendered here every frame (not via the observation
                    // loop): a steady DC circuit mutates nothing that
                    // observation reliably re-fires on, but its electrons
                    // must keep drifting.
                    renderer?.handZoom = scaleRig.liveScale
                    renderer?.tick(dt: event.deltaTime, model: model)
                    if let renderer {
                        syncBloom(renderer: renderer, dt: event.deltaTime)
                    }
                }
            )
            #if DEBUG
            if UserDefaults.standard.double(forKey: "trueSpeed") > 0 {
                model.trueSpeedMode = true
            }
            // `-electronView 1` shrinks the bench into the copper at
            // launch. Its switch is a plate on the layers bank standing
            // beside the bench, and the simulator has no hand to press
            // it — so without this the app's named centrepiece (the
            // demo reel's, per DECISIONS.md) is the one thing that
            // cannot be screenshot from the CLI at all.
            if UserDefaults.standard.bool(forKey: "electronView") {
                model.electronView = true
            }
            // `-skyline 1` raises the voltage towers at launch. Same
            // reason as the two above: the toggle lives on the layers
            // bank, which needs a hand. This one earned its arg by
            // being the module's heaviest per-frame path — every tower
            // and cap rebuilt its material each frame until the ramp
            // was banked — and a rewrite of a picture nobody can see
            // from the CLI is a rewrite nobody can check.
            if UserDefaults.standard.bool(forKey: "skyline") {
                model.showVoltageHeights = true
            }
            let forcedScale = UserDefaults.standard.double(forKey: "viewScale")
            if forcedScale > 0 {
                scaleRig.updateMagnification(Float(forcedScale))
                scaleRig.endGesture()
            }
            #endif

            #if DEBUG
            // `-circRing 1` opens the first component's control ring
            // at launch, for CLI screenshots.
            if UserDefaults.standard.bool(forKey: "circRing"),
               let first = model.components.first {
                ring.openID = first.id
            }
            // THE THREE SURFACES ADDED ON 2026-08-08, none of which the
            // simulator can reach with a finger, and all of which I have
            // been asking the owner to check on device for want of a
            // way to photograph them.
            //
            // `-circPreset series|parallel|divider|rcCharger|shortCircuit`
            // loads one. It used to also put that preset's authored
            // paragraph on the insight card; the card was deleted on
            // 2026-08-09 and the paragraphs with it, so this now just
            // builds the circuit.
            if let name = UserDefaults.standard.string(forKey: "circPreset"),
               let preset = CircuitsModel.Preset(rawValue: name) {
                model.loadPreset(preset)
                lastPreset = preset
            }
            // `-circPresetsOpen 1` unfolds the presets tab. Its five
            // plates are behind a `SummonHandle` and a handle is a
            // pinch, so folded is the only state a screenshot could ever
            // catch without this.
            if UserDefaults.standard.bool(forKey: "circPresetsOpen") {
                presetsHandle.setOpen(true)
            }
            // `-circScroll <n>` scrolls the parts rack n slots. A rack
            // that only ever shows its first six is a rack whose scroll
            // cannot be reviewed — and the carets change with it, so
            // this is also the only way to photograph the up caret lit.
            let scroll = UserDefaults.standard.integer(forKey: "circScroll")
            if scroll != 0 { parts.scroll(by: scroll) }

            // `-circField 1` switches on the bench's own magnetic
            // field. The plate is on the layers bank and the simulator
            // has no finger to flick it with, and this is the one layer
            // whose whole content is invisible until it is on.
            if UserDefaults.standard.bool(forKey: "circField") {
                model.showMagneticField = true
            }
            // `-circClear 1` ARMS the Clear plate — it does not fire it.
            // Firing would photograph an empty bench, which looks the
            // same as a bench nobody built on. The armed state is the
            // half that cannot otherwise be seen, and on this bench it
            // is the half that matters: the plate can destroy a circuit
            // saved from a previous launch.
            if UserDefaults.standard.bool(forKey: "circClear") {
                benchVerbs.arm("clear", holds: true)
            }
            #endif
            self.renderer = renderer
        } attachments: {
            Attachment(id: Self.readoutCardID) {
                CircuitsSelectedReadout()
                    // Never intercept a pinch: this floats 14 cm above a
                    // part whose body, terminals and end grips are all
                    // grab targets.
                    .allowsHitTesting(false)
                    .environment(model)
            }
        }
        // Leaving the lab must not leave anything running or held.
        //
        // `teardown` cancels the renderer's event subscriptions and any
        // geometry job in flight (see `GeometryPipeline.cancel`), and the
        // drag state is cleared because NOTHING ELSE CAN CLEAR IT: an
        // in-flight grab that never receives its `onEnded` — the space
        // closing under it is the ordinary way that happens — otherwise
        // strands the object wherever the hand left it and re-targets
        // every later drag at the same one, with no exit but leaving.
        .onDisappear {
            renderer?.teardown()
            // A GRIP SURVIVES THE SPACE CLOSING, and that is worse than
            // it sounds. `Bloom` is a class, so `gripDrag` outlives this
            // view; left set, `updateGrip` claims EVERY subsequent drag
            // in the module and nothing at all can be grabbed. That
            // exact failure is documented in PendulumsSpaceView's
            // `onEnded` — it cost this module every one of its verbs
            // once already.
            bloom.endGrip()
        }
        .gesture(
            TapGesture()
                .targetedToAnyEntity()
                .onEnded { value in
                    // Ring petals first; then the bench's own tap
                    // grammar (terminals wire, wires delete, levers
                    // flip, bodies toggle their control ring).
                    if layers?.handleTap(value.entity) == true { return }
                    // Ahead of `handleTap(on:)`, which is what reads a
                    // TERMINAL — the meter stands among the bench's
                    // terminals by design, and turning its dial must not
                    // also count as probing whatever is behind it.
                    if meter?.handleTap(value.entity, model: model) == true { return }
                    if bloom.handleTap(value.entity) { return }
                    // Ahead of `handleTap(on:)` for the same reason the
                    // meter is. The tray this plate used to stand at the
                    // end of is gone (2026-08-03) and the palette that
                    // replaced it is on the far flanks, so the crowding
                    // that made the ordering urgent has eased — but the
                    // ordering is what makes it a RULE rather than a
                    // distance: a verb plate is never also a reach for
                    // the bench behind it, wherever it happens to stand.
                    if verbs?.handleTap(value.entity) == true { return }
                    // The rack's carets, before anything else on that
                    // flank: they sit at the ends of the parts column and
                    // a miss would otherwise fall through to whatever is
                    // behind them.
                    if palette?.handleTap(value.entity) == true { return }
                    if presetsHandle.handleTap(value.entity) { return }
                    if presetsHandle.isOpen,
                       presets?.handleTap(value.entity) == true { return }
                    handleTap(on: value.entity)
                }
        )
        // One drag gesture, four grabs — all relative, nothing lurches
        // toward the hand: a terminal pulls a live wire; an end grip
        // aims/stretches its part; a palette source hands you a NEW part
        // at your fingertips; a part body carries the part. Tap-tap
        // wiring still works too.
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .targetedToAnyEntity()
                .onChanged { value in
                    guard let renderer else { return }
                    // Into the BENCH's own frame, not the room's. The
                    // bench can be zoomed (Electron View, two hands) and
                    // moved (lab placement); converting through viewRoot
                    // inverts both exactly, so a part follows the hand
                    // 1:1 on screen at any zoom instead of flying four
                    // times as far.
                    let handF = renderer.viewRoot.convert(
                        position: SIMD3<Float>(value.convert(
                            value.location3D, from: .local, to: .scene)),
                        from: nil)
                    let hand = SIMD3<Double>(handF)

                    // THE PROBES, before anything else on the bench.
                    //
                    // They are the one thing here that is not part of the
                    // circuit: a probe carried across a terminal must not
                    // also start dragging that terminal's wire, and a
                    // probe is deliberately easy to pick up, so it has to
                    // claim its drag first.
                    if probeDrag == nil, let meter,
                       let slot = meter.probeSlot(for: value.entity) {
                        probeDrag = slot
                    }
                    if let slot = probeDrag, let meter {
                        let world = SIMD3<Float>(value.convert(
                            value.location3D, from: .local, to: .scene))
                        meter.moveProbe(
                            slot,
                            local: meter.root.convert(position: world, from: nil),
                            bench: hand, model: model)
                        return
                    }

                    // THE METER ITSELF, next.
                    //
                    // In the RENDERER's frame, not the bench's: the meter
                    // hangs off `root` rather than `viewRoot` precisely so
                    // an 8× Electron View cannot carry the instrument out
                    // of reach, and converting its drag through the zoom
                    // would undo that — the case would fly eight times as
                    // far as the hand at full magnification.
                    if let meter {
                        let world = SIMD3<Float>(value.convert(
                            value.location3D, from: .local, to: .scene))
                        let local = renderer.root.convert(position: world, from: nil)
                        if meterDrag == nil, meter.isBody(value.entity) {
                            meterDrag = (meter.anchor, local)
                        }
                        if let drag = meterDrag {
                            meter.place(at: drag.start + (local - drag.hand))
                            return
                        }
                    }

                    if bloom.updateGrip(hand: handF) { return }
                    if wireDragFrom == nil, partDrag == nil {
                        if bloom.beginGrip(value.entity, hand: handF) { return }
                        beginCircuitDrag(entity: value.entity, hand: hand, renderer: renderer)
                    }
                    if let source = wireDragFrom,
                       let sourceComponent = model.components.first(
                         where: { $0.id == source.componentID }) {
                        let target = nearestTerminal(to: handF, excluding: source)
                        renderer.rubberTargetTerminal = target?.terminal
                        renderer.showRubberBand(
                            from: SIMD3<Float>(sourceComponent.terminalPosition(source.end)),
                            to: target.map { SIMD3<Float>($0.position) } ?? handF)
                    } else if let palette, palette.isDragging {
                        // Browsing, or the frame a pull commits on. The
                        // slot comes back exactly once — returning it
                        // every frame would put one part on the bench
                        // per frame.
                        if let slot = palette.updateDrag(hand: handF),
                           let source = palette.source(at: slot) {
                            if let id = palette.pull(source, at: hand) {
                                spawnedPartID = id
                                partDrag = RelativeDrag(name: id.uuidString,
                                                        target: hand, hand: hand)
                                renderer.previewComponentID = id
                                model.beginCarry(id: id)
                            }
                        }
                    } else if let partDrag {
                        applyCircuitDrag(partDrag, hand: hand)
                    }
                }
                .onEnded { value in
                    probeDrag = nil
                    meterDrag = nil
                    palette?.endDrag()
                    bloom.endGrip()
                    defer {
                        renderer?.hideRubberBand()
                        renderer?.previewComponentID = nil
                        wireDragFrom = nil
                        partDrag = nil
                        spawnedPartID = nil
                        gripDrag = nil
                        model.endCarry()
                    }
                    guard let renderer else { return }
                    // Into the BENCH's own frame, not the room's. The
                    // bench can be zoomed (Electron View, two hands) and
                    // moved (lab placement); converting through viewRoot
                    // inverts both exactly, so a part follows the hand
                    // 1:1 on screen at any zoom instead of flying four
                    // times as far.
                    let handF = renderer.viewRoot.convert(
                        position: SIMD3<Float>(value.convert(
                            value.location3D, from: .local, to: .scene)),
                        from: nil)
                    let hand = SIMD3<Double>(handF)
                    if let source = wireDragFrom {
                        if let target = nearestTerminal(to: handF, excluding: source) {
                            model.connectTerminals(source, target.terminal)
                        }
                        return
                    }
                    guard let partDrag else { return }
                    applyCircuitDrag(partDrag, hand: hand)
                    if let gripDrag {
                        model.autoConnect(id: gripDrag.grip.componentID)
                    } else if let id = spawnedPartID ?? UUID(uuidString: partDrag.name) {
                        model.autoConnect(id: id)
                    }
                }
        )
        .spatialScale(scaleRig)
    }

    /// Resolves what the pinch landed on and opens the right session:
    /// wire (terminal), aim/stretch (grip), pull (palette), carry (body).

    /// A part's own controls. Its value has no size of its own, so the
    /// grip's honesty is the CONSEQUENCE — pull a bulb's resistance up
    /// and it visibly dims, pull the battery's volts and the electron
    /// drift quickens while your hand is still moving. Switches get a
    /// petal instead, because open and closed is not a continuum.
    private func syncBloom(renderer: CircuitsRenderer, dt: Double) {
        if let openID = ring.openID,
           !model.components.contains(where: { $0.id == openID }) {
            ring.openID = nil     // deleted out from under the ring
        }
        guard let uuid = ring.openID,
              let part = model.components.first(where: { $0.id == uuid }) else {
            bloom.update(anchor: .zero, viewer: nil, revealTarget: 0, dt: dt)
            bloom.clearTarget()
            return
        }

        var petals: [Bloom.Petal] = []
        if part.kind == .switcher {
            petals.append(.init(name: "Open or close", symbol: "power",
                                tint: DesignTokens.Palette.neutralActionUI) {
                model.toggleSwitch(id: uuid)
            })
        }
        if part.failed {
            // A blown bulb's most-wanted action, finally reachable.
            petals.append(.init(name: "Replace", symbol: "arrow.triangle.2.circlepath",
                                tint: UIColor(red: 0.95, green: 0.60, blue: 0.15, alpha: 1)) {
                model.replaceFailed(id: uuid)
            })
        } else if model.isWired(id: uuid) {
            petals.append(.init(name: "Detach", symbol: "scissors",
                                tint: DesignTokens.Palette.neutralActionUI) {
                model.detachComponent(id: uuid)
            })
        }
        petals.append(.init(name: "Delete", symbol: "trash",
                            tint: DesignTokens.Palette.destructiveUI) {
            model.removeComponent(id: uuid)
        })

        let range = CircuitsModel.valueRange(for: part.kind)
        bloom.retarget(
            uuid,
            petals: petals,
            grip: range.upperBound > range.lowerBound
                ? .init(name: "Value",
                        range: range,
                        read: { model.componentValue(id: uuid) },
                        write: { model.setComponentValue(id: uuid, $0) },
                        format: { CircuitsModel.formatValue($0, for: part.kind) },
                        radius: { 0.05 })
                : nil)

        let viewer = appModel.room.headPosition.map {
            renderer.viewRoot.convert(position: SIMD3<Float>($0), from: nil)
        }
        bloom.update(anchor: SIMD3<Float>(part.position),
                     viewer: viewer, revealTarget: 1, dt: dt)
    }

    private func beginCircuitDrag(
        entity: Entity, hand: SIMD3<Double>, renderer: CircuitsRenderer
    ) {
        var current: Entity? = entity
        while let candidate = current {
            let name = candidate.name
            if name.hasPrefix("t0-") || name.hasPrefix("t1-") {
                wireDragFrom = terminal(on: candidate)
                return
            }
            if let grip = stretchTerminal(from: name),
               let component = model.components.first(
                where: { $0.id == grip.componentID }) {
                let sign = grip.end == 0 ? -1.0 : 1.0
                let gripWorld = component.position + sign
                    * (CircuitsModel.terminalOffset + CircuitsModel.endGripOffset)
                    * component.axis
                gripDrag = (grip, component.terminalPosition(1 - grip.end))
                partDrag = RelativeDrag(name: name, target: gripWorld, hand: hand)
                renderer.previewComponentID = grip.componentID
                model.select(id: grip.componentID)
                model.beginCarry(id: grip.componentID)
                return
            }
            // THE RACK CLAIMS THE DRAG BEFORE IT KNOWS WHAT IT IS.
            //
            // A pinch on a slot means two things now — slide the rack to
            // see the other six, or take this one — and which cannot be
            // known until the hand has travelled (`ScrollGesture`). So
            // the drag opens here and resolves in `onChanged`; the part
            // is still born AT THE FINGERTIPS when it comes, which is
            // the whole reason a well beat the old tray.
            if palette?.beginDrag(candidate, hand: SIMD3<Float>(hand)) == true {
                return
            }
            if let id = UUID(uuidString: name),
               let component = model.components.first(where: { $0.id == id }) {
                partDrag = RelativeDrag(name: name, target: component.position, hand: hand)
                renderer.previewComponentID = id
                model.select(id: id)
                model.beginCarry(id: id)
                return
            }
            current = candidate.parent
        }
    }

    private func applyCircuitDrag(_ drag: RelativeDrag, hand: SIMD3<Double>) {
        let position = drag.position(forHand: hand)
        if let gripDrag {
            model.dragEnd(id: gripDrag.grip.componentID,
                          grabbedEnd: gripDrag.grip.end,
                          pivot: gripDrag.pivot, hand: position)
            model.breakOverstretchedWires(id: gripDrag.grip.componentID)
        } else if let id = spawnedPartID ?? UUID(uuidString: drag.name) {
            model.move(id: id, to: position)
            model.breakOverstretchedWires(id: id)
        }
    }

    /// The terminal an entity (or any ancestor) represents, if any.
    private func terminal(on entity: Entity) -> CircuitsModel.Terminal? {
        var current: Entity? = entity
        while let candidate = current {
            let name = candidate.name
            if name.hasPrefix("t0-") || name.hasPrefix("t1-"),
               let id = UUID(uuidString: String(name.dropFirst(3))) {
                return CircuitsModel.Terminal(
                    componentID: id, end: name.hasPrefix("t0-") ? 0 : 1)
            }
            current = candidate.parent
        }
        return nil
    }

    /// The closest connectable terminal within reach of the hand.
    private func nearestTerminal(
        to hand: SIMD3<Float>, excluding source: CircuitsModel.Terminal
    ) -> (terminal: CircuitsModel.Terminal, position: SIMD3<Double>)? {
        var best: (CircuitsModel.Terminal, SIMD3<Double>, Float)?
        for component in model.components {
            for end in 0...1 {
                let terminal = CircuitsModel.Terminal(componentID: component.id, end: end)
                guard terminal != source else { continue }
                let position = component.terminalPosition(end)
                let distance = simd_distance(SIMD3<Float>(position), hand)
                guard distance < 0.09 else { continue }
                if best == nil || distance < best!.2 {
                    best = (terminal, position, distance)
                }
            }
        }
        return best.map { ($0.0, $0.1) }
    }

    /// Terminals ("t0-"/"t1-"), wires ("w-"), and levers ("k-") are tap
    /// targets; walk up the hierarchy to find whichever was hit.
    private func handleTap(on entity: Entity) {
        var current: Entity? = entity
        while let candidate = current {
            let name = candidate.name
            if name.hasPrefix("t0-") || name.hasPrefix("t1-") {
                let end = name.hasPrefix("t0-") ? 0 : 1
                if let id = UUID(uuidString: String(name.dropFirst(3))) {
                    let terminal = CircuitsModel.Terminal(componentID: id, end: end)
                    if model.multimeterArmed {
                        model.probeTap(terminal)
                    } else {
                        model.tapTerminal(terminal)
                    }
                }
                return
            }
            if name.hasPrefix("w-"), let id = UUID(uuidString: String(name.dropFirst(2))) {
                model.deleteWire(id: id)
                return
            }
            if name.hasPrefix("k-"), let id = UUID(uuidString: String(name.dropFirst(2))) {
                model.toggleSwitch(id: id)
                return
            }
            // A tap on a component body toggles its control ring.
            if let id = UUID(uuidString: name),
               model.components.contains(where: { $0.id == id }) {
                if ring.openID == id {
                    ring.openID = nil
                    SoundPalette.play(.releaseTick, on: entity, volume: 0.3)
                } else {
                    ring.openID = id
                    SoundPalette.play(.pop, on: entity, volume: 0.35)
                }
                return
            }
            current = candidate.parent
        }
        if ring.openID != nil {
            SoundPalette.play(.releaseTick, on: entity, volume: 0.3)
        }
        ring.openID = nil
    }

    /// The end-grip being pulled, parsed from "s0-"/"s1-" entity names.
    private func stretchTerminal(from name: String) -> CircuitsModel.Terminal? {
        guard name.hasPrefix("s0-") || name.hasPrefix("s1-"),
              let id = UUID(uuidString: String(name.dropFirst(3))) else { return nil }
        return CircuitsModel.Terminal(componentID: id, end: name.hasPrefix("s0-") ? 0 : 1)
    }

    /// Component bodies (named by UUID, marked by the white center knob)
    /// are carried directly. A palette source makes a part AT THE HAND
    /// and hands it to the same drag, so making one and moving one are
    /// one gesture. End grips ("s0-"/"s1-") swing the part around its
    /// opposite end — pinned where it was when the pull began — and set
    /// a wire's length from the hand's reach.
    ///
    /// The palette resolves by ENTITY, through `Well.pull`, rather than
    /// by parsing a `"tray-<kind>"` prefix off a name. Name-parsing is
    /// how the tray did it and it is the loosest coupling in this file:
    /// a renamed entity failed silently, as a part that simply could not
    /// be made. `SpatialPicker` made the same move for the same reason.
}

// CircuitsSelectedReadout lives in CircuitsSelectedReadout.swift.
//
// It pointed at `CircuitsControlsPanel.swift` until 2026-08-09, and
// that file was deleted on 2026-08-01 with every other module panel —
// a signpost to a room that had been demolished eight days earlier.
// The readout moved to its own file in the same sweep.

