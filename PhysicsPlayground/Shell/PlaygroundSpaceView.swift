//
//  PlaygroundSpaceView.swift
//  Physics Playground — Shell
//
//  The single shared immersive space: the spatial hub when no module is
//  active, the module's scene otherwise. `.id(module.id)` gives each
//  module its own view identity so per-module @State is rebuilt on a
//  switch, while module models live on in AppModel.
//

import AVFAudio
import Combine
import RealityKit
import RenderKit
import SwiftUI

struct PlaygroundSpaceView: View {
    static let spaceID = "PlaygroundSpace"

    @Environment(AppModel.self) private var appModel
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace

    /// Nothing builds until the prop cache is warm: a cold
    /// `PropCache.prototype` falls back to a synchronous load and would hang
    /// the first frames. The space opens on plain passthrough, the cache
    /// fills, then the arrival choreography starts.
    @State private var ready = false

    /// The flat catalog does not stand behind the gallery: on the home
    /// screen it duplicated the exhibits. Known cost: no in-app exit from the
    /// home screen except the Digital Crown.
    private func syncMainWindow() {
        if appModel.activeModuleID == nil {
            dismissWindow(id: MainWindowView.windowID)
        } else if appModel.wantsMainWindow {
            // Only when none is up: a second `openWindow` on a value-less group is
            // a second window.
            openWindow(id: MainWindowView.windowID)
        }
    }

    /// XCUITest cannot see into an immersive space, so under `-uiTesting`
    /// the app turns round on the way in and becomes a window app. Not
    /// `#if DEBUG`-gated: the UI test target runs the shipping
    /// configuration. It only dismisses; `onDisappear` below reopens the
    /// window, and opening it here as well made two.
    private func retreatForUITesting() -> Bool {
        guard HubView.isUITesting else { return false }
        Task { await dismissImmersiveSpace() }
        return true
    }

    #if DEBUG
    /// `-frameTour <seconds>`: walks every lab through the one door, back
    /// to the home between each, that long in each place, round and round —
    /// so `-frameLog` measures the doors as well as the rooms, which the
    /// simulator cannot otherwise reach without a pinch. `-frameTourLabs
    /// gravitylab,optics` walks only those.
    private func runFrameTour() async {
        let defaults = UserDefaults.standard
        let dwell = defaults.double(forKey: "frameTour")
        guard dwell > 0 else { return }
        let only = defaults.string(forKey: "frameTourLabs")?.split(separator: ",").map(String.init)
        let stops = (only ?? ModuleCatalog.allIDs).flatMap { [Optional($0), nil] }
        while !Task.isCancelled {
            for stop in stops {
                try? await Task.sleep(for: .seconds(dwell))
                guard !Task.isCancelled else { return }
                LaunchTrace.mark("[frames] door to \(stop ?? "home")")
                appModel.go(to: stop)
            }
        }
    }

