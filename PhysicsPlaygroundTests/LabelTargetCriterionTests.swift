//
//  LabelTargetCriterionTests.swift
//  PhysicsPlaygroundTests
//
//  A WORD YOU CAN AIM AT AND PINCH THROUGH.
//
//  Every control in this app wears a name plate, because an unlabelled
//  disc asks to be pinched on faith — the palette bead learned that and
//  the picker, the wells and the reel all followed. The plates are then
//  placed OUTSIDE the control, past its edge, so they do not straddle
//  the icon they name. And the collider stayed matched to the control.
//
//  So the most legible part of a control — the part naming what it does,
//  the part a person actually looks at — is a hole. You aim at the word,
//  the pinch goes through it, and something behind it answers instead.
//
//  `SpatialLayerBank` and `SpatialActionBank` each found this
//  independently and each wrote a comment about it ("THE LABEL IS A HOLE
//  WITHOUT THIS", "the word naming the verb was scenery you could pinch
//  through"). Two fixes, two comments, no rule — so the five primitives
//  written before and after them kept the defect.
//
//  THE CRITERION. For any control a hand can aim at, every piece of
//  VISIBLE GEOMETRY under it must lie inside its touch target. Centre-in
//  -bounds, not fully-contained: an icon may sit slightly proud of a
//  plate's face and still be perfectly aimable, but if the CENTRE of a
//  visible child falls outside the collider then aiming dead at that
//  child misses the control entirely.
//
//  This is deliberately not "labels must have colliders", which is the
//  listing version — it passes the moment somebody adds a collider of
//  the wrong size, and says nothing about the icons, rims and pointers
//  that are also visible and also aimed at.
//
//  THE ONE PLACE THIS RULE COLLIDES WITH AN OLDER ONE, found by pointing
//  the criterion at the wrong entity and reading what it said.
//
//  `SpatialTrackControl` — the rail — carries its value readout 40 mm
//  above the track and its subtitle 36 mm below, against a target
//  50 mm tall. Both are outside it. But the rail is 1 cm thick and up to
//  34 cm long, and its own header states the rule that governs here:
//
//      // Generous ALONG the rail is the affordance; generous across it
//      // is a trap. […] an input-targetable collider must be no larger
//      // than the thing it represents.
//
//  Covering those two labels means a target 126 mm tall on a rail 10 mm
//  thick, which shields the apparatus the rail is bolted to from every
//  pinch — the `SpatialScaleHandle` failure that made whole modules
//  silently non-interactive (DECISIONS, 2026-07-29).
//
//  So the rail is NOT tested here, and the reason is a judgement, not an
//  oversight: those two are READOUTS — a number and a derived line — not
//  the name of a control you would otherwise have nothing to aim at. The
//  plates' labels are the only thing identifying them; the rail is a
//  30 cm object you aim at directly. If that judgement is wrong the fix
//  is to move the labels inside the target, not to widen it.
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

    /// The reel is the ONLY thing a pause puts on screen, which makes the
    /// nameplate saying what it is the most load-bearing label in the
    /// app — and it hung 72 mm below a 52 mm sphere.
    func testTimeCapsuleReelLabelIsAimable() throws {
        let appModel = AppModel()
        let module = try XCTUnwrap(ModuleCatalog.all(appModel: appModel)
            .first { $0.id == KinematicsModule.id })
        let rail = TimeRail(module: module)
        // BY NAME. Picking "the first child with an input target" found
        // the SCRUB TRACK instead, which is a different control entirely
        // — and the wrong-entity version of this test still failed, for
        // reasons that turned out to be real. See the note below.
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

    /// A LABEL THAT IS A SIBLING, NOT A CHILD — the one shape the walk
    /// above cannot see, and therefore the one worth pinning by hand.
    ///
    /// The palette bead's "Labs" plate is added to the palette root so it
    /// does not inherit the bead's spin, which means no parent walk can
    /// attribute it to the bead. That is exactly why it survived while
    /// the picker's and the petals' labels were being found — and it is
    /// the label on the single object present in every lab at all times.
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
            .init(id: "gravitylab", title: "Gravity Lab", accent: .white),
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
