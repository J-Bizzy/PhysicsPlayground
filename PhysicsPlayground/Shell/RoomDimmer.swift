//
//  RoomDimmer.swift
//  Physics Playground — Shell
//
//  The dimming shell: a dark translucent sphere the user stands inside,
//  dense where the physics is and thinning toward the floor, so the
//  experiment sits in a pool of contrast while the room and the user's
//  own feet stay visible. Rendered inside-out with an alpha ramp baked
//  into a small texture. The level ramps rather than snapping, so a lab
//  switch never changes the room's brightness in one frame.
//

import RealityKit
import RenderKit
import SwiftUI
import UIKit

struct RoomDimmerView: View {
    @Environment(AppModel.self) private var appModel

    /// The house radius. `AppModel.dimmingRadius` carries the live value:
    /// Orbital Mechanics puts Jupiter 2.6 m out, so its shell stands at 16 m.
    nonisolated static let defaultRadius: Float = 3.4

    /// How fast the shell answers a new target; 9 settles in ~0.25 s,
    /// beside the hub's own dissolve.
    static let rampRate: Double = 9

    /// The ramp as arithmetic, so no-overshoot can be tested over a swept
    /// grid. On `Motion.ease`, which jumps under Reduce Motion.
    static func step(shown: Double, toward target: Double, dt: Double) -> Double {
        Motion.ease(shown, toward: target, dt: dt, rate: rampRate)
    }

    var body: some View {
        RealityView { content in
            let shell = Self.makeShell(level: appModel.dimmingShown,
                                       radius: appModel.dimmingRadius)
            content.add(shell)
            // Ticked from the scene, not the update closure: `dimmingShown` is
            // `@ObservationIgnored` so it cannot invalidate this view at 90 Hz.
            // Everything is read from `appModel` inside the tick, never captured,
            // or the radius would freeze at launch.
            subscription = content.subscribe(to: SceneEvents.Update.self) { event in
                Self.tick(shell, appModel: appModel, dt: event.deltaTime)
            }
        } update: { _ in
            // Nothing per-frame here on purpose; see above.
        }
        .onDisappear {
            // An uncancelled subscription leaks the shell.
            subscription?.cancel()
            subscription = nil
        }
    }

    @State private var subscription: EventSubscription?

    /// One frame of the ramp.
    @MainActor
    private static func tick(_ shell: Entity, appModel: AppModel, dt: Double) {
        let shown = step(shown: appModel.dimmingShown,
                         toward: appModel.roomDimming, dt: dt)
        appModel.dimmingShown = shown

        // The radius moves only while the shell is invisible (below 0.03), so
        // the swap never drags a dome through the apparatus.
        if shown < 0.03, let dome = shell.children.first {
            let radius = appModel.dimmingRadius
            dome.scale = SIMD3(-radius, radius, radius)
        }

        shell.isEnabled = shown > 0.01
        shell.components.set(OpacityComponent(opacity: Float(shown)))
    }

    /// The shell: an inside-out sphere wearing a vertical alpha ramp —
    /// dense at eye level and above, fading toward the floor.
    @MainActor
    static func makeShell(level: Double,
                          radius: Float = RoomDimmerView.defaultRadius) -> Entity {
        let root = Entity()
        root.name = "room-dimmer"

        var material = UnlitMaterial(color: UIColor(white: 0.02, alpha: 1))
        if let texture = rampTexture() {
            material.color = .init(tint: .white, texture: .init(texture))
        }
        material.blending = .transparent(opacity: 0.9)
        material.opacityThreshold = 0

        // Built at unit radius and sized by the transform, so the radius can
        // change without regenerating a mesh.
        let dome = ModelEntity(mesh: Primitives.sphere(radius: 1), materials: [material])
        dome.scale = SIMD3(-radius, radius, radius)   // negative x: seen from the inside
        dome.position = [0, 1.4, 0]
        root.addChild(dome)

        root.components.set(OpacityComponent(opacity: Float(level)))
        root.isEnabled = level > 0.01
        return root
    }

    /// A 1 × 128 vertical gradient: dense across the upper hemisphere,
    /// clearing toward the bottom.
    private static func rampTexture() -> TextureResource? {
        let height = 128
        let width = 4
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        for row in 0..<height {
            // v = 0 at the sphere's top, 1 at its bottom (image space).
            let v = Double(row) / Double(height - 1)
            // Full strength down to the horizon, then a smooth fade over the lower
            // quarter.
            let fade: Double
            if v < 0.62 {
                fade = 1.0
            } else {
                let t = min((v - 0.62) / 0.30, 1.0)
                fade = 1 - t * t * (3 - 2 * t)     // smoothstep out
            }
            for column in 0..<width {
                let index = (row * width + column) * 4
                pixels[index + 0] = 5      // near-black tint
                pixels[index + 1] = 5
                pixels[index + 2] = 7
                pixels[index + 3] = UInt8(max(0, min(255, fade * 235)))
            }
        }
        guard let provider = CGDataProvider(data: Data(pixels) as CFData),
              let image = CGImage(
                width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                provider: provider, decode: nil, shouldInterpolate: true,
                intent: .defaultIntent)
        else { return nil }
        return try? TextureResource(
            image: image,
            options: .init(semantic: .color, mipmapsMode: .none))
    }
}
