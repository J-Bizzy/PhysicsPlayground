//
//  WindTunnelSpaceView.swift
//  Physics Playground — Wind Tunnel module
//
//  The wind tunnel immersive scene. The cylinder and probe route through
//  RenderKit's ManipulationRouter into plane coordinates; particles and
//  the cylinder's spin animation tick on SceneEvents.Update.
//

import PhysicsCore
import SwiftUI
import RealityKit
import RenderKit

struct WindTunnelSpaceView: View {
    @Environment(WindTunnelModel.self) private var model
    @Environment(AppModel.self) private var appModel
    @State private var renderer: WindTunnelRenderer?
    @State private var fanDrag: RelativeDrag?
    @State private var sensing = WindTunnelSensing()
    /// Two gauges standing at the mouth of the section: the wind you are
    /// running and the spin you are putting on the cylinder. Both were
    /// sliders on a card; both are the kind of number a tunnel operator
    /// reaches out and turns.
    @State private var dials: DialConsole?

    var body: some View {
        RealityView { content, attachments in
            let renderer = WindTunnelRenderer()
            content.add(renderer.root)

            // Control pods: the wind card floats beside the fan, the
            // test-body card hangs low under the section.
            let podsRoot = PodMount.makeRoot(module: "windtunnel")
            let console = DialConsole([
                .init(name: "dial-wind", title: "Wind",
                      center: SIMD3(-0.86, 1.16, -0.78),
                      range: WindTunnelModel.windSpeedRange,
                      accent: DesignTokens.Palette.windAccentUI,
                      read: { model.windSpeed },
                      write: { model.windSpeed = $0 },
                      format: { String(format: "%.2f m/s", $0) }),
                .init(name: "dial-spin", title: "Spin",
                      center: SIMD3(0.86, 1.16, -0.78),
                      range: WindTunnelModel.circulationRange,
                      accent: DesignTokens.Palette.windAccentUI,
                      read: { model.circulation },
                      write: { model.circulation = $0 },
                      format: { String(format: "%.0f rpm", $0 / (2 * .pi
                          * model.cylinderRadius * model.cylinderRadius) * 60 / (2 * .pi)) }),
            ])
            renderer.root.addChild(console.root)
            dials = console

            renderer.root.addChild(podsRoot)
            PodMount.mount(attachments.entity(for: "pod-wind"), name: "Wind",
                           at: [-1.35, 1.95, -1.15], in: podsRoot)
            PodMount.mount(attachments.entity(for: "pod-body"), name: "Test body",
                           at: [0.72, 1.05, -1.0], in: podsRoot)
            if let readout = attachments.entity(for: "probe") {
                readout.position = [0, 0.02, 0]
                renderer.probeAnchor.addChild(readout)
            }

            renderer.subscriptions.append(
                content.subscribe(to: SceneEvents.Update.self) { [weak renderer] event in
                    dials?.sync()
                    // On device, the room and hands flow into the field.
                    if sensing.isRunning {
                        model.obstacles = sensing.field
                    }
                    renderer?.tick(dt: event.deltaTime, model: model)
                    podsRoot.isEnabled = appModel.controlPodsVisible
                    PodMount.persistIfMoved(podsRoot)
                    // The lab's placement in the user's room — a pure
                    // display offset, safe because every grab in this app
                    // moves a body by hand DISPLACEMENT, which a constant
                    // translation leaves untouched.
                    renderer?.root.position = appModel.labPlacement.offset
                    // …but the control pods do NOT go with it: the user
                    // parked them where they wanted them, and moving the
                    // apparatus is not a request to move the controls.
                    podsRoot.position = -appModel.labPlacement.offset
                }
            )

            self.renderer = renderer
        } attachments: {
            Attachment(id: "pod-wind") {
                WindPod()
                    .environment(model)
            }
            Attachment(id: "pod-body") {
                TestBodyPod()
                    .environment(model)
            }
            Attachment(id: "probe") {
                WindTunnelProbeReadout()
                    .environment(model)
                    .padding(12)
                    .glassBackgroundEffect()
            }
        }
        // The fan moves by the hand's displacement — no system
        // manipulation, no lurch toward the hand; its beam and hum ride
        // along in the same frame.
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .targetedToAnyEntity()
                .onChanged { value in
                    guard let renderer else { return }
                    let hand = SIMD3<Double>(SIMD3<Float>(value.convert(
                        value.location3D, from: .local, to: .scene)))
                    if dials?.advanceTwist(hand: hand) == true { return }
                    if fanDrag == nil {
                        if dials?.beginTwist(on: value.entity, hand: hand) == true { return }
                        fanDrag = beginDrag(entity: value.entity, hand: hand, renderer: renderer)
                    }
                    guard let fanDrag else { return }
                    apply(drag: fanDrag, hand: hand, renderer: renderer)
                }
                .onEnded { value in
                    if let fanDrag, let renderer {
                        let hand = SIMD3<Double>(SIMD3<Float>(value.convert(
                            value.location3D, from: .local, to: .scene)))
                        apply(drag: fanDrag, hand: hand, renderer: renderer)
                    }
                    fanDrag = nil
                    dials?.endTwist()
                }
        )
        .task {
            // Hand tracking + scene reconstruction: device-only, quietly
            // absent in the simulator.
            await sensing.start()
        }
    }

    /// Resolves a pinch to a relative-drag session (fan, cylinder,
    /// test body, or probe).
    private func beginDrag(
        entity: Entity, hand: SIMD3<Double>, renderer: WindTunnelRenderer
    ) -> RelativeDrag? {
        let section = SIMD3<Double>(WindTunnelRenderer.sectionCenter)
        var current: Entity? = entity
        while let candidate = current {
            switch candidate.name {
            case "fan":
                guard let target = renderer.fanWorldPosition() else { return nil }
                return RelativeDrag(name: "fan", target: target, hand: hand)
            case WindTunnelRenderer.cylinderName:
                let target = section
                    + SIMD3(model.cylinderCenter.x, 0, model.cylinderCenter.y)
                return RelativeDrag(name: candidate.name, target: target, hand: hand)
            case WindTunnelRenderer.probeName:
                let target = section + SIMD3(model.probePosition.x,
                                             Double(renderer.probeHeight),
                                             model.probePosition.y)
                return RelativeDrag(name: candidate.name, target: target, hand: hand)
            default:
                current = candidate.parent
            }
        }
        return nil
    }

    private func apply(drag: RelativeDrag, hand: SIMD3<Double>, renderer: WindTunnelRenderer) {
        let position = SIMD3<Float>(drag.position(forHand: hand))
        switch drag.name {
        case "fan":
            renderer.moveFan(toWorld: SIMD3<Double>(position))
        case WindTunnelRenderer.cylinderName:
            model.moveCylinder(to: renderer.planePoint(fromWorld: position))
        case WindTunnelRenderer.probeName:
            renderer.probeHeight = min(
                max(position.y - WindTunnelRenderer.sectionCenter.y,
                    -WindTunnelRenderer.halfHeight),
                WindTunnelRenderer.halfHeight)
            model.moveProbe(to: renderer.planePoint(fromWorld: position))
        default:
            break
        }
    }
}

