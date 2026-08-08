//
//  MagneticFieldTests.swift
//  PhysicsCoreTests
//
//  The dipole pinned to the textbook: the on-axis field is exactly twice
//  the equatorial and points the opposite way; the dipole–dipole force
//  obeys Newton's third law and gives attract head-to-tail / repel
//  side-by-side; the torque aligns a magnet with the field; and field
//  lines close back on the magnet.
//

import XCTest
import simd
@testable import PhysicsCore

final class MagneticFieldTests: XCTestCase {

    private let k = MagneticField.mu0over4pi

    /// On the axis B = (μ₀/4π)(2m/r³) along m; on the equator it's half
    /// that, pointing opposite — the classic 2:1 dipole signature.
    func testAxialFieldIsTwiceEquatorialAndOpposite() {
        let m0 = 5.0, r = 0.3
        let magnet = BarMagnet(position: .zero, moment: SIMD3(m0, 0, 0))

        let axial = MagneticField.vector(at: SIMD3(r, 0, 0), dueTo: magnet)
        let equatorial = MagneticField.vector(at: SIMD3(0, r, 0), dueTo: magnet)

        XCTAssertEqual(axial.x, k * 2 * m0 / (r * r * r), accuracy: 1e-18)
        XCTAssertEqual(axial.y, 0, accuracy: 1e-20)
        // Equatorial points along −m and is half the magnitude.
        XCTAssertEqual(equatorial.x, -k * m0 / (r * r * r), accuracy: 1e-18)
        XCTAssertEqual(simd_length(axial), 2 * simd_length(equatorial), accuracy: 1e-18)
    }

    /// Newton's third law for two arbitrary dipoles.
    func testForceObeysNewtonsThirdLaw() {
        let a = BarMagnet(position: SIMD3(-0.1, 0.05, 0), moment: SIMD3(3, 1, -2))
        let b = BarMagnet(position: SIMD3(0.2, -0.1, 0.15), moment: SIMD3(-1, 2, 1))
        let fBA = MagneticField.force(on: b, dueTo: a)
        let fAB = MagneticField.force(on: a, dueTo: b)
        XCTAssertEqual(fBA.x, -fAB.x, accuracy: 1e-16)
        XCTAssertEqual(fBA.y, -fAB.y, accuracy: 1e-16)
        XCTAssertEqual(fBA.z, -fAB.z, accuracy: 1e-16)
    }

    /// Two magnets pointing the same way along their line of centres
    /// attract (N meets S); placed side by side they repel.
    func testAttractHeadToTailRepelSideBySide() {
        let a = BarMagnet(position: .zero, moment: SIMD3(5, 0, 0))
        let headToTail = BarMagnet(position: SIMD3(0.3, 0, 0), moment: SIMD3(5, 0, 0))
        let sideBySide = BarMagnet(position: SIMD3(0, 0.3, 0), moment: SIMD3(5, 0, 0))

        // Head-to-tail: pulled back toward a (−x).
        XCTAssertLessThan(MagneticField.force(on: headToTail, dueTo: a).x, 0)
        // Side-by-side parallel: pushed away (+y).
        XCTAssertGreaterThan(MagneticField.force(on: sideBySide, dueTo: a).y, 0)
    }

    /// Torque is zero when the moment lies along the local field and
    /// equals |m||B| when perpendicular — and it turns the magnet toward
    /// alignment (τ = m × B).
    func testTorqueAlignsWithField() {
        let source = BarMagnet(position: .zero, moment: SIMD3(5, 0, 0))
        let point = SIMD3(0.4, 0, 0)                 // on axis: B along +x
        let field = MagneticField.vector(at: point, dueTo: source)

        let aligned = BarMagnet(position: point, moment: SIMD3(2, 0, 0))
        XCTAssertEqual(simd_length(MagneticField.torque(on: aligned, inFieldOf: [source])),
                       0, accuracy: 1e-20)

        let perpendicular = BarMagnet(position: point, moment: SIMD3(0, 2, 0))
        let torque = MagneticField.torque(on: perpendicular, inFieldOf: [source])
        XCTAssertEqual(simd_length(torque), 2 * simd_length(field), accuracy: 1e-18)
        // m=+y, B=+x → τ = m×B along −z: rotating +y toward +x, i.e. into
        // alignment with the field.
        XCTAssertLessThan(torque.z, 0)
    }

