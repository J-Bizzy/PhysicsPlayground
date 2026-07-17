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
    @State private var renderer: WindTunnelRenderer?
    @State private var router = ManipulationRouter()
    @State private var sensing = WindTunnelSensing()

    var body: some View {
        RealityView { content, attachments in
            let renderer = WindTunnelRenderer()
            content.add(renderer.root)

            if let quick = attachments.entity(for: "quick") {
                quick.position = [-1.45, 1.25, -0.9]
                quick.orientation = simd_quatf(angle: 0.35, axis: [0, 1, 0])
                renderer.root.addChild(quick)
            }
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
                }
            )

            self.renderer = renderer
        } attachments: {
            Attachment(id: "quick") {
                WindTunnelQuickPanel()
                    .environment(model)
                    .padding(18)
                    .frame(width: 320)
                    .glassBackgroundEffect()
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

/// The floating in-space panel: wind, spin, time.
struct WindTunnelQuickPanel: View {
    @Environment(WindTunnelModel.self) private var model

    var body: some View {
        @Bindable var model = model

        VStack(alignment: .leading, spacing: 14) {
            // The shape zoo: same frontal size, wildly different drag.
            VStack(alignment: .leading, spacing: 6) {
                Text("Test body")
                    .font(DesignTokens.TypeScale.label)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 88), spacing: 6)], spacing: 6) {
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
            }

            Text("Cd \(model.testBody.dragCoefficient, specifier: "%.2f")   drag \(model.dragForce, specifier: "%.3f") N")
                .font(DesignTokens.TypeScale.label.monospacedDigit())
                .foregroundStyle(DesignTokens.Palette.forceVector)
                .accessibilityLabel("Drag coefficient \(model.testBody.dragCoefficient), drag force \(model.dragForce) newtons")

            VStack(alignment: .leading, spacing: 6) {
                Text("Wind: \(model.windSpeed, specifier: "%.2f") m/s")
                    .font(DesignTokens.TypeScale.label.monospacedDigit())
                Slider(value: $model.windSpeed, in: WindTunnelModel.windSpeedRange)
                    .accessibilityLabel("Wind speed")
            }
            if model.testBody == .cylinder {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Spin: \(model.spinRPM, specifier: "%.0f") rpm")
                        .font(DesignTokens.TypeScale.label.monospacedDigit())
                    Slider(value: $model.circulation, in: WindTunnelModel.circulationRange)
                        .accessibilityLabel("Spin (circulation)")
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

            if model.testBody == .cylinder, abs(model.liftPerSpan) > 0.02 {
                Text("Lift: \(abs(model.liftPerSpan), specifier: "%.2f") N/m")
                    .font(DesignTokens.TypeScale.label.monospacedDigit())
                    .foregroundStyle(DesignTokens.Palette.forceVector)
            }
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