/// The wind's own pod, floating beside the fan it controls: speed,
/// time, and — for the cylinder — spin and its Kutta–Joukowski lift.
struct WindPod: View {
    @Environment(WindTunnelModel.self) private var model

    var body: some View {
        @Bindable var model = model

        ControlPod(title: "Wind", icon: "wind",
                   tint: DesignTokens.Palette.windAccent) {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(model.windSpeed, specifier: "%.2f") m/s")
                    .font(DesignTokens.TypeScale.control.monospacedDigit())
                Slider(value: $model.windSpeed, in: WindTunnelModel.windSpeedRange)
                    .accessibilityLabel("Wind speed")
            }
            if model.testBody == .cylinder {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Spin: \(model.spinRPM, specifier: "%.0f") rpm")
                        .font(DesignTokens.TypeScale.control.monospacedDigit())
                    Slider(value: $model.circulation, in: WindTunnelModel.circulationRange)
                        .accessibilityLabel("Spin (circulation)")
                }
                if abs(model.liftPerSpan) > 0.02 {
                    Text("Lift: \(abs(model.liftPerSpan), specifier: "%.2f") N/m")
                        .font(DesignTokens.TypeScale.control.monospacedDigit())
                        .foregroundStyle(DesignTokens.Palette.forceVector)
                }
            }
            HStack(spacing: DesignTokens.Panel.rowSpacing) {
                Button {
                    model.isPaused.toggle()
                } label: {
                    Image(systemName: model.isPaused ? "play.fill" : "pause.fill")
                }
                .buttonStyle(.podQuiet)
                .accessibilityLabel(model.isPaused ? "Resume air" : "Freeze air")
                VStack(alignment: .leading, spacing: 2) {
                    Text("Slow motion ×\(model.timeScale, specifier: "%.1f")")
                        .font(DesignTokens.TypeScale.footnote.monospacedDigit())
                    Slider(value: $model.timeScale, in: WindTunnelModel.timeScaleRange)
                        .accessibilityLabel("Time scale")
                }
            }
        }
    }
}

