//
//  LagrangeCaptureTests.swift
//  PhysicsPlaygroundTests
//
//  A release near a Lagrange point parks the body there and rewrites
//  the thrown velocity with the co-rotating one — correct, and
//  unexplained it looks like the throw was thrown away. These pin that a
//  capture records which point and which body, and that every point the
//  model can capture at has a paragraph.
//

import XCTest
import PhysicsCore
import simd
import RealityKit
import RenderKit
@testable import PhysicsPlayground

@MainActor
final class LagrangeCaptureTests: XCTestCase {

    /// Every point the model can park a body at can explain itself — a
    /// criterion over `Lagrange.Points`, not a list of five.
    func testEveryLagrangePointHasSomethingToSay() {
        let (earth, moon) = Lagrange.earthMoonSystem()
        let points = Lagrange.points(primary: earth, secondary: moon)
        XCTAssertFalse(points.all.isEmpty)
        for point in points.all {
            let text = OrbitalMechanicsModel.lagrangeExplanations[point.name]
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
        for (name, text) in OrbitalMechanicsModel.lagrangeExplanations {
            XCTAssertTrue(seen.insert(text).inserted,
                          "\(name) repeats another point's paragraph")
        }
    }

    /// The two stable points say so, while the saddles admit they are not:
    /// the one content claim worth asserting.
    func testTheParagraphsAgreeWithTheStability() throws {
        let saddles = ["L1", "L2", "L3"]
        for name in saddles {
            let text = try XCTUnwrap(OrbitalMechanicsModel.lagrangeExplanations[name])
                .lowercased()
            XCTAssertTrue(text.contains("unstable") || text.contains("saddle")
                            || text.contains("slide off"),
                          "\(name) is a saddle point and its paragraph does "
                          + "not say so")
        }
        for name in ["L4", "L5"] {
            let text = try XCTUnwrap(OrbitalMechanicsModel.lagrangeExplanations[name])
                .lowercased()
            XCTAssertTrue(text.contains("stable") || text.contains("trojan"),
                          "\(name) is stable and its paragraph does not say so")
        }
    }

    // MARK: The capture records enough to be explained

    /// A capture must name the point and the body, because the callout
    /// rides the body — L1's occupant slides off over the following days
    /// with the sentence predicting it travelling alongside.
    func testACaptureRecordsThePointAndTheBody() throws {
        let model = OrbitalMechanicsModel()
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
            OrbitalMechanicsModel.lagrangeExplanations[model.capturedPointName ?? ""])
    }

