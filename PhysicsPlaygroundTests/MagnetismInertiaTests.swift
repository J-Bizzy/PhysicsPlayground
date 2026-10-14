//
//  MagnetismInertiaTests.swift
//  The bench half of `DipoleDynamicsTests`: `-magInertia 1` actually changes the
//  room and the default is still the glide. Both benches ship; see DECISIONS.md.
//

import XCTest
import PhysicsCore
import simd
@testable import PhysicsPlayground

@MainActor
final class MagnetismInertiaTests: XCTestCase {

    /// Releases a needle in a strong neighbour's field; returns the angle between the two moments each frame.
    private func release(inertia: Bool, frames: Int) -> [Double] {
        let model = MagnetismModel()
        model.reset()
        model.inertiaOn = inertia

        // One magnet makes the field (held still), the other swings in it.
        while model.magnets.count < 2 { model.addMagnet() }
        let anchor = model.magnets[0]
        let swinger = model.magnets[1]
        model.setStrength(id: anchor.id, 12)
        model.move(id: anchor.id, to: MagnetismModel.regionCenter)
        // Off the anchor's axis at 45°: straight out along +x the field is parallel
        // to the swinger's moment, m × B ≡ 0 and nothing swings (the first draft did exactly that).
        let reach = 0.30 / 2.0.squareRoot()
        model.move(id: swinger.id,
                   to: MagnetismModel.regionCenter + SIMD3(reach, reach, 0))
        model.grab(id: anchor.id)

        var angles: [Double] = []
        for _ in 0..<frames {
            model.step(dt: 1.0 / 90)
            guard let a = model.magnets.first(where: { $0.id == anchor.id }),
                  let b = model.magnets.first(where: { $0.id == swinger.id })
            else { break }
            let cosine = simd_dot(simd_normalize(a.moment), simd_normalize(b.moment))
            angles.append(acos(min(max(cosine, -1), 1)))
        }
        return angles
    }

    /// Without inertia the angle can only shrink (the step is clamped at alignment);
    /// with inertia it must overshoot at least once.
    func testOnlyTheInertialBenchOvershootsAlignment() {
        let glide = release(inertia: false, frames: 900)
        let inertial = release(inertia: true, frames: 900)

        XCTAssertFalse(glide.isEmpty)
        XCTAssertFalse(inertial.isEmpty)

        XCTAssertEqual(overshoots(in: glide), 0,
                       """
                       The overdamped bench turned back on itself, which it \
                       cannot do: `stepOverdamped` clamps the rotation to the \
                       angle remaining, precisely so an aligned pair lands on \
                       alignment and stops.
                       """)
        XCTAssertGreaterThan(overshoots(in: inertial), 0,
                             """
                             The inertial bench never swung past alignment. \
                             That is the one thing it exists to do — a needle \
                             with rotational inertia carries through and rings \
                             back, and nothing without inertia can.
                             """)
    }

    /// Counts direction reversals — a reversal is an overshoot.
    private func overshoots(in angles: [Double]) -> Int {
        var count = 0
        for index in 2..<max(angles.count, 2) where index < angles.count {
            let falling = angles[index - 1] < angles[index - 2] - 1e-6
            let rising = angles[index] > angles[index - 1] + 1e-6
            if falling, rising { count += 1 }
        }
        return count
    }

    /// The glide is still the default: no inertia unless the launch argument asked.
    func testTheDefaultBenchIsStillTheGlide() {
        XCTAssertFalse(UserDefaults.standard.bool(forKey: "magInertia"),
                       "Precondition: the test runner has no -magInertia.")
        XCTAssertFalse(MagnetismModel().inertiaOn)
    }

    /// Known limitation, pinned as one: an inertial pair in contact does not settle —
    /// `separated()` moves a magnet, doing work the field claws back (a positional pump).
    /// This asserts what is true: bounded and finite, not settled. If the contact is
    /// fixed, replace this with a settling test.
    func testTheInertialBenchIsBoundedEvenWhereItDoesNotSettle() {
        let model = MagnetismModel()
        model.reset()
        model.inertiaOn = true
        while model.magnets.count < 2 { model.addMagnet() }
        model.move(id: model.magnets[1].id,
                   to: MagnetismModel.regionCenter + SIMD3(0.21, 0.21, 0))

        for _ in 0..<9_000 {                     // 100 s
            model.step(dt: 1.0 / 90)
            for magnet in model.magnets {
                XCTAssertTrue(magnet.position.x.isFinite
                              && magnet.position.y.isFinite
                              && magnet.position.z.isFinite,
                              "A magnet's position went non-finite.")
                let offset = simd_abs(magnet.position - MagnetismModel.regionCenter)
                XCTAssertLessThanOrEqual(
                    offset.x, MagnetismModel.safetyHalfExtents.x + 1e-6)
                XCTAssertLessThanOrEqual(
                    offset.y, MagnetismModel.safetyHalfExtents.y + 1e-6)
                XCTAssertLessThanOrEqual(
                    offset.z, MagnetismModel.safetyHalfExtents.z + 1e-6)
                // The moment's length must survive rotation — `DipoleDynamics.step` renormalises for this.
                XCTAssertEqual(magnet.strength, MagnetismModel.defaultStrength,
                               accuracy: 1e-6,
                               "A magnet's strength drifted while it turned.")
            }
        }
    }

    /// Switching modes must not smuggle a velocity across: the glide's "speed" is a mobility, not a momentum.
    func testSwitchingModesStartsFromRest() {
        let model = MagnetismModel()
        model.reset()
        while model.magnets.count < 2 { model.addMagnet() }
        model.move(id: model.magnets[1].id,
                   to: MagnetismModel.regionCenter + SIMD3(0.22, 0, 0))

        for _ in 0..<200 { model.step(dt: 1.0 / 90) }   // glide, moving
        model.inertiaOn = true
        let before = model.magnets.map(\.position)
        model.step(dt: 1.0 / 90)
        let after = model.magnets.map(\.position)

        for (a, b) in zip(before, after) {
            // From rest one frame moves (F/m)·dt² — vanishing beside a carried-over glide speed (~5 mm).
            XCTAssertLessThan(simd_distance(a, b), 1e-3,
                              "A magnet jumped on the frame the mode changed.")
        }
    }
}