/// The shape zoo under the test section: same frontal size, wildly
/// different measured drag.
struct TestBodyPod: View {
    @Environment(WindTunnelModel.self) private var model

    var body: some View {
        ControlPod(title: "Test body", icon: "cube",
                   tint: DesignTokens.Palette.windAccent, width: 290) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 84), spacing: 6)], spacing: 6) {
                ForEach(DragBody.allCases) { body in
                    Button {
                        model.testBody = body
                    } label: {
                        VStack(spacing: 1) {
                            Text(bodyName(body))
                                .font(DesignTokens.TypeScale.footnote)
                            Text("Cd \(body.dragCoefficient, specifier: "%.2f")")
                                .font(.system(size: 10).monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.podQuiet)
                    .tint(model.testBody == body ? DesignTokens.Palette.windAccent : nil)
                    .accessibilityLabel("Put the \(bodyName(body)) in the wind")
                }
            }
            Text("Cd \(model.testBody.dragCoefficient, specifier: "%.2f")   drag \(model.dragForce, specifier: "%.3f") N")
                .font(DesignTokens.TypeScale.control.monospacedDigit())
                .foregroundStyle(DesignTokens.Palette.forceVector)
                .accessibilityLabel("Drag coefficient \(model.testBody.dragCoefficient), drag force \(model.dragForce) newtons")
        }
    }

    private func bodyName(_ body: DragBody) -> String {
        switch body {
        case .cylinder: "Cylinder"
        case .sphere: "Sphere"
        case .teardrop: "Teardrop"
        case .cube: "Cube"
        case .flatDisc: "Flat disc"
        case .cone: "Cone"
        case .car: "Car"
        case .truck: "Truck"
        case .plane: "Plane"
        }
    }
}

/// The little card floating above the probe.
struct WindTunnelProbeReadout: View {
    @Environment(WindTunnelModel.self) private var model

    var body: some View {
        let readout = model.probeReadout
        VStack(alignment: .leading, spacing: 4) {
            Text("\(readout.speed, specifier: "%.2f") m/s")
                .font(DesignTokens.TypeScale.sectionHeader.monospacedDigit())
            Text("×\(readout.speedRatio, specifier: "%.2f") of the wind")
                .font(DesignTokens.TypeScale.footnote.monospacedDigit())
                .foregroundStyle(.secondary)
            Text("Cp = \(readout.pressureCoefficient, specifier: "%.2f")")
                .font(DesignTokens.TypeScale.footnote.monospacedDigit())
                .foregroundStyle(readout.pressureCoefficient > 0 ? .green : .orange)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Probe: \(model.probeReadout.speed) meters per second, pressure coefficient \(model.probeReadout.pressureCoefficient)")
    }
}
