//
//  WavesSpaceView.swift
//  Physics Playground — Waves module
//
//  The 3D interference field immersive scene. Sources and the probe are
//  free-floating grabbables routed through RenderKit's
//  ManipulationRouter (positions are room coordinates, 1:1); the wave
//  clock is SceneEvents.Update, scaled and pausable in the model.
//

import PhysicsCore
import SwiftUI
import RealityKit
import RenderKit

struct WavesSpaceView: View {
    @Environment(WavesModel.self) private var model
    @State private var renderer: WavesRenderer?
    @State private var drag: RelativeDrag?
    @Environment(AppModel.self) private var appModel
    /// The per-source control ring: invert phase, flyby, delete, and
    /// the amplitude bead. Tap a source to open it.
    @State private var bloom = Bloom()
    @State private var ring = RingState()
    /// The medium's two defining numbers, as gauges you turn: frequency
    /// and wave speed. Between them they set the wavelength, which is the
    /// length the whole pattern is built from — λ = c/f, and the silence
    /// surfaces move when either moves.
    ///
    /// Placed low and in front, outside the interference volume worth
    /// walking through rather than inside it, and at ~16° below eye so
    /// they read at the same glance as the field (see the Wind Tunnel
    /// gauges for what happens when that angle is not checked).
    ///
    /// This module gets gauges but NOT a scale rig — see DECISIONS.md,
    /// 2026-07-29: a display-only scale would move the visible nodal
    /// sheets while the audible node stayed put, which is the one thing
    /// the Silence Walk cannot survive.
    @State private var frequencyDial: SpatialDialControl?
    @State private var speedDial: SpatialDialControl?
    /// The layers bank, standing beside the gauges: which representations
    /// of the field are switched on.
    ///
    /// "Listen to the field" is in here rather than left on the panel
    /// because it IS a layer — the amplitude at your ears is another way
    /// of showing the same field, and it happens to be the one that makes
    /// this module unforgettable. Putting it on the bank puts it where a
    /// user will actually find it.
    ///
    /// The gaze probe stays on the panel: it is an input mode, not a
    /// representation, and it is device-only.
    @State private var layers: SpatialLayerBank?

