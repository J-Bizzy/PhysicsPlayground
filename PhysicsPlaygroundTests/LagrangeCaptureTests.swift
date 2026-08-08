//
//  LagrangeCaptureTests.swift
//  PhysicsPlaygroundTests
//
//  FIVE PARAGRAPHS, ZERO READERS, BESIDE A SILENT OVERWRITE.
//
//  `GravityLabModel.lagrangeExplanations` holds one paragraph per point
//  on why L1–L3 shed their occupants and L4/L5 hold. Nothing read them.
//  Next to them sat `capturedPointName`, written in four places and read
//  in none.
//
//  The silence was not cosmetic, which is what makes this worth a test
//  rather than a tidy-up. `release()` snaps a body dropped near a
//  Lagrange point onto the point and OVERWRITES the velocity the user
//  just threw with `Lagrange.corotatingVelocity`. That is correct — a
//  body parked at L4 must move with the rotating frame or it is not
//  parked — and, unexplained, it looks exactly like the throw was
//  thrown away. The app had the sentence that answers that and no
//  surface to say it on.
//
//  WHAT THESE TESTS PIN. Not the wording — that is the author's. They
//  pin the two things that would silently rot: that a capture still
//  RECORDS which point and which body (so a callout can find them), and
//  that every point the model can capture at has a paragraph. A sixth
//  point added without prose, or a renamed key, would otherwise show an
//  empty callout on a body whose velocity had just been rewritten.
//

import XCTest
import PhysicsCore
import simd
@testable import PhysicsPlayground

@MainActor
final class LagrangeCaptureTests: XCTestCase {

    /// Every point the model can park a body at can explain itself.
    ///
    /// A CRITERION OVER THE POINTS, not a list of five: `Lagrange.Points`
    /// decides what exists, so adding L6 tomorrow fails here rather than
    /// showing a blank paragraph in the room.
    func testEveryLagrangePointHasSomethingToSay() {
        let (earth, moon) = Lagrange.earthMoonSystem()
        let points = Lagrange.points(primary: earth, secondary: moon)
        XCTAssertFalse(points.all.isEmpty)
        for point in points.all {
            let text = GravityLabModel.lagrangeExplanations[point.name]
            XCTAssertNotNil(text, """
                \(point.name) can be captured and has no paragraph — a body \
                parked there would have its thrown velocity overwritten with \
                nothing said about why.
                """)
            XCTAssertGreaterThan(text?.count ?? 0, 40,
                                 "\(point.name)'s paragraph is a stub")
        }
    }

    /// The five say five different things. Copy-pasted prose would be
    /// worse than none: it would teach that the points are alike, when
    /// the whole lesson is that three are saddles and two are stable.
    func testThePointsDoNotShareAParagraph() {
        var seen: Set<String> = []
        for (name, text) in GravityLabModel.lagrangeExplanations {
            XCTAssertTrue(seen.insert(text).inserted,
                          "\(name) repeats another point's paragraph")
        }
    }

    /// …and the two STABLE points say so, while the saddles admit they
    /// are not. This is the one content claim worth asserting, because
    /// getting it backwards would teach the opposite of the physics that
    /// `LagrangeTests` pins in PhysicsCore.
    func testTheParagraphsAgreeWithTheStability() throws {
        let saddles = ["L1", "L2", "L3"]
        for name in saddles {
            let text = try XCTUnwrap(GravityLabModel.lagrangeExplanations[name])
                .lowercased()
            XCTAssertTrue(text.contains("unstable") || text.contains("saddle")
                            || text.contains("slide off"),
                          "\(name) is a saddle point and its paragraph does "
                          + "not say so")
        }
        for name in ["L4", "L5"] {
            let text = try XCTUnwrap(GravityLabModel.lagrangeExplanations[name])
                .lowercased()
            XCTAssertTrue(text.contains("stable") || text.contains("trojan"),
                          "\(name) is stable and its paragraph does not say so")
        }
    }

    // MARK: The capture records enough to be explained

    /// A CAPTURE MUST NAME THE POINT AND THE BODY, because the callout
    /// rides the body — L1's occupant slides off over the following days
    /// with the sentence predicting it travelling alongside.
    func testACaptureRecordsThePointAndTheBody() throws {
        let model = GravityLabModel()
        model.showLagrangePoints = true

        // A body to host the points, and one to park.
        let host = try XCTUnwrap(model.bodies.dropFirst().first)
        model.select(id: host.id)
        let points = model.lagrangePoints
        try XCTSkipIf(points.isEmpty, "no Lagrange pair in the opening system")
        let target = try XCTUnwrap(points.first { $0.name == "L4" } ?? points.first)

        let mover = try XCTUnwrap(model.bodies.first { $0.id != host.id
                                    && $0.id != model.primaryBody?.id })
        let display = target.position * model.simToDisplay
        model.grab(id: mover.id, at: display, timestamp: 0)
        model.hold(id: mover.id, at: display, timestamp: 0.1)
        model.release(id: mover.id, timestamp: 0.2)

        XCTAssertEqual(model.capturedPointName, target.name)
        XCTAssertEqual(model.capturedBodyID, mover.id, """
            the capture named the point but not the body, so nothing can \
            anchor the explanation to the thing that was captured.
            """)
        XCTAssertNotNil(
            GravityLabModel.lagrangeExplanations[model.capturedPointName ?? ""])
    }

    /// Grabbing the body again clears it — the paragraph belongs to a
    /// capture, not to the session.
    func testPickingTheBodyUpAgainClearsTheCapture() throws {
        let model = GravityLabModel()
        model.showLagrangePoints = true
        let host = try XCTUnwrap(model.bodies.dropFirst().first)
        model.select(id: host.id)
        let points = model.lagrangePoints
        try XCTSkipIf(points.isEmpty, "no Lagrange pair in the opening system")
        let target = try XCTUnwrap(points.first)
        let mover = try XCTUnwrap(model.bodies.first { $0.id != host.id
                                    && $0.id != model.primaryBody?.id })

        let display = target.position * model.simToDisplay
        model.grab(id: mover.id, at: display, timestamp: 0)
        model.hold(id: mover.id, at: display, timestamp: 0.1)
        model.release(id: mover.id, timestamp: 0.2)
        XCTAssertNotNil(model.capturedPointName)

        model.grab(id: mover.id, at: display, timestamp: 0.3)
        XCTAssertNil(model.capturedPointName)
        XCTAssertNil(model.capturedBodyID)
    }
}
