//
//  VignettePropTests.swift
//  Physics Playground — app tests
//
//  The props the hub miniatures load, and the one thing about them that
//  cannot be checked by looking at either side alone: which way round
//  they come out. The exporter maps Blender (x, y, z) → RealityKit
//  (x, z, −y); a prop authored in the wrong plane still loads and simply
//  faces the wall.
//

import XCTest
import RealityKit
import simd
@testable import PhysicsPlayground

@MainActor
final class VignettePropTests: XCTestCase {

    private func extents(of name: String) throws -> SIMD3<Float> {
        let loaded = try XCTUnwrap(try? Entity.load(named: name),
                                   "\(name).usdz is not in the bundle — run "
                                   + "Tools/moduleprops.py / vignetteprops.py")
        let box = loaded.visualBounds(relativeTo: nil).extents
        XCTAssertGreaterThan(min(box.x, min(box.y, box.z)), 0,
                             "\(name) has no thickness on some axis")
        return box
    }

    /// Everything the miniatures load, loads. A miniature falls back to
    /// primitives when an asset is missing, which is the right behaviour
    /// and also completely silent — so the only way a dropped file gets
    /// noticed is here.
    func testEveryPropTheMiniaturesAskForExists() throws {
        for name in ["BarMagnet", "PendulumStand", "PendulumBob",
                     "CompassBody", "CompassNeedle",
                     "LauncherCarriage", "QuadrantPointer", "TargetStand",
                     "CometNucleus", "ChargePlus", "ChargeMinus",
                     "CircuitBattery", "CircuitBulb", "CircuitSwitch",
                     "LauncherBarrel"] {
            _ = try extents(of: name)
        }
    }

    /// The bar magnet lies along X, which is the axis
    /// `HubVignettes.magnetism()` separates the pair along. Authored up
    /// Blender's Z instead, it would arrive standing on end and the two
    /// bars would approach each other sideways.
    func testTheBarMagnetLiesAlongX() throws {
        let box = try extents(of: "BarMagnet")
        XCTAssertGreaterThan(box.x, box.y * 2, "the magnet is not a BAR")
        XCTAssertEqual(box.y, box.z, accuracy: box.y * 0.35,
                       "the magnet's section should be near square")
    }

    /// The stand is wider than it is tall and taller than it is deep —
    /// beam along X, standing up Y. On its back, the pendulums would
    /// hang out of the exhibit toward the reader.
    func testTheStandStandsUp() throws {
        let box = try extents(of: "PendulumStand")
        XCTAssertGreaterThan(box.x, box.y,
                             "the stand should be wider than it is tall")
        XCTAssertGreaterThan(box.y, box.z,
                             "the stand is deeper than it is tall — it has "
                             + "probably arrived lying on its back")
    }

    /// The bob hangs up Y: sphere below, stem and eye above. Its height
    /// is its longest span, which is also what the importer normalises
    /// on — `hang` computes the eye's position from exactly that ratio.
    func testTheBobHangsUpY() throws {
        let box = try extents(of: "PendulumBob")
        XCTAssertGreaterThan(box.y, box.x,
                             "the bob's stem and eye should make Y its "
                             + "longest axis")
        XCTAssertEqual(box.x, box.z, accuracy: box.x * 0.1,
                       "the bob is not round in plan")
    }

    /// The compass is a dish lying dial-up: thin on Y, round in XZ. On
    /// edge, the needle would sweep through the bowl.
    func testTheCompassLiesDialUp() throws {
        let box = try extents(of: "CompassBody")
        XCTAssertLessThan(box.y, min(box.x, box.z) * 0.5,
                          "the compass bowl is on edge — its axis is not Y")
        XCTAssertEqual(box.x, box.z, accuracy: box.x * 0.08,
                       "the bowl is not round")
    }

    /// The needle lies along X — north at +X, the handedness
    /// `magnetism()` steers by — and is symmetric about its pivot, which
    /// is the property that lets the importer's box-centring be the
    /// pivot.
    func testTheNeedleLiesAlongX() throws {
        let box = try extents(of: "CompassNeedle")
        XCTAssertGreaterThan(box.x, box.z * 3, "the needle is not a needle")
        XCTAssertGreaterThan(box.x, box.y * 3,
                             "the needle stands on end")
    }

    /// The pointer is a long X spike too: its authored origin is its
    /// hinge, and `projectile()` un-centres it after import on the
    /// assumption that the long axis arrives along X.
    func testThePointerLiesAlongX() throws {
        let box = try extents(of: "QuadrantPointer")
        XCTAssertGreaterThan(box.x, box.y * 3, "the pointer is not a spike")
        XCTAssertGreaterThan(box.x, box.z * 3,
                             "the pointer is fatter than it is long in Z")
    }

    /// The target's ring is horizontal — the ball falls through it — so
    /// the stand's width (mast plus ring reach) beats its height, and
    /// its height beats its depth.
    func testTheTargetRingIsHorizontal() throws {
        let box = try extents(of: "TargetStand")
        XCTAssertGreaterThan(box.x, box.y,
                             "the ring should reach sideways off the mast")
        XCTAssertGreaterThan(box.y, box.z * 0.9,
                             "the stand has fallen over")
    }

    /// The comet is bilobed along X: two overlapping lobes, so X is the
    /// long axis and neither of the others comes close. A sphere here
    /// would mean the displacement or the second lobe went missing.
    func testTheCometIsBilobedAlongX() throws {
        let box = try extents(of: "CometNucleus")
        XCTAssertGreaterThan(box.x, box.y * 1.25,
                             "the nucleus is round — the second lobe is missing")
        XCTAssertGreaterThan(box.x, box.z * 1.25,
                             "the nucleus is round — the second lobe is missing")
    }

    /// Each charge's moulded sign stands sub-millimetre proud on +Z, the
    /// reader's side; it is the only thing that breaks the sphere's
    /// symmetry, so Z strictly beats both other axes.
    func testTheChargeSignsFaceTheReader() throws {
        for name in ["ChargePlus", "ChargeMinus"] {
            let box = try extents(of: name)
            XCTAssertEqual(box.x, box.y, accuracy: box.x * 0.03,
                           "\(name) is not round")
            XCTAssertGreaterThan(box.z, box.x * 1.005,
                                 "\(name)'s sign does not stand proud toward "
                                 + "the reader")
            XCTAssertLessThan(box.z, box.x * 1.1,
                              "\(name)'s Z span is far beyond a moulded sign "
                              + "— something else is sticking out")
        }
    }



    /// The launcher barrel points up +Y, which is the contract
    /// `KinematicsRenderer` already relies on ("0.30 m base-to-muzzle
    /// along +Y") and which the miniature now shares — it slides the
    /// barrel up half its own length to put the breech on the origin.
    func testTheLauncherBarrelPointsUp() throws {
        let box = try extents(of: "LauncherBarrel")
        XCTAssertGreaterThan(box.y, box.x * 2,
                             "the barrel is not aligned with +Y")
    }
}
