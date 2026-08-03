//
//  CircuitSolverTests.swift
//  PhysicsCoreTests
//
//  The solver is pinned to the results every EE course starts from:
//  Ohm's law, series and parallel combination, the voltage divider,
//  Kirchhoff's current law at a junction, energy conservation, switch
//  behavior — and the RC charging curve, checked point-by-point
//  against V(1 − e^(−t/RC)).
//

import XCTest
@testable import PhysicsCore

final class CircuitSolverTests: XCTestCase {

    private let internalR = 0.05

    private func battery(_ volts: Double, _ a: Int, _ b: Int) -> CircuitElement {
        CircuitElement(nodeA: a, nodeB: b,
                       kind: .battery(volts: volts, internalResistance: internalR))
    }

    private func resistor(_ ohms: Double, _ a: Int, _ b: Int) -> CircuitElement {
        CircuitElement(nodeA: a, nodeB: b, kind: .resistor(ohms: ohms))
    }

    /// 9 V across 100 Ω: I = V/(R + r_int), exactly.
    func testOhmsLaw() {
        let elements = [battery(9, 1, 0), resistor(100, 1, 0)]
        let solution = CircuitSolver.solve(elements: elements, nodeCount: 2)
        let expected = 9.0 / (100 + internalR)
        XCTAssertEqual(solution.currents[1], expected, accuracy: expected * 1e-6)
        // The battery drives that same current out of its + terminal.
        XCTAssertEqual(solution.currents[0], -expected, accuracy: expected * 1e-6)
    }

    /// Series resistors add; the divider splits voltage proportionally.
    func testSeriesResistorsAndVoltageDivider() {
        let elements = [battery(12, 1, 0), resistor(300, 1, 2), resistor(100, 2, 0)]
        let solution = CircuitSolver.solve(elements: elements, nodeCount: 3)
        let expected = 12.0 / (400 + internalR)
        XCTAssertEqual(solution.currents[1], expected, accuracy: expected * 1e-6)
        // Divider: the 100 Ω sees a quarter of the (loaded) source voltage.
        XCTAssertEqual(solution.nodeVoltages[2], 12 * 100 / (400 + internalR),
                       accuracy: 1e-6)
    }

    /// Parallel resistors combine as the product over the sum.
    func testParallelResistors() {
        let elements = [battery(6, 1, 0), resistor(100, 1, 0), resistor(300, 1, 0)]
        let solution = CircuitSolver.solve(elements: elements, nodeCount: 2)
        let parallel = 75.0  // 100·300/400
        let total = 6.0 / (parallel + internalR)
        let branchSum = solution.currents[1] + solution.currents[2]
        XCTAssertEqual(branchSum, total, accuracy: total * 1e-6)
        // And each branch by Ohm's law from the shared node voltage.
        XCTAssertEqual(solution.currents[1],
                       solution.nodeVoltages[1] / 100, accuracy: 1e-9)
    }

    /// Kirchhoff's current law: at every non-ground node, element
    /// currents sum to zero.
    func testKirchhoffCurrentLaw() {
        let elements = [
            battery(9, 1, 0), resistor(220, 1, 2),
            resistor(470, 2, 0), resistor(330, 2, 0),
        ]
        let solution = CircuitSolver.solve(elements: elements, nodeCount: 3)
        // Node 2: in from the 220 Ω, out through the 470 and 330. The
        // tolerance is the solver's documented 1 nS stabilizing leak.
        let net = solution.currents[1] - solution.currents[2] - solution.currents[3]
        XCTAssertEqual(net, 0, accuracy: 1e-7)
    }

    /// Energy conservation: the battery's delivered power equals the sum
    /// dissipated everywhere (its own internal resistance included).
    func testPowerBalances() {
        let elements = [battery(9, 1, 0), resistor(150, 1, 2), resistor(50, 2, 0)]
        let solution = CircuitSolver.solve(elements: elements, nodeCount: 3)
        let total = solution.powers.reduce(0, +)
        // Off only by what the 1 nS stabilizing leak sips.
        XCTAssertEqual(total, 0, accuracy: 1e-6,
                       "power delivered must equal power dissipated")
        XCTAssertLessThan(solution.powers[0], 0, "the battery is the source")
    }

