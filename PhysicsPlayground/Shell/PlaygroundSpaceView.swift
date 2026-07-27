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
import SwiftUI

struct PlaygroundSpaceView: View {
    static let spaceID = "PlaygroundSpace"

    @Environment(AppModel.self) private var appModel

    var body: some View {
        Group {
            // Studio Mode's dark gallery sits behind whatever is active —
            // hub ring or module — and survives switches between them.
            if appModel.studioMode {
                StudioEnvironmentView()
                    .id("studio")
            } else if appModel.roomDimming > 0.01 {
                // The middle setting: the room stays, but a dark shell
                // gives the physics its contrast back.
                RoomDimmerView(level: appModel.roomDimming)
                    .id("dimmer")
            }
            if let module = appModel.activeModule {
                ZStack {
                    module.makeScene()
                        .id(module.id)
                    // Real furniture hides virtual content behind it, and
                    // the shared room sensing stays alive while a module
                    // is on screen (device-only; inert in the simulator).
                    RoomOcclusionView()
                        .id("occlusion")
                    // The lab anchor: drag it to put the apparatus where
                    // you actually have room. Hidden until asked for.
                    LabAnchorView(module: module)
                        .id("lab-anchor-\(module.id)")
                    // The four-bead navigation cluster — kept as the
                    // ZStack's second child, the slot where RealityView
                    // content provably renders.
                    ModuleOrbControlsView(module: module)
                        .id("orbs-\(module.id)")
                    // The shared shell pods: the module's controls, its
                    // experiments, and its legend, surrounding the user.
                    ShellPodsView(module: module)
                        .id("shellpods-\(module.id)")
                    // The experiments watcher: notices when the physics
                    // reaches a goal and chimes exactly once.
                    ExperimentCheckerView(moduleID: module.id)
                        .id("experiments-\(module.id)")
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
        .onAppear { appModel.isImmersiveSpaceOpen = true }
        .onDisappear { appModel.isImmersiveSpaceOpen = false }
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
