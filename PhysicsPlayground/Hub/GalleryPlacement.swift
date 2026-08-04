//
//  GalleryPlacement.swift
//  Physics Playground — Hub
//
//  Put the gallery where you actually have room — the hub's sibling of
//  `LabPlacement`, and the replacement for the Settings window's
//  "Gallery" section (distance/height sliders and a Recenter button;
//  owner's call, 2026-08-03).
//
//  Two things decided the shape. First, the sliders repositioned by
//  REBUILDING: they bumped `layoutVersion`, which tore the RealityView
//  down and re-ran `HubScene.build` — on a `@State` scene that
//  survived the teardown, so every reposition stacked a second gallery
//  on top of the first. A transform never rebuilds anything. Second,
//  the fix the owner asked for is the native one: a grab bar under the
//  gallery, like the bar under every visionOS window, remembered
//  across launches so the room opens exactly where it was left.
//
//  It is a pure display transform on `HubScene.root`, applied every
//  frame — the same argument that makes `LabPlacement` safe: every
//  grab in the hub converts through `root`, so a constant translation
//  and yaw change nothing about how carrying an exhibit works.
//

import Foundation
import Observation
import simd

@MainActor
@Observable
final class GalleryPlacement {
    /// Where the whole gallery stands, relative to where it builds.
    private(set) var offset: SIMD3<Float> = .zero
    /// Yaw about Y, radians — set by a tap on the bar, which swings the
    /// crescent round to face wherever the wearer is looking.
    private(set) var yaw: Float = 0

    private static let offsetKey = "hub.galleryOffset"
    private static let yawKey = "hub.galleryYaw"

    init() {
        if let saved = UserDefaults.standard.array(forKey: Self.offsetKey)
            as? [Double], saved.count == 3 {
            offset = SIMD3(Float(saved[0]), Float(saved[1]), Float(saved[2]))
        }
        if UserDefaults.standard.object(forKey: Self.yawKey) != nil {
            yaw = Float(UserDefaults.standard.double(forKey: Self.yawKey))
        }
    }

    func move(to newOffset: SIMD3<Float>) {
        // Generous but bounded: far enough to put the gallery across
        // the room, not so far it ends up in next door.
        offset = simd_clamp(newOffset,
                            SIMD3(-3, -0.9, -3), SIMD3(3, 0.9, 3))
        persist()
    }

    func turn(to newYaw: Float) {
        yaw = newYaw
        persist()
    }

    /// A tap on the bar: home position, facing the wearer if the room
    /// knows which way that is.
    func recentre(facing yaw: Float?) {
        offset = .zero
        if let yaw { self.yaw = yaw }
        persist()
    }

    private func persist() {
        UserDefaults.standard.set(
            [Double(offset.x), Double(offset.y), Double(offset.z)],
            forKey: Self.offsetKey)
        UserDefaults.standard.set(Double(yaw), forKey: Self.yawKey)
    }
}
