//
//  PlaygroundSpaceView.swift
//  Physics Playground — Shell
//
//  The single shared immersive space. With no module active it shows the
//  spatial hub menu (floating title + module bubbles); entering a module
//  swaps in its scene. `.id(module.id)` gives each module its own view
//  identity so per-module @State (like renderers) is rebuilt cleanly on
//  switch, while module *models* live on in AppModel.
//

import RealityKit
import RenderKit
import SwiftUI

struct PlaygroundSpaceView: View {
    static let spaceID = "PlaygroundSpace"

    @Environment(AppModel.self) private var appModel
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace

    /// THE ASSETS ARE READY. Nothing builds until the prop cache is warm.
    ///
    /// `PropCache.prototype` falls back to a SYNCHRONOUS `Entity.load`
    /// when it misses, so a gallery built cold parses twenty usdz on
    /// Thread 1 and hangs the first frames. That used to be covered by
    /// warming during the window phase — the front door was on screen
    /// while the cache filled. Launching straight into the space
    /// (2026-08-22) deletes that phase, so the wait moves here: the
    /// space opens on plain passthrough, the cache fills, and only then
    /// does the arrival choreography start, with everything it needs.
    /// The user waits exactly as long as before and sees their own room
    /// instead of a slab.
    @State private var ready = false

    /// THE FLAT CATALOG DOES NOT STAND BEHIND THE GALLERY: the window is
    /// a lab's title bar and the way back out, but on the home screen it
    /// duplicated the exhibits it stood behind. Known cost: with it
    /// dismissed there is no in-app exit from the home screen, only the
    /// Digital Crown.
    private func syncMainWindow() {
        if appModel.activeModuleID == nil {
            dismissWindow(id: MainWindowView.windowID)
        } else {
            openWindow(id: MainWindowView.windowID)
        }
    }

    /// XCUITest cannot see into an immersive space, so under `-uiTesting`
    /// the app has to be a window app.
    ///
    /// This USED to be a suppressed auto-open: the window was the launch
    /// scene, and the argument simply stopped it opening the gallery.
    /// There is no auto-open left to suppress — the space IS the launch
    /// scene now, chosen by a static Info.plist key that no launch
    /// argument can reach — so the only place left to turn round is
    /// here, on the way in. Not `#if DEBUG`-gated, for the same reason
    /// `HubView.isUITesting` is not: the UI test target runs the
    /// shipping configuration, and a hook that vanishes in Release
    /// cannot test what ships.
    /// It only DISMISSES; it does not open the window. The `onDisappear`
    /// below already reopens the main window unconditionally, and
    /// opening it here as well produced two — the module's title bar in
    /// one and the catalog still sitting in the other, which is exactly
    /// what `testTappingALabEntersIt`'s last assertion is written to
    /// catch ("the module opened but the catalog is still up behind it").
    private func retreatForUITesting() -> Bool {
        guard HubView.isUITesting else { return false }
        Task { await dismissImmersiveSpace() }
        return true
    }

    #if DEBUG
    /// The screenshot hooks that need a scene to have appeared.
    ///
    /// MOVED HERE FROM `MainWindowView.task` (2026-08-22) BECAUSE THAT
    /// WINDOW NO LONGER LAUNCHES. Seven arguments were read there and
    /// nowhere else, so leaving them behind would have silently broken
    /// `-settingsOpen`, `-notebookOpen`, `-notebookSeed`, `-seedCircuits`,
    /// `-seedMotor` and `-circuitVoltageHeights` — the CLI screenshot
    /// workflow the project leans on precisely because the simulator
    /// cannot be gaze-pinched. `-openModule`'s companion went the other
    /// way and was DELETED rather than moved: it existed only to open
    /// the space for a module launched from the command line, and the
    /// space is now always open.
    private func applyDebugLaunchArguments() {
        let defaults = UserDefaults.standard
        if defaults.bool(forKey: "settingsOpen") {
            openWindow(id: SettingsView.windowID)
        }
        // `-notebookSeed 1` fills the notebook with sample observations
        // first, so the entry cards can be screenshot-checked.
        if defaults.bool(forKey: "notebookSeed"),
           appModel.notebook.entries.isEmpty {
            appModel.notebook.record(
                moduleID: "electrostatics", moduleTitle: "Electric Fields",
                title: "Seeded observation 1",
                readings: [.init("Charges", "2"),
                           .init("Net charge", "0.0", "C"),
                           .init("|E| 10 cm away", "8.99e5", "N/C")])
            appModel.notebook.record(
                moduleID: "pendulums", moduleTitle: "Pendulums",
                title: "Seeded observation 1",
                readings: [.init("Length", "0.80", "m"),
                           .init("Period", "1.79", "s")])
        }
        if defaults.bool(forKey: "notebookOpen") {
            openWindow(id: NotebookView.windowID)
        }
        // `-seedCircuits 1` drops a few parts (one aimed off-axis) so
        // component visuals can be screenshot-checked from the CLI.
        guard defaults.bool(forKey: "seedCircuits") else { return }
        let circuits = appModel.circuitsModel
        if circuits.components.isEmpty {
            circuits.add(.battery, at: SIMD3(-0.35, 1.3, -0.9))
            circuits.add(.bulb, at: SIMD3(0.35, 1.3, -0.9))
            circuits.add(.resistor, at: SIMD3(0, 1.5, -0.9))
            if let part = circuits.components.last {
                circuits.setAxis(id: part.id, axis: SIMD3(0.35, 0.4, 0.05))
            }
        }
        // `-circuitVoltageHeights 1` raises the voltage skyline.
        if defaults.bool(forKey: "circuitVoltageHeights") {
            circuits.showVoltageHeights = true
        }
        // `-seedMotor 1` builds a battery→motor loop so the rotor spins.
        if defaults.bool(forKey: "seedMotor") {
            circuits.clearBench()
            if let battery = circuits.add(.battery, at: SIMD3(-0.3, 1.3, -0.85)),
               let motor = circuits.add(.motor, at: SIMD3(0.3, 1.3, -0.85)) {
                circuits.connectTerminals(.init(componentID: battery, end: 0),
                                          .init(componentID: motor, end: 0))
                circuits.connectTerminals(.init(componentID: battery, end: 1),
                                          .init(componentID: motor, end: 1))
            }
        }
    }
    #endif

