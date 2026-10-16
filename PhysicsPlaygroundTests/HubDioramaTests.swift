//
//  HubDioramaTests.swift
//  PhysicsPlaygroundTests
//
//  The home's dioramas are the labs in miniature, so their motion is held
//  to the labs' physics: the cradle swings at the exact large-amplitude
//  period of the lab's 0.55 m cables and hands the swing across; the prism
//  sends violet further than red, onto its screen; the coil's LED lights
//  both colours and is dark when the magnet stops; the orrery keeps
//  Kepler's third law and solves Kepler's equation; and every lab's stage
//  is the same size in its portal, which is what makes them one set.
//

import XCTest
import PhysicsCore
import RealityKit
import simd
@testable import PhysicsPlayground

@MainActor
final class HubDioramaTests: XCTestCase {

    // MARK: The cradle

    /// T = 4√(L/g)·K(sin(θ₀/2)), the complete elliptic integral by the
    /// arithmetic–geometric mean: the large-amplitude period, about 2 %
    /// longer than 2π√(L/g) at 0.55 rad.
    func testTheCradleSwingsAtTheExactLargeAmplitudePeriod() {
        let swing = HubVignettes.cradleSwing
        let k = sin(swing.amplitude / 2)
        var a = 1.0, b = (1 - k * k).squareRoot()
        for _ in 0..<12 { (a, b) = ((a + b) / 2, (a * b).squareRoot()) }
        let K = Double.pi / (2 * a)
        let exact = 4 * (0.55 / 9.81).squareRoot() * K
        XCTAssertEqual(swing.period, exact, accuracy: exact * 1e-4)
        XCTAssertGreaterThan(swing.period, 2 * .pi * (0.55 / 9.81).squareRoot() * 1.015)
    }

    /// Released on the left, at rest on the bottom, out on the right, and
    /// back — each end ball still while the other moves.
    func testTheCradleHandsTheSwingAcross() {
        let swing = HubVignettes.cradleSwing
        let q = swing.quarter
        let start = swing.cradle(at: 0)
        XCTAssertEqual(start.left, -swing.amplitude, accuracy: 1e-9)
        XCTAssertEqual(start.right, 0)
        XCTAssertEqual(swing.cradle(at: q).left, 0, accuracy: 1e-3)
        XCTAssertEqual(swing.cradle(at: 2 * q).right, swing.amplitude, accuracy: 1e-3)
        for step in 0..<200 {
            let ends = swing.cradle(at: Double(step) * swing.period / 200)
            XCTAssertTrue(ends.left == 0 || ends.right == 0, "both end balls moved at once")
            XCTAssertLessThanOrEqual(ends.left, 0)
            XCTAssertGreaterThanOrEqual(ends.right, 0)
        }
    }

    // MARK: The prism

    /// White light at least deviation: violet turned further than red, the
    /// fan a few degrees wide, and both ends of it on the screen.
    func testTheSpectrumFallsInOrderOnTheScreen() throws {
        let bench = HubVignettes.OpticsBench.shared
        let prism = OpticalElement(
            position: bench.prismCentre, orientation: simd_quatd(angle: 0, axis: SIMD3(0, 0, 1)),
            shape: .prism(apexAngle: OpticsModel.prismApex, side: OpticsModel.prismSide,
                          length: OpticsModel.prismHeight),
            glass: HubVignettes.dioramaGlass)
        func landing(_ nm: Double) throws -> SIMD3<Double> {
            let trace = LightTracer.trace(
                [.init(origin: bench.start, direction: bench.incoming, nanometers: nm)],
                elements: [prism], room: LightTracer.Room(maxSegment: 0.4),
                options: .init(followsPartialReflections: false))
            let out = try XCTUnwrap(trace.segments.last { $0.inside == nil && $0.direction.y < 0 })
            let t = simd_dot(bench.screenPoint - out.a, bench.screenNormal)
                / simd_dot(out.b - out.a, bench.screenNormal)
            return out.a + (out.b - out.a) * t
        }
        let violet = try landing(420), red = try landing(660)
        XCTAssertLessThan(violet.y, red.y, "violet should be bent further, toward the base")
        for hit in [violet, red] {
            XCTAssertLessThan(simd_distance(hit, bench.screenPoint), 0.05, "the light missed the screen")
        }
    }

    // MARK: The coil

    /// One stroke lights both colours — one going in, the other coming out —
    /// and the LED is dark where the magnet turns round and stands still.
    func testTheCoilLightsBothWaysAndIsDarkAtRest() {
        let levels = HubVignettes.coilLEDLevels
        XCTAssertGreaterThanOrEqual(levels.max() ?? 0, 3, "the red LED never plainly lit")
        XCTAssertLessThanOrEqual(levels.min() ?? 0, -3, "the green LED never plainly lit")
        // sin(2πt/P) turns at a quarter and three quarters of the stroke.
        for phase in [0.25, 0.75] {
            XCTAssertEqual(levels[Int(phase * Double(levels.count))], 0,
                           "lit while the magnet stood still at \(phase)")
        }
    }

    // MARK: The orrery

    /// T² = a³ in years and AU: the table's real periods and axes agree.
    func testTheOrreryKeepsKeplersThirdLaw() {
        for planet in HubVignettes.orreryPlanets {
            XCTAssertEqual(planet.period * planet.period / (planet.a * planet.a * planet.a), 1,
                           accuracy: 0.002, planet.name)
        }
    }

    /// The true anomaly it places a planet by satisfies Kepler's equation.
    func testTheTrueAnomalySolvesKeplersEquation() {
        let e = 0.2056
        for mean in stride(from: 0.1, to: 6.2, by: 0.37) {
            let nu = HubVignettes.trueAnomaly(meanAnomaly: mean, eccentricity: e)
            let E = 2 * atan(sqrt((1 - e) / (1 + e)) * tan(nu / 2))
            var back = E - e * sin(E)
            if back < 0 { back += 2 * .pi }
            XCTAssertEqual(back, mean, accuracy: 1e-9)
        }
    }

    // MARK: The set

    /// Every lab's stage is the same size in its portal, whatever stands on
    /// it: the one thing that makes seven exhibits a row.
    func testEveryStageIsTheSameSizeInItsPortal() throws {
        var widths: [String: Float] = [:]
        for id in ModuleCatalog.allIDs {
            let built = HubVignettes.make(for: id)
            let stage = try XCTUnwrap(built.entity.findEntity(named: HubVignettes.stageName),
                                      "\(id) stands on no stage")
            widths[id] = stage.visualBounds(relativeTo: built.entity).extents.x
        }
        let reference = try XCTUnwrap(widths.values.first)
        for (id, width) in widths {
            XCTAssertEqual(width, reference, accuracy: reference * 0.002, "\(id)'s stage differs")
        }
    }
}