    /// A single magnet's field lines are closed loops: a traced line
    /// starts and ends near the magnet it belongs to.
    func testFieldLinesCloseOnTheMagnet() {
        let magnet = BarMagnet(position: .zero, moment: SIMD3(0, 5, 0))
        var config = MagneticFieldLineTracer.Config()
        config.boundsRadius = 1.5
        let lines = MagneticFieldLineTracer.trace(magnets: [magnet], config: config)
        XCTAssertFalse(lines.isEmpty, "a magnet should radiate field lines")
        // At least one substantial loop returns near where it began.
        let loops = lines.filter { line in
            guard let first = line.first, let last = line.last, line.count > 8 else { return false }
            return simd_distance(first, magnet.position) < 0.12
                && simd_distance(last, magnet.position) < 0.12
        }
        XCTAssertFalse(loops.isEmpty, "field lines should loop back to the magnet")
    }

    // MARK: The finite bar

    /// The pole-pair bar carries the same total moment as the point
    /// dipole, so far away the two must agree — that convergence is the
    /// whole licence for using either. Checked at four bar-lengths and
    /// again at twenty, where the error has to have shrunk.
    func testTheFiniteBarConvergesToThePointDipoleFarAway() {
        let length = 0.16
        let magnet = BarMagnet(position: .zero, moment: SIMD3(0, 6, 0))

        func relativeError(at radius: Double) -> Double {
            // Off-axis, so the test is not fooled by an accidental
            // agreement on one symmetry axis.
            let point = SIMD3(radius * 0.6, radius * 0.8, 0)
            let ideal = MagneticField.vector(at: point, dueTo: magnet)
            let bar = MagneticField.barVector(at: point, dueTo: magnet, length: length)
            return simd_length(bar - ideal) / simd_length(ideal)
        }

        let near = relativeError(at: length * 4)
        let far = relativeError(at: length * 20)
        XCTAssertLessThan(near, 0.05,
                          "the bar has drifted off the dipole it is made of")
        XCTAssertLessThan(far, near / 10,
                          "the error is not falling with distance — the bar "
                          + "does not carry the moment it claims")
    }

    /// …and CLOSE to the bar the two genuinely disagree. If they did not,
    /// there would be no reason for the tracer to pay for the pole-pair
    /// model at all.
    func testTheFiniteBarDepartsFromThePointDipoleNearTheMagnet() {
        let length = 0.16
        let magnet = BarMagnet(position: .zero, moment: SIMD3(0, 6, 0))
        // Just off the bar's flank — where the field lines are seeded.
        let point = SIMD3(0.115, 0.02, 0)
        let ideal = MagneticField.vector(at: point, dueTo: magnet)
        let bar = MagneticField.barVector(at: point, dueTo: magnet, length: length)
        let error = simd_length(bar - ideal) / simd_length(ideal)
        XCTAssertGreaterThan(error, 0.10,
                             "at two-thirds of a bar-length the point dipole "
                             + "is supposed to be a poor model of a bar")
    }

    // MARK: Seeding

    /// Seeds are spread by equal slices of FLUX, not equal area. For a
    /// dipole the flux through a cap of half-angle θ goes as sin²θ, so
    /// the k-th of n seeds sits at sin²θ = (k + ½)/n. Checked against
    /// that closed form directly, in a tilted frame so the test cannot
    /// pass by accident on a coordinate axis.
    func testSeedsAreSpacedByEqualFlux() {
        let axis = simd_normalize(SIMD3<Double>(1, 2, -0.5))
        let n = 12
        let directions = MagneticFieldLineTracer.fluxSeedDirections(
            axis: axis, count: n)
        XCTAssertEqual(directions.count, n)
        for (k, direction) in directions.enumerated() {
            XCTAssertEqual(simd_length(direction), 1, accuracy: 1e-12,
                           "seed \(k) is not on the unit sphere")
            let cosTheta = simd_dot(direction, axis)
            let sin2 = 1 - cosTheta * cosTheta
            XCTAssertEqual(sin2, (Double(k) + 0.5) / Double(n), accuracy: 1e-12,
                           "seed \(k) does not carry its equal share of flux")
        }
    }

    /// Every seed is on the NORTH half. Both halves would be redundant:
    /// each seed is traced in both directions and comes back a closed
    /// loop that already crosses the south.
    func testSeedsStayOnTheNorthHalfOfTheSphere() {
        let axis = simd_normalize(SIMD3<Double>(0, -1, 0.3))
        for direction in MagneticFieldLineTracer.fluxSeedDirections(
            axis: axis, count: 20) {
            XCTAssertGreaterThanOrEqual(simd_dot(direction, axis), 0,
                                        "a seed crossed into the far hemisphere")
        }
    }

