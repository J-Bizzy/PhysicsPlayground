//
//  PeriodTagTests.swift
//  PhysicsPlaygroundTests
//
//  Pendulums' period tag — "T = 1.42 s" over a pivot — on `BackedLabel`:
//  a plate exists behind the glyphs, and the run is centred on both
//  axes. Not reachable from a screenshot: the tag hides when pivots
//  crowd, and `-penRing 1` opens a ring without selecting the pendulum.
//

import XCTest
import RealityKit
import RenderKit
@testable import PhysicsPlayground

@MainActor
final class PeriodTagTests: XCTestCase {

    /// A lone pendulum, so the crowding rule cannot suppress the tag.
    private func loneModel() -> PendulumsModel {
        let model = PendulumsModel()
        model.reset()
        while model.pendulums.count > 1 {
            model.removePendulum(id: model.pendulums[model.pendulums.count - 1].id)
        }
        return model
    }

    func testThePeriodTagWearsTheHousePlate() throws {
        let model = loneModel()
        try XCTSkipIf(model.pendulums.count != 1,
                      "fixture needs exactly one pendulum to dodge the crowding rule")
        let renderer = PendulumsRenderer()
        renderer.tick(dt: 1.0 / 90.0, model: model)

        let plates = modelEntities(under: renderer.root).filter { entity in
            // The backing is the only unlit near-black plane in the tag.
            guard let mesh = entity.model?.mesh else { return false }
            let extents = mesh.bounds.extents
            return extents.z < 0.001 && extents.x > 0 && extents.y > 0
        }
        XCTAssertFalse(plates.isEmpty, """
            the period tag has no backing plate behind it.

            A live numeral over passthrough with no plate is the defect \
            BackedLabel exists to fix — see its header. If the tag was \
            deliberately un-plated, this test is the place to say so.
            """)
    }

    /// A chaotic rig has no period, so the double wears no tag — in the
    /// room, on its card, or in the Physics box. It is the only pendulum here
    /// and selected, so neither crowding nor selection can explain an
    /// absent tag.
    func testTheDoublePendulumWearsNoPeriodTag() throws {
        let appModel = AppModel()
        let model = appModel.pendulumsModel
        model.reset()
        while let last = model.pendulums.last {
            model.removePendulum(id: last.id)
        }
        let id = try XCTUnwrap(model.addDoublePendulum())
        XCTAssertEqual(model.selectedID, id)
        XCTAssertEqual(model.pendulums.count, 1)

        let renderer = PendulumsRenderer()
        renderer.tick(dt: 1.0 / 90.0, model: model)

        // The same thin-plate filter as the plated-tag test: a lone
        // simple pendulum produces exactly this, a lone double must not.
        let plates = modelEntities(under: renderer.root).filter { entity in
            guard let mesh = entity.model?.mesh else { return false }
            let extents = mesh.bounds.extents
            return extents.z < 0.001 && extents.x > 0 && extents.y > 0
        }
        XCTAssertTrue(plates.isEmpty, """
            a double pendulum is wearing a period tag. 2π√(L/g) is the \
            upper rod's small-angle period; a chaotic system has none.
            """)

        let readings = PendulumsModule.readings(appModel: appModel)
        XCTAssertTrue(readings.contains { $0.name == "Length" },
                      "the double is selected, so its length is written")
        XCTAssertFalse(readings.contains { $0.name.hasPrefix("Period") },
                       "the Physics box must not show a period for a chaotic rig")
    }

    func testThePeriodTagIsCentredOnBothAxes() {
        // Straight at the type, rather than through the renderer: the
        // claim is about BackedLabel's centring, and the tag's only job
        // is to use it.
        let label = BackedLabel(size: 0.024)
        label.setText("T = 1.42 s", color: .white)

        // The glyphs: everything with depth (the plate is flat).
        let glyphs = modelEntities(under: label.root)
            .filter { ($0.model?.mesh.bounds.extents.z ?? 0) > 0.0005 }
        guard !glyphs.isEmpty else { return XCTFail("no glyph run was built") }

        var lower = SIMD3<Float>(repeating: .greatestFiniteMagnitude)
        var upper = SIMD3<Float>(repeating: -.greatestFiniteMagnitude)
        for glyph in glyphs where glyph.isEnabled {
            let box = glyph.visualBounds(relativeTo: label.root)
            lower = simd_min(lower, box.min)
            upper = simd_max(upper, box.max)
        }
        let centreY = (lower.y + upper.y) / 2
        let centreX = (lower.x + upper.x) / 2
        XCTAssertEqual(centreX, 0, accuracy: 1e-6,
                       "the run is not centred horizontally on its anchor")
        XCTAssertEqual(centreY, 0, accuracy: 1e-6, """
            the run is not centred VERTICALLY on its anchor — the \
            baseline-on-the-anchor bug the hub fixed in its wordmark and \
            the period tag carried until 2026-08-09.
            """)
    }

    private func modelEntities(under entity: Entity) -> [ModelEntity] {
        var found: [ModelEntity] = []
        if let model = entity as? ModelEntity, model.model != nil {
            found.append(model)
        }
        for child in entity.children {
            found += modelEntities(under: child)
        }
        return found
    }
}
