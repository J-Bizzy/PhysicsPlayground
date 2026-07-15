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

    var body: some View {
        RealityView { content, attachments in
            let renderer = WindTunnelRenderer()
            content.add(renderer.root)

            if let quick = attachments.entity(for: "quick") {
                quick.position = [-0.62, 1.14, -0.82]
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
                    renderer?.tick(dt: event.deltaTime, model: model)
                }
            )

            renderer.startObserving(model)
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
    }

    private func configureRouter(renderer: WindTunnelRenderer) {
        router.onBegin = { [weak renderer] name, position in
            guard let renderer else { return }
            switch name {
            case WindTunnelRenderer.cylinderName:
                renderer.isManipulatingCylinder = true
                model.moveCylinder(to: renderer.planePoint(fromWorld: position))
            case WindTunnelRenderer.probeName:
                renderer.isManipulatingProbe = true
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
            VStack(alignment: .leading, spacing: 6) {
                Text("Wind: \(model.windSpeed, specifier: "%.2f") m/s")
                    .font(DesignTokens.TypeScale.label.monospacedDigit())
                Slider(value: $model.windSpeed, in: WindTunnelModel.windSpeedRange)
                    .accessibilityLabel("Wind speed")
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Spin: \(model.spinRPM, specifier: "%.0f") rpm")
                    .font(DesignTokens.TypeScale.label.monospacedDigit())
                Slider(value: $model.circulation, in: WindTunnelModel.circulationRange)
                    .accessibilityLabel("Spin (circulation)")
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

            if abs(model.liftPerSpan) > 0.02 {
                Text("Lift: \(abs(model.liftPerSpan), specifier: "%.2f") N/m")
                    .font(DesignTokens.TypeScale.label.monospacedDigit())
                    .foregroundStyle(DesignTokens.Palette.forceVector)
            }
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
