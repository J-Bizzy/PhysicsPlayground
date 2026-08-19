//  CircuitSolverTests.swift
//  Solver pinned to the textbook results: Ohm, series/parallel, KCL, energy, switches, RC/RL transients, diodes, color bands.

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
        XCTAssertEqual(solution.currents[1],
                       solution.nodeVoltages[1] / 100, accuracy: 1e-9)
    }

    /// At every non-ground node, element currents sum to zero.
    func testKirchhoffCurrentLaw() {
        let elements = [
            battery(9, 1, 0), resistor(220, 1, 2),
            resistor(470, 2, 0), resistor(330, 2, 0),
        ]
        let solution = CircuitSolver.solve(elements: elements, nodeCount: 3)
        // Tolerance is the solver's documented 1 nS stabilizing leak.
        let net = solution.currents[1] - solution.currents[2] - solution.currents[3]
        XCTAssertEqual(net, 0, accuracy: 1e-7)
    }

    /// Delivered power equals total dissipation, internal resistance included.
    func testPowerBalances() {
        let elements = [battery(9, 1, 0), resistor(150, 1, 2), resistor(50, 2, 0)]
        let solution = CircuitSolver.solve(elements: elements, nodeCount: 3)
        let total = solution.powers.reduce(0, +)
        // Off only by the 1 nS stabilizing leak.
        XCTAssertEqual(total, 0, accuracy: 1e-6,
                       "power delivered must equal power dissipated")
        XCTAssertLessThan(solution.powers[0], 0, "the battery is the source")
    }

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

    /// Stepped RC charging traces V·(1 − e^(−t/RC)); backward Euler at
    /// dt = τ/2000 stays within 1% through the whole curve.
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
        XCTAssertEqual(capacitorVoltage, volts * (1 - exp(-3)), accuracy: 0.1)
    }

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

    /// Round-trip property: whatever bands come out must multiply back to the input within
    /// the code's two significant figures. Mid-decade examples passed over two real bugs.
    func testEveryBandCodeReadsBackAsItsResistance() throws {
        // Decade boundaries, sub-10 Ω, and the app's rail range; 996 used to paint 900.
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
            // Two significant figures: half a unit in the last digit is the exact tolerance.
            let tolerance = 0.5 * pow(10, Double(bands.multiplier))
            XCTAssertEqual(read, ohms, accuracy: tolerance,
                           """
                           \(ohms) Ω is painted as \
                           \(bands.digit1)-\(bands.digit2)-×10^\(bands.multiplier), \
                           which reads back as \(read) Ω.
                           """)
        }
    }

    /// Below 10 Ω needs the gold ×0.1 multiplier; the old clamp painted 4.7 Ω as 47 Ω.
    func testASubTenOhmResistorGetsTheGoldMultiplier() throws {
        let bands = try XCTUnwrap(CircuitSolver.colorBands(ohms: 4.7))
        XCTAssertEqual(bands.digit1, 4)
        XCTAssertEqual(bands.digit2, 7)
        XCTAssertEqual(bands.multiplier, -1, "×0.1 is the gold band.")
    }

    /// A two-digit rounding carry must promote the exponent: 996 rounds to 1.0 kΩ,
    /// not a clamped 900 Ω. Reachable via the value bead (10…4700 Ω continuous).
    func testACarryAtTheDecadeBoundaryPromotesTheExponent() throws {
        let bands = try XCTUnwrap(CircuitSolver.colorBands(ohms: 996))
        XCTAssertEqual(bands.digit1, 1)
        XCTAssertEqual(bands.digit2, 0)
        XCTAssertEqual(bands.multiplier, 2, "996 rounds to 1.0 kΩ, not 900 Ω.")
    }

    /// Stepped V–R–L follows i(t) = (V/R)(1 − e^(−tR/L)) to backward-Euler accuracy.
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
