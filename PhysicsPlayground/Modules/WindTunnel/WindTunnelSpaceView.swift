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
    @State private var router = ManipulationRouter()
    @State private var sensing = WindTunnelSensing()

    var body: some View {
        RealityView { content, attachments in
            let renderer = WindTunnelRenderer()
            content.add(renderer.root)

            // Control pods: the wind card floats beside the fan, the
            // test-body card hangs low under the section.
            let podsRoot = Entity()
            renderer.root.addChild(podsRoot)
            PodMount.mount(attachments.entity(for: "pod-wind"), name: "Wind",
                           at: [-1.35, 1.95, -1.15], in: podsRoot)
            PodMount.mount(attachments.entity(for: "pod-body"), name: "Test body",
                           at: [0.7, 0.95, -0.95], in: podsRoot)
            if let readout = attachments.entity(for: "probe") {
                readout.position = [0, 0.02, 0]
                renderer.probeAnchor.addChild(readout)
            }

            configureRouter(renderer: renderer)
            renderer.subscriptions = router.subscriptions(for: content)
            renderer.subscriptions.append(
                content.subscribe(to: SceneEvents.Update.self) { [weak renderer] event in
                    // On device, the room and hands flow into the field.
                    if sensing.isRunning {
                        model.obstacles = sensing.field
                    }
                    renderer?.tick(dt: event.deltaTime, model: model)
                    podsRoot.isEnabled = appModel.controlPodsVisible
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
        .task {
            // Hand tracking + scene reconstruction: device-only, quietly
            // absent in the simulator.
            await sensing.start()
        }
    }

    private func configureRouter(renderer: WindTunnelRenderer) {
        func updateProbeHeight(_ renderer: WindTunnelRenderer, _ position: SIMD3<Float>) {
            renderer.probeHeight = min(
                max(position.y - WindTunnelRenderer.sectionCenter.y,
                    -WindTunnelRenderer.halfHeight),
                WindTunnelRenderer.halfHeight)
        }
        router.onBegin = { [weak renderer] name, position in
            guard let renderer else { return }
            switch name {
            case WindTunnelRenderer.cylinderName:
                renderer.isManipulatingCylinder = true
                model.moveCylinder(to: renderer.planePoint(fromWorld: position))
            case WindTunnelRenderer.probeName:
                renderer.isManipulatingProbe = true
                updateProbeHeight(renderer, position)
                model.moveProbe(to: renderer.planePoint(fromWorld: position))
            default: break
            }
        }
        router.onMove = { [weak renderer] name, position in
            guard let renderer else { return }
            switch name {
            case WindTunnelRenderer.cylinderName:
                model.moveCylinder(to: renderer.planePoint(fromWorld: position))
            case WindTunnelRenderer.probeName:
                updateProbeHeight(renderer, position)
                model.moveProbe(to: renderer.planePoint(fromWorld: position))
            default: break
            }
        }
        router.onEnd = { [weak renderer] name, position in
            guard let renderer else { return }
            switch name {
            case WindTunnelRenderer.cylinderName:
                model.moveCylinder(to: renderer.planePoint(fromWorld: position))
                renderer.isManipulatingCylinder = false
            case WindTunnelRenderer.probeName:
                updateProbeHeight(renderer, position)
                model.moveProbe(to: renderer.planePoint(fromWorld: position))
                renderer.isManipulatingProbe = false
            default: break
            }
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
                .buttonStyle(.bordered)
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
                        Text(bodyName(body))
                            .font(DesignTokens.TypeScale.footnote)
                    }
                    .buttonStyle(.bordered)
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