    // MARK: Density

    /// A stronger magnet draws more loops. This was the promise the
    /// module's strength bead made and could not keep: the tracer
    /// integrates the NORMALIZED field, so with a fixed seed count a
    /// magnet's loops were identical at every strength and pulling the
    /// bead rebuilt an unchanged mesh.
    func testAStrongerMagnetEarnsMoreLines() {
        var config = MagneticFieldLineTracer.Config()
        config.referenceStrength = 6
        config.seedsPerMagnet = 12
        XCTAssertEqual(config.seedCount(forStrength: 6), 12)
        XCTAssertEqual(config.seedCount(forStrength: 12), 24)
        XCTAssertEqual(config.seedCount(forStrength: 3), 6)
        // Bounded at both ends: one loop is not a field, and a maxed
        // magnet must not blow the frame budget.
        XCTAssertEqual(config.seedCount(forStrength: 0.01),
                       config.seedRange.lowerBound)
        XCTAssertEqual(config.seedCount(forStrength: 1e6),
                       config.seedRange.upperBound)
    }

    /// Lines are born and die OUTSIDE the bar they belong to. They used
    /// to be seeded 6 cm from the centre of a 16 cm magnet and to
    /// terminate at 5 cm — inside its body — so every loop emerged from
    /// the middle of a flank and vanished into it, with a dead sphere
    /// where the poles should have been.
    func testLinesAreSeededClearOfTheBarItself() {
        var config = MagneticFieldLineTracer.Config()
        config.magnetLength = 0.16
        let halfLength = config.magnetLength / 2
        XCTAssertGreaterThan(config.seedRadius, halfLength,
                             "lines start inside the magnet")
        XCTAssertGreaterThan(config.terminationRadius, halfLength,
                             "lines end inside the magnet")
        // …and the stop sphere is inside the seed sphere, or every line
        // terminates on the step it was born.
        XCTAssertLessThan(config.terminationRadius, config.seedRadius)
    }
}

/// Volume seeding: the field drawn evenly through the room it is in,
/// rather than in a tight bundle around the bar.
///
/// The property that matters most here is NOT that lines appear — it is
/// that the same closed loop is not drawn many times over. Seeds
/// scattered through a volume land on shared loops constantly, and the
/// naive version of this produces a handful of curves stacked on each
/// other at random offsets: exactly the "some read thick, some thin, for
/// no reason" defect the 2026-07-31 seeding pass removed.
final class MagneticVolumeSeedingTests: XCTestCase {

    private func magnet() -> BarMagnet {
        BarMagnet(position: .zero, moment: SIMD3(6, 0, 0))
    }

    private var halfExtents: SIMD3<Double> { SIMD3(0.62, 0.85, 0.55) }

    private func config() -> MagneticFieldLineTracer.Config {
        var config = MagneticFieldLineTracer.Config()
        config.magnetLength = 0.16
        config.boundsRadius = 1.4
        config.stepSize = 0.008
        config.maxSteps = 700
        return config
    }

    func testSeedsFillTheBoxWithoutClumpingOntoAPlane() {
        let seeds = MagneticFieldLineTracer.volumeSeeds(
            center: .zero, halfExtents: halfExtents, count: 200)
        XCTAssertEqual(seeds.count, 200)

        // Inside the box, every one of them.
        for seed in seeds {
            XCTAssertLessThanOrEqual(abs(seed.x), halfExtents.x + 1e-12)
            XCTAssertLessThanOrEqual(abs(seed.y), halfExtents.y + 1e-12)
            XCTAssertLessThanOrEqual(abs(seed.z), halfExtents.z + 1e-12)
        }
        // Both halves of every axis get used — a sequence that collapsed
        // onto a plane or a diagonal would still be "inside the box".
        for axis in 0..<3 {
            let values = seeds.map { $0[axis] }
            XCTAssertGreaterThan(values.filter { $0 > 0 }.count, 60, "axis \(axis)")
            XCTAssertLessThan(values.filter { $0 > 0 }.count, 140, "axis \(axis)")
        }
        // Deterministic: a worker's output has to be reproducible.
        let again = MagneticFieldLineTracer.volumeSeeds(
            center: .zero, halfExtents: halfExtents, count: 200)
        XCTAssertEqual(seeds, again)
    }

