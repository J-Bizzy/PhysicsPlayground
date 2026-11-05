//
//  ControlLanguageCriterionTests.swift
//  PhysicsPlaygroundTests
//
//  One control language (2026-10-14). Every control the app draws is
//  the family in `RenderKit/Controls` — `ControlButton`, `ControlToggle`,
//  `ControlSlider`, `ControlSegments`, `ControlMenu`, `MoreButton` —
//  whether it stands in a window or in
//  the room. Fourteen ways to draw a control grew one feature at a time;
//  this keeps a fifteenth from starting.
//

import XCTest
import RealityKit
import RenderKit
@testable import PhysicsPlayground

@MainActor
final class ControlLanguageCriterionTests: XCTestCase {

    // MARK: The app builds no control of its own

    /// Constructions that mean "a control drawn its own way". The family
    /// itself lives in RenderKit, outside the scanned tree. A system
    /// dialog's `Button` is the system's, so `Button(` stays allowed.
    private static let banned = [
        "ButtonStyle {", "ButtonStyle(", ".buttonStyle(", ".toggleStyle(",
        "Slider(", "Toggle(", "Stepper(", "Picker(",
    ]

    /// `banned` as whole words: `ControlToggle(` is the family, `Toggle(`
    /// is not.
    private static let patterns: [(String, NSRegularExpression)] = banned.map { name in
        let escaped = NSRegularExpression.escapedPattern(for: name)
        // swiftlint:disable:next force_try
        return (name, try! NSRegularExpression(pattern: "(?<![A-Za-z])" + escaped))
    }

    func testTheAppDrawsNoControlOutsideTheFamily() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("PhysicsPlayground")
        guard let walker = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: nil) else {
            return XCTFail("cannot walk \(root.path)")
        }
        var scanned = 0
        var offenders: [String] = []
        for case let url as URL in walker where url.pathExtension == "swift" {
            scanned += 1
            let text = try String(contentsOf: url, encoding: .utf8)
            for (number, line) in text.split(separator: "\n",
                                             omittingEmptySubsequences: false)
                .enumerated() {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard !trimmed.hasPrefix("//") else { continue }
                let range = NSRange(trimmed.startIndex..., in: trimmed)
                for (name, pattern) in Self.patterns
                where pattern.firstMatch(in: trimmed, range: range) != nil {
                    offenders.append("\(url.lastPathComponent):\(number + 1) `\(name)`")
                }
            }
        }
        XCTAssertGreaterThan(scanned, 50, "the scan read almost nothing — a moved tree passes vacuously")
        XCTAssertTrue(offenders.isEmpty, """
            these lines draw a control outside the one family:
            \(offenders.joined(separator: "\n"))
            Use ControlButton, ControlToggle, ControlSlider, ControlSegments, \
            ControlMenu or MoreButton \
            (RenderKit/Controls). If the family cannot say what you need, \
            grow the family — do not start a second language.
            """)
    }

    // MARK: Every control in the room is the family's

    /// An action plate, a picker choice, a petal: each is an entity
    /// carrying the family's SwiftUI view. No mesh of its own, no collider
    /// of its own — the glass is the target, so nothing invisible stands
    /// in front of the apparatus.
    func testEveryRoomControlIsTheFamilysView() {
        let actions = SpatialActionBank(accent: .white, actions: [
            SpatialAction(id: "clear", label: "Clear", symbol: "trash",
                          confirms: true, fire: {}),
        ])
        let picker = SpatialPicker(accessibilityNoun: "World", choices: [
            PickerChoice(id: "moon", label: "Moon", symbol: "moon"),
        ], staysOpen: true)
        let bloom = Bloom()
        bloom.configure(petals: [
            Bloom.Petal(name: "Delete", symbol: "trash",
                        tint: DesignTokens.Palette.destructiveUI) {},
        ], grip: nil)

        let controls: [(String, Entity)] = [
            ("action plate", actions.root.children.first!),
            ("picker choice", picker.root.children.first!),
            ("petal", bloom.root.children.first { $0.name == "bloom-Delete" }!),
        ]
        for (what, entity) in controls {
            XCTAssertTrue(ControlAttachment.isControl(entity),
                          "the \(what) is not drawn by the control family")
            XCTAssertNil(entity.components[CollisionComponent.self],
                         "the \(what) carries a collider of its own; the glass is the target")
            XCTAssertNil(entity.components[ModelComponent.self],
                         "the \(what) still builds a mesh of its own")
        }
    }

    /// The rail is the family's slider on its own glass.
    func testTheRoomSliderIsTheFamilysView() {
        var value = 0.5
        let track = SpatialTrackControl(
            name: "g", center: .zero, normal: [0, 0, 1], accent: .white,
            range: 0...1, read: { value }, write: { value = $0 },
            format: { "\($0)" })
        XCTAssertTrue(track.root.children.contains(where: ControlAttachment.isControl),
                      "the slider is not drawn by the control family")
        XCTAssertNil(track.root.components[CollisionComponent.self])
    }

    // MARK: The glow means live

    /// The one glow appears on what is held and leaves when it is let go —
    /// and a tracker never leaves two things glowing.
    func testTheLiveGlowFollowsTheHand() {
        let first = ModelEntity(mesh: Primitives.sphere(radius: 0.05))
        let second = ModelEntity(mesh: Primitives.sphere(radius: 0.05))
        let tracker = LiveGlowTracker()

        tracker.update(first)
        XCTAssertTrue(LiveGlow.isLive(first))
        tracker.update(second)
        XCTAssertFalse(LiveGlow.isLive(first), "the glow stayed on what was let go")
        XCTAssertTrue(LiveGlow.isLive(second))
        tracker.update(nil)
        XCTAssertFalse(LiveGlow.isLive(second))
    }

    /// The aura is light, never a target.
    func testTheLiveGlowIsNeverATarget() throws {
        let body = ModelEntity(mesh: Primitives.sphere(radius: 0.05))
        LiveGlow.set(true, on: body)
        let aura = try XCTUnwrap(body.children.first { $0.name == LiveGlow.auraName })
        XCTAssertNil(aura.components[CollisionComponent.self])
        XCTAssertNil(aura.components[InputTargetComponent.self])
        XCTAssertNil(aura.components[HoverEffectComponent.self])
    }
}
