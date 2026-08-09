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
import RealityKit
import RenderKit
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
        // L4 EXPLICITLY. `points.first` is L1, which sits inside the
        // host planet's Hill sphere — parking a second planet there is
        // not a capture experiment, it is a collision, and the two merge
        // on the first frame. L4 is 60 degrees away and stable, which is
        // the case the paragraph is about.
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

    /// THE PARAGRAPH IS NOT INSIDE THE STAR.
    ///
    /// The first photograph ever taken of this callout (2026-08-08,
    /// `-openModule gravitylab -gravLagrange 1`) showed its last three
    /// lines cut off mid-word — "displaced bodies orbi", "Jupiter's L4
    /// hol". Nothing was wrong with the strings, the wrap width or the
    /// backing plate; the text was simply standing INSIDE the sun's halo,
    /// with some glyphs in front of the sphere's surface and some behind.
    ///
    /// Inner planets are where this bites: Mercury's L-points are 0.387
    /// AU out, and at display scale the halo is a good fraction of that.
    /// Every test above passed while it happened, because all of them ask
    /// what the callout SAYS and none asked where it is.
    ///
    /// Measured through the renderer's real `tick`, not by calling the
    /// placement helper — the helper being right is not the claim; the
    /// callout arriving somewhere legible is.
    func testTheCapturedParagraphStandsClearOfTheStar() throws {
        let model = GravityLabModel()
        model.showLagrangePoints = true
        let host = try XCTUnwrap(model.bodies.dropFirst().first)
        model.select(id: host.id)
        let points = model.lagrangePoints
        try XCTSkipIf(points.isEmpty, "no Lagrange pair in the opening system")
        // L4 EXPLICITLY. `points.first` is L1, which sits inside the
        // host planet's Hill sphere — parking a second planet there is
        // not a capture experiment, it is a collision, and the two merge
        // on the first frame. L4 is 60 degrees away and stable, which is
        // the case the paragraph is about.
        let target = try XCTUnwrap(points.first { $0.name == "L4" } ?? points.first)
        let mover = try XCTUnwrap(model.bodies.first { $0.id != host.id
                                    && $0.id != model.primaryBody?.id })
        let display = target.position * model.simToDisplay
        model.grab(id: mover.id, at: display, timestamp: 0)
        model.hold(id: mover.id, at: display, timestamp: 0.1)
        model.release(id: mover.id, timestamp: 0.2)
        try XCTSkipIf(model.capturedPointName == nil, "the throw did not capture")

        let renderer = GravityLabRenderer()
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
            * Float(GravityLabRenderer.glowBaseRadius
                    / GravityLabRenderer.glowReferenceRadius)
        let at = callout.root.position(relativeTo: nil)

        XCTAssertGreaterThan(distance(at, starAt), halo, """
            the Lagrange paragraph is \(distance(at, starAt)) m from the star, \
            inside its \(halo) m halo — the text renders half in front of the \
            sphere and half behind it, which is what cut the last three lines \
            off mid-word in the first screenshot of this feature.
            """)
    }

    /// …and it still FOLLOWS THE BODY, which is the whole argument for
    /// putting it there. Standing off toward the reader must not turn it
    /// into a fixed sign: L1, L2 and L3 are saddles, the captured body
    /// slides off them over the next few days, and the sentence saying so
    /// has to travel with it.
    func testTheParagraphStillTravelsWithTheBody() throws {
        let model = GravityLabModel()
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

        let renderer = GravityLabRenderer()
        renderer.viewerInSystem = SIMD3<Float>(0, 0, 1.4)
        renderer.tick(model)
        let first = try XCTUnwrap(renderer.lagrangeCallout).root
            .position(relativeTo: nil)

        let seatedAt = SIMD3<Float>(mover.body.position)

        // Run until the body has visibly moved — in chunks, because the
        // capture is allowed to LAPSE (that is the physics: L4 holds, the
        // saddles do not) and a lapse is a skip rather than a pass. The
        // first version of this test ran 25 days in one go, the capture
        // ended somewhere inside it, and the callout froze exactly where
        // it had been — which is what a disabled callout does, and is not
        // evidence about tracking either way.
        //
        // `step` takes WALL-CLOCK seconds and clamps to 1/30 — the first
        // version passed `dt: 600` thinking it was ten minutes of sim
        // time, and got a single frame. Three sim days per wall second,
        // so this is a couple of months of sky.
        // ONE FRAME AT A TIME. The body is parked at L4 with no orbital
        // velocity, so it is falling into the star from the moment it is
        // let go and has a couple of sim months to live; stepping in
        // chunks of ten overshot its whole lifetime and reported "never
        // moved" about a body that had already merged.
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

    /// A CAPTURE DOES NOT OUTLIVE THE BODY IT IS ABOUT.
    ///
    /// This is the defect the placement test tripped over on 2026-08-08
    /// while trying to measure something else. A planet parked at an
    /// inner world's L4 has no orbital velocity, falls into the star, and
    /// merges — and `capturedPointName` / `capturedBodyID` went on naming
    /// it. Nothing rendered wrong, because `syncLagrangeCapture` guards
    /// its lookup and quietly disables the callout; the model was simply
    /// holding a verdict about an object that no longer existed, which is
    /// the failure `reset()` already apologises for in this same file.
    ///
    /// Asserted through `step` rather than by calling the sweep, and
    /// against the CONDITION (the id resolves) rather than against the
    /// two removal sites that exist today.
    /// A CAPTURE DOES NOT OUTLIVE THE BODY IT IS ABOUT.
    ///
    /// Found on 2026-08-08 by the placement test above, which was trying
    /// to measure something else entirely. `capturedPointName` and
    /// `capturedBodyID` were cleared on grab and on `reset()` and nowhere
    /// else, so a captured body that merged or was deleted left the model
    /// holding a verdict about an object that no longer existed — the
    /// failure `reset()` already apologises for in this same file.
    ///
    /// Nothing rendered wrong, which is why it lasted: `syncLagrangeCapture`
    /// guards its lookup and quietly disables the callout. Silent wrong
    /// state, and the only reader happening to be defensive.
    ///
    /// BOTH REMOVAL PATHS, and they do not look alike — one deletes a
    /// body, the other replaces two with a heavier one carrying a new id.
    /// Asserted through `step` rather than by calling the sweep.
    func testACaptureDoesNotSurviveTheBodyItNames() throws {
        // 1. THE MERGE. L1 sits inside the host planet's Hill sphere, so
        //    a second planet parked there falls together with it within
        //    a few frames — a deterministic removal, no waiting.
        let model = GravityLabModel()
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

        // 2. THE DELETE, at a point that holds, so nothing else can be
        //    what cleared it.
        let second = GravityLabModel()
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

    /// …AND A LIVE CAPTURE IS NOT SWEPT AWAY. Without this the sweep
    /// could clear unconditionally and every test above would still pass.
    func testASurvivingCaptureIsLeftAlone() throws {
        let model = GravityLabModel()
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
