//
//  ResetCoverageTests.swift
//  PhysicsPlaygroundTests
//
//  THE SEVENTH INSTANCE CANNOT HIDE.
//
//  Six modules have now shipped the same defect: a `Bool` on the model
//  that `reset()` forgot. Pendulums' `frictionOn`, Magnetism's
//  `dynamicsOn`, Kinematics' `respectRoomWalls`, three of Circuits' four
//  at once (2026-07-31), and then — found by this pass on 2026-08-03,
//  after CLAUDE.md had already been updated to warn about exactly this —
//  Gravity Lab's `keplerSweepOn` and Electric Fields' `chargesRespond`.
//
//  Every previous fix was a test that LISTED the flags it knew about.
//  That is the same act of attention that missed them in the first
//  place, so it caught nothing new: the fifth and sixth sat behind lit
//  switch plates for two days with per-module reset tests passing over
//  them.
//
//  This one enumerates instead. It reflects over the model, finds every
//  `Bool` it has, and asserts that a model which has been mutated and
//  then reset is indistinguishable from a fresh one. Nothing here names
//  a property, so a flag added tomorrow is covered tomorrow.
//
//  WHY BOOLS SPECIFICALLY. A flag is what a switch plate shows, and a
//  lit lamp makes a claim every frame — that is what makes this class of
//  bug visible the moment it gets a control and invisible before. The
//  same sweep over Doubles would drag in accumulators, clocks and
//  personal bests that are deliberately NOT reset (`bestStreak`,
//  `bestPredictionMissAU`, `simTime`), and a test with a growing
//  exception list is the listing test again.
//
//  `@Observable` stores each tracked property in an underscored backing
//  field, so that is what `Mirror` reports and what this reads.
//

import XCTest
@testable import PhysicsPlayground

@MainActor
final class ResetCoverageTests: XCTestCase {

    /// Every `Bool` the model carries, keyed by property name with the
    /// `@Observable` underscore stripped.
    private func flags(of model: Any) -> [String: Bool] {
        var found: [String: Bool] = [:]
        for child in Mirror(reflecting: model).children {
            guard let label = child.label,
                  let value = child.value as? Bool else { continue }
            found[label.hasPrefix("_") ? String(label.dropFirst()) : label] = value
        }
        return found
    }

    /// Flip every flag away from where it started, then reset, then
    /// compare against a model that was never touched.
    ///
    /// `flip` is handed the model and must invert its flags; it is per
    /// module because the properties are concrete, but it does not get
    /// to choose WHICH flags — it is handed the names by reflection.
    private func assertResetRestoresEveryFlag<M>(
        fresh: () -> M,
        flip: (M, String) -> Void,
        reset: (M) -> Void,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        let reference = flags(of: fresh())
        XCTAssertFalse(reference.isEmpty,
                       "Reflection found no Bool at all — the mechanism is broken, "
                       + "not the model.",
                       file: file, line: line)

        let model = fresh()
        for name in reference.keys { flip(model, name) }

        let mutated = flags(of: model)
        let moved = reference.filter { mutated[$0.key] != $0.value }
        XCTAssertFalse(moved.isEmpty,
                       "The flip closure moved nothing, so this test would pass "
                       + "against any reset() at all.",
                       file: file, line: line)

        reset(model)

        let after = flags(of: model)
        for (name, expected) in reference {
            XCTAssertEqual(
                after[name], expected,
                """
                reset() did not restore `\(name)`.

                This is the defect that has now shipped six times. A flag \
                with no visible control drifts out of reset() and stays \
                wrong because nothing in the room contradicts it — and the \
                moment it gets a switch plate, the lamp makes a false claim \
                every frame.

                Fix reset(), not this test.
                """,
                file: file, line: line)
        }
    }

    // MARK: The six

    /// The two found on 2026-08-03 are first, because they are the ones
    /// this mechanism exists to have caught.

    func testGravityLabResetRestoresEveryFlag() {
        assertResetRestoresEveryFlag(
            fresh: { GravityLabModel() },
            flip: { model, name in
                switch name {
                case "keplerSweepOn": model.keplerSweepOn.toggle()
                case "isPaused": model.isPaused.toggle()
                case "showVelocityVector": model.showVelocityVector.toggle()
                case "showAccelerationVector": model.showAccelerationVector.toggle()
                case "showForceVector": model.showForceVector.toggle()
                case "showFieldParticles": model.showFieldParticles.toggle()
                case "showSpacetimeGrid": model.showSpacetimeGrid.toggle()
                case "showLagrangePoints": model.showLagrangePoints.toggle()
                case "playOrbitalChord": model.playOrbitalChord.toggle()
                default:
                    XCTFail("GravityLabModel gained a flag this test cannot "
                            + "flip: `\(name)`. Add a case — do not delete "
                            + "the assertion.")
                }
            },
            reset: { $0.reset() })
    }