    var body: some View {
        RealityView { content in
            let renderer = WavesRenderer()
            content.add(renderer.root)
            renderer.root.addChild(bloom.root)

            let faceNormal = SIMD3<Float>(0, 0.4, 1)
            let frequency = SpatialDialControl(
                name: "frequency-dial",
                center: SIMD3(-0.40, 1.00, -1.70),
                normal: faceNormal,
                accent: UIColor(DesignTokens.Palette.wavesAccent),
                range: WavesModel.frequencyRange,
                read: { model.frequency },
                write: { model.frequency = $0 },
                // Just the frequency. λ was on here too until a screenshot
                // showed the field already draws its own "λ = 33 cm"
                // callout directly above these gauges, and the doubled
                // label was wide enough to collide with the speed gauge's.
                format: { String(format: "%.1f Hz", $0) })
            let speed = SpatialDialControl(
                name: "speed-dial",
                center: SIMD3(-0.05, 1.00, -1.70),
                normal: faceNormal,
                accent: UIColor(DesignTokens.Palette.wavesAccent),
                range: WavesModel.speedRange,
                read: { model.waveSpeed },
                write: { model.waveSpeed = $0 },
                format: { String(format: "%.2f m/s", $0) })
            renderer.root.addChild(frequency.root)
            renderer.root.addChild(speed.root)
            self.frequencyDial = frequency
            self.speedDial = speed

            let bank = SpatialLayerBank(
                accent: UIColor(DesignTokens.Palette.wavesAccent),
                layers: [
                    .init(id: "silence", label: "Silence surfaces",
                          symbol: "circle.dotted",
                          isOn: { model.showSilenceSurfaces },
                          toggle: { model.showSilenceSurfaces.toggle() }),
                    .init(id: "wavefronts", label: "Wavefronts",
                          symbol: "wave.3.right",
                          isOn: { model.showWavefronts },
                          toggle: { model.showWavefronts.toggle() }),
                    .init(id: "listen", label: "Listen",
                          symbol: "ear",
                          isOn: { model.listenToField },
                          toggle: { model.listenToField.toggle() }),
                    .init(id: "fringes", label: "Fringe screen",
                          symbol: "barcode",
                          isOn: { model.showFringeScreen },
                          toggle: { model.showFringeScreen.toggle() }),
                ])
            renderer.root.addChild(bank.root)
            self.layers = bank

            #if DEBUG
            // `-wavesFringes 1` raises the screen at launch, so the fringe
            // pattern can be screenshot-checked from the CLI.
            if UserDefaults.standard.bool(forKey: "wavesFringes") {
                model.showFringeScreen = true
            }
            #endif

            renderer.subscriptions.append(
                content.subscribe(to: SceneEvents.Update.self) { [weak renderer] event in
                    model.step(dt: event.deltaTime)
                    // Look-to-measure: with the probe following the head
                    // ray, turning to face a part of the field reads it
                    // out there. Head direction, not eye gaze — visionOS
                    // never hands an app the eyes, and nothing here
                    // pretends otherwise.
                    if model.lookProbe, let ray = appModel.room.lookRay,
                       let point = WavesModel.region.point(
                        onRay: ray.origin, direction: ray.direction,
                        reach: model.lookReach) {
                        model.moveProbe(to: point)
                    }
                    syncBloom(dt: event.deltaTime)
                    // Out here, not at the end of syncBloom: that returns
                    // early when no source ring is open, which would leave
                    // the needles frozen most of the time.
                    frequencyDial?.refresh()
                    speedDial?.refresh()
                    // Beside the gauges, same ~15° band, clear of the
                    // interference volume worth walking through.
                    layers?.update(
                        anchor: SIMD3(0.42, 1.05, -1.65),
                        viewer: appModel.room.headPosition.map { SIMD3<Float>($0) },
                        dt: event.deltaTime)
                    renderer?.tick(model, listener: appModel.room.headPosition)
                    // The lab's placement in the user's room — a pure
                    // display offset, safe because every grab in this app
                    // moves a body by hand DISPLACEMENT, which a constant
                    // translation leaves untouched.
                    renderer?.root.position = appModel.labPlacement.offset
                    // …but the control pods do NOT go with it: the user
                    // parked them where they wanted them, and moving the
                    // apparatus is not a request to move the controls.
                }
            )

            #if DEBUG
            // `-wavRing 1` opens the first source's control ring at
            // launch, for CLI screenshots.
            if UserDefaults.standard.bool(forKey: "wavRing"),
               let first = model.sources.first {
                model.select(id: first.id)
                ring.openID = first.id
            }
            #endif
            renderer.tick(model, listener: appModel.room.headPosition)
            self.renderer = renderer
        }
        .simultaneousGesture(
            TapGesture()
                .targetedToAnyEntity()
                .onEnded { value in
                    if bloom.handleTap(value.entity) { return }
                    // A tap on a source selects it and toggles its
                    // control ring; anything else folds the ring.
                    if layers?.handleTap(value.entity) == true { return }
                    var current: Entity? = value.entity
                    while let candidate = current {
                        if let id = UUID(uuidString: candidate.name),
                           model.sources.contains(where: { $0.id == id }) {
                            model.select(id: id)
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
                    let hand = SIMD3<Double>(SIMD3<Float>(value.convert(
                        value.location3D, from: .local, to: .scene)))
                    // Gauges first, in their parent's space — the root
                    // carries `LabPlacement.offset`, so a world-space hand
                    // would twist by an amount that drifts once the user
                    // moves their lab.
                    if let renderer {
                        let inRoot = SIMD3<Double>(renderer.root.convert(
                            position: SIMD3<Float>(hand), from: nil))
                        if twistDials(entity: value.entity, hand: inRoot) { return }
                    }
                    if bloom.updateGrip(hand: SIMD3<Float>(hand)) { return }
                    if drag == nil,
                       bloom.beginGrip(value.entity, hand: SIMD3<Float>(hand)) {
                        return
                    }
                    if drag == nil {
                        var current: Entity? = value.entity
                        while let candidate = current {
                            if candidate.name == WavesRenderer.probeName {
                                drag = RelativeDrag(name: candidate.name,
                                                    target: model.probePosition, hand: hand)
                                break
                            }
                            if let id = UUID(uuidString: candidate.name),
                               let source = model.sources.first(where: { $0.id == id }) {
                                model.select(id: id)
                                drag = RelativeDrag(name: candidate.name,
                                                    target: source.wave.position, hand: hand)
                                break
                            }
                            current = candidate.parent
                        }
                    }
                    guard let drag else { return }
                    let position = drag.position(forHand: hand)
                    if drag.name == WavesRenderer.probeName {
                        model.moveProbe(to: position)
                    } else if let id = UUID(uuidString: drag.name) {
                        model.moveSource(id: id, to: position)
                    }
                }
                .onEnded { _ in
                    frequencyDial?.endTwist()
                    speedDial?.endTwist()
                    bloom.endGrip()
                    drag = nil
                }
        )
    }

    /// Routes a drag to whichever gauge it started on. True once a twist
    /// owns the gesture, so the caller stops looking.
    private func twistDials(entity: Entity, hand: SIMD3<Double>) -> Bool {
        for dial in [frequencyDial, speedDial].compactMap({ $0 }) {
            if dial.isTwisting {
                dial.updateTwist(hand: hand)
                return true
            }
            if dial.root.isEnabled, dial.owns(entity) {
                dial.beginTwist(hand: hand)
                dial.updateTwist(hand: hand)
                return true
            }
        }
        return false
    }

    /// The tapped source's ring: amplitude is the bead you pull;
    /// inverting phase, sending it on a Doppler flyby, and deleting
    /// are the petals. The whole field reorganises live under all of
    /// them — the readout IS the room.
    private func syncBloom(dt: Double) {
        if let openID = ring.openID,
           !model.sources.contains(where: { $0.id == openID }) {
            ring.openID = nil
        }
        guard let uuid = ring.openID,
              let source = model.sources.first(where: { $0.id == uuid }) else {
            bloom.update(anchor: .zero, viewer: nil, revealTarget: 0, dt: dt)
            bloom.clearTarget()
            return
        }

        bloom.retarget(
            uuid,
            petals: [
                .init(name: "Invert phase", symbol: "arrow.up.arrow.down",
                      tint: UIColor(white: 0.45, alpha: 1)) {
                    model.select(id: uuid)
                    model.selectedInverted.toggle()
                },
                .init(name: "Doppler flyby", symbol: "wind",
                      tint: UIColor(white: 0.45, alpha: 1)) {
                    model.select(id: uuid)
                    model.selectedIsFlying.toggle()
                },
                .init(name: "Delete", symbol: "trash",
                      tint: UIColor(red: 0.85, green: 0.25, blue: 0.25, alpha: 1)) {
                    model.select(id: uuid)
                    model.removeSelectedSource()
                },
            ],
            grip: .init(
                name: "Amplitude",
                range: WavesModel.amplitudeRange,
                read: { model.selectedAmplitude },
                write: { model.selectedAmplitude = $0 },
                format: { String(format: "%.1f mm", $0 * 1000) },
                radius: { 0.05 }))

        let viewer = appModel.room.headPosition.map { SIMD3<Float>($0) }
        bloom.update(anchor: SIMD3<Float>(source.wave.position),
                     viewer: viewer, revealTarget: 1, dt: dt)
    }
}

/// The probe's live reading — amplitude, path difference, and the
/// interference verdict. Lives in the panel's Numbers section.
struct WavesProbeReadout: View {
    @Environment(WavesModel.self) private var model

    var body: some View {
        let readout = model.probeReadout
        VStack(alignment: .leading, spacing: 4) {
            Text("\(readout.amplitude * 1000, specifier: "%.1f") mm")
                .font(DesignTokens.TypeScale.sectionHeader.monospacedDigit())
            if let cycles = readout.pathDifferenceInWavelengths {
                Text("Δr = \(cycles, specifier: "%.2f") λ")
                    .font(DesignTokens.TypeScale.footnote.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            if let kind = readout.interference {
                Text(label(for: kind))
                    .font(DesignTokens.TypeScale.footnote.bold())
                    .foregroundStyle(color(for: kind))
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func label(for kind: WaveField.Interference) -> String {
        switch kind {
        case .constructive: "constructive"
        case .destructive: "silent"
        case .intermediate: "in between"
        }
    }

    private func color(for kind: WaveField.Interference) -> Color {
        switch kind {
        case .constructive: .green
        case .destructive: .red
        case .intermediate: .secondary
        }
    }
}
