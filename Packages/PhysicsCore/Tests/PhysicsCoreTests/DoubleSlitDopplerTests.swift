//
//  DoubleSlitDopplerTests.swift
//  PhysicsCoreTests
//
//  The wave lab's two headline effects, pinned exactly: double-slit
//  fringes land at y = L·tan(asin(mλ/d)) with zeros exactly between
//  them, and a moving source's crests bunch to (c−v)/f ahead and
//  stretch to (c+v)/f behind — Doppler emerging from nothing but
//  "crests expand from where they were emitted."
//

import XCTest
import simd
@testable import PhysicsCore

final class DoubleSlitDopplerTests: XCTestCase {

    private let wavelength = 0.05
    private let separation = 0.12
    private let distance = 0.8

    /// Bright fringes: the two-slit factor is exactly 1 at
    /// sinθ = mλ/d; with a hair-thin slit the whole intensity is ~1.
    func testBrightFringesAreBright() {
        for order in 0...2 {
            let y = distance * tan(asin(Double(order) * wavelength / separation))
            let intensity = DoubleSlit.intensity(
                y: y, distance: distance, separation: separation,
                slitWidth: wavelength / 1000, wavelength: wavelength)
            XCTAssertEqual(intensity, 1.0, accuracy: 1e-5, "order \(order)")
        }
    }

    /// Dark fringes: exactly zero at sinθ = (m+½)λ/d. (Order 2 would
    /// need sinθ > 1 with these numbers — it doesn't exist.)
    func testDarkFringesAreDark() {
        for order in 0...1 {
            let sinTheta = (Double(order) + 0.5) * wavelength / separation
            let y = distance * tan(asin(sinTheta))
            let intensity = DoubleSlit.intensity(
                y: y, distance: distance, separation: separation,
                slitWidth: wavelength / 1000, wavelength: wavelength)
            XCTAssertEqual(intensity, 0.0, accuracy: 1e-12, "order \(order)")
        }
    }

    /// The single-slit envelope kills the pattern at sinθ = λ/w.
    func testEnvelopeZero() {
        let width = 0.1   // λ/w = 0.5 — the zero sits at a real angle
        let y = distance * tan(asin(wavelength / width))
        let intensity = DoubleSlit.intensity(
            y: y, distance: distance, separation: separation,
            slitWidth: width, wavelength: wavelength)
        XCTAssertEqual(intensity, 0.0, accuracy: 1e-12)
    }

    /// Δy = λL/d, and the exact fringe list is symmetric around zero.
    func testFringeSpacingAndPositions() {
        XCTAssertEqual(
            DoubleSlit.fringeSpacing(distance: distance, separation: separation,
                                     wavelength: wavelength),
            wavelength * distance / separation, accuracy: 1e-15)
        let fringes = DoubleSlit.brightFringes(
            distance: distance, separation: separation,
            wavelength: wavelength, count: 3)
        XCTAssertEqual(fringes.count, 3)
        XCTAssertEqual(fringes[1], 0, accuracy: 1e-15)
        XCTAssertEqual(fringes[2], -fringes[0], accuracy: 1e-12)
        XCTAssertEqual(fringes[2],
                       distance * tan(asin(wavelength / separation)),
                       accuracy: 1e-12)
    }

    /// A source gliding at v = 0.3·c: crest spacing ahead is exactly
    /// (c−v)·T and behind exactly (c+v)·T, regardless of how raggedly
    /// the clock advances (emissions interpolate to exact times).
    func testDopplerCrestSpacing() {
        let speed = 1.0          // wave speed c
        let sourceSpeed = 0.3
        let period = 0.5
        var trail = EmissionTrail(period: period, capacity: 12)

        // Advance in awkward 0.13 s bites to exercise interpolation.
        var time = 0.0
        while time < 3.0 {
            trail.advance(to: time, sourcePosition: SIMD3(sourceSpeed * time, 0, 0))
            time += 0.13
        }
        trail.advance(to: 3.0, sourcePosition: SIMD3(sourceSpeed * 3.0, 0, 0))

        let shells = trail.shells(at: 3.0, speed: speed)
        XCTAssertGreaterThanOrEqual(shells.count, 5)
        // Leading edges (ahead of motion) and trailing edges (behind).
        let leading = shells.map { $0.center.x + $0.radius }.sorted()
        let trailing = shells.map { $0.center.x - $0.radius }.sorted()
        for pair in zip(leading, leading.dropFirst()) {
            XCTAssertEqual(pair.1 - pair.0, (speed - sourceSpeed) * period,
                           accuracy: 1e-12, "compressed ahead")
        }
        for pair in zip(trailing, trailing.dropFirst()) {
            XCTAssertEqual(pair.1 - pair.0, (speed + sourceSpeed) * period,
                           accuracy: 1e-12, "stretched behind")
        }
    }

    /// The ring buffer keeps only the newest crests.
    func testTrailCapacity() {
        var trail = EmissionTrail(period: 0.1, capacity: 4)
        trail.advance(to: 0, sourcePosition: .zero)
        trail.advance(to: 2.0, sourcePosition: SIMD3(2, 0, 0))
        XCTAssertEqual(trail.events.count, 4)
        XCTAssertEqual(trail.events.last!.time, 1.9, accuracy: 1e-9,
                       "the newest crests survive; older ones rolled off")
    }
}
