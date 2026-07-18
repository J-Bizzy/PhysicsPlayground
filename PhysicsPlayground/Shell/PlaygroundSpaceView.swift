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
            if let module = appModel.activeModule {
                ZStack {
                    module.makeScene()
                        .id(module.id)
                    // The shared orb controls (pause / back) every module gets.
                    ModuleOrbControlsView(module: module)
                        .id("orbs-\(module.id)")
                    // Quiet lab room tone under every module (not the hub);
                    // no per-module id, so it runs seamlessly across switches.
                    AmbientLabAudioView()
                        .id("ambient")
                    // Watches this module's challenge predicates.
                    ChallengeCheckerView(moduleID: module.id)
                        .id("challenges-\(module.id)")
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
    @State private var controller: AudioPlaybackController?

    var body: some View {
        RealityView { content in
            let emitter = Entity()
            emitter.position = [0, 1.7, -1.0]
            content.add(emitter)
            Task { @MainActor in
                // warmUp synthesizes off-launch; retry briefly until ready.
                for _ in 0..<40 where controller == nil {
                    if let started = SoundPalette.startAmbient(on: emitter) {
                        controller = started
                        return
                    }
                    try? await Task.sleep(for: .milliseconds(250))
                }
            }
        }
        .onDisappear {
            controller?.stop()
            controller = nil
        }
    }
}
