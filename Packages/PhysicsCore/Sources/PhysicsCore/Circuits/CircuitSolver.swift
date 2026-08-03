//
//  CircuitSolver.swift
//  PhysicsCore — Circuits
//
//  A nodal-analysis circuit solver. Every element is reduced to its
//  Norton companion — a conductance g between its nodes plus a current
//  injection J — which keeps the whole solver one symmetric linear
//  system G·v = I (no extended MNA rows needed):
//
//    · resistor R:            g = 1/R
//    · battery (V, r_int):    g = 1/r_int,  J = V/r_int   (Thévenin→Norton;
//      the internal resistance is physically honest AND keeps shorted
//      batteries finite)
//    · capacitor C (backward Euler over dt):
//                             g = C/dt,     J = (C/dt)·v_previous
//      — this is what makes RC charging follow the real 1−e^(−t/RC)
//      curve, verified by the tests
//    · closed switch:         g = 1/1 mΩ
//    · open switch:           nothing stamped
//
//  Ground is node 0. A tiny diagonal leak keeps floating (unwired)
//  nodes solvable. Gaussian elimination with partial pivoting — circuits
//  here are ≤ a few dozen nodes, so this is microseconds.
//
//  Sign conventions: element current is positive flowing from nodeA
//  through the element to nodeB; a battery's + terminal is nodeA.
//  Kirchhoff's laws are consequences of the formulation — the tests
//  check them anyway.
//

import Foundation

public struct CircuitElement: Sendable, Equatable {
    public enum Kind: Sendable, Equatable {
        /// + terminal at nodeA.
        case battery(volts: Double, internalResistance: Double)
        case resistor(ohms: Double)
        case capacitor(farads: Double, previousVoltage: Double)
        /// A closed switch (or any near-ideal link).
        case conductor
        /// An open switch: no connection at all.
        case open
        /// Backward-Euler inductor: i = i_prev + (dt/L)·v — RL rise
        /// follows the real 1 − e^(−tR/L) curve.
        case inductor(henries: Double, previousCurrent: Double)
        /// An ideal-ish diode: forward drop + small on-resistance when
        /// conducting (anode = nodeA), otherwise open. Conduction state
        /// is found by solveWithDiodes' fixed-point iteration.
        case diode(forwardDrop: Double, onResistance: Double, isConducting: Bool)
    }

    public var nodeA: Int
    public var nodeB: Int
    public var kind: Kind

    public init(nodeA: Int, nodeB: Int, kind: Kind) {
        self.nodeA = nodeA
        self.nodeB = nodeB
        self.kind = kind
    }
}

public enum CircuitSolver {
    public static let switchResistance = 1e-3
    static let leakConductance = 1e-9

    public struct Solution: Sendable {
        public var nodeVoltages: [Double]
        /// Current through each element, positive from nodeA to nodeB.
        public var currents: [Double]
        /// Voltage across each element, v(nodeA) − v(nodeB).
        public var voltages: [Double]
        /// Power dissipated (or, negative, delivered) by each element, W.
        public var powers: [Double]
    }

    /// Norton companion for one element: (conductance, injected current
    /// into nodeA).
    private static func companion(_ kind: CircuitElement.Kind, timeStep: Double) -> (Double, Double) {
        switch kind {
        case .battery(let volts, let internalResistance):
            let r = max(internalResistance, 1e-3)
            return (1 / r, volts / r)
        case .resistor(let ohms):
            return (1 / max(ohms, 1e-6), 0)
        case .capacitor(let farads, let previousVoltage):
            let g = farads / timeStep
            return (g, g * previousVoltage)
        case .conductor:
            return (1 / switchResistance, 0)
        case .open:
            return (0, 0)
        case .inductor(let henries, let previousCurrent):
            let g = timeStep / max(henries, 1e-9)
            // i_AB = g·v_AB + i_prev  →  Norton injection −i_prev into A.
            return (g, -previousCurrent)
        case .diode(let forwardDrop, let onResistance, let isConducting):
            guard isConducting else { return (0, 0) }
            let r = max(onResistance, 1e-3)
            // Same Thévenin→Norton shape as a battery opposing the flow.
            return (1 / r, forwardDrop / r)
        }
    }