    /// The screenshot hooks that need a scene to have appeared.
    private func applyDebugLaunchArguments() {
        let defaults = UserDefaults.standard
        if defaults.bool(forKey: "settingsOpen") {
            openWindow(id: SettingsView.windowID)
        }
        // `-moreOpen 1` unfolds the title bar's More (the lab's secondary
        // controls and its live numbers), since the simulator cannot press it
        // while photographing the room.
        if defaults.bool(forKey: "moreOpen") {
            appModel.moreOpen = true
        }
        // Each of these clears the bench, builds one small loop a hand could
        // have built, and selects the part the feature is about.
        // `-circCoil 1`: battery → resistor → inductor, field layer lit.
        if defaults.bool(forKey: "circCoil") {
            let circuits = appModel.circuitsModel
            circuits.clearBench()
            if let battery = circuits.add(.battery, at: SIMD3(-0.45, 1.25, -0.85)),
               let resistor = circuits.add(.resistor, at: SIMD3(0, 1.5, -0.85)),
               let coil = circuits.add(.inductor, at: SIMD3(0.45, 1.25, -0.85)) {
                _ = circuits.connectTerminals(.init(componentID: battery, end: 1),
                                              .init(componentID: resistor, end: 0))
                _ = circuits.connectTerminals(.init(componentID: resistor, end: 1),
                                              .init(componentID: coil, end: 0))
                _ = circuits.connectTerminals(.init(componentID: coil, end: 1),
                                              .init(componentID: battery, end: 0))
                circuits.select(id: coil)
            }
            circuits.showMagneticField = true
        }
        // `-circHeat 1` (or `-circFault resistor`): a 9 V battery across a
        // 10 Ω resistor — 8 W into a 2 W part, which scorches in under a
        // second of overload.
        let fault = defaults.string(forKey: "circFault")
        if defaults.bool(forKey: "circHeat") || fault == "resistor" {
            let circuits = appModel.circuitsModel
            circuits.clearBench()
            if let battery = circuits.add(.battery, at: SIMD3(-0.35, 1.3, -0.85)),
               let resistor = circuits.add(.resistor, at: SIMD3(0.35, 1.3, -0.85)) {
                circuits.setComponentValue(id: resistor, 10)
                _ = circuits.connectTerminals(.init(componentID: battery, end: 1),
                                              .init(componentID: resistor, end: 0))
                _ = circuits.connectTerminals(.init(componentID: resistor, end: 1),
                                              .init(componentID: battery, end: 0))
                circuits.select(id: resistor)
            }
        }
        // `-circAC 1.5`: an AC source across a bulb at that many hertz (clamped
        // to the rail), the source selected so its frequency rail hangs under it.
        if defaults.object(forKey: "circAC") != nil {
            let circuits = appModel.circuitsModel
            circuits.clearBench()
            if let source = circuits.add(.acSource, at: SIMD3(-0.35, 1.3, -0.85)),
               let bulb = circuits.add(.bulb, at: SIMD3(0.35, 1.3, -0.85)) {
                circuits.setACFrequency(id: source, defaults.double(forKey: "circAC"))
                _ = circuits.connectTerminals(.init(componentID: source, end: 1),
                                              .init(componentID: bulb, end: 0))
                _ = circuits.connectTerminals(.init(componentID: bulb, end: 1),
                                              .init(componentID: source, end: 0))
                circuits.select(id: source)
            }
        }
        // `-circKit 1`: every part on the shelf, unwired, in two rows of five
        // — the lab kit at a glance.
        if defaults.bool(forKey: "circKit") {
            let circuits = appModel.circuitsModel
            circuits.clearBench()
            let kinds: [CircuitsModel.ComponentKind] = [
                .battery, .acSource, .switcher, .fuse, .resistor,
                .capacitor, .inductor, .bulb, .led, .motor,
            ]
            for (index, kind) in kinds.enumerated() {
                let row = Double(index / 5), column = Double(index % 5)
                circuits.add(kind, at: SIMD3(-0.48 + column * 0.24, 1.42 - row * 0.24, -0.85))
            }
            circuits.settleStage()
        }
        // `-circLED 1`: 9 V through 470 Ω into an LED — about 15 mA, lit red.
        // `-circFault fuse|led` stages the overload that ends that part: a
        // fuse shorting a battery, an LED straight across one.
        if defaults.bool(forKey: "circLED") || fault == "led" || fault == "fuse" {
            let circuits = appModel.circuitsModel
            circuits.clearBench()
            let kind: CircuitsModel.ComponentKind = fault == "fuse" ? .fuse : .led
            if let battery = circuits.add(.battery, at: SIMD3(-0.35, 1.3, -0.85)),
               let part = circuits.add(kind, at: SIMD3(0.35, 1.3, -0.85)) {
                // Out of the battery's + (terminal 0) and into the LED's
                // anode (its terminal 0), so it is forward-biased.
                var feed = CircuitsModel.Terminal(componentID: battery, end: 0)
                if fault == nil, let resistor = circuits.add(.resistor, at: SIMD3(0, 1.48, -0.85)) {
                    circuits.setComponentValue(id: resistor, 470)
                    _ = circuits.connectTerminals(feed, .init(componentID: resistor, end: 0))
                    feed = .init(componentID: resistor, end: 1)
                }
                _ = circuits.connectTerminals(feed, .init(componentID: part, end: 0))
                _ = circuits.connectTerminals(.init(componentID: part, end: 1),
                                              .init(componentID: battery, end: 1))
                circuits.select(id: part)
            }
            circuits.settleStage()
        }
        // `-seedCircuits 1` drops a few parts (one aimed off-axis) for a
        // screenshot.
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
        // A ZStack around the Group, so the flag at the bottom has a stable
        // sibling to hang off.
        ZStack {
            // Nothing builds until the cache is warm; the gate covers the hub and
            // the modules too.
            if ready {
            Group {
                // What stands around the wearer (`Surroundings`): deep space
                // behind whatever is active — the home or a lab — surviving
                // switches between them, or the room with its dimming shell.
                if appModel.surroundings == .deepSpace {
                    DeepSpaceView(showsSun: !(appModel.activeModule?.drawsItsOwnSun ?? false))
                        .id("deep-space")
                }
                // The middle setting: the room stays, a dark shell gives the physics its
                // contrast back. Mounted unconditionally so it can ramp down when a lab
                // is left; off, it is one disabled entity. The dome is sized by its
                // transform, so the radius needs no `.id()`. It stays while deep space
                // arrives, which it does over the room (`AppModel.skyArrived`).
                if appModel.surroundings == .room || !appModel.isSkyUp {
                    RoomDimmerView()
                        .id("dimmer")
                }
                // The house music, for as long as the space is open: the home,
                // every lab and every door, one player so nothing restarts
                // (2026-11-02; it played in labs only until then).
                HouseMusicView()
                    .id("music")
                // The door (`AppModel.go(to:)`): the scene being left stays mounted,
                // drawn, until the one replacing it has settled, and the two cross-fade.
                ForEach(appModel.mountedScenes, id: \.self) { scene in
                    switch scene {
                    case .home:
                        HubSpaceView()
                            .id("hub")
                    case .lab(let id):
                        if let module = ModuleCatalog.descriptor(id: id, appModel: appModel) {
                            module.makeScene()
                                .id(module.id)
                        }
                    }
                }
                // What goes with the lab on screen, and only with it.
                if let module = appModel.activeModule {
                    ZStack {
                        // The shared room sensing stays alive while a module
                        // is on screen (device-only; inert in the simulator).
                        RoomSensingView()
                            .id("room-sensing")
                        // The lab anchor: drag it to put the apparatus where
                        // you actually have room. Hidden until asked for.
                        LabAnchorView(module: module)
                            .id("lab-anchor-\(module.id)")
                        // The Time Capsule's rail: folded away until the
                        // module is paused with a recording worth scrubbing.
                        TimeRailView(module: module)
                            .id("time-rail-\(module.id)")
                    }
                    #if DEBUG
                    // `-pauseAfter` counts from here — the lab on screen —
                    // not from launch; see `AppModel.runStagedPause`.
                    .task(id: module.id) { await appModel.runStagedPause(for: module) }
                    #endif
                }
            }
            }

            // The flag hangs off a sibling leaf, not a modifier on the Group: a
            // Group applies each modifier to every child, in no promised order, so
            // the flag could read false with the space open. As a ZStack sibling
            // the leaf exists exactly once.
            Color.clear
                .frame(width: 0, height: 0)
                .onAppear {
                    appModel.isImmersiveSpaceOpen = true
                    syncMainWindow()
                }
                // The launch path: the only place guaranteed to run once on every start.
                .task {
                    // Mix with the wearer's own sound rather than stopping it.
                    HouseAudioSession.configure()
                    SoundPalette.warmUp()
                    SoundPalette.masterVolume = appModel.settings.masterVolume
                    // Before the retreat, not after: `-uiTesting 1` and a screenshot
                    // argument arrive together.
                    #if DEBUG
                    applyDebugLaunchArguments()
                    #endif
                    guard !retreatForUITesting() else { return }
                    // The sky is drawn off the main thread beside the props, and
                    // never outlasts them.
                    async let sky = SkyResources.prepare()
                    await PropCache.warmUp()
                    _ = await sky
                    ready = true
                    #if DEBUG
                    LaunchTrace.mark(appModel.activeModuleID.map { "space ready, mounting \($0)" }
                                     ?? "space ready, mounting the home")
                    await runFrameTour()
                    #endif
                }
                .onDisappear {
                    appModel.isImmersiveSpaceOpen = false
                    // Always bring the window back: once it is dismissed this leaf is the
                    // only thing that can notice the space closing. Guarded so one window
                    // never becomes two.
                    if appModel.wantsMainWindow {
                        openWindow(id: MainWindowView.windowID)
                    }
                }
                // The window follows the module, not the space: leaving a lab by the
                // Home petal returns to the gallery with the space still open.
                .onChange(of: appModel.activeModuleID) { syncMainWindow() }

            // The one place VoiceOver's actions arrive. One subscription rather
            // than six: `SpatialActionComponent` rides the entity that knows what
            // to do, so this walks up from whatever was activated exactly as the
            // gesture chains do.
            AccessibilityActionRouter()

            #if DEBUG
            // `-frameLog 1`: frame pacing in the console (`FrameLog`).
            if UserDefaults.standard.bool(forKey: "frameLog") {
                FrameLogView(scene: { [appModel] in
                    (appModel.activeModuleID ?? "home")
                        + (appModel.surroundings == .deepSpace ? " (space)" : "")
                })
            }
            #endif
        }
    }
}

