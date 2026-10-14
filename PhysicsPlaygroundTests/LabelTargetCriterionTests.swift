//
//  LabelTargetCriterionTests.swift
//  PhysicsPlaygroundTests
//
//  The most legible part of a control — the word naming it — must not
//  be a hole you pinch through. For any control a hand can aim at,
//  every piece of visible geometry under it must have its centre inside
//  the touch target. The rail is deliberately not tested: its value and
//  subtitle are readouts, not the name of the control, and covering
//  them would mean a target that shields the apparatus behind it.
//

import XCTest
import RealityKit
import RenderKit
@testable import PhysicsPlayground

@MainActor
final class LabelTargetCriterionTests: XCTestCase {

    private struct Hole {
        let control: String
        let child: String
        let centre: SIMD3<Float>
        let target: BoundingBox
    }

    /// The union of a control's collider shapes, in the control's frame.
    private func targetBounds(of entity: Entity) -> BoundingBox? {
        guard let collision = entity.components[CollisionComponent.self],
              !collision.shapes.isEmpty else { return nil }
        return collision.shapes.dropFirst().reduce(collision.shapes[0].bounds) {
            $0.union($1.bounds)
        }
    }

    /// Every visible child of an aimable control whose centre lands
    /// outside that control's target.
    private func holes(under root: Entity, label: String) -> [Hole] {
        var found: [Hole] = []

        func walk(_ entity: Entity, path: String) {
            if entity.components[InputTargetComponent.self] != nil,
               let target = targetBounds(of: entity) {
                for child in entity.children {
                    // Only geometry that is actually drawn. An empty
                    // pivot is not something anyone aims at.
                    let bounds = child.visualBounds(relativeTo: entity)
                    let extents = bounds.extents
                    guard extents.x > 1e-5 || extents.y > 1e-5 || extents.z > 1e-5
                    else { continue }
                    let centre = bounds.center
                    let inside =
                        centre.x >= target.min.x && centre.x <= target.max.x &&
                        centre.y >= target.min.y && centre.y <= target.max.y &&
                        centre.z >= target.min.z && centre.z <= target.max.z
                    if !inside {
                        found.append(Hole(
                            control: path,
                            child: child.name.isEmpty ? "·" : child.name,
                            centre: centre, target: target))
                    }
                }
            }
            for child in entity.children {
                walk(child, path: "\(path)/\(child.name.isEmpty ? "·" : child.name)")
            }
        }

        walk(root, path: label)
        return found
    }

    private func assertNoHoles(_ root: Entity, _ label: String,
                               file: StaticString = #filePath, line: UInt = #line) {
        let found = holes(under: root, label: label)
        guard !found.isEmpty else { return }
        let report = found.map {
            let c = $0.centre, t = $0.target
            return String(
                format: """
                  %@ → child "%@" centred (%.3f, %.3f, %.3f), \
                target x[%.3f…%.3f] y[%.3f…%.3f] z[%.3f…%.3f]
                """,
                $0.control, $0.child, c.x, c.y, c.z,
                t.min.x, t.max.x, t.min.y, t.max.y, t.min.z, t.max.z)
        }.joined(separator: "\n")
        XCTFail("""
            \(found.count) visible part(s) of \(label) sit outside their own \
            control's touch target, so aiming at them pinches whatever is \
            behind instead. Widen the collider to cover the part, the way \
            `SpatialLayerBank` and `SpatialActionBank` already do for their \
            labels:
            \(report)
            """, file: file, line: line)
    }

    /// The criterion must be able to fail.
    func testTheCriterionCatchesALabelOutsideItsTarget() {
        let plate = ModelEntity(mesh: .generateBox(size: [0.05, 0.03, 0.01]),
                                materials: [UnlitMaterial(color: .white)])
        plate.name = "plate"
        plate.components.set(InputTargetComponent())
        plate.components.set(CollisionComponent(
            shapes: [.generateBox(size: [0.05, 0.03, 0.01])]))
        let label = ModelEntity(mesh: .generateBox(size: [0.04, 0.01, 0.001]),
                                materials: [UnlitMaterial(color: .white)])
        label.name = "label"
        label.position = [0, -0.06, 0]           // well below the plate
        plate.addChild(label)

        XCTAssertEqual(holes(under: plate, label: "fixture").count, 1)
    }

    /// …and must accept one that is covered.
    func testTheCriterionAcceptsACoveredLabel() {
        let plate = ModelEntity(mesh: .generateBox(size: [0.05, 0.03, 0.01]),
                                materials: [UnlitMaterial(color: .white)])
        plate.components.set(InputTargetComponent())
        plate.components.set(CollisionComponent(shapes: [
            .generateBox(size: [0.05, 0.03, 0.01]),
            .generateBox(size: [0.05, 0.02, 0.01])
                .offsetBy(translation: [0, -0.06, 0]),
        ]))
        let label = ModelEntity(mesh: .generateBox(size: [0.04, 0.01, 0.001]),
                                materials: [UnlitMaterial(color: .white)])
        label.position = [0, -0.06, 0]
        plate.addChild(label)

        XCTAssertTrue(holes(under: plate, label: "fixture").isEmpty)
    }

