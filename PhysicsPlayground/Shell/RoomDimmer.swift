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
//  Rendered inside-out with an alpha ramp baked into a small texture — no
//  shader graph. It said "no per-frame work" until 2026-08-23, and now
//  there is some: the level RAMPS rather than snapping, so a frame during
//  a transition eases one Double and writes one OpacityComponent. Settled,
//  which is almost always, `Motion.ease` returns the target exactly and the
//  write is idempotent.
//
//  WHY IT RAMPS. The level was assigned in one frame on every module entry
//  and exit, so the wearer's actual living room changed brightness with a
//  jump — hub 0, five labs 0.35, Gravity Lab 0.85. `AtmosphereCriterionTests`
//  had already named this the loudest difference between two rooms that are
//  meant to feel like one place; it could fix the VALUES and not the step
//  between them.
//

import RealityKit
import RenderKit
import SwiftUI
import UIKit

struct RoomDimmerView: View {
    @Environment(AppModel.self) private var appModel

    /// How far out the shell stands lives on `AppModel.dimmingRadius` rather
    /// than being passed in, because the ramp reads it every frame and a
    /// captured prop would freeze at whatever the app launched with.
    ///
    /// It varies at all because one module's apparatus is bigger than the
    /// shell that is supposed to sit behind it: Gravity Lab puts Jupiter
    /// 2.6 m out and Neptune at 15, so a 3.4 m dome cuts straight
    /// through the solar system — the inner planets read against
    /// darkness and the outer ones against the wall, which is the exact
    /// inconsistency the dimmer exists to remove.
    static let defaultRadius: Float = 3.4

    /// How fast the shell answers a new target. 9 settles in ~0.25 s, which
    /// sits beside the hub's own τ ≈ 0.18 s dissolve rather than arguing
    /// with it.
    static let rampRate: Double = 9

    /// The ramp, as arithmetic — so the one thing that must never happen
    /// (overshoot, or a dip past the target on the way) can be tested over
    /// a swept grid instead of judged in a headset.
    ///
    /// On `Motion.ease`, which returns the target outright under Reduce
    /// Motion. That is correct here and is the reason not to hand-roll it:
    /// somebody who wants the room to stop changing brightness wants it to
    /// stop, not to change more smoothly.
    static func step(shown: Double, toward target: Double, dt: Double) -> Double {
        Motion.ease(shown, toward: target, dt: dt, rate: rampRate)
    }

    var body: some View {
        RealityView { content in
            let shell = Self.makeShell(level: appModel.dimmingShown,
                                       radius: appModel.dimmingRadius)
            content.add(shell)
            // THE RAMP IS TICKED FROM THE SCENE, not from the update
            // closure. `dimmingShown` is `@ObservationIgnored` precisely so
            // it cannot invalidate this view 90 times a second, which means
            // `update:` is not called as it changes — the frame clock is.
            //
            // Everything the tick needs is read from `appModel` INSIDE it,
            // never captured here. This closure is made once and the view's
            // identity is now stable, so a captured radius would be the one
            // the app launched with — and Gravity Lab's 16 m shell would
            // never arrive.
            subscription = content.subscribe(to: SceneEvents.Update.self) { event in
                Self.tick(shell, appModel: appModel, dt: event.deltaTime)
            }
        } update: { _ in
            // Nothing per-frame here on purpose; see above.
        }
        .onDisappear {
            // An uncancelled subscription has already leaked once in this
            // shell — see the note in `PlaygroundSpaceView`.
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

        // THE RADIUS MOVES ONLY WHILE NOTHING CAN BE SEEN OF IT. Gravity
        // Lab stands its shell at 16 m and everything else at 3.4; changing
        // that mid-ramp drags a dome through the apparatus in plain view,
        // which is the exact seam the radius exists to avoid. Below 0.03 the
        // shell is invisible, so the swap is free.
        if shown < 0.03, let dome = shell.children.first {
            let radius = appModel.dimmingRadius
            dome.scale = SIMD3(-radius, radius, radius)
        }

        shell.isEnabled = shown > 0.01
        shell.components.set(OpacityComponent(opacity: Float(shown)))
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

        // BUILT AT UNIT RADIUS, sized by the transform. `generateSphere`
        // tessellates identically at any radius and the alpha ramp is
        // UV-mapped, so this is the same picture — but it lets the radius
        // change without regenerating a mesh, which is what allows the
        // Gravity Lab swap to happen inside a ramp rather than by rebuilding
        // the whole view.
        let dome = ModelEntity(mesh: .generateSphere(radius: 1), materials: [material])
        dome.scale = SIMD3(-radius, radius, radius)   // negative x: seen from the inside
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
