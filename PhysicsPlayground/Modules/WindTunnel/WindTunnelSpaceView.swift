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
    @State private var bloom = Bloom()
    @State private var fanDrag: RelativeDrag?
    /// Two gauges standing at the mouth of the section: the wind you are
    /// running and the spin you are putting on the cylinder. Both were
    /// sliders on a card; both are the kind of number a tunnel operator
    /// reaches out and turns.

    var body: some View {
        RealityView { content in
            let renderer = WindTunnelRenderer()
            content.add(renderer.root)
            renderer.sectionRoot.addChild(bloom.root)

            renderer.subscriptions.append(
                content.subscribe(to: SceneEvents.Update.self) { [weak renderer] event in
                    // On device, the room and hands flow into the field,
                    // from the SHARED room session rather than a private
                    // one this module used to run in parallel with it.
                    if appModel.room.hasScannedRoom {
                        model.obstacles = appModel.room.obstacles
                    }
                    renderer?.tick(dt: event.deltaTime, model: model)
                    if let renderer {
                        syncBloom(renderer: renderer, dt: event.deltaTime)
                    }
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

            self.renderer = renderer
        }
        // The fan moves by the hand's displacement — no system
        // manipulation, no lurch toward the hand; its beam and hum ride
        // along in the same frame.
        .simultaneousGesture(
            TapGesture()
                .targetedToAnyEntity()
                .onEnded { value in _ = bloom.handleTap(value.entity) }
        )
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .targetedToAnyEntity()
                .onChanged { value in
                    guard let renderer else { return }
                    let hand = SIMD3<Double>(SIMD3<Float>(value.convert(
                        value.location3D, from: .local, to: .scene)))
                    if fanDrag == nil {
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
                }
        )
        .task {
            // Hand tracking + scene reconstruction: device-only, quietly
            // absent in the simulator.
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

    /// The test body's own controls. SIZE is the grip, because size is
    /// what drag is made of — F = ½ρv²C_dA, so pulling the body wider
    /// grows its frontal area and the drag readout climbs as you pull.
    /// Shape is the petal, because a sphere is not a big teardrop.
    private func syncBloom(renderer: WindTunnelRenderer, dt: Double) {
        let anchor = SIMD3<Float>(Float(model.cylinderCenter.x), 0,
                                  Float(model.cylinderCenter.y))
        bloom.retarget(
            "test-body",
            petals: [
                .init(name: "Next shape", symbol: "shippingbox",
                      tint: UIColor(white: 0.45, alpha: 1)) {
                    let all = DragBody.allCases
                    if let i = all.firstIndex(of: model.testBody) {
                        model.testBody = all[(i + 1) % all.count]
                    }
                },
            ],
            grip: .init(
                name: "Size",
                range: 0.03...0.14,
                read: { model.cylinderRadius },
                write: { model.cylinderRadius = $0 },
                format: { String(format: "%.0f cm across", $0 * 200) },
                radius: { Float(model.cylinderRadius * model.testBody.sizeMultiplier) + 0.03 }))

        let viewer = appModel.room.headPosition.map {
            renderer.sectionRoot.convert(position: SIMD3<Float>($0), from: nil)
        }
        bloom.update(anchor: anchor, viewer: viewer, revealTarget: 1, dt: dt)
    }}

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
