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

    /// THE FLAT CATALOG DOES NOT STAND BEHIND THE GALLERY (2026-08-10).
    ///
    /// The main window has three jobs and only two of them survive the
    /// gallery opening. Before it opens, it is the front door — the
    /// wordmark, "Enter the Gallery", and the way back if that fails.
    /// Inside a lab it is that lab's title bar. But on the HOME SCREEN
    /// with the gallery up, it was a list of six labs parked a couple
    /// of metres behind a crescent of six exhibits that say the same
    /// thing better, and the wordmark had already been lowered twice to
    /// dodge it (`HubSpaceView`, which also records that "some overlap
    /// is inherent"). Owner's call: the room is the home screen.
    ///
    /// THE COST IS REAL AND IS THE OWNER'S. "Put the Gallery away" is
    /// the app's only `dismissImmersiveSpace`, and the palette bead that
    /// carries Home and Dim exists only while a module does — so on the
    /// home screen there is now no in-app exit, only the Digital Crown.
    /// That is a documented trade, not an oversight: the button was
    /// added on 2026-08-07 for discoverability, and a window standing in
    /// front of the thing it describes costs more than a signpost for a
    /// gesture the system already provides everywhere.
    private func syncMainWindow() {
        // Never in UI tests: XCUITest cannot see into an immersive
        // space, so the flat catalog is the only surface it has. The
        // gallery is normally held back under `-uiTesting`, but a test
        // that opens it must not lose the window it is driving.
        #if DEBUG
        if UserDefaults.standard.bool(forKey: "uiTesting") { return }
        #endif
        if appModel.activeModuleID == nil {
            dismissWindow(id: MainWindowView.windowID)
        } else {
            openWindow(id: MainWindowView.windowID)
        }
    }

    var body: some View {
        // A ZSTACK AROUND THE GROUP, so the flag at the bottom has a
        // stable sibling to hang off. See the comment down there.
        ZStack {
            Group {
                // Studio Mode's dark gallery sits behind whatever is active —
                // hub ring or module — and survives switches between them.
                if appModel.studioMode {
                    StudioEnvironmentView()
                        .id("studio")
                } else if appModel.roomDimming > 0.01 {
                    // The middle setting: the room stays, but a dark shell
                    // gives the physics its contrast back.
                    RoomDimmerView(
                        level: appModel.roomDimming,
                        radius: appModel.activeModule?.preferredDimmingRadius
                            ?? RoomDimmerView.defaultRadius)
                        // Keyed on the radius as well as on being the dimmer:
                        // the shell's mesh is built once in `make`, so a
                        // module that wants a different one needs a new view
                        // identity to get it.
                        .id("dimmer-\(appModel.activeModule?.preferredDimmingRadius ?? 0)")
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
                        // NO CARD OF WORDS STANDS IN A LAB, and the room
                        // has now rejected two of them.
                        //
                        // `FirstRunHint` hung at head height on the left
                        // of every module, naming the lab and saying
                        // "pinch to explore" until it was dismissed. It
                        // came out on 2026-08-08 — unnecessary, and in
                        // the way. Its replacement, `RoomTeach`, moved
                        // the same paragraph in FRONT of the apparatus
                        // so the window could not stand through it, and
                        // the owner cut that on 2026-08-09 for the same
                        // reason one step worse: a 262-line card whose
                        // whole job was to cover the bench it described.
                        //
                        // The teach survives in the module WINDOW
                        // (`ModuleHostView`, `ModuleDescriptor.firstRunHint`),
                        // which is where it started and the one place it
                        // obscures no physics. `AppSettings.seenHints`
                        // stays: that window copy is gated on it.
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

            // THE FLAG HANGS OFF A STABLE LEAF THAT IS A SIBLING OF THE
            // `Group`, NOT A MODIFIER ON IT.
            //
            // A `Group` does not wrap its children in a container view
            // — it applies each modifier to EVERY child individually. So
            // this pair was one `onAppear`/`onDisappear` per child, and
            // the child count changes with state: entering a dimmed
            // module (Gravity Lab dims 0.85, Electric Fields and
            // Magnetism 0.35) removes `HubSpaceView` and adds
            // `RoomDimmerView` plus the module `ZStack`. SwiftUI does
            // not order those callbacks, so when the removal lands last
            // the flag reads FALSE with the space open — and
            // `ModuleHostView` then offers "Show in room" for a lab that
            // is already in the room, which fails with "Couldn't open
            // the room."
            //
            // MOVING IT TO `.background` ON THE SAME `Group` DOES NOT
            // FIX THAT, and the first attempt at this did exactly that.
            // A background is a modifier like any other, so it
            // distributes over the children too: one leaf per PRESENT
            // child rather than one leaf, and the dimmer branch coming
            // and going still fires a spurious `onDisappear`. The fix
            // has to be a SIBLING, not a modifier.
            //
            // Inside this `ZStack` the leaf is a sibling of the whole
            // `Group`, so it exists exactly once for as long as this
            // view does, whatever the branches inside do.
            Color.clear
                .frame(width: 0, height: 0)
                .onAppear {
                    appModel.isImmersiveSpaceOpen = true
                    syncMainWindow()
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