    func testVolumeTracingReachesFurtherOutThanFluxSeeding() {
        let magnets = [magnet()]
        let flux = MagneticFieldLineTracer.trace(magnets: magnets, config: config())
        let volume = MagneticFieldLineTracer.traceThroughVolume(
            magnets: magnets, config: config(),
            center: .zero, halfExtents: halfExtents)

        XCTAssertFalse(volume.isEmpty, "no lines at all")

        // The whole point: lines that live out where the user is
        // standing, not only in a bundle around the bar. Compare the
        // MEDIAN distance from the magnet across every drawn point.
        func medianRadius(_ lines: [[SIMD3<Double>]]) -> Double {
            let radii = lines.flatMap { $0 }.map { simd_length($0) }.sorted()
            return radii.isEmpty ? 0 : radii[radii.count / 2]
        }
        XCTAssertGreaterThan(medianRadius(volume), medianRadius(flux),
                             "volume seeding did not spread the field out")
    }

    /// THE DEDUP PROPERTY. No two returned loops may be substantially the
    /// same curve — which is what makes this different from simply
    /// throwing more seeds at the problem.
    func testNoTwoLoopsAreTheSameCurve() {
        let lines = MagneticFieldLineTracer.traceThroughVolume(
            magnets: [magnet()], config: config(),
            center: .zero, halfExtents: halfExtents, spacing: 0.11)
        XCTAssertGreaterThan(lines.count, 3, "too few lines to be a field")

        for i in 0..<lines.count {
            for j in (i + 1)..<lines.count {
                let a = stride(from: 0, to: lines[i].count, by: 8).map { lines[i][$0] }
                let b = stride(from: 0, to: lines[j].count, by: 8).map { lines[j][$0] }
                var retraced = 0
                for point in a {
                    let nearest = b.reduce(Double.infinity) {
                        min($0, simd_distance($1, point))
                    }
                    if nearest < 0.11 { retraced += 1 }
                }
                let overlap = Double(retraced) / Double(a.count)
                XCTAssertLessThanOrEqual(
                    overlap, 0.70,
                    "lines \(i) and \(j) are \(Int(overlap * 100))% the same curve")
            }
        }
    }

    func testEveryLineIsStillATrueStreamlineOfB() {
        let magnets = [magnet()]
        let lines = MagneticFieldLineTracer.traceThroughVolume(
            magnets: magnets, config: config(),
            center: .zero, halfExtents: halfExtents)

        // Evenness is a seeding choice; being a field line is not
        // negotiable. Each step must lie along the local B.
        for line in lines {
            for index in stride(from: 4, to: line.count - 4, by: 17) {
                let step = line[index + 1] - line[index]
                guard simd_length(step) > 1e-9 else { continue }
                let field = MagneticField.barVector(
                    at: line[index], dueTo: magnets, length: 0.16)
                guard simd_length(field) > 1e-13 else { continue }
                let alignment = abs(simd_dot(simd_normalize(step),
                                             simd_normalize(field)))
                XCTAssertGreaterThan(alignment, 0.9,
                                     "a drawn segment is not along B")
            }
        }
    }

    func testTheBudgetIsRespected() {
        let lines = MagneticFieldLineTracer.traceThroughVolume(
            magnets: [magnet()], config: config(),
            center: .zero, halfExtents: halfExtents, budget: 6)
        XCTAssertLessThanOrEqual(lines.count, 6)
    }
}

/// Earth's field — the reason a compass carried away from the bench
/// still knows which way to point.
final class GeomagneticFieldTests: XCTestCase {

    func testTheFieldPointsNorthAndDOWN() {
        let b = GeomagneticField.vector()
        XCTAssertEqual(simd_length(b), GeomagneticField.referenceMagnitude,
                       accuracy: 1e-12)
        // North component positive along north…
        XCTAssertGreaterThan(simd_dot(b, GeomagneticField.north), 0)
        // …and the vertical component INTO the ground, which is the
        // thing a flat dial can never show.
        XCTAssertLessThan(simd_dot(b, GeomagneticField.up), 0)

        // 65° below horizontal: the vertical part should be the larger.
        let horizontal = simd_dot(b, GeomagneticField.north)
        let vertical = -simd_dot(b, GeomagneticField.up)
        XCTAssertEqual(atan2(vertical, horizontal) * 180 / .pi,
                       GeomagneticField.referenceDipDegrees, accuracy: 1e-9)
        XCTAssertGreaterThan(vertical, horizontal,
                             "at 65° the field is mostly vertical")
    }