/// Delivers VoiceOver's actions to whichever control was activated: a
/// `RealityView` holding two scene subscriptions for as long as the
/// space is open. `.increment` and `.decrement` are one call with a
/// sign; the primitive knows its own range.
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

/// An invisible emitter looping the house music (`AmbientScore`) for as
/// long as the space is open. It is played head-locked, so where the
/// emitter stands does not matter.
private struct HouseMusicView: View {
    @Environment(AppModel.self) private var appModel
    @State private var controller: AudioPlaybackController?
    @State private var emitter = Entity()

    /// How late the score may be ready and still swell: past this the
    /// wordmark is down, so a first launch's late score just fades in.
    private static let swellGrace: Duration = .seconds(2)

    var body: some View {
        RealityView { content in
            emitter.position = [0, 1.7, -1.0]
            content.add(emitter)
            // The space opening is the arrival: the music swells with it —
            // unless the wearer is listening to something of their own.
            if wanted { start(swell: true) }
        }
        .onChange(of: appModel.settings.ambientAudio) {
            // The settings toggle applies immediately, not next visit.
            if wanted { start(swell: false) } else { stop() }
        }
        // The wearer's own audio starting or stopping: the music yields,
        // and comes back plainly (2026-11-07).
        .onReceive(NotificationCenter.default.publisher(
            for: AVAudioSession.silenceSecondaryAudioHintNotification)) { note in
            let raw = note.userInfo?[AVAudioSessionSilenceSecondaryAudioHintTypeKey] as? UInt
            let begins = raw.flatMap(AVAudioSession.SilenceSecondaryAudioHintType.init(rawValue:)) == .begin
            if begins { stop() } else if wanted { start(swell: false) }
        }
        .onDisappear { stop() }
    }

    /// Asked for, and nothing of the wearer's own playing.
    private var wanted: Bool {
        HouseAudioSession.musicPlays(wanted: appModel.settings.ambientAudio,
                                     othersArePlaying: HouseAudioSession.othersArePlaying)
    }

    private func start(swell: Bool) {
        guard controller == nil else { return }
        let swellUntil = ContinuousClock.now + Self.swellGrace
        Task { @MainActor in
            // warmUp renders the score off-launch, after the one-shots; on a
            // first launch that can take a few seconds, so wait for it.
            for _ in 0..<120 where controller == nil {
                guard wanted else { return }
                let swells = swell && ContinuousClock.now < swellUntil
                if let started = SoundPalette.startAmbient(on: emitter, swell: swells) {
                    controller = started
                    #if DEBUG
                    LaunchTrace.mark(swells ? "music in, swelling with the arrival" : "music in")
                    #endif
                    return
                }
                try? await Task.sleep(for: .milliseconds(250))
            }
        }
    }

    private func stop() {
        if let controller { SoundPalette.stopAmbient(controller) }
        controller = nil
    }
}
