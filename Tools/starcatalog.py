#!/usr/bin/env python3
"""
The naked-eye sky for Physics Playground: the Yale Bright Star Catalogue,
5th Revised Edition (Hoffleit & Warren 1991; CDS/VizieR V/50, public
domain), reduced to what a drawn star needs.

    python3 -I Tools/starcatalog.py <dir>/catalog.gz \\
        PhysicsPlayground/Sky/BrightStarCatalog.bin

Input:  catalog.gz from https://cdsarc.cds.unistra.fr/ftp/V/50/ (573,921
        bytes; SHA-256 3dc44b1e90be8fbe5bcc7656032560f51275f985c7e3f783c9028e1838ec7bed
        as downloaded on 2026-10-19). Fixed-width, 197 bytes a line; the
        byte layout is the catalogue's own ReadMe.
Output: the compact binary `PhysicsCore.StarCatalog` decodes:

    "BSC5"  u16 version (1)  u32 count
    count x 16 bytes, little-endian:
        u16 HR   u8 flags (bit 0: B-V estimated)   u8 pad
        f32 RA (rad, J2000)   f32 Dec (rad, J2000)
        i16 V (centimag)   i16 B-V (millimag)

Only the converted file and this script are committed, never the raw
catalogue. The 14 entries removed from the catalogue (novae, clusters and
the like; their positions are blank) are skipped. A star with no B-V gets
one estimated from its spectral type's main-sequence colour, and is
flagged as estimated.
"""

import gzip
import hashlib
import math
import struct
import sys

# Main-sequence B-V by spectral class at subclasses 0 and 5 (Johnson;
# Schmidt-Kaler 1982, rounded), for the stars the catalogue gives no colour.
CLASS_COLOUR = {
    "O": (-0.32, -0.32), "B": (-0.30, -0.17), "A": (0.00, 0.15),
    "F": (0.30, 0.44), "G": (0.58, 0.68), "K": (0.81, 1.15),
    "M": (1.40, 1.64), "C": (2.0, 2.4), "N": (2.0, 2.4), "R": (1.0, 1.5), "S": (1.6, 1.9),
}
ORDER = "OBAFGKM"


def field(line, start, end):
    """Bytes start..end, 1-based and inclusive as the ReadMe numbers them."""
    return line[start - 1:end].strip()


def estimated_colour(spectral):
    """B-V from a spectral type such as 'K0III' or 'B9.5V', or None."""
    spectral = spectral.lstrip("gdcskm")  # luminosity prefixes the catalogue uses
    if not spectral:
        return None
    letter = spectral[0]
    if letter not in CLASS_COLOUR:
        return None
    digits = ""
    for ch in spectral[1:]:
        if ch.isdigit() or (ch == "." and digits):
            digits += ch
        else:
            break
    sub = float(digits) if digits else 5.0
    zero, five = CLASS_COLOUR[letter]
    if sub <= 5:
        return zero + (five - zero) * sub / 5
    # Past subclass 5, run on toward the next class's subclass 0.
    if letter in ORDER and ORDER.index(letter) + 1 < len(ORDER):
        nxt = CLASS_COLOUR[ORDER[ORDER.index(letter) + 1]][0]
        return five + (nxt - five) * (sub - 5) / 5
    return five


def main():
    source, destination = sys.argv[1], sys.argv[2]
    raw = open(source, "rb").read()
    digest = hashlib.sha256(raw).hexdigest()
    lines = gzip.decompress(raw).decode("latin-1").splitlines()

    stars = []
    skipped = 0
    estimated = 0
    for line in lines:
        line = line.ljust(197)
        hr = field(line, 1, 4)
        rah, ram, ras = field(line, 76, 77), field(line, 78, 79), field(line, 80, 83)
        sign, ded, dem, des = field(line, 84, 84), field(line, 85, 86), field(line, 87, 88), field(line, 89, 90)
        vmag = field(line, 103, 107)
        if not hr or not rah or not ded or not vmag:
            skipped += 1
            continue
        ra = (int(rah) + int(ram) / 60 + float(ras) / 3600) * 15
        dec = int(ded) + int(dem) / 60 + int(des) / 3600
        if sign == "-":
            dec = -dec
        bv_text = field(line, 110, 114)
        flags = 0
        if bv_text:
            bv = float(bv_text)
        else:
            bv = estimated_colour(field(line, 128, 147))
            if bv is None:
                bv = 0.6
            flags |= 1
            estimated += 1
        stars.append((int(hr), flags, math.radians(ra), math.radians(dec),
                      round(float(vmag) * 100), round(bv * 1000)))

    with open(destination, "wb") as out:
        out.write(struct.pack("<4sHI", b"BSC5", 1, len(stars)))
        for hr, flags, ra, dec, v, bv in stars:
            out.write(struct.pack("<HBBffhh", hr, flags, 0, ra, dec, v, bv))

    print(f"input SHA-256 {digest}")
    print(f"{len(stars)} stars written, {skipped} skipped, {estimated} colours estimated")
    print(f"{destination}: {10 + 16 * len(stars)} bytes")


if __name__ == "__main__":
    main()