    /// An open switch stops everything; a closed one conducts.
    func testSwitchGatesTheCircuit() {
        let open = [battery(9, 1, 0), CircuitElement(nodeA: 1, nodeB: 2, kind: .open),
                    resistor(100, 2, 0)]
        let openSolution = CircuitSolver.solve(elements: open, nodeCount: 3)
        XCTAssertEqual(openSolution.currents[2], 0, accuracy: 1e-7)

        let closed = [battery(9, 1, 0), CircuitElement(nodeA: 1, nodeB: 2, kind: .conductor),
                      resistor(100, 2, 0)]
        let closedSolution = CircuitSolver.solve(elements: closed, nodeCount: 3)
        let expected = 9.0 / (100 + internalR + CircuitSolver.switchResistance)
        XCTAssertEqual(closedSolution.currents[2], expected, accuracy: expected * 1e-4)
    }

    /// The flagship transient: an RC series circuit charged step by step
    /// must trace V·(1 − e^(−t/RC)) — backward Euler with a fine step
    /// stays within 1% through the whole curve.
    func testRCChargingCurve() {
        let volts = 9.0, ohms = 1000.0, farads = 1e-3
        let tau = ohms * farads   // 1 s
        let dt = tau / 2000
        var capacitorVoltage = 0.0
        var time = 0.0

        while time < 3 * tau {
            let elements = [
                battery(volts, 1, 0),
                resistor(ohms, 1, 2),
                CircuitElement(nodeA: 2, nodeB: 0,
                               kind: .capacitor(farads: farads,
                                                previousVoltage: capacitorVoltage)),
            ]
            let solution = CircuitSolver.solve(elements: elements, nodeCount: 3, timeStep: dt)
            capacitorVoltage = solution.voltages[2]
            time += dt

            let exact = volts * (1 - exp(-time / tau))
            XCTAssertEqual(capacitorVoltage, exact, accuracy: max(volts * 0.01, 0.01),
                           "RC curve diverged at t = \(time)")
        }
        // After 3τ the capacitor is ~95% charged.
        XCTAssertEqual(capacitorVoltage, volts * (1 - exp(-3)), accuracy: 0.1)
    }

    /// Floating (unwired) elements don't break the solve, and carry no
    /// current.
    func testFloatingElementsAreQuiet() {
        let elements = [battery(9, 1, 0), resistor(100, 1, 0), resistor(220, 2, 3)]
        let solution = CircuitSolver.solve(elements: elements, nodeCount: 4)
        XCTAssertEqual(solution.currents[2], 0, accuracy: 1e-9)
        XCTAssertGreaterThan(solution.currents[1], 0.08)
    }

    /// The 4-band color code: 4.7 kΩ = yellow(4) violet(7) red(×100).
    func testResistorColorCode() {
        let bands = try! XCTUnwrap(CircuitSolver.colorBands(ohms: 4700))
        XCTAssertEqual(bands.digit1, 4)
        XCTAssertEqual(bands.digit2, 7)
        XCTAssertEqual(bands.multiplier, 2)

        let small = try! XCTUnwrap(CircuitSolver.colorBands(ohms: 56))
        XCTAssertEqual(small.digit1, 5)
        XCTAssertEqual(small.digit2, 6)
        XCTAssertEqual(small.multiplier, 0)
    }

    /// The band code has to READ BACK as the resistance it was given.
    ///
    /// The two tests above pick 4700 and 56 — both comfortably
    /// mid-decade, which is precisely why they passed over two real bugs
    /// for months. This one asserts the round trip instead of two chosen
    /// examples: whatever bands come out must multiply back to the value
    /// that went in, within the two significant figures the code carries.
    func testEveryBandCodeReadsBackAsItsResistance() throws {
        // Decade boundaries, sub-10 Ω values, and a sweep across the
        // app's own rail range. 996 is the case that was wrong: it used
        // to paint 900.
        var values: [Double] = [1, 4.7, 9.9, 9.99, 10, 47, 99.6, 100,
                                220, 470, 996, 1000, 4700, 47000, 9.96e9]
        values += stride(from: 10.0, through: 4700.0, by: 7.3).map { $0 }

        for ohms in values {
            let bands = try XCTUnwrap(CircuitSolver.colorBands(ohms: ohms),
                                      "\(ohms) Ω produced no code at all.")
            XCTAssertTrue((0...9).contains(bands.digit1),
                          "\(ohms) Ω: first digit \(bands.digit1) is not a band.")
            XCTAssertTrue((0...9).contains(bands.digit2),
                          "\(ohms) Ω: second digit \(bands.digit2) is not a band.")

            let read = Double(bands.digit1 * 10 + bands.digit2)
                * pow(10, Double(bands.multiplier))
            // Two significant figures: the code cannot carry more, so
            // half a unit in the last digit is the exact tolerance.
            let tolerance = 0.5 * pow(10, Double(bands.multiplier))
            XCTAssertEqual(read, ohms, accuracy: tolerance,
                           """
                           \(ohms) Ω is painted as \
                           \(bands.digit1)-\(bands.digit2)-×10^\(bands.multiplier), \
                           which reads back as \(read) Ω.
                           """)
        }
    }

