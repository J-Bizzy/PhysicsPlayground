//
//  RoomDimmer.swift
//  Physics Playground — Shell
//
//  The contrast fix, short of shutting the room out entirely.
//
//  Passthrough is a BRIGHT medium: cream walls, daylight, pale
//  furniture. Cyan field lines, white smoke, a pale Sun and frosted
//  type all had less luminance than the wall behind them and simply
//  vanished. Studio Mode solves that by deleting the room — which is
//  right for Gravity Lab and wrong for a wind tunnel you want to reach
//  into with your real hands.
//
//  So: a DIMMING SHELL. A dark translucent sphere the user stands
//  inside, dense in front of them where the physics is and thinning
//  smoothly toward the floor, so the experiment sits in a pool of
//  contrast while the room, the furniture and the user's own feet stay
//  visible. Every glowing thing gains its contrast back without losing
//  the mixed-reality premise.
//
//  Rendered inside-out with an alpha ramp baked into a small texture —
//  cheap, no per-frame work, no shader graph.
//

import RealityKit
import SwiftUI
import UIKit

struct RoomDimmerView: View {
    /// 0 = off, 1 = as dark as the shell goes.
    let level: Double
    /// How far out the shell stands, metres.
    ///
    /// A parameter because one module's apparatus is bigger than the
    /// shell that is supposed to sit behind it: Gravity Lab puts Jupiter
    /// 2.6 m out and Neptune at 15, so a 3.4 m dome cuts straight
    /// through the solar system — the inner planets read against
    /// darkness and the outer ones against the wall, which is the exact
    /// inconsistency the dimmer exists to remove.
    var radius: Float = RoomDimmerView.defaultRadius

    static let defaultRadius: Float = 3.4

    var body: some View {
        RealityView { content in
            content.add(Self.makeShell(level: level, radius: radius))
        } update: { content in
            guard let shell = content.entities.first else { return }
            shell.isEnabled = level > 0.01
            // Re-tint rather than rebuild: the opacity component is the
            // one knob, so a slider never regenerates geometry.
            shell.components.set(OpacityComponent(opacity: Float(level)))
        }
    }

    /// The shell: an inside-out sphere just past arm's reach, wearing a
    /// vertical alpha ramp — opaque-ish at eye level and above, fading
    /// out toward the floor so the user keeps their footing.
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

        let dome = ModelEntity(mesh: .generateSphere(radius: radius), materials: [material])
        dome.scale = SIMD3(-1, 1, 1)          // seen from the inside
        dome.position = [0, 1.4, 0]
        root.addChild(dome)

        root.components.set(OpacityComponent(opacity: Float(level)))
        root.isEnabled = level > 0.01
        return root
    }

    /// A 1 × 128 vertical gradient: dense across the upper hemisphere
    /// (where walls and ceiling wash content out), clearing toward the
    /// bottom so the floor and the user's body stay in view.
    private static func rampTexture() -> TextureResource? {
        let height = 128
        let width = 4
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        for row in 0..<height {
            // v = 0 at the sphere's top, 1 at its bottom (image space).
            let v = Double(row) / Double(height - 1)
            // Full strength down to the horizon, then a smooth fade over
            // the lower quarter of the sphere.
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
