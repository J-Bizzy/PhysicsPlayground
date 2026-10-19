//
//  StarCatalog.swift
//  PhysicsCore — Astronomy
//
//  The naked-eye sky as the app carries it: the Yale Bright Star
//  Catalogue (5th revised edition, Hoffleit & Warren 1991 — public domain),
//  reduced by `Tools/starcatalog.py` to the five numbers a drawn star needs
//  and packed in a compact little-endian binary:
//
//      "BSC5"  u16 version  u32 count
//      count × 16 bytes:
//          u16 HR number   u8 flags (bit 0: B−V estimated)   u8 pad
//          f32 RA (rad, J2000)   f32 Dec (rad, J2000)
//          i16 V (centimag)   i16 B−V (millimag)
//

import Foundation

/// One star as drawn.
public struct CatalogStar: Sendable, Equatable {
    /// The Bright Star (Harvard Revised) number.
    public var hr: Int
    /// Right ascension and declination, radians, J2000.
    public var rightAscension: Double
    public var declination: Double
    /// Visual magnitude, V.
    public var magnitude: Double
    /// The B−V colour index, magnitudes.
    public var colourIndex: Double
    /// Whether B−V was estimated from the spectral type (the catalogue
    /// gives none for a few hundred stars).
    public var colourEstimated: Bool

    public init(hr: Int, rightAscension: Double, declination: Double,
                magnitude: Double, colourIndex: Double, colourEstimated: Bool = false) {
        self.hr = hr
        self.rightAscension = rightAscension
        self.declination = declination
        self.magnitude = magnitude
        self.colourIndex = colourIndex
        self.colourEstimated = colourEstimated
    }
}

public enum StarCatalog {
    public static let magic = Array("BSC5".utf8)
    public static let version: UInt16 = 1
    static let headerSize = 10
    static let recordSize = 16

    public enum DecodeError: Error, Equatable {
        case badMagic, unsupportedVersion(UInt16), truncated
    }

    public static func encode(_ stars: [CatalogStar]) -> Data {
        var data = Data(magic)
        append(version, to: &data)
        append(UInt32(stars.count), to: &data)
        for star in stars {
            append(UInt16(clamping: star.hr), to: &data)
            data.append(star.colourEstimated ? 1 : 0)
            data.append(0)
            append(Float(star.rightAscension).bitPattern, to: &data)
            append(Float(star.declination).bitPattern, to: &data)
            append(UInt16(bitPattern: Int16(clamping: Int((star.magnitude * 100).rounded()))), to: &data)
            append(UInt16(bitPattern: Int16(clamping: Int((star.colourIndex * 1000).rounded()))), to: &data)
        }
        return data
    }

    public static func decode(_ data: Data) throws -> [CatalogStar] {
        let bytes = [UInt8](data)
        guard bytes.count >= headerSize else { throw DecodeError.truncated }
        guard Array(bytes[0..<4]) == magic else { throw DecodeError.badMagic }
        let version = UInt16(bytes[4]) | UInt16(bytes[5]) << 8
        guard version == Self.version else { throw DecodeError.unsupportedVersion(version) }
        let count = Int(read32(bytes, 6))
        guard bytes.count >= headerSize + count * recordSize else { throw DecodeError.truncated }
        var stars: [CatalogStar] = []
        stars.reserveCapacity(count)
        for index in 0..<count {
            let o = headerSize + index * recordSize
            let hr = Int(UInt16(bytes[o]) | UInt16(bytes[o + 1]) << 8)
            let flags = bytes[o + 2]
            let ra = Double(Float(bitPattern: read32(bytes, o + 4)))
            let dec = Double(Float(bitPattern: read32(bytes, o + 8)))
            let v = Int16(bitPattern: UInt16(bytes[o + 12]) | UInt16(bytes[o + 13]) << 8)
            let bv = Int16(bitPattern: UInt16(bytes[o + 14]) | UInt16(bytes[o + 15]) << 8)
            stars.append(CatalogStar(hr: hr, rightAscension: ra, declination: dec,
                                     magnitude: Double(v) / 100, colourIndex: Double(bv) / 1000,
                                     colourEstimated: flags & 1 == 1))
        }
        return stars
    }

    private static func append(_ value: UInt16, to data: inout Data) {
        data.append(UInt8(value & 0xFF))
        data.append(UInt8(value >> 8))
    }

    private static func append(_ value: UInt32, to data: inout Data) {
        for shift in stride(from: 0, to: 32, by: 8) { data.append(UInt8((value >> UInt32(shift)) & 0xFF)) }
    }

    private static func read32(_ bytes: [UInt8], _ o: Int) -> UInt32 {
        UInt32(bytes[o]) | UInt32(bytes[o + 1]) << 8 | UInt32(bytes[o + 2]) << 16 | UInt32(bytes[o + 3]) << 24
    }
}
