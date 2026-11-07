//
//  RoomSensingTests.swift
//  PhysicsPlaygroundTests
//
//  What the wearer is told when a permission is refused (2026-11-07).
//  `RoomModel.retain()` once set `.denied` only when no provider was left
//  to run — and `WorldTrackingProvider` needs no permission, so on a device
//  the list was never empty and a refused room was never reported: the
//  title bar's triangle, promised by SUPPORT.md, could not appear.
//

import ARKit
import XCTest
@testable import PhysicsPlayground

@MainActor
final class RoomSensingTests: XCTestCase {

    /// The room refused is the refusal the wearer notices, whatever else
    /// was granted.
    func testARefusedRoomIsReported() {
        XCTAssertEqual(RoomModel.Sensing.verdict(denied: [.worldSensing]), .denied)
        XCTAssertEqual(RoomModel.Sensing.verdict(denied: [.worldSensing, .handTracking]), .denied)
    }

    /// Hands refused alone changes nothing a warning could help with:
    /// grabs are the system's gestures.
    func testHandsRefusedAloneIsNotAWarning() {
        XCTAssertEqual(RoomModel.Sensing.verdict(denied: [.handTracking]), .fine)
        XCTAssertEqual(RoomModel.Sensing.verdict(denied: []), .fine)
    }

    /// The refused room's sentence names its remedy, and the remedy is
    /// a button beside it (`OpenSettingsButton`).
    func testTheRefusalNamesTheSettingsPath() {
        XCTAssertTrue(RoomModel.Sensing.denied.detail.contains("Settings"))
        XCTAssertTrue(RoomModel.Sensing.denied.detail.contains("World Sensing"))
    }
}