    /// Grabbing the body again clears it — the paragraph belongs to a
    /// capture, not to the session.
    func testPickingTheBodyUpAgainClearsTheCapture() throws {
        let model = OrbitalMechanicsModel()
        model.showLagrangePoints = true
        let host = try XCTUnwrap(model.bodies.dropFirst().first)
        model.select(id: host.id)
        let points = model.lagrangePoints
        try XCTSkipIf(points.isEmpty, "no Lagrange pair in the opening system")
        // L4 explicitly: L1 sits inside the host planet's Hill sphere, and a
        // second planet parked there merges on the first frame.
        let target = try XCTUnwrap(points.first { $0.name == "L4" } ?? points.first)
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

    // MARK: Where the paragraph stands

    /// The paragraph is not inside the star: inner planets' L-points are
    /// close in, and the callout once stood inside the sun's halo with its
    /// last lines cut off. Measured through the renderer's real `tick`.
    func testTheCapturedParagraphStandsClearOfTheStar() throws {
        let model = OrbitalMechanicsModel()
        model.showLagrangePoints = true
        let host = try XCTUnwrap(model.bodies.dropFirst().first)
        model.select(id: host.id)
        let points = model.lagrangePoints
        try XCTSkipIf(points.isEmpty, "no Lagrange pair in the opening system")
        // L4 explicitly, as above.
        let target = try XCTUnwrap(points.first { $0.name == "L4" } ?? points.first)
        let mover = try XCTUnwrap(model.bodies.first { $0.id != host.id
                                    && $0.id != model.primaryBody?.id })
        let display = target.position * model.simToDisplay
        model.grab(id: mover.id, at: display, timestamp: 0)
        model.hold(id: mover.id, at: display, timestamp: 0.1)
        model.release(id: mover.id, timestamp: 0.2)
        try XCTSkipIf(model.capturedPointName == nil, "the throw did not capture")

        let renderer = OrbitalMechanicsRenderer()
        // A viewer in front of the system, which is what the space view
        // writes every frame; without one there is no ray to stand off
        // along and the callout stays on the body.
        renderer.viewerInSystem = SIMD3<Float>(0, 0, 1.4)
        renderer.tick(model)

        let callout = try XCTUnwrap(renderer.lagrangeCallout,
                                    "the capture produced no callout at all")
        XCTAssertTrue(callout.isEnabled)

        let star = try XCTUnwrap(model.primaryBody)
        let starAt = SIMD3<Float>(star.body.position) * Float(model.simToDisplay)
        let halo = Float(star.displayRadius)
            * Float(OrbitalMechanicsRenderer.glowBaseRadius
                    / OrbitalMechanicsRenderer.glowReferenceRadius)
        let at = callout.root.position(relativeTo: nil)

        XCTAssertGreaterThan(distance(at, starAt), halo, """
            the Lagrange paragraph is \(distance(at, starAt)) m from the star, \
            inside its \(halo) m halo — the text renders half in front of the \
            sphere and half behind it, which is what cut the last three lines \
            off mid-word in the first screenshot of this feature.
            """)
    }

    /// And it still follows the body: the saddles' occupants slide off over
    /// the following days, and the sentence saying so travels with them.
    func testTheParagraphStillTravelsWithTheBody() throws {
        let model = OrbitalMechanicsModel()
        model.showLagrangePoints = true
        let host = try XCTUnwrap(model.bodies.dropFirst().first)
        model.select(id: host.id)
        try XCTSkipIf(model.lagrangePoints.isEmpty, "no Lagrange pair")
        let target = try XCTUnwrap(model.lagrangePoints.first { $0.name == "L4" }
                                   ?? model.lagrangePoints.first)
        let mover = try XCTUnwrap(model.bodies.first { $0.id != host.id
                                    && $0.id != model.primaryBody?.id })
        let display = target.position * model.simToDisplay
        model.grab(id: mover.id, at: display, timestamp: 0)
        model.hold(id: mover.id, at: display, timestamp: 0.1)
        model.release(id: mover.id, timestamp: 0.2)
        try XCTSkipIf(model.capturedPointName == nil, "the throw did not capture")

        let renderer = OrbitalMechanicsRenderer()
        renderer.viewerInSystem = SIMD3<Float>(0, 0, 1.4)
        renderer.tick(model)
        let first = try XCTUnwrap(renderer.lagrangeCallout).root
            .position(relativeTo: nil)

        let seatedAt = SIMD3<Float>(mover.body.position)

        // Run one frame at a time until the body has visibly moved: the
        // capture may lapse (that is the physics) and the parked body is
        // falling into the star, so a coarse step overshoots its whole
        // lifetime. `step` takes wall-clock seconds, clamped to 1/30.
        var moved = false
        for _ in 0..<400 {
            model.step(dt: 1.0 / 30)
            guard let now = model.bodies.first(where: { $0.id == mover.id })?
                    .body.position else { break }
            if distance(SIMD3<Float>(now), seatedAt) > 1e-4 {
                moved = true
                break
            }
        }
        try XCTSkipIf(!moved, "the captured body never moved")

        renderer.tick(model)
        let later = try XCTUnwrap(renderer.lagrangeCallout).root
            .position(relativeTo: nil)

        XCTAssertGreaterThan(distance(first, later), 1e-5, """
            the body it describes moved and the paragraph did not. It has \
            become a fixed sign, and a fixed sign cannot show a saddle \
            point failing to hold.
            """)
    }

    /// A capture does not outlive the body it names: a captured body that
    /// merged or was deleted once left the model holding a verdict about an
    /// object that no longer existed, invisibly, because the renderer's
    /// lookup was defensive. Both removal paths, through `step`.
    func testACaptureDoesNotSurviveTheBodyItNames() throws {
        // The merge: a second planet parked at L1 falls together with the host
        // within a few frames.
        let model = OrbitalMechanicsModel()
        model.showLagrangePoints = true
        let host = try XCTUnwrap(model.bodies.dropFirst().first)
        model.select(id: host.id)
        let inner = try XCTUnwrap(model.lagrangePoints.first { $0.name == "L1" }
                                  ?? model.lagrangePoints.first)
        let mover = try XCTUnwrap(model.bodies.first { $0.id != host.id
                                    && $0.id != model.primaryBody?.id })
        let at = inner.position * model.simToDisplay
        model.grab(id: mover.id, at: at, timestamp: 0)
        model.hold(id: mover.id, at: at, timestamp: 0.1)
        model.release(id: mover.id, timestamp: 0.2)
        try XCTSkipIf(model.capturedBodyID == nil, "the throw did not capture")

        var gone = false
        for _ in 0..<400 {
            model.step(dt: 1.0 / 30)
            if !model.bodies.contains(where: { $0.id == mover.id }) {
                gone = true
                break
            }
        }
        try XCTSkipIf(!gone, "the body at L1 never merged")
        XCTAssertNil(model.capturedBodyID, """
            the captured body merged away and the capture still names it. \
            `pruneCapture` is not running on the collision path — note it \
            has to run AFTER the physics, not at the top of `step`.
            """)
        XCTAssertNil(model.capturedPointName)

        // 2. The delete, at a point that holds, so nothing else can be
        //    what cleared it.
        let second = OrbitalMechanicsModel()
        second.showLagrangePoints = true
        let h = try XCTUnwrap(second.bodies.dropFirst().first)
        second.select(id: h.id)
        let stable = try XCTUnwrap(second.lagrangePoints.first { $0.name == "L4" }
                                   ?? second.lagrangePoints.first)
        let body = try XCTUnwrap(second.bodies.first { $0.id != h.id
                                   && $0.id != second.primaryBody?.id })
        let seat = stable.position * second.simToDisplay
        second.grab(id: body.id, at: seat, timestamp: 0)
        second.hold(id: body.id, at: seat, timestamp: 0.1)
        second.release(id: body.id, timestamp: 0.2)
        try XCTSkipIf(second.capturedBodyID == nil, "no capture to delete")

        second.removeBody(id: body.id)
        second.step(dt: 1.0 / 30)
        XCTAssertNil(second.capturedBodyID,
                     "the deleted body is still the captured one")
        XCTAssertNil(second.capturedPointName,
                     "the paragraph still names a body that was deleted")
    }

    /// …and A live capture is not swept away. Without this the sweep
    /// could clear unconditionally and every test above would still pass.
    func testASurvivingCaptureIsLeftAlone() throws {
        let model = OrbitalMechanicsModel()
        model.showLagrangePoints = true
        let host = try XCTUnwrap(model.bodies.dropFirst().first)
        model.select(id: host.id)
        let target = try XCTUnwrap(model.lagrangePoints.first { $0.name == "L4" }
                                   ?? model.lagrangePoints.first)
        let mover = try XCTUnwrap(model.bodies.first { $0.id != host.id
                                    && $0.id != model.primaryBody?.id })
        let at = target.position * model.simToDisplay
        model.grab(id: mover.id, at: at, timestamp: 0)
        model.hold(id: mover.id, at: at, timestamp: 0.1)
        model.release(id: mover.id, timestamp: 0.2)
        let name = try XCTUnwrap(model.capturedPointName)

        for _ in 0..<120 { model.step(dt: 1.0 / 30) }
        try XCTSkipIf(!model.bodies.contains { $0.id == mover.id },
                      "the body did not survive, so this proves nothing")
        XCTAssertEqual(model.capturedPointName, name,
                       "the sweep cleared a capture whose body is still there")
        XCTAssertEqual(model.capturedBodyID, mover.id)
    }
}
