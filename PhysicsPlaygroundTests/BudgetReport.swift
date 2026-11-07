//
//  BudgetReport.swift
//  PhysicsPlaygroundTests
//
//  What a scene's triangles are spent on, for a budget test's failure
//  message to name and for its log line to record. Shared by every
//  `*BudgetTests` since 2026-11-06, when the Fields pass (2026-11-03) was
//  carried to the other labs and the home.
//

import XCTest
import RealityKit
@testable import PhysicsPlayground

@MainActor
enum BudgetReport {

    /// The entities over `over` triangles, heaviest first.
    static func heaviest(_ root: Entity, over: Int = 1_000, top: Int = 8) -> String {
        var rows: [(String, Int)] = []
        func walk(_ entity: Entity, under: String) {
            guard entity.isEnabled else { return }
            // Named by the nearest named ancestor too, since a mesh part
            // of a milled prop is just "Cylinder".
            let own = entity.name.isEmpty ? "?" : String(entity.name.prefix(18))
            let label = entity.name.isEmpty ? under + "/?" : (under.isEmpty ? own : under + "/" + own)
            if let model = entity.components[ModelComponent.self] {
                let triangles = CircuitBudgetTests.cost(of: model.mesh).triangles
                if triangles > over { rows.append((label, triangles)) }
            }
            let next = entity.name.isEmpty ? under : own
            entity.children.forEach { walk($0, under: next) }
        }
        walk(root, under: "")
        return rows.sorted { $0.1 > $1.1 }.prefix(top).map { "\($0.0) \($0.1)" }.joined(separator: ", ")
    }

    /// One line in the test log per measured scene, so a run records the
    /// numbers whether or not an assertion fires.
    @discardableResult
    static func log(_ label: String, _ root: Entity) -> CircuitBudgetTests.Cost {
        let cost = CircuitBudgetTests.cost(of: root)
        print("[budget] \(label): \(cost); unmeasured \(cost.unmeasured.count); heaviest: \(heaviest(root))")
        return cost
    }
}