    func testAHorizontalFieldIsWhatZeroDipMeans() {
        let b = GeomagneticField.vector(dipDegrees: 0)
        XCTAssertEqual(simd_dot(b, GeomagneticField.up), 0, accuracy: 1e-18)
    }

    func testDipAtNinetyDegreesPointsStraightDown() {
        let b = GeomagneticField.vector(dipDegrees: 90)
        XCTAssertEqual(simd_dot(b, GeomagneticField.north), 0, accuracy: 1e-18)
        XCTAssertEqual(-simd_dot(b, GeomagneticField.up),
                       GeomagneticField.referenceMagnitude, accuracy: 1e-12)
    }

    /// tan I = 2 tan φ — and the consequence people find surprising:
    /// the field is already steeper than 45° well before the latitude is.
    func testTheDipLawIsTwoTanLatitude() {
        XCTAssertEqual(GeomagneticField.dipDegrees(atLatitude: 0), 0, accuracy: 1e-12)
        XCTAssertEqual(GeomagneticField.dipDegrees(atLatitude: 90), 90, accuracy: 1e-9)
        // 45° of latitude already gives 63° of dip.
        XCTAssertEqual(GeomagneticField.dipDegrees(atLatitude: 45), 63.43, accuracy: 0.01)
        // Southern hemisphere tips the other way.
        XCTAssertEqual(GeomagneticField.dipDegrees(atLatitude: -30),
                       -GeomagneticField.dipDegrees(atLatitude: 30), accuracy: 1e-12)
    }

    /// THE NUMBER THE WHOLE FEATURE RESTS ON: a default magnet and Earth
    /// are comparable at about arm's length, so walking a compass away
    /// from the bench genuinely hands it over to Earth. If this drifted
    /// far from ~0.3 m the demonstration would stop working — either the
    /// magnets would never win, or Earth never would.
    func testTheCrossoverIsAboutArmsLength() {
        let r = GeomagneticField.crossoverDistance(momentMagnitude: 6.0)
        XCTAssertEqual(r, 0.31, accuracy: 0.03)

        // And it really is where the two fields are equal: check against
        // the dipole field the app actually integrates.
        let magnet = BarMagnet(position: .zero, moment: SIMD3(6, 0, 0))
        let onAxis = MagneticField.vector(at: SIMD3(r, 0, 0), dueTo: magnet)
        XCTAssertEqual(simd_length(onAxis), GeomagneticField.referenceMagnitude,
                       accuracy: GeomagneticField.referenceMagnitude * 0.02)
    }

    /// Close in, the magnet must dominate outright; far out, Earth must.
    func testTheMagnetWinsCloseAndEarthWinsFar() {
        let magnet = BarMagnet(position: .zero, moment: SIMD3(6, 0, 0))
        let earth = GeomagneticField.referenceMagnitude

        let near = MagneticField.vector(at: SIMD3(0.15, 0, 0), dueTo: magnet)
        XCTAssertGreaterThan(simd_length(near), earth * 5)

        let far = MagneticField.vector(at: SIMD3(0.60, 0, 0), dueTo: magnet)
        XCTAssertLessThan(simd_length(far), earth / 5)
    }

    // MARK: The finite bar's force

    private static let barLength = 0.16

    /// FAR AWAY, A BAR IS A DIPOLE. This is the safety property for
    /// replacing the dynamics' force: the new one must agree with the
    /// old wherever the old one was right, or the fix has changed
    /// something it had no business changing.
    func testBarForceMeetsTheDipoleForceFarAway() {
        let L = Self.barLength
        let a = BarMagnet(position: .zero, moment: SIMD3(1.0, 0, 0))
        for ratio in [8.0, 12.0, 20.0] {
            let b = BarMagnet(position: SIMD3(L * ratio, 0, 0),
                              moment: SIMD3(1.0, 0, 0))
            let dipole = MagneticField.force(on: b, dueTo: a)
            let bar = MagneticField.barForce(on: b, dueTo: a, length: L)
            let error = simd_length(bar - dipole) / simd_length(dipole)
            // Measured: 2.7 % at r/L = 8, 1.2 % at 12, 0.4 % at 20 —
            // the O((L/r)^2) convergence the expansion promises. 7 % at
            // r/L = 5 is still real disagreement, which is why the
            // sampling starts at 8.
            XCTAssertLessThan(error, 0.035,
                              "at r/L = \(ratio) the two models differ by "
                              + "\(error * 100)%, where the expansion should "
                              + "have converged")
        }
    }

