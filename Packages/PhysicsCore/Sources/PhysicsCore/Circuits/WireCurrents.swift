//
//  WireCurrents.swift
//  PhysicsCore — Circuits
//
//  The current in each wire of a circuit whose wires the solver collapsed
//  into nodes. To the nodal solve a wire is an ideal short: everything one
//  wire joins is one node, so the solve never says how a node's current
//  divides among the wires that make it up. This does, from Kirchhoff's
//  current law at every terminal — the current each component pushes into
//  the wiring at its terminals is the injection, and the wires carry it
//  between them.
//
//  On a tree of wires (every net Circuit Workshop lets you build — a wire
//  between two points already joined is refused) KCL alone fixes every
//  wire's current, whatever the wires are made of. A loop of wires is
//  indeterminate for ideal wires, so each wire is given a conductance — the
//  caller passes its copper's, 1/length — and the loop's current divides
//  the way real wires divide it. Solved per connected group as a small
//  nodal system, grounded at the group's first terminal; a mismatch in the
//  group's injections (the circuit solver's node leak) goes to ground.
//
//  SI units.
//

import Foundation

public enum WireCurrents {
    /// A wire between two terminal slots.
    public struct Edge: Sendable, Equatable {
        public var a: Int
        public var b: Int
        public init(a: Int, b: Int) {
            self.a = a
            self.b = b
        }
    }

    /// Each edge's current, A, positive from `a` to `b`. `injections[slot]`
    /// is the current pushed into the wiring at that slot (its component's
    /// current leaving through it); `conductances[edge]` is each wire's, S.
    public static func solve(slotCount: Int, edges: [Edge],
                             conductances: [Double], injections: [Double]) -> [Double] {
        var currents = [Double](repeating: 0, count: edges.count)
        guard !edges.isEmpty, slotCount > 0,
              conductances.count == edges.count, injections.count == slotCount else {
            return currents
        }
        var partition = NetPartition(slotCount: slotCount)
        for edge in edges { partition.union(edge.a, edge.b) }

        // The groups, each as its slots and its edges.
        var groupOfRoot: [Int: Int] = [:]
        var groupSlots: [[Int]] = []
        var groupEdges: [[Int]] = []
        for (index, edge) in edges.enumerated() {
            let root = partition.find(edge.a)
            let group: Int
            if let existing = groupOfRoot[root] {
                group = existing
            } else {
                group = groupSlots.count
                groupOfRoot[root] = group
                groupSlots.append([])
                groupEdges.append([])
            }
            groupEdges[group].append(index)
            for slot in [edge.a, edge.b] where !groupSlots[group].contains(slot) {
                groupSlots[group].append(slot)
            }
        }

        for group in groupSlots.indices {
            let slots = groupSlots[group]
            var local: [Int: Int] = [:]
            for (index, slot) in slots.enumerated() { local[slot] = index }
            // Ground the first slot: the reduced system is the rest.
            let unknowns = slots.count - 1
            var potentials = [Double](repeating: 0, count: slots.count)
            if unknowns > 0 {
                var matrix = [[Double]](repeating: [Double](repeating: 0, count: unknowns),
                                        count: unknowns)
                var rhs = (1..<slots.count).map { injections[slots[$0]] }
                for edgeIndex in groupEdges[group] {
                    let edge = edges[edgeIndex]
                    let g = conductances[edgeIndex]
                    guard let i = local[edge.a], let j = local[edge.b], i != j else { continue }
                    if i > 0 { matrix[i - 1][i - 1] += g }
                    if j > 0 { matrix[j - 1][j - 1] += g }
                    if i > 0, j > 0 {
                        matrix[i - 1][j - 1] -= g
                        matrix[j - 1][i - 1] -= g
                    }
                }
                let solved = eliminate(matrix: &matrix, rhs: &rhs)
                for index in 0..<unknowns { potentials[index + 1] = solved[index] }
            }
            for edgeIndex in groupEdges[group] {
                let edge = edges[edgeIndex]
                guard let i = local[edge.a], let j = local[edge.b] else { continue }
                currents[edgeIndex] = conductances[edgeIndex] * (potentials[i] - potentials[j])
            }
        }
        return currents
    }

    /// Gaussian elimination with partial pivoting; a singular column is left
    /// at zero, which a disconnected-in-name slot (no edges of weight) is.
    private static func eliminate(matrix: inout [[Double]], rhs: inout [Double]) -> [Double] {
        let n = rhs.count
        for pivot in 0..<n {
            var best = pivot
            for row in (pivot + 1)..<n where abs(matrix[row][pivot]) > abs(matrix[best][pivot]) {
                best = row
            }
            if best != pivot {
                matrix.swapAt(pivot, best)
                rhs.swapAt(pivot, best)
            }
            let diagonal = matrix[pivot][pivot]
            guard abs(diagonal) > 1e-15 else { continue }
            for row in (pivot + 1)..<n where matrix[row][pivot] != 0 {
                let factor = matrix[row][pivot] / diagonal
                for column in pivot..<n {
                    matrix[row][column] -= factor * matrix[pivot][column]
                }
                rhs[row] -= factor * rhs[pivot]
            }
        }
        var solution = [Double](repeating: 0, count: n)
        for row in stride(from: n - 1, through: 0, by: -1) {
            var sum = rhs[row]
            for column in (row + 1)..<n { sum -= matrix[row][column] * solution[column] }
            let diagonal = matrix[row][row]
            solution[row] = abs(diagonal) > 1e-15 ? sum / diagonal : 0
        }
        return solution
    }
}
