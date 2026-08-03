//
//  MagnetismInertiaTests.swift
//  PhysicsPlaygroundTests
//
//  The bench half of `DipoleDynamicsTests`. That file proves the physics
//  in isolation — the magnetometer period, the overshoot, the energy.
//  This one proves the MODEL is wired to it: that `-magInertia 1`
//  actually changes how the room behaves, and that the default is still
//  the glide.
//
//  Both benches ship at once on purpose. This reverses a decision
//  `MagnetismModel`'s own header records, and a reversal made on feel
//  has to be judged on feel, in a headset, against the thing it
//  replaces. See DECISIONS.md 2026-08-03.
//

import XCTest
import PhysicsCore
import simd
@testable import PhysicsPlayground

@MainActor
final class MagnetismInertiaTests: XCTestCase {

    /// A needle held at right angles to a strong neighbour's field, then
    /// let go. Returns the angle between the two moments each frame.
    private func release(inertia: Bool, frames: Int) -> [Double] {
        let model = MagnetismModel()
        model.reset()
        model.inertiaOn = inertia

        // Two magnets: one to make the field, one to swing in it. The
        // maker is held so it stays put and only the other one moves.
        while model.magnets.count < 2 { model.addMagnet() }
        let anchor = model.magnets[0]
        let swinger = model.magnets[1]
        model.setStrength(id: anchor.id, 12)
        model.move(id: anchor.id, to: MagnetismModel.regionCenter)
        // OFF THE ANCHOR'S AXIS, at 45°, and that is not incidental.
        // Both magnets are born with their moment along +x, so a swinger
        // placed straight out along +x sits where the anchor's field is
        // ALSO along +x — m × B is identically zero and nothing swings.
        // The first draft of this test did exactly that and read as the
        // inertial bench failing to overshoot.
        //
        // At 45° the dipole field runs about 72° off the swinger's own
        // moment (B ∝ 3(m·r̂)r̂ − m gives (0.5, 1.5) for m along x̂), which
        // is a real release angle.
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

    /// **The difference, stated as a behaviour rather than a flag.**
    ///
    /// Without inertia the angle between two magnets can only shrink —
    /// the mobility law turns the moment toward the field and explicitly
    /// clamps the step so it never goes past. With inertia it must
    /// overshoot at least once: the needle carries through alignment and
    /// comes back.
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

    /// Counts direction reversals in a sequence that should otherwise
    /// decrease monotonically. A reversal IS an overshoot.
    private func overshoots(in angles: [Double]) -> Int {
        var count = 0
        for index in 2..<max(angles.count, 2) where index < angles.count {
            let falling = angles[index - 1] < angles[index - 2] - 1e-6
            let rising = angles[index] > angles[index - 1] + 1e-6
            if falling, rising { count += 1 }
        }
        return count
    }

    /// **The glide is still the default.** A fresh model must not have
    /// inertia unless the launch argument asked for it, because the
    /// owner has not yet judged the two side by side.
    func testTheDefaultBenchIsStillTheGlide() {
        XCTAssertFalse(UserDefaults.standard.bool(forKey: "magInertia"),
                       "Precondition: the test runner has no -magInertia.")
        XCTAssertFalse(MagnetismModel().inertiaOn)
    }

    /// **A KNOWN LIMITATION, PINNED AS ONE.**
    ///
    /// A pair of inertial magnets in CONTACT does not come to rest. It
    /// was measured rather than suspected: the angle's variation over
    /// the last second grows from 1.28 rad at t = 10 s to 2.82 rad at
    /// t = 300 s. The motion is not decaying, and the damping is not the
    /// reason — at 0.9 s⁻¹ over five minutes any free rotation is gone
    /// many times over.
    ///
    /// What drives it is the contact itself. `separated()` resolves an
    /// overlap by MOVING a magnet, which does work against an attraction
    /// that is enormous at that range, and the field pulls it straight
    /// back. `killVelocityIntoContacts` takes out the closing velocity
    /// and does not stop the positional pump. This is the same standoff
    /// `softenedAtContact` was written to defeat for the glide, in the
    /// regime where a projection-based contact and a real inertia meet.
    ///
    /// So the inertial bench is honest in FREE FIELD — every claim in
    /// `DipoleDynamicsTests` holds, including that a needle settles — and
    /// unfinished at contact. That is precisely why it ships behind
    /// `-magInertia 1` with the glide as the default, and it is the first
    /// thing to watch on device.
    ///
    /// This test asserts what IS true: it may not settle, but it must not
    /// run away. Bounded, in the station, finite. If somebody fixes the
    /// contact, this test should be replaced by a settling one.
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
                    offset.x, MagnetismModel.regionHalfExtents.x + 1e-6)
                XCTAssertLessThanOrEqual(
                    offset.y, MagnetismModel.regionHalfExtents.y + 1e-6)
                XCTAssertLessThanOrEqual(
                    offset.z, MagnetismModel.regionHalfExtents.z + 1e-6)
                // The moment's LENGTH is a property of the magnet and must
                // survive any amount of rotation — `DipoleDynamics.step`
                // renormalises for exactly this reason.
                XCTAssertEqual(magnet.strength, MagnetismModel.defaultStrength,
                               accuracy: 1e-6,
                               "A magnet's strength drifted while it turned.")
            }
        }
    }

    /// Switching modes must not smuggle a velocity across. The glide's
    /// "speed" is a mobility, not a momentum, and inheriting it as one
    /// would launch a magnet across the bench.
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
            // One frame of a body starting from rest moves it by
            // (F/m)·dt² — vanishing beside a carried-over glide speed,
            // which is capped at 0.5 m/s and would move it ~5 mm.
            XCTAssertLessThan(simd_distance(a, b), 1e-3,
                              "A magnet jumped on the frame the mode changed.")
        }
    }
}