    var body: some View {
        // A ZSTACK AROUND THE GROUP, so the flag at the bottom has a
        // stable sibling to hang off. See the comment down there.
        ZStack {
            // NOTHING BUILDS UNTIL THE CACHE IS WARM — see `ready`. The
            // gate is here rather than inside the Group so it covers the
            // hub and the modules too, not just the backdrop chain.
            if ready {
            Group {
                // Studio Mode's dark gallery sits behind whatever is active —
                // hub ring or module — and survives switches between them.
                if appModel.studioMode {
                    StudioEnvironmentView()
                        .id("studio")
                } else {
                    // The middle setting: the room stays, but a dark shell
                    // gives the physics its contrast back.
                    //
                    // MOUNTED UNCONDITIONALLY, and both halves of that matter.
                    // It used to hang off `roomDimming > 0.01`, which meant a
                    // shell whose target had just become 0 was torn out of the
                    // hierarchy at full opacity — there was no view left to
                    // ramp DOWN, so leaving a lab could only ever snap. And a
                    // conditional child changes the `Group`'s child count,
                    // which is the thing the ZStack note further down already
                    // frets about. Off, it is one entity with `isEnabled` false.
                    //
                    // No `.id()` on the radius any more either: the dome is
                    // built at unit radius and sized by its transform, and the
                    // radius itself is read per-frame off `AppModel`. A module
                    // wanting a 16 m shell no longer needs a new view identity
                    // to get one — which is what let the Gravity Lab ramp
                    // survive its own radius change.
                    RoomDimmerView()
                        .id("dimmer")
                }
                if let module = appModel.activeModule {
                    ZStack {
                        module.makeScene()
                            .id(module.id)
                        // The shared room sensing stays alive while a module
                        // is on screen (device-only; inert in the simulator).
                        RoomSensingView()
                            .id("room-sensing")
                        // The lab anchor: drag it to put the apparatus where
                        // you actually have room. Hidden until asked for.
                        LabAnchorView(module: module)
                            .id("lab-anchor-\(module.id)")
                        // ONE bead, in the slot where RealityView content
                        // provably renders. Pinch it and the labs unfold.
                        PaletteView(module: module)
                            .id("palette-\(module.id)")
                        // The Time Capsule's rail: folded away until the
                        // module is paused with a recording worth scrubbing.
                        TimeRailView(module: module)
                            .id("time-rail-\(module.id)")
                        // NO CARD OF WORDS STANDS IN A LAB — the teach lives
                        // only in the module WINDOW (`ModuleHostView`,
                        // `ModuleDescriptor.firstRunHint`, gated on
                        // `AppSettings.seenHints`).
                        //
                        // Quiet lab room tone under every module (not the hub);
                        // no per-module id, so it runs seamlessly across switches.
                        AmbientLabAudioView()
                            .id("ambient")
                    }
                } else {
                    HubSpaceView()
                        .id("hub")
                }
            }
            }

            // THE FLAG MUST HANG OFF A SIBLING LEAF, NOT A MODIFIER ON THE
            // `Group`: a Group applies each modifier to EVERY child, so the
            // pair would fire once per child and the child count changes
            // with state (a dimmed module swaps branches). SwiftUI does not
            // order those callbacks, so the flag could read false with the
            // space open. `.background` fails the same way — it distributes
            // too. As a ZStack sibling the leaf exists exactly once.
            Color.clear
                .frame(width: 0, height: 0)
                .onAppear {
                    appModel.isImmersiveSpaceOpen = true
                    syncMainWindow()
                }
                // THE LAUNCH PATH RUNS HERE NOW. It used to live in
                // `MainWindowView.task`, which was the launch scene; the
                // space is, so this is the only place guaranteed to run
                // once on every start.
                .task {
                    SoundPalette.warmUp()
                    SoundPalette.masterVolume = appModel.settings.masterVolume
                    // BEFORE THE RETREAT, NOT AFTER. `-uiTesting 1` and a
                    // screenshot argument arrive together — the settings
                    // UI test passes both — so putting this behind the
                    // guard silently dropped `-settingsOpen` for exactly
                    // the run that needed it.
                    #if DEBUG
                    applyDebugLaunchArguments()
                    #endif
                    guard !retreatForUITesting() else { return }
                    await PropCache.warmUp()
                    ready = true
                }
                .onDisappear {
                    appModel.isImmersiveSpaceOpen = false
                    // ALWAYS BRING THE WINDOW BACK. This is the leaf
                    // that outlives it, and it is the only thing that
                    // can: once the window is dismissed there is no
                    // view of it left to notice the space closing. If
                    // this line is ever removed, closing the gallery
                    // with the Digital Crown leaves the app with no
                    // scene at all.
                    openWindow(id: MainWindowView.windowID)
                }
                // The window follows the MODULE, not the space: leaving
                // a lab by the palette's Home petal returns to the
                // gallery with the space still open, and that is a
                // home-screen state like any other.
                .onChange(of: appModel.activeModuleID) { syncMainWindow() }

            // THE ONE PLACE VOICEOVER'S ACTIONS ARRIVE.
            //
            // Every plate, petal, disc, rail and well in six labs was
            // announced, readable and impossible to operate: a grep for
            // `systemActions` returned zero matches across the whole
            // project, and since the window panels were deleted there is
            // no fallback surface, so this app was six rooms of readouts
            // with no controls in them.
            //
            // ONE subscription rather than six, because the routing is
            // not per-module: `SpatialActionComponent` rides the entity
            // that knows what to do, so this walks up from whatever was
            // activated exactly as the gesture chains do. A module that
            // grows a new control gets this for free — and a module that
            // forgets is caught by `SpatialActionCriterionTests`, which
            // fails any interactive primitive that cannot be operated.
            AccessibilityActionRouter()
        }
    }
}

