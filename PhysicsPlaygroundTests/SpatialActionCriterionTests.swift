//
//  SpatialActionCriterionTests.swift
//  PhysicsPlaygroundTests
//
//  An entity that is hit-testable and announces itself must be operable
//  without hands. Every plate, petal, disc, rail, well and grip was once
//  spoken correctly and could not be pressed, and with no flat fallback
//  surface that made six rooms of readouts with no controls. Enforced
//  by a source-tree scan, so a primitive written tomorrow is caught
//  tomorrow; the fixtures stay because a scan proves a closure exists
//  and cannot prove it reaches the right code.
//

import XCTest
import RealityKit
import RenderKit
@testable import PhysicsPlayground

@MainActor
final class SpatialActionCriterionTests: XCTestCase {

    private struct Unreachable {
        let path: String
        let label: String
    }

    /// Walks a built scene for controls a hand can reach and VoiceOver
    /// cannot.
    private func unreachable(under root: Entity, label: String) -> [Unreachable] {
        var found: [Unreachable] = []

        func walk(_ entity: Entity, path: String) {
            let accessibility = entity.components[AccessibilityComponent.self]
            let isTargetable = entity.components[InputTargetComponent.self] != nil
            if isTargetable, let accessibility, accessibility.isAccessibilityElement {
                let action = entity.components[SpatialActionComponent.self]
                let operable = action?.activate != nil || action?.adjust != nil
                if !operable {
                    found.append(Unreachable(
                        path: path,
                        label: accessibility.label.map(String.init(localized:)) ?? "—"))
                }
            }
            for child in entity.children {
                walk(child, path: "\(path)/\(child.name.isEmpty ? "·" : child.name)")
            }
        }

        walk(root, path: label)
        return found
    }

    private func assertOperable(_ root: Entity, _ label: String,
                                file: StaticString = #filePath, line: UInt = #line) {
        let found = unreachable(under: root, label: label)
        guard !found.isEmpty else { return }
        let report = found.map { "  \($0.path) — spoken as \"\($0.label)\"" }
            .joined(separator: "\n")
        XCTFail("""
            \(found.count) control(s) in \(label) can be pinched but not \
            operated without hands. Attach `SpatialActions.attach` (or a \
            `SpatialActionComponent`) so VoiceOver's Activate reaches the same \
            code the tap does:
            \(report)
            """, file: file, line: line)
    }

    /// The criterion has to be able to fail, or every green run below
    /// means nothing.
    func testTheCriterionCatchesAControlItCannotOperate() {
        let plate = ModelEntity(mesh: .generateBox(size: [0.05, 0.05, 0.01]),
                                materials: [UnlitMaterial(color: .white)])
        plate.name = "mute-plate"
        plate.components.set(InputTargetComponent())
        var accessibility = AccessibilityComponent()
        accessibility.isAccessibilityElement = true
        accessibility.label = "Field lines"
        plate.components.set(accessibility)

        XCTAssertEqual(unreachable(under: plate, label: "fixture").count, 1)
    }

    /// …and must accept one that is wired.
    func testTheCriterionAcceptsAnOperableControl() {
        let plate = ModelEntity(mesh: .generateBox(size: [0.05, 0.05, 0.01]),
                                materials: [UnlitMaterial(color: .white)])
        plate.components.set(InputTargetComponent())
        SpatialActions.attach(to: plate, label: "Field lines", value: "showing",
                              activate: {})
        XCTAssertTrue(unreachable(under: plate, label: "fixture").isEmpty)
    }

    // MARK: The primitives

    func testActionBankPlatesCanBeOperatedWithoutHands() {
        var fired = 0
        let bank = SpatialActionBank(accent: .white, actions: [
            .init(id: "reset", label: "Reset", symbol: "arrow.counterclockwise",
                  fire: { fired += 1 }),
        ])
        for _ in 0..<40 {
            bank.update(anchor: .zero, viewer: [0, 0, 1], dt: 1 / 90, resetNonce: 0)
        }
        assertOperable(bank.root, "SpatialActionBank")
    }

    /// A destructive plate must still confirm, however it is pressed: the
    /// glass button's action is the bank's own arm-then-fire path, and the
    /// plate offers no entity-level shortcut straight at `fire`.
    func testADestructivePlateStillConfirmsForVoiceOver() throws {
        var fired = 0
        let bank = SpatialActionBank(accent: .white, actions: [
            .init(id: "clear", label: "Clear", symbol: "trash",
                  confirms: true, fire: { fired += 1 }),
        ])
        for _ in 0..<40 {
            bank.update(anchor: .zero, viewer: [0, 0, 1], dt: 1 / 90, resetNonce: 0)
        }
        let plate = try XCTUnwrap(bank.root.children.first { $0.name == "action-clear" })
        XCTAssertNil(plate.components[SpatialActionComponent.self])

        XCTAssertTrue(bank.handleTap(plate))
        XCTAssertEqual(fired, 0, "one press fired a destructive verb")
        XCTAssertEqual(bank.control(for: "clear")?.isArmed, true)
        XCTAssertTrue(bank.handleTap(plate))
        XCTAssertEqual(fired, 1, "the second press should confirm it")
    }

