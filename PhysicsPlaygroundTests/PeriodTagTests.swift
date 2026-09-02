//
//  PeriodTagTests.swift
//  PhysicsPlaygroundTests
//
//  Pendulums' period tag — "T = 1.42 s" over a pivot — moved onto
//  `BackedLabel` on 2026-08-09, the last of the modules' live numerals
//  to stop being naked unlit text. This pins what that move was FOR,
//  because none of it is reachable from a screenshot.
//
//  It cannot be reached from one for a reason worth recording. The tag
//  is hidden when pivots crowd — within 15 cm, only the SELECTED
//  pendulum keeps its label, so a Newton's cradle shows at most one —
//  and `-penRing 1`, the argument that looks like it would select a
//  pendulum, sets `RingState.openID` and not `model.selectedID`. So the
//  default scene photographs with every period tag suppressed, and a
//  screenshot of it says nothing either way about the type behind it.
//  That is exactly the case this project keeps saying tests are for.
//
//  The two claims are the backing and the baseline:
//
//  1. A PLATE EXISTS BEHIND THE GLYPHS. The whole point of
//     `BackedLabel` is that bright type over passthrough has no floor
//     under its contrast, and the tag hung 30 cm from a switch bank
//     whose every plate already wore one.
//
//  2. THE RUN IS CENTRED ON BOTH AXES. The hand-rolled version did
//     `position = [-(minX+maxX)/2, 0, 0]` — X only — so the glyphs sat
//     with their baseline on the anchor and their mass floating above
//     it. The hub fixed the identical bug in its own text and
//     `BackedLabel` was built centred; the tag was the last caller
//     still doing it by hand.
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

    /// A chaotic rig has no period, so it wears no tag — in the room, on
    /// its card, or in the notebook. `Pendulum.period(gravity:)` is
    /// 2π√(L/g) of the upper rod alone, which the double stamped over a
    /// system whose whole point is that it never repeats (2026-09-01).
    /// The double is the ONLY pendulum here and is selected by
    /// `addDoublePendulum`, so neither the crowding rule nor the
    /// selection rule can be the reason the tag is absent — the
    /// symmetric case above shows a lone simple pendulum gets one.
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
                       "the notebook must not write a period for a chaotic rig")
    }

    func testThePeriodTagIsCentredOnBothAxes() {
        // Straight at the type, rather than through the renderer: the
        // claim is about BackedLabel's centring, and the tag's only job
        // is to use it.
        let label = BackedLabel(size: 0.024)
        label.setText("T = 1.42 s", color: .white)

        let glyphs = modelEntities(under: label.root)
            .filter { ($0.model?.mesh.bounds.extents.z ?? 0) > 0.0005 }
        let run = try? XCTUnwrap(glyphs.first)
        guard let run else { return XCTFail("no glyph run was built") }

        let bounds = run.model!.mesh.bounds
        let centreY = run.position.y + (bounds.min.y + bounds.max.y) / 2
        let centreX = run.position.x + (bounds.min.x + bounds.max.x) / 2
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