    // MARK: The primitives

    func testLayerBankLabelsAreAimable() {
        let bank = SpatialLayerBank(accent: .white, layers: [
            LayerSwitch(id: "lines", label: "Parallel plates", isOn: { true },
                        toggle: {}),
        ])
        for _ in 0..<40 { bank.update(anchor: .zero, viewer: [0, 0, 1], dt: 1 / 90) }
        assertNoHoles(bank.root, "SpatialLayerBank")
    }

    func testActionBankLabelsAreAimable() {
        let bank = SpatialActionBank(accent: .white, actions: [
            .init(id: "clear", label: "Clear the bench", symbol: "trash", fire: {}),
        ])
        for _ in 0..<40 {
            bank.update(anchor: .zero, viewer: [0, 0, 1], dt: 1 / 90, resetNonce: 0)
        }
        assertNoHoles(bank.root, "SpatialActionBank")
    }

    func testSummonHandleLabelsAreAimable() {
        let handle = SummonHandle(title: "Analysis", symbol: "chart.xyaxis.line",
                                  accent: .white)
        handle.summary = { "off" }
        for _ in 0..<40 { handle.update(anchor: .zero, viewer: [0, 0, 1], dt: 1 / 90) }
        assertNoHoles(handle.root, "SummonHandle")
    }

    func testPickerLabelsAreAimable() {
        let picker = SpatialPicker(
            accessibilityNoun: "World",
            choices: [.init(id: "a", label: "Earth", symbol: "globe")])
        picker.open()
        for _ in 0..<60 { picker.update(anchor: .zero, viewer: [0, 0, 1], dt: 1 / 90) }
        assertNoHoles(picker.root, "SpatialPicker")
    }

    /// The reel is the only thing a pause puts on screen, which makes its
    /// nameplate the most load-bearing label in the app.
    func testTimeCapsuleReelLabelIsAimable() throws {
        let appModel = AppModel()
        let module = try XCTUnwrap(ModuleCatalog.all(appModel: appModel)
            .first { $0.id == KinematicsModule.id })
        let rail = TimeRail(module: module)
        // By name: "the first child with an input target" found the scrub
        // track instead.
        let reel = try XCTUnwrap(rail.root.children.first {
            $0.name == "time-reel"
        })
        assertNoHoles(reel, "TimeRail reel")
    }

    func testWellLabelsAreAimable() {
        let well = Well([
            .init(name: "magnet", tint: .white, label: "Add magnet",
                  preview: { ModelEntity(mesh: .generateSphere(radius: 0.02)) },
                  position: .zero, spawn: { _ in UUID() }),
        ])
        for _ in 0..<10 { well.update(dt: 1 / 90) }
        assertNoHoles(well.root, "Well")
    }

    /// The shelf's crown is a target of its own, and its title floats
    /// above the column outside any target.
    func testAShelvedWellsCrownIsAimable() {
        let well = Well((0..<8).map { index in
            .init(name: "part\(index)", tint: .white, label: "Part \(index)",
                  preview: { ModelEntity(mesh: .generateSphere(radius: 0.02)) },
                  position: CircuitsPartsLayout.rightSlot(index: index),
                  spawn: { _ in UUID() })
        })
        well.facing = CircuitsPartsLayout.viewer
        well.windowTitle = "Parts"
        well.visibleCount = 6
        for _ in 0..<10 { well.update(dt: 1 / 90) }
        assertNoHoles(well.root, "Well shelf")
    }

    /// A label that is a sibling, not a child — the one shape the walk
    /// above cannot see: the palette bead's "Labs" plate is added to the
    /// palette root so it does not inherit the bead's spin.
    func testThePaletteBeadsSiblingLabelIsInsideItsTarget() throws {
        let palette = Palette(slots: [])
        palette.place(at: .zero)
        let bead = try XCTUnwrap(palette.root.children.first {
            $0.name == "palette-bead"
        })
        let label = try XCTUnwrap(palette.root.children.first {
            $0 !== bead && $0.visualBounds(relativeTo: palette.root).extents.x > 1e-4
        })
        let centre = label.visualBounds(relativeTo: bead).center
        let target = try XCTUnwrap(targetBounds(of: bead))
        let inside =
            centre.x >= target.min.x && centre.x <= target.max.x &&
            centre.y >= target.min.y && centre.y <= target.max.y &&
            centre.z >= target.min.z && centre.z <= target.max.z
        XCTAssertTrue(inside, """
            the palette bead's label is centred at \(centre) but its target \
            spans \(target.min)…\(target.max), so the words on the one control \
            present in every lab cannot be pinched.
            """)
    }

    func testPaletteLabelsAreAimable() {
        let palette = Palette(slots: [
            .init(id: "gravitylab", title: "Orbits", accent: .white),
        ])
        palette.place(at: .zero)
        // Opened through the bead, since `isOpen` is private — which is
        // also the path a hand takes.
        _ = palette.handleTap(palette.root.children.first { $0.name == "palette-bead" }
                              ?? Entity())
        for _ in 0..<80 { palette.update(dt: 1 / 90, viewer: [0, 0, 1]) }
        assertNoHoles(palette.root, "Palette")
    }
}
