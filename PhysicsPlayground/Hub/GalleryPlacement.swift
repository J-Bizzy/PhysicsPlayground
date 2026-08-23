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

    /// How far the restored facing may sit from the wearer's own before the
    /// gallery counts as behind them. Generous on purpose — a deliberate
    /// quarter-turn is a placement, not a mistake.
    static let refaceTolerance: Float = 70 * .pi / 180

    /// The rescue, as arithmetic so it can be tested without a headset.
    ///
    /// The saved offset and yaw are relative to where the scene BUILDS, which
    /// is wherever the wearer happened to be standing last launch. Relaunch
    /// from another chair — or another room — and the same numbers put the
    /// gallery behind them, before the app has shown them anything. So the
    /// placement is still restored (the grab bar's promise, `testThePlacementSurvivesRelaunch`),
    /// and only a facing that has gone badly wrong is overridden.
    ///
    /// Signed shortest angle, not `abs(a - b)`: the two facings straddle ±π
    /// as often as not, and the naive difference reads 350° apart for two
    /// directions 10° apart.
    static func reFacedYaw(saved: Float, lookYaw: Float,
                           tolerance: Float = GalleryPlacement.refaceTolerance) -> Float {
        var delta = (lookYaw - saved).truncatingRemainder(dividingBy: 2 * .pi)
        if delta > .pi { delta -= 2 * .pi }
        if delta < -.pi { delta += 2 * .pi }
        return abs(delta) <= tolerance ? saved : lookYaw
    }

    /// Called once per launch, on the first frame the room knows which way the
    /// wearer is looking. Turns the gallery to face them ONLY if the restored
    /// facing would have put it behind them; the offset is never touched, so a
    /// placement the user chose survives.
    func refaceIfBehind(lookYaw: Float) {
        let next = Self.reFacedYaw(saved: yaw, lookYaw: lookYaw)
        guard next != yaw else { return }
        yaw = next
        persist()
    }

    private func persist() {
        UserDefaults.standard.set(
            [Double(offset.x), Double(offset.y), Double(offset.z)],
            forKey: Self.offsetKey)
        UserDefaults.standard.set(Double(yaw), forKey: Self.yawKey)
    }
}