    public static func solve(
        elements: [CircuitElement],
        nodeCount: Int,
        timeStep: Double = 1.0 / 90.0
    ) -> Solution {
        precondition(nodeCount >= 1)
        var conductance = [[Double]](
            repeating: [Double](repeating: 0, count: nodeCount), count: nodeCount)
        var injection = [Double](repeating: 0, count: nodeCount)

        for element in elements {
            let (g, current) = companion(element.kind, timeStep: timeStep)
            guard g > 0 else { continue }
            let a = element.nodeA, b = element.nodeB
            conductance[a][a] += g
            conductance[b][b] += g
            conductance[a][b] -= g
            conductance[b][a] -= g
            injection[a] += current
            injection[b] -= current
        }
        for index in 0..<nodeCount {
            conductance[index][index] += leakConductance
        }

        // Ground node 0 and solve the reduced (n−1) system.
        let unknowns = nodeCount - 1
        var voltages = [Double](repeating: 0, count: nodeCount)
        if unknowns > 0 {
            var matrix = (0..<unknowns).map { row in
                (0..<unknowns).map { column in conductance[row + 1][column + 1] }
            }
            var rhs = (0..<unknowns).map { injection[$0 + 1] }

            // Gaussian elimination with partial pivoting.
            for pivot in 0..<unknowns {
                var best = pivot
                for row in (pivot + 1)..<unknowns
                where abs(matrix[row][pivot]) > abs(matrix[best][pivot]) {
                    best = row
                }
                if best != pivot {
                    matrix.swapAt(pivot, best)
                    rhs.swapAt(pivot, best)
                }
                let diagonal = matrix[pivot][pivot]
                guard abs(diagonal) > 1e-15 else { continue }
                for row in (pivot + 1)..<unknowns where matrix[row][pivot] != 0 {
                    let factor = matrix[row][pivot] / diagonal
                    for column in pivot..<unknowns {
                        matrix[row][column] -= factor * matrix[pivot][column]
                    }
                    rhs[row] -= factor * rhs[pivot]
                }
            }
            for row in stride(from: unknowns - 1, through: 0, by: -1) {
                var sum = rhs[row]
                for column in (row + 1)..<unknowns {
                    sum -= matrix[row][column] * voltages[column + 1]
                }
                let diagonal = matrix[row][row]
                voltages[row + 1] = abs(diagonal) > 1e-15 ? sum / diagonal : 0
            }
        }

        // Element outputs from the node solution.
        var currents = [Double](repeating: 0, count: elements.count)
        var elementVoltages = [Double](repeating: 0, count: elements.count)
        var powers = [Double](repeating: 0, count: elements.count)
        for (index, element) in elements.enumerated() {
            let vAB = voltages[element.nodeA] - voltages[element.nodeB]
            elementVoltages[index] = vAB
            switch element.kind {
            case .battery(let volts, let internalResistance):
                let r = max(internalResistance, 1e-3)
                // Internal current A→B; negative means the battery is
                // driving current out of its + terminal, as it should.
                let current = (vAB - volts) / r
                currents[index] = current
                // Net power: internal dissipation minus delivered EMF power
                // (negative overall when supplying the circuit).
                powers[index] = current * current * r + current * volts
            case .resistor(let ohms):
                let current = vAB / max(ohms, 1e-6)
                currents[index] = current
                powers[index] = vAB * current
            case .capacitor(let farads, let previousVoltage):
                let g = farads / timeStep
                let current = g * (vAB - previousVoltage)
                currents[index] = current
                powers[index] = vAB * current
            case .conductor:
                let current = vAB / switchResistance
                currents[index] = current
                powers[index] = vAB * current
            case .open:
                break
            case .inductor(let henries, let previousCurrent):
                let g = timeStep / max(henries, 1e-9)
                let current = g * vAB + previousCurrent
                currents[index] = current
                powers[index] = vAB * current
            case .diode(let forwardDrop, let onResistance, let isConducting):
                guard isConducting else { break }
                let r = max(onResistance, 1e-3)
                let current = (vAB - forwardDrop) / r
                currents[index] = current
                powers[index] = vAB * current
            }
        }

        return Solution(nodeVoltages: voltages, currents: currents,
                        voltages: elementVoltages, powers: powers)
    }