    /// CLOSE IN, IT IS NOT — and by a margin that decides where the
    /// magnets end up. Magnetism's `contactDistance` is 0.92 bar-lengths,
    /// which is exactly where the dipole expansion has no claim.
    func testBarForceDivergesFromTheDipoleAtContact() {
        let L = Self.barLength
        let a = BarMagnet(position: .zero, moment: SIMD3(1.0, 0, 0))
        let b = BarMagnet(position: SIMD3(L * 0.92, 0, 0),
                          moment: SIMD3(1.0, 0, 0))
        let dipole = simd_length(MagneticField.force(on: b, dueTo: a))
        let bar = simd_length(MagneticField.barForce(on: b, dueTo: a, length: L))
        XCTAssertGreaterThan(
            abs(bar - dipole) / bar, 0.2,
            "if these now agree at contact, either the pole model or the "
            + "dipole one has changed — this test exists to record that they "
            + "genuinely do not, which is why the dynamics moved")
    }

    /// Newton's third law, EXACTLY. A sum of pole-pole central forces
    /// has it by construction, where the dipole expansion only has it to
    /// the order it is carried to.
    func testBarForceObeysNewtonsThirdLaw() {
        let L = Self.barLength
        let a = BarMagnet(position: SIMD3(-0.05, 0.02, 0),
                          moment: SIMD3(0.8, 0.6, 0))
        let b = BarMagnet(position: SIMD3(0.09, -0.01, 0.03),
                          moment: SIMD3(-0.3, 0.9, 0.2))
        let fBA = MagneticField.barForce(on: b, dueTo: a, length: L)
        let fAB = MagneticField.barForce(on: a, dueTo: b, length: L)
        XCTAssertEqual(simd_length(fBA + fAB), 0,
                       accuracy: simd_length(fBA) * 1e-9,
                       "the pair does not push on each other equally")
    }

    /// Head to tail attracts and side by side repels, WELL CLEAR of the
    /// poles. Two bar-lengths apart, not one — see the singularity test
    /// below for why one is not a legal question to ask.
    func testBarForceKeepsTheSignsAUserWouldCheck() {
        let L = Self.barLength
        let a = BarMagnet(position: .zero, moment: SIMD3(1.0, 0, 0))
        let headToTail = BarMagnet(position: SIMD3(L * 2, 0, 0),
                                   moment: SIMD3(1.0, 0, 0))
        XCTAssertLessThan(MagneticField.barForce(on: headToTail, dueTo: a,
                                                 length: L).x, 0,
                          "north-to-south should pull them together")
        let sideBySide = BarMagnet(position: SIMD3(0, L * 2, 0),
                                   moment: SIMD3(1.0, 0, 0))
        XCTAssertGreaterThan(MagneticField.barForce(on: sideBySide, dueTo: a,
                                                    length: L).y, 0,
                             "parallel and abreast should shove apart")
    }

    /// THE POLE MODEL HAS ITS OWN SINGULARITY, AND IT SITS EXACTLY WHERE
    /// THE MAGNETS MEET. This is the test that stopped the dynamics
    /// being switched over.
    ///
    /// Two bars head to tail at one bar-length apart put A's north pole
    /// and B's south pole at the SAME POINT. `poleCoreRadius` softens
    /// the divide-by-zero but cannot rescue the answer: measured, the
    /// force comes out REPULSIVE for a pair that must attract, and a
    /// fifth of a bar-length further out it is seven times the dipole
    /// value.
    ///
    /// So audit P1-22 is right that the dipole is the wrong model at
    /// `contactDistance` (50 % low there) and wrong that the bar field
    /// is the remedy for the FORCE. Both are unusable at contact, in
    /// opposite directions. A near-field force that is actually correct
    /// needs the magnetised VOLUME integrated, which neither of these
    /// is.
    func testTheBarForceIsUnusableWhereThePolesMeet() {
        let L = Self.barLength
        let a = BarMagnet(position: .zero, moment: SIMD3(1.0, 0, 0))
        let touching = BarMagnet(position: SIMD3(L, 0, 0),
                                 moment: SIMD3(1.0, 0, 0))
        let force = MagneticField.barForce(on: touching, dueTo: a, length: L)

        XCTAssertGreaterThan(
            force.x, 0,
            "The pole-pair force at one bar-length is no longer repulsive. "
            + "If the pole cores were widened or the model changed that may "
            + "be an improvement — but Magnetism's dynamics were left on the "
            + "point dipole BECAUSE of this, so re-read `MagnetismModel.step` "
            + "before celebrating.")
    }

}
