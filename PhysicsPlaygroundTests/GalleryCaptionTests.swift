//
//  GalleryCaptionTests.swift
//  PhysicsPlaygroundTests
//
//  The promise is spoken, not drawn: `HubDomain.promise` is the
//  VoiceOver label of the exhibit and the spoken hint of the catalog
//  row. What is left to assert is that every lab has a line to speak.
//

import XCTest
@testable import PhysicsPlayground

@MainActor
final class GalleryCaptionTests: XCTestCase {

    /// Every lab has one; an empty string is a lab VoiceOver describes as
    /// nothing.
    func testEveryLabPromisesSomething() {
        for module in ModuleCatalog.all(appModel: AppModel()) {
            let promise = HubDomain.promise(for: module.id)
            XCTAssertFalse(promise.isEmpty,
                           "\(module.id) has no promise line to speak")
        }
    }
}