    /// Solves a network containing diodes by fixed-point iteration on
    /// their conduction states: assume, solve, check each diode against
    /// its own solution (conducting must carry forward current; blocking
    /// must see less than the forward drop), repeat until stable. Two
    /// states per diode and monotone updates make this converge in a
    /// few passes for the networks this app builds.
    public static func solveWithDiodes(
        elements: [CircuitElement],
        nodeCount: Int,
        timeStep: Double = 1.0 / 90.0,
        maxIterations: Int = 8
    ) -> (solution: Solution, elements: [CircuitElement]) {
        var working = elements
        var solution = solve(elements: working, nodeCount: nodeCount, timeStep: timeStep)
        for _ in 0..<maxIterations {
            var changed = false
            for (index, element) in working.enumerated() {
                guard case .diode(let drop, let r, let conducting) = element.kind else { continue }
                let vAB = solution.voltages[index]
                let shouldConduct: Bool
                if conducting {
                    shouldConduct = solution.currents[index] > -1e-9
                } else {
                    shouldConduct = vAB > drop
                }
                if shouldConduct != conducting {
                    working[index].kind = .diode(
                        forwardDrop: drop, onResistance: r, isConducting: shouldConduct)
                    changed = true
                }
            }
            guard changed else { break }
            solution = solve(elements: working, nodeCount: nodeCount, timeStep: timeStep)
        }
        return (solution, working)
    }

    // MARK: Resistor color code (the EE garnish)

    /// The real 4-band code for a resistance, e.g. 4700 → [yellow,
    /// violet, red] + gold tolerance. Returns band indices 0–9 for the
    /// two digits and the multiplier exponent. nil for out-of-range.
    ///
    /// TWO ARITHMETIC BUGS LIVED HERE UNTIL 2026-08-03, and the second
    /// was reachable by dragging a bead.
    ///
    /// 1. **The decade boundary.** Rounding to two digits can carry:
    ///    996 Ω normalises to 99.6, which rounds to **100**, and the old
    ///    code then took `min(100 / 10, 9) = 9` and `100 % 10 = 0` —
    ///    painting **900 Ω on a 996 Ω resistor**. The clamp hid the carry
    ///    instead of handling it. The fix is to notice the carry and
    ///    promote the exponent, which is what a carry means.
    /// 2. **No gold band.** The multiplier was `max(exponent - 1, 0)`, so
    ///    it could never go negative — but a real 4-band code uses gold
    ///    (×0.1) for 1–9.9 Ω. Every resistance below 10 Ω was painted an
    ///    order of magnitude high: 4.7 Ω read as 47 Ω.
    ///
    /// The app's own resistor rail runs 10…4700 Ω continuously
    /// (`CircuitsModel.valueRange`), so (2) was unreachable in the
    /// shipping app and (1) was one bead-drag away. The tests covered
    /// 4700 and 56 — both safely mid-decade, which is why neither was
    /// caught.
    ///
    /// `multiplier` is a signed power of ten: −1 is the gold band.
    public static func colorBands(ohms: Double) -> (digit1: Int, digit2: Int, multiplier: Int)? {
        guard ohms >= 1, ohms < 1e11 else { return nil }
        var exponent = Int(floor(log10(ohms)))
        var twoDigits = Int((ohms / pow(10, Double(exponent - 1))).rounded())
        // The carry. 99.6 → 100 is not a three-digit mantissa, it is the
        // next decade: 100 × 10^(e-1) == 10 × 10^e.
        if twoDigits >= 100 {
            twoDigits /= 10
            exponent += 1
        }
        return (twoDigits / 10, twoDigits % 10, exponent - 1)
    }
}