    // MARK: The criterion over the SOURCE

    /// Every file that stands an input target. `Grabbable` is the honest
    /// remainder: it took an `activate` closure that every call site passed
    /// nothing to, and the scan stayed green because a default argument is
    /// indistinguishable from a wired one. The per-module routing tests
    /// below are the only check that can tell "exists" from "connected".

    private func scanRoots() throws -> [URL] {
        let thisFile = URL(fileURLWithPath: #filePath)
        let app = thisFile.deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("PhysicsPlayground")
        var roots = ["Modules", "Hub", "DesignSystem", "Shell"]
            .map { app.appendingPathComponent($0) }
        // RenderKit too: its primitives stand input targets as well.
        roots.append(thisFile.deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Packages/RenderKit/Sources/RenderKit"))
        for root in roots {
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: root.path,
                                                 isDirectory: &isDirectory),
                  isDirectory.boolValue else {
                XCTFail("""
                    \(root.lastPathComponent) is not reachable from \
                    \(thisFile.path), so this check would pass without \
                    reading anything. If the tree moved, fix this path — do \
                    not let it skip.
                    """)
                throw XCTSkip("source tree not reachable")
            }
        }
        return roots
    }

    /// A file that makes something pinchable must also say what happens
    /// when it is activated without a pinch.
    func testEveryFileThatStandsAControlAlsoMakesItOperable() throws {
        var offenders: [String] = []
        for root in try scanRoots() {
            let files = FileManager.default.enumerator(
                at: root, includingPropertiesForKeys: nil)?
                .compactMap { $0 as? URL }
                .filter { $0.pathExtension == "swift" } ?? []
            for file in files {
                guard let text = try? String(contentsOf: file, encoding: .utf8),
                      text.contains("InputTargetComponent()") else { continue }
                let operable = text.contains("SpatialActions.attach")
                    || text.contains("SpatialActionComponent(")
                if !operable { offenders.append(file.lastPathComponent) }
            }
        }
        XCTAssertTrue(offenders.isEmpty, """
            \(offenders.count) file(s) attach an `InputTargetComponent` and \
            never make it operable without hands, so every control they \
            stand in the room is announced and unusable by VoiceOver:
            \(offenders.sorted().map { "  \($0)" }.joined(separator: "\n"))
            Route the action through the same `handleTap` a pinch takes — \
            never straight at the callback, or a destructive control loses \
            its confirmation.
            """)
    }

    /// The scan has to be able to fail, and has to be reading real files.
    func testTheSourceScanIsActuallyReadingTheTree() throws {
        var seen = 0
        for root in try scanRoots() {
            let files = FileManager.default.enumerator(
                at: root, includingPropertiesForKeys: nil)?
                .compactMap { $0 as? URL }
                .filter { $0.pathExtension == "swift" } ?? []
            for file in files {
                if let text = try? String(contentsOf: file, encoding: .utf8),
                   text.contains("InputTargetComponent()") { seen += 1 }
            }
        }
        // Ten when this was written. A floor, not an equality — the point
        // is that a scan matching nothing must not read as compliance.
        XCTAssertGreaterThanOrEqual(seen, 8, """
            the scan found \(seen) files standing controls, which is fewer \
            than the app is known to have — it is matching on the wrong \
            thing, and its green result means nothing.
            """)
    }

    // MARK: The carried objects

    /// Builds each module's renderer for real, points `onObjectTap` at a
    /// counter, and drives an activation through the same walk VoiceOver
    /// uses — the check the file scan cannot make.
    private func assertObjectsRoute(
        _ root: Entity, _ label: String, taps: () -> Int,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        var targets: [Entity] = []
        func walk(_ entity: Entity) {
            if entity.components[InputTargetComponent.self] != nil {
                targets.append(entity)
            }
            entity.children.forEach(walk)
        }
        walk(root)
        XCTAssertFalse(targets.isEmpty,
                       "\(label) built no grabbable objects to test",
                       file: file, line: line)

        let before = taps()
        var routed = 0
        for target in targets where SpatialActions.activate(target) { routed += 1 }
        XCTAssertGreaterThan(routed, 0, """
            none of \(label)'s \(targets.count) carried objects could be \
            activated — `Grabbable`'s `activate` is being passed nothing.
            """, file: file, line: line)
        XCTAssertGreaterThan(taps(), before, """
            \(label)'s objects declare an action that does not reach the \
            module's own tap routing.
            """, file: file, line: line)
    }

    func testMagnetismObjectsRouteToTheModule() {
        var taps = 0
        let renderer = MagnetismRenderer()
        renderer.onObjectTap = { _ in taps += 1 }
        let model = MagnetismModel()
        renderer.tick(model)
        assertObjectsRoute(renderer.root, "Magnetism", taps: { taps })
    }

    func testPendulumsObjectsRouteToTheModule() {
        var taps = 0
        let renderer = PendulumsRenderer()
        renderer.onObjectTap = { _ in taps += 1 }
        renderer.tick(dt: 1 / 90, model: PendulumsModel())
        assertObjectsRoute(renderer.root, "Pendulums", taps: { taps })
    }

    func testKinematicsObjectsRouteToTheModule() {
        var taps = 0
        let renderer = KinematicsRenderer()
        renderer.onObjectTap = { _ in taps += 1 }
        renderer.tick(KinematicsModel())
        assertObjectsRoute(renderer.root, "Projectiles", taps: { taps })
    }

    func testOrbitalMechanicsObjectsRouteToTheModule() {
        var taps = 0
        let renderer = OrbitalMechanicsRenderer()
        renderer.onObjectTap = { _ in taps += 1 }
        renderer.tick(OrbitalMechanicsModel())
        assertObjectsRoute(renderer.root, "Orbital Mechanics", taps: { taps })
    }

    func testElectricFieldsObjectsRouteToTheModule() {
        var taps = 0
        let renderer = FieldRenderer()
        renderer.onObjectTap = { _ in taps += 1 }
        renderer.tick(FieldModel())
        assertObjectsRoute(renderer.root, "Electric Fields", taps: { taps })
    }

    // MARK: The primitives it named late

    func testBloomPetalsAndBeadCanBeOperatedWithoutHands() {
        var fired = 0
        var value = 5.0
        let bloom = Bloom()
        bloom.configure(
            petals: [.init(name: "Delete", symbol: "trash", tint: .white,
                           action: { fired += 1 })],
            grip: .init(name: "Mass", range: 1...9,
                        read: { value }, write: { value = $0 },
                        format: { "\(Int($0)) kg" }, radius: { 0.05 }))
        for _ in 0..<80 {
            bloom.update(anchor: .zero, viewer: [0, 0, 1], revealTarget: 1, dt: 1 / 90)
        }
        assertOperable(bloom.root, "Bloom")

        // The bead is the app's only adjustable, so it is the one place
        // increment has to actually move a number.
        let bead = bloom.root.children.first { $0.name == "bloom-grip" }
        XCTAssertTrue(SpatialActions.adjust(bead ?? Entity(), by: 1))
        XCTAssertEqual(value, 5.4, accuracy: 1e-9)
        XCTAssertTrue(SpatialActions.adjust(bead ?? Entity(), by: -3))
        XCTAssertEqual(value, 4.2, accuracy: 1e-9)
        // …and must stop at the ends rather than running past them.
        for _ in 0..<50 { SpatialActions.adjust(bead ?? Entity(), by: -1) }
        XCTAssertEqual(value, 1.0, accuracy: 1e-9)
    }

    /// A `confirms` petal takes two presses however it is pressed: its
    /// glass button runs the ring's own arm-then-fire path.
    func testAConfirmingPetalStillConfirmsForVoiceOver() throws {
        var fired = 0
        let bloom = Bloom()
        bloom.configure(
            petals: [.init(name: "Clear", symbol: "trash", tint: .white,
                           confirms: true, action: { fired += 1 })],
            grip: nil)
        for _ in 0..<80 {
            bloom.update(anchor: .zero, viewer: [0, 0, 1], revealTarget: 1, dt: 1 / 90)
        }
        let petal = try XCTUnwrap(bloom.root.children.first { $0.name == "bloom-Clear" })
        XCTAssertNil(petal.components[SpatialActionComponent.self])
        XCTAssertTrue(bloom.handleTap(petal))
        XCTAssertEqual(fired, 0, "one press fired a destructive petal")
        XCTAssertEqual(bloom.control(named: "Clear")?.isArmed, true)
        XCTAssertTrue(bloom.handleTap(petal))
        XCTAssertEqual(fired, 1)
    }

    func testPickerDiscsCanBeOperatedWithoutHands() throws {
        var chosen: String?
        var selection = "a"
        let picker = SpatialPicker(
            accessibilityNoun: "World",
            choices: [.init(id: "a", label: "Earth", symbol: "globe"),
                      .init(id: "b", label: "Mars", symbol: "globe")])
        picker.selectedID = { selection }
        picker.onSelect = { chosen = $0 }
        picker.open()
        for _ in 0..<80 { picker.update(anchor: .zero, viewer: [0, 0, 1], dt: 1 / 90) }
        assertOperable(picker.root, "SpatialPicker")
        XCTAssertEqual(picker.control(for: "a")?.isOn, true)

        // The current choice follows the model, not the last press.
        selection = "b"
        for _ in 0..<4 { picker.update(anchor: .zero, viewer: [0, 0, 1], dt: 1 / 90) }
        XCTAssertEqual(picker.control(for: "a")?.isOn, false)
        XCTAssertEqual(picker.control(for: "b")?.isOn, true)
        let disc = try XCTUnwrap(picker.root.children.first { $0.name == "picker-a" })
        XCTAssertTrue(ControlAttachment.isControl(disc))
        XCTAssertTrue(picker.handleTap(disc))
        XCTAssertEqual(chosen, "a")
    }

}
