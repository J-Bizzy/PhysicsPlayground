//
//  ResetCoverageTests.swift
//  PhysicsPlaygroundTests
//
//  Six modules have shipped the same defect: a `Bool` on the model that
//  `reset()` forgot, behind a lit switch plate. This enumerates instead
//  of listing: it reflects over each model, finds every `Bool`, and
//  asserts a mutated-then-reset model matches a fresh one. Bools only —
//  a sweep over Doubles would drag in clocks and accumulators that are
//  deliberately not reset. What it cannot see is state owned by a view
//  (the multimeter); that needs the `resetNonce` pattern and a test of
//  its own.
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

    /// Flip every flag away from where it started, then reset, then compare
    /// against a model that was never touched. `flip` is handed the names
    /// by reflection.
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

    // MARK: The labs

    /// The two found behind lit plates are first, because they are the ones
    /// this mechanism exists to have caught.

    func testOrbitalMechanicsResetRestoresEveryFlag() {
        assertResetRestoresEveryFlag(
            fresh: { OrbitalMechanicsModel() },
            flip: { model, name in
                switch name {
                case "keplerSweepOn": model.keplerSweepOn.toggle()
                case "isPaused": model.isPaused.toggle()
                case "showVelocityVector": model.showVelocityVector.toggle()
                case "showForceVector": model.showForceVector.toggle()
                case "showLagrangePoints": model.showLagrangePoints.toggle()
                case "playOrbitalChord": model.playOrbitalChord.toggle()
                default:
                    XCTFail("OrbitalMechanicsModel gained a flag this test cannot "
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
                case "showVelocity": model.showVelocity.toggle()
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
                case "compassOn": model.compassOn.toggle()
                case "earthFieldOn": model.earthFieldOn.toggle()
                case "inertiaOn": model.inertiaOn.toggle()
                // A `let` recording what `-magInertia` asked for at launch; reflection
                // cannot tell a `let` from a `var`, so it is named rather than skipped.
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

    func testOpticsResetRestoresEveryFlag() {
        assertResetRestoresEveryFlag(
            fresh: { OpticsModel() },
            flip: { model, name in
                switch name {
                case "isPaused": model.isPaused.toggle()
                case "showsWeakReflections": model.showsWeakReflections.toggle()
                case "showsAngles": model.showsAngles.toggle()
                // The two lights' switches, inside their `Source` values.
                case "isOn":
                    model.laser.isOn.toggle()
                    model.torch.isOn.toggle()
                default:
                    XCTFail("OpticsModel gained a flag this test cannot flip: "
                            + "`\(name)`. Add a case — do not delete the "
                            + "assertion.")
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