    /// Below 10 Ω a real 4-band code uses the GOLD multiplier, ×0.1. The
    /// old clamp `max(exponent - 1, 0)` could not express it, so every
    /// resistance in this range was painted an order of magnitude high —
    /// 4.7 Ω as 47 Ω.
    func testASubTenOhmResistorGetsTheGoldMultiplier() throws {
        let bands = try XCTUnwrap(CircuitSolver.colorBands(ohms: 4.7))
        XCTAssertEqual(bands.digit1, 4)
        XCTAssertEqual(bands.digit2, 7)
        XCTAssertEqual(bands.multiplier, -1, "×0.1 is the gold band.")
    }

    /// Rounding to two digits can CARRY, and a carry is the next decade
    /// rather than a three-digit mantissa. 996 normalises to 99.6, which
    /// rounds to 100 — the old code clamped that to 9 and 0 and painted
    /// 900 Ω on a 996 Ω resistor. Reachable in the app by dragging the
    /// value bead, which runs 10…4700 Ω continuously.
    func testACarryAtTheDecadeBoundaryPromotesTheExponent() throws {
        let bands = try XCTUnwrap(CircuitSolver.colorBands(ohms: 996))
        XCTAssertEqual(bands.digit1, 1)
        XCTAssertEqual(bands.digit2, 0)
        XCTAssertEqual(bands.multiplier, 2, "996 rounds to 1.0 kΩ, not 900 Ω.")
    }

    /// RL charging: stepping V–R–L follows i(t) = (V/R)(1 − e^(−tR/L))
    /// to backward-Euler accuracy.
    func testInductorRLChargingCurve() {
        let volts = 6.0, r = 10.0, henries = 0.5
        let dt = 1e-4
        var iPrev = 0.0
        var time = 0.0
        for _ in 0..<2000 {
            let elements = [
                CircuitElement(nodeA: 1, nodeB: 0,
                               kind: .battery(volts: volts, internalResistance: 1e-3)),
                CircuitElement(nodeA: 1, nodeB: 2, kind: .resistor(ohms: r)),
                CircuitElement(nodeA: 2, nodeB: 0,
                               kind: .inductor(henries: henries, previousCurrent: iPrev)),
            ]
            let solution = CircuitSolver.solve(elements: elements, nodeCount: 3, timeStep: dt)
            iPrev = solution.currents[2]
            time += dt
        }
        let expected = volts / r * (1 - exp(-time * r / henries))
        XCTAssertEqual(iPrev, expected, accuracy: expected * 0.01,
                       "RL rise follows 1 − e^(−tR/L) within 1%")
    }

    /// Forward LED: I = (V − Vf)/R exactly; reversed: dark, no current.
    func testDiodeConductsForwardBlocksReverse() {
        let forward = [
            CircuitElement(nodeA: 1, nodeB: 0,
                           kind: .battery(volts: 5, internalResistance: 1e-3)),
            CircuitElement(nodeA: 1, nodeB: 2, kind: .resistor(ohms: 220)),
            CircuitElement(nodeA: 2, nodeB: 0,
                           kind: .diode(forwardDrop: 2.0, onResistance: 1.0, isConducting: false)),
        ]
        let lit = CircuitSolver.solveWithDiodes(elements: forward, nodeCount: 3)
        let expected = (5.0 - 2.0) / 221.0
        XCTAssertEqual(lit.solution.currents[2], expected, accuracy: expected * 0.02)

        let reversed = [
            CircuitElement(nodeA: 1, nodeB: 0,
                           kind: .battery(volts: 5, internalResistance: 1e-3)),
            CircuitElement(nodeA: 1, nodeB: 2, kind: .resistor(ohms: 220)),
            CircuitElement(nodeA: 0, nodeB: 2,
                           kind: .diode(forwardDrop: 2.0, onResistance: 1.0, isConducting: true)),
        ]
        let dark = CircuitSolver.solveWithDiodes(elements: reversed, nodeCount: 3)
        XCTAssertEqual(abs(dark.solution.currents[2]), 0, accuracy: 1e-6,
                       "reverse-biased diode carries nothing")
    }
}
