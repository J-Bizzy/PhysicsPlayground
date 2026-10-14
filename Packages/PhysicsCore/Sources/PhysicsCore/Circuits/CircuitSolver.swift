//
//  CircuitSolver.swift
//  Nodal analysis via Norton companions — one symmetric G·v = I system, Gaussian elimination with partial pivoting; backward-Euler C and L give the real 1−e^(−t/RC) / 1−e^(−tR/L) curves; ground is node 0, a tiny diagonal leak keeps floating nodes solvable.
//  Signs: element current positive nodeA→nodeB; a battery's + terminal is nodeA.
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
        /// Ideal-ish diode: drop + on-resistance when conducting (anode = nodeA), else open;
        /// state found by solveWithDiodes' fixed-point iteration.
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
    /// Tiny per-node conductance to ground so unwired islands stay solvable. Public because it is a
    /// noise floor: every open element leaks voltage × this, so any "is current flowing" threshold must derive from it.
    public static let leakConductance = 1e-9

    /// Smallest current that counts as "live" given the driving voltage — 10× the leak floor.
    /// Must stay independent of any stamped meter: the guard runs the moment a probe lands, before any solve.
    public static func liveCurrentThreshold(volts: Double) -> Double {
        max(abs(volts) * leakConductance * 10, 1e-9)
    }


    public struct Solution: Sendable {
        public var nodeVoltages: [Double]
        /// Current through each element, positive from nodeA to nodeB.
        public var currents: [Double]
        /// Voltage across each element, v(nodeA) − v(nodeB).
        public var voltages: [Double]
        /// Power dissipated (or, negative, delivered) by each element, W.
        public var powers: [Double]
    }

    /// Norton companion for one element: (conductance, injected current into nodeA).
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

        var currents = [Double](repeating: 0, count: elements.count)
        var elementVoltages = [Double](repeating: 0, count: elements.count)
        var powers = [Double](repeating: 0, count: elements.count)
        for (index, element) in elements.enumerated() {
            let vAB = voltages[element.nodeA] - voltages[element.nodeB]
            elementVoltages[index] = vAB
            switch element.kind {
            case .battery(let volts, let internalResistance):
                let r = max(internalResistance, 1e-3)
                // Internal current A→B; negative = driving out of the + terminal.
                let current = (vAB - volts) / r
                currents[index] = current
                // Net power: internal dissipation + EMF term (negative when supplying).
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

    /// Diode networks by fixed-point iteration on conduction states (conducting must carry forward
    /// current; blocking must see less than the drop) — converges in a few passes for these networks.
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

    /// Real 4-band resistor code: two digit indices 0–9 plus a signed multiplier exponent
    /// (−1 = gold, ×0.1, needed for 1–9.9 Ω). nil out of range.
    public static func colorBands(ohms: Double) -> (digit1: Int, digit2: Int, multiplier: Int)? {
        guard ohms >= 1, ohms < 1e11 else { return nil }
        var exponent = Int(floor(log10(ohms)))
        var twoDigits = Int((ohms / pow(10, Double(exponent - 1))).rounded())
        // Rounding carry: 99.6 → 100 is the next decade — promote the exponent or 996 Ω paints as 900 Ω.
        if twoDigits >= 100 {
            twoDigits /= 10
            exponent += 1
        }
        return (twoDigits / 10, twoDigits % 10, exponent - 1)
    }
}