    func testFieldResetRestoresEveryFlag() {
        assertResetRestoresEveryFlag(
            fresh: { FieldModel() },
            flip: { model, name in
                switch name {
                case "chargesRespond": model.chargesRespond.toggle()
                case "showLines": model.showLines.toggle()
                case "capacitorOn": model.capacitorOn.toggle()
                case "magneticFieldOn": model.magneticFieldOn.toggle()
                case "gaussSurfaceOn": model.gaussSurfaceOn.toggle()
                case "electronMode": model.electronMode.toggle()
                case "probeIsPositive": model.probeIsPositive.toggle()
                case "isPaused": model.isPaused.toggle()
                default:
                    XCTFail("FieldModel gained a flag this test cannot flip: "
                            + "`\(name)`. Add a case — do not delete the "
                            + "assertion.")
                }
            },
            reset: { $0.reset() })
    }

    func testPendulumsResetRestoresEveryFlag() {
        assertResetRestoresEveryFlag(
            fresh: { PendulumsModel() },
            flip: { model, name in
                switch name {
                case "frictionOn": model.frictionOn.toggle()
                case "foucaultOn": model.foucaultOn.toggle()
                case "showVelocity": model.showVelocity.toggle()
                case "showAcceleration": model.showAcceleration.toggle()
                case "showForces": model.showForces.toggle()
                case "isPaused": model.isPaused.toggle()
                default:
                    XCTFail("PendulumsModel gained a flag this test cannot "
                            + "flip: `\(name)`. Add a case — do not delete "
                            + "the assertion.")
                }
            },
            reset: { $0.reset() })
    }

    func testMagnetismResetRestoresEveryFlag() {
        assertResetRestoresEveryFlag(
            fresh: { MagnetismModel() },
            flip: { model, name in
                switch name {
                case "dynamicsOn": model.dynamicsOn.toggle()
                case "showFieldLines": model.showFieldLines.toggle()
                case "showCompasses": model.showCompasses.toggle()
                case "compassOn": model.compassOn.toggle()
                case "earthFieldOn": model.earthFieldOn.toggle()
                case "inertiaOn": model.inertiaOn.toggle()
                // A `let` recording what `-magInertia` asked for at
                // launch. Reflection cannot tell a `let` from a `var`,
                // so it surfaces here and is named rather than skipped —
                // an unexplained hole in this switch is how the next
                // real flag would slip through. It is immutable, so
                // there is nothing to flip and nothing to restore.
                case "inertiaAtLaunch": break
                case "isPaused": model.isPaused.toggle()
                default:
                    XCTFail("MagnetismModel gained a flag this test cannot "
                            + "flip: `\(name)`. Add a case — do not delete "
                            + "the assertion.")
                }
            },
            reset: { $0.reset() })
    }

    func testKinematicsResetRestoresEveryFlag() {
        assertResetRestoresEveryFlag(
            fresh: { KinematicsModel() },
            flip: { model, name in
                switch name {
                case "respectRoomWalls": model.respectRoomWalls.toggle()
                case "airResistance": model.airResistance.toggle()
                case "catchingEnabled": model.catchingEnabled.toggle()
                case "hoopsOrbit": model.hoopsOrbit.toggle()
                case "isPaused": model.isPaused.toggle()
                default:
                    XCTFail("KinematicsModel gained a flag this test cannot "
                            + "flip: `\(name)`. Add a case — do not delete "
                            + "the assertion.")
                }
            },
            reset: { $0.reset() })
    }

    func testCircuitsResetRestoresEveryFlag() {
        assertResetRestoresEveryFlag(
            fresh: { CircuitsModel() },
            flip: { model, name in
                switch name {
                case "showElectronFlow": model.showElectronFlow.toggle()
                case "trueSpeedMode": model.trueSpeedMode.toggle()
                case "showVoltageHeights": model.showVoltageHeights.toggle()
                case "showMagneticField": model.showMagneticField.toggle()
                case "electronView": model.electronView.toggle()
                case "multimeterArmed": model.multimeterArmed.toggle()
                case "isPaused": model.isPaused.toggle()
                default:
                    XCTFail("CircuitsModel gained a flag this test cannot "
                            + "flip: `\(name)`. Add a case — do not delete "
                            + "the assertion.")
                }
            },
            reset: { $0.reset() })
    }
}