/// Delivers VoiceOver's actions to whichever control was activated.
///
/// A `RealityView` with nothing in it but two subscriptions: the events
/// arrive on the scene, not on a view, and this is the smallest thing
/// that can hold a scene subscription for as long as the space is open.
///
/// `.increment` and `.decrement` are one call with a sign, because a
/// rail and a grip differ only in what a step means and only they know
/// their own range — `SpatialActionComponent.adjust` takes the sign and
/// the primitive turns it into `span / 20`.
private struct AccessibilityActionRouter: View {
    @State private var subscriptions: [EventSubscription] = []

    var body: some View {
        RealityView { content in
            subscriptions = [
                content.subscribe(to: AccessibilityEvents.Activate.self) { event in
                    SpatialActions.activate(event.entity)
                },
                content.subscribe(to: AccessibilityEvents.Increment.self) { event in
                    SpatialActions.adjust(event.entity, by: 1)
                },
                content.subscribe(to: AccessibilityEvents.Decrement.self) { event in
                    SpatialActions.adjust(event.entity, by: -1)
                },
            ]
        }
        .onDisappear {
            subscriptions.forEach { $0.cancel() }
            subscriptions = []
        }
    }
}

/// An invisible emitter looping the synthesized laboratory ambience.
private struct AmbientLabAudioView: View {
    @Environment(AppModel.self) private var appModel
    @State private var controller: AudioPlaybackController?
    @State private var emitter = Entity()

    var body: some View {
        RealityView { content in
            emitter.position = [0, 1.7, -1.0]
            content.add(emitter)
            if appModel.settings.ambientAudio { start() }
        }
        .onChange(of: appModel.settings.ambientAudio) {
            // The settings toggle applies immediately, not next visit.
            if appModel.settings.ambientAudio { start() } else { stop() }
        }
        .onDisappear { stop() }
    }

    private func start() {
        guard controller == nil else { return }
        Task { @MainActor in
            // warmUp synthesizes off-launch; retry briefly until ready.
            for _ in 0..<40 where controller == nil {
                guard appModel.settings.ambientAudio else { return }
                if let started = SoundPalette.startAmbient(on: emitter) {
                    controller = started
                    return
                }
                try? await Task.sleep(for: .milliseconds(250))
            }
        }
    }

    private func stop() {
        controller?.stop()
        controller = nil
    }
}
