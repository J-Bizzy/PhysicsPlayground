//
//  PlaygroundSpaceView.swift
//  Physics Playground — Shell
//
//  The single shared immersive space: the spatial hub when no module is
//  active, the module's scene otherwise. `.id(module.id)` gives each
//  module its own view identity so per-module @State is rebuilt on a
//  switch, while module models live on in AppModel.
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
    /// The screenshot hooks that need a scene to have appeared.
    private func applyDebugLaunchArguments() {
        let defaults = UserDefaults.standard
        if defaults.bool(forKey: "settingsOpen") {
            openWindow(id: SettingsView.windowID)
        }
        // `-physicsOpen 1` unfolds the Physics box, since the simulator cannot
        // press the title bar's button while photographing the room.
        if defaults.bool(forKey: "physicsOpen") {
            appModel.physicsBoardOpen = true
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
        // `-circHeat 1`: a 9 V battery across a 10 Ω resistor — 8 W into
        // a 2 W part, which scorches in under a second of overload.
        if defaults.bool(forKey: "circHeat") {
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
        // `-circAC 3`: an AC source across a bulb at that many hertz, the
        // source selected so its frequency rail hangs under it.
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
                // Studio Mode's dark gallery sits behind whatever is active —
                // hub ring or module — and survives switches between them.
                if appModel.studioMode {
                    StudioEnvironmentView()
                        .id("studio")
                } else {
                    // The middle setting: the room stays, a dark shell gives the physics its
                    // contrast back. Mounted unconditionally so it can ramp down when a lab
                    // is left; off, it is one disabled entity. The dome is sized by its
                    // transform, so the radius needs no `.id()`.
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
                        // One bead; pinch it and the labs unfold.
                        PaletteView(module: module)
                            .id("palette-\(module.id)")
                        // The Time Capsule's rail: folded away until the
                        // module is paused with a recording worth scrubbing.
                        TimeRailView(module: module)
                            .id("time-rail-\(module.id)")
                        // The Physics box: folded until the title bar's ƒ button.
                        PhysicsBoardView(module: module)
                            .id("physics-\(module.id)")
                        // Quiet lab room tone under every module (not the hub); no per-module
                        // id, so it runs seamlessly across switches.
                        AmbientLabAudioView()
                            .id("ambient")
                    }
                    #if DEBUG
                    // `-pauseAfter` counts from here — the lab on screen —
                    // not from launch; see `AppModel.runStagedPause`.
                    .task(id: module.id) { await appModel.runStagedPause(for: module) }
                    #endif
                } else {
                    HubSpaceView()
                        .id("hub")
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
                    SoundPalette.warmUp()
                    SoundPalette.masterVolume = appModel.settings.masterVolume
                    // Before the retreat, not after: `-uiTesting 1` and a screenshot
                    // argument arrive together.
                    #if DEBUG
                    applyDebugLaunchArguments()
                    #endif
                    guard !retreatForUITesting() else { return }
                    await PropCache.warmUp()
                    ready = true
                    #if DEBUG
                    LaunchTrace.mark(appModel.activeModuleID.map { "space ready, mounting \($0)" }
                                     ?? "space ready, mounting the home")
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
