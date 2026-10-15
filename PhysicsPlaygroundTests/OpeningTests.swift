//
//  OpeningTests.swift
//  PhysicsPlaygroundTests
//
//  The opening is physics, so it is tested as physics: the swirl is
//  a solution of m·a = q·v×B + m·g, the magnetic force does no work, the
//  ripple obeys deep-water dispersion and comes to rest, the settle never
//  overshoots, and every hand-over happens with the particles at rest.
//

import XCTest
import simd
@testable import PhysicsPlayground

final class OpeningTests: XCTestCase {

    private let portals = PortalLayout.portals(count: 7)
    private var cloud: [Opening.Particle] { Opening.particles(for: portals) }

    // MARK: The clock

    func testTheOpeningRunsThreeToFourSeconds() {
        XCTAssertGreaterThanOrEqual(Opening.duration, 3.0)
        XCTAssertLessThanOrEqual(Opening.duration, 4.0)
    }

    /// The calibration bell is baked into its WAV at a fixed second; the
    /// particles must land on it.
    @MainActor
    func testTheParticlesLandOnTheBell() {
        XCTAssertEqual(Opening.landingTime, SoundPalette.calibrationLanding,
                       accuracy: 1e-9)
    }

    // MARK: The swirl is crossed-field motion

    /// The closed form satisfies the equation of motion: the acceleration
    /// is the Lorentz force per unit mass plus gravity, a = ω(vy, −vx) − g ŷ.
    func testTheSwirlIsASolutionOfTheLorentzEquation() {
        let h = 1e-4
        for charge in [1.0, -1.0] {
            let omega = charge * Opening.cyclotronRate
            for t in stride(from: 0.05, to: Opening.swirlDuration - 0.05, by: 0.07) {
                let before = Opening.cycloid(time: t - h, charge: charge)
                let now = Opening.cycloid(time: t, charge: charge)
                let after = Opening.cycloid(time: t + h, charge: charge)
                let a = (after - 2 * now + before) / (h * h)
                let v = Opening.cycloidVelocity(time: t, charge: charge)
                let expected = SIMD3(omega * v.y, -omega * v.x - Opening.g, 0)
                XCTAssertEqual(a.x, expected.x, accuracy: 1e-3)
                XCTAssertEqual(a.y, expected.y, accuracy: 1e-3)
            }
        }
    }

    /// A released charge first falls with exactly g: the field acts on
    /// velocity, and there is none yet.
    func testItFirstFallsWithG() {
        let t = 1e-3
        let drop = -Opening.cycloid(time: t, charge: 1).y
        XCTAssertEqual(drop, 0.5 * Opening.g * t * t, accuracy: 1e-9)
    }

    /// The magnetic force does no work: kinetic energy per unit mass is
    /// exactly what the fall released.
    func testTheFieldDoesNoWork() {
        for charge in [1.0, -1.0] {
            for t in stride(from: 0, through: Opening.swirlDuration, by: 0.05) {
                let v = Opening.cycloidVelocity(time: t, charge: charge)
                let drop = -Opening.cycloid(time: t, charge: charge).y
                XCTAssertEqual(0.5 * simd_length_squared(v), Opening.g * drop,
                               accuracy: 1e-9)
            }
        }
    }

    /// One arch, rest to rest: after a cyclotron period the charge is
    /// back at its height, at rest, one drift 2πg/ω² sideways — and the
    /// two signs drift opposite ways.
    func testOneArchEndsAtRestOneDriftAway() {
        for charge in [1.0, -1.0] {
            let end = Opening.cycloid(time: Opening.swirlDuration, charge: charge)
            let v = Opening.cycloidVelocity(time: Opening.swirlDuration, charge: charge)
            XCTAssertEqual(end.y, 0, accuracy: 1e-9)
            XCTAssertEqual(simd_length(v), 0, accuracy: 1e-9)
            XCTAssertEqual(end.x, -charge * Opening.driftPerArch, accuracy: 1e-9)
        }
    }

    // MARK: The ripple is a deep-water wave

    func testTheRippleObeysDeepWaterDispersion() {
        XCTAssertEqual(Opening.waveFrequency * Opening.waveFrequency,
                       Opening.g * Opening.waveNumber, accuracy: 1e-9)
        XCTAssertLessThan(Opening.waveNumber * Opening.waveAmplitude, 0.3,
                          "too steep for the linear solution to hold")
    }

    /// Surface particles move on circles whose radius is the local
    /// amplitude, and the ripple starts and ends with them at rest.
    func testTheRippleOrbitsAreCirclesThatBeginAndEndAtRest() {
        let rest = SIMD3<Double>(0.2, 1.9, -1.3)
        for elapsed in stride(from: 0, through: Opening.rippleDuration, by: 0.05) {
            let offset = Opening.ripple(at: rest, elapsed: elapsed)
            XCTAssertEqual(simd_length(offset),
                           Opening.waveAmplitude * Opening.rippleEnvelope(elapsed),
                           accuracy: 1e-12)
        }
        let h = 1e-5
        for edge in [0.0, Opening.rippleDuration] {
            let speed = simd_length(Opening.ripple(at: rest, elapsed: edge + h)
                                    - Opening.ripple(at: rest, elapsed: edge - h)) / (2 * h)
            XCTAssertLessThan(speed, 1e-3, "the ripple hands over in motion")
        }
    }

