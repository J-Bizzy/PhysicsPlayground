//
//  StarCatalogTests.swift
//  The bundled catalogue's codec: a round trip at the stored precision,
//  and a refusal of anything that is not one.
//

import XCTest
@testable import PhysicsCore

final class StarCatalogTests: XCTestCase {

    private let sirius = CatalogStar(hr: 2491, rightAscension: 1.767793, declination: -0.291751,
                                     magnitude: -1.46, colourIndex: 0.00)
    private let estimated = CatalogStar(hr: 9110, rightAscension: 6.2, declination: 1.1,
                                        magnitude: 6.37, colourIndex: 1.234, colourEstimated: true)

    func testARoundTripKeepsEveryFieldAtItsPrecision() throws {
        let data = StarCatalog.encode([sirius, estimated])
        XCTAssertEqual(data.count, 10 + 2 * 16)
        let back = try StarCatalog.decode(data)
        XCTAssertEqual(back.count, 2)
        for (a, b) in zip(back, [sirius, estimated]) {
            XCTAssertEqual(a.hr, b.hr)
            XCTAssertEqual(a.rightAscension, b.rightAscension, accuracy: 1e-6)
            XCTAssertEqual(a.declination, b.declination, accuracy: 1e-6)
            XCTAssertEqual(a.magnitude, b.magnitude, accuracy: 0.005)
            XCTAssertEqual(a.colourIndex, b.colourIndex, accuracy: 0.0005)
            XCTAssertEqual(a.colourEstimated, b.colourEstimated)
        }
    }

    func testAnythingElseIsRefused() {
        var data = StarCatalog.encode([sirius])
        data[0] = UInt8(ascii: "X")
        XCTAssertThrowsError(try StarCatalog.decode(data)) {
            XCTAssertEqual($0 as? StarCatalog.DecodeError, .badMagic)
        }
        let truncated = StarCatalog.encode([sirius]).dropLast(3)
        XCTAssertThrowsError(try StarCatalog.decode(Data(truncated))) {
            XCTAssertEqual($0 as? StarCatalog.DecodeError, .truncated)
        }
        var future = StarCatalog.encode([sirius])
        future[4] = 9
        XCTAssertThrowsError(try StarCatalog.decode(future)) {
            XCTAssertEqual($0 as? StarCatalog.DecodeError, .unsupportedVersion(9))
        }
    }
}
