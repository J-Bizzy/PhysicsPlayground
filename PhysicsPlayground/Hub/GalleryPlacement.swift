//  GalleryPlacement.swift — grab-bar placement of the gallery, persisted across launches.
//  A pure display transform on `HubScene.root`, applied every frame — never repositions by
//  rebuilding (rebuild once stacked a second gallery); grabs convert through `root` so it's safe.

import Foundation
import Observation
import simd

@MainActor
@Observable
final class GalleryPlacement {
    /// Where the whole gallery stands, relative to where it builds.
    private(set) var offset: SIMD3<Float> = .zero
    /// Yaw about Y, radians — a bar tap swings the crescent to face the wearer.
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
        // Bounded: across the room, not into next door.
        offset = simd_clamp(newOffset,
                            SIMD3(-3, -0.9, -3), SIMD3(3, 0.9, 3))
        persist()
    }

    func turn(to newYaw: Float) {
        yaw = newYaw
        persist()
    }

    /// Bar tap: home position, facing the wearer if the room knows which way that is.
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