    // MARK: The settle

    /// Critically damped: the particle closes on its target monotonically
    /// and lands within a millimetre at the bell.
    func testTheSettleNeverOvershootsAndLands() {
        for particle in cloud {
            let from = Opening.afterSwirl(particle)
            var last = Double.infinity
            for elapsed in stride(from: 0, through: Opening.settleDuration, by: 0.02) {
                let distance = simd_distance(
                    Opening.settle(from: from, to: particle.target, elapsed: elapsed),
                    particle.target)
                XCTAssertLessThanOrEqual(distance, last + 1e-12)
                last = distance
            }
            XCTAssertLessThan(simd_distance(
                Opening.settle(from: from, to: particle.target,
                               elapsed: Opening.settleDuration),
                particle.target), 0.01)
        }
    }

    // MARK: The hand-overs

    /// Position is continuous across every phase boundary: nothing jumps.
    func testNothingJumpsBetweenPhases() {
        let h = 1e-6
        for particle in cloud.prefix(24) {
            for boundary in [Opening.swirlStart, Opening.rippleStart,
                             Opening.settleStart] {
                let before = Opening.position(of: particle, at: boundary - h)
                let after = Opening.position(of: particle, at: boundary + h)
                XCTAssertLessThan(simd_distance(before, after), 1e-4,
                                  "a particle jumped at t = \(boundary)")
            }
        }
    }

    // MARK: The room

    /// The cloud stays above the portals and out of the wearer's face.
    func testTheCloudKeepsClearOfTheWearer() {
        let head = SIMD3<Double>(0, 1.6, 0)
        for particle in cloud {
            for t in stride(from: 0, through: Opening.settleStart, by: 0.02) {
                let p = Opening.position(of: particle, at: t)
                XCTAssertGreaterThan(p.y, PortalLayout.height,
                                     "a particle fell through the portal row")
                XCTAssertGreaterThan(simd_distance(p, head), 0.6,
                                     "a particle passed within 60 cm of the face")
            }
        }
    }

    /// Every particle ends on its own portal's rim.
    func testEveryParticleLandsOnItsPortalsRim() {
        for particle in cloud {
            let portal = portals[particle.portal]
            XCTAssertEqual(simd_distance(particle.target, portal.position),
                           PortalLayout.rimRadius, accuracy: 1e-9)
            XCTAssertEqual(Opening.position(of: particle, at: Opening.duration),
                           particle.target)
        }
        XCTAssertEqual(Set(cloud.map(\.portal)), Set(0..<7))
    }

    // MARK: The portals

    /// Seven portals on one arc, each facing the wearer, none touching.
    func testThePortalsFaceTheWearerAndDoNotTouch() {
        XCTAssertEqual(portals.count, 7)
        for portal in portals {
            // The face's normal (+z rotated by yaw) points at the wearer.
            let normal = SIMD3(sin(portal.yaw), 0, cos(portal.yaw))
            let toWearer = simd_normalize(SIMD3(-portal.position.x, 0, -portal.position.z))
            XCTAssertEqual(simd_dot(normal, toWearer), 1, accuracy: 1e-9)
        }
        for (a, b) in zip(portals, portals.dropFirst()) {
            XCTAssertGreaterThan(simd_distance(a.position, b.position),
                                 2 * PortalLayout.rimRadius + 0.2)
        }
    }

    // MARK: Arriving

    /// The portals grow the last few per cent into place as their glass
    /// fades up — smaller before, monotonically larger, and exactly full
    /// size by the time the opening hands over (or `finishOpening` would
    /// snap them).
    func testThePortalsGrowIntoPlaceAndFinishFullSize() {
        XCTAssertEqual(Opening.portalScale(at: 0), 1 - Opening.portalGrowth, accuracy: 1e-6)
        var previous: Float = 0
        for step in 0...400 {
            let t = Opening.duration * Double(step) / 400
            let scale = Opening.portalScale(at: t)
            XCTAssertGreaterThanOrEqual(scale, previous - 1e-6, "a portal shrank at \(t) s")
            XCTAssertLessThanOrEqual(scale, 1 + 1e-6, "a portal overshot at \(t) s")
            previous = scale
        }
        XCTAssertEqual(Opening.portalScale(at: Opening.duration), 1, accuracy: 1e-6)
    }

    /// The wordmark rises into place as it fades up, and is exactly in
    /// place when the opening ends.
    func testTheWordmarkRisesIntoPlace() {
        XCTAssertEqual(Opening.titleOffset(at: 0), -Opening.titleRiseDistance, accuracy: 1e-6)
        var previous = -Float.infinity
        for step in 0...400 {
            let t = Opening.duration * Double(step) / 400
            let offset = Opening.titleOffset(at: t)
            XCTAssertGreaterThanOrEqual(offset, previous - 1e-6)
            XCTAssertLessThanOrEqual(offset, 1e-6, "the wordmark rose past its place")
            previous = offset
        }
        XCTAssertEqual(Opening.titleOffset(at: Opening.duration), 0, accuracy: 1e-6)
    }
}
