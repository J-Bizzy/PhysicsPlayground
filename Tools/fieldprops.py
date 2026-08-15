#!/usr/bin/env python3
"""
Electric Fields' capacitor apparatus, milled rather than generated.

    /Applications/Blender.app/Contents/MacOS/Blender --background \
        --python Tools/fieldprops.py

Outputs, under PhysicsPlayground/Models/Electromagnetism/:
    CapacitorPlate.usdz    one machined plate: chamfered square, corner
                           bosses and a corona-ball terminal on its back
    SlabHandle.usdz        the brass T-handle the dielectric slab is
                           slid by

WHAT IS AND IS NOT MODELED

The PLATES are rigid and never deform — the textbook case for a baked
asset. The DIELECTRIC SLAB is deliberately NOT here: it stretches with
the gap (x scale runs ~0.3–2.3× as a hand pulls the plates), and a baked
chamfer or a moulded glyph distorts visibly under non-uniform scale, so
the slab stays a procedural rounded box in `FieldRenderer` and only its
fixed-size HANDLE is milled.

ORIENTATION. The plate's thickness runs along Blender X (RealityKit X —
the gap axis); its back furniture (bosses, terminal) sits on the −x
face. The + plate uses the asset as authored; the − plate turns π about
Y so its furniture faces outward too. The handle's stem runs along
Blender +Y, which the export maps to RealityKit −Z — out of the gap,
toward the reader.

COLOUR IS SWIFT'S, as everywhere: one mesh per asset, named for its
role ("Plate", "Handle"), painted by the renderer so the +/− accents
stay `DesignTokens.Palette`'s to decide.
"""

import os
import sys

sys.dont_write_bytecode = True
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import math  # noqa: E402
from blenderprops import (reset_scene, material, shade, bevel, box,  # noqa: E402
                          cylinder, join, export)

ROOT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                    "PhysicsPlayground", "Models", "Electromagnetism")

PLATE_SIZE = 0.5
PLATE_THICKNESS = 0.018


def build_plate():
    steel = material("PlatePreview", (0.55, 0.56, 0.58), roughness=0.3,
                     metallic=0.9)

    parts = []
    slab = box("Face", (PLATE_THICKNESS, PLATE_SIZE, PLATE_SIZE))
    bevel(slab, 0.005, segments=2)
    parts.append(shade(slab, steel))

    back = -PLATE_THICKNESS / 2
    # Corner bosses — the standoffs a bench plate mounts by.
    for sy in (-1, 1):
        for sz in (-1, 1):
            boss = cylinder("Boss", 0.020, 0.014,
                            location=(back - 0.007,
                                      sy * PLATE_SIZE * 0.42,
                                      sz * PLATE_SIZE * 0.42),
                            rotation=(0, math.radians(90), 0), vertices=24)
            parts.append(shade(boss, steel))

    # The high-voltage terminal: stem out the back, corona ball on top —
    # a ball, because at bench kilovolts anything pointed would leak.
    stem = cylinder("Stem", 0.009, 0.05,
                    location=(back - 0.025, 0, 0),
                    rotation=(0, math.radians(90), 0), vertices=24)
    parts.append(shade(stem, steel))
    import bpy
    bpy.ops.mesh.primitive_uv_sphere_add(radius=0.024,
                                         location=(back - 0.056, 0, 0),
                                         segments=32, ring_count=16)
    ball = bpy.context.active_object
    ball.name = "Corona"
    for polygon in ball.data.polygons:
        polygon.use_smooth = True
    parts.append(shade(ball, steel))

    plate = join("Plate", parts)
    plate.data.name = "Plate"
    return plate


def build_handle():
    brass = material("HandlePreview", (0.58, 0.44, 0.16), roughness=0.26,
                     metallic=0.92)

    parts = []
    stem = cylinder("Stem", 0.007, 0.055, location=(0, 0.0275, 0),
                    rotation=(math.radians(90), 0, 0), vertices=24)
    parts.append(shade(stem, brass))
    bar = cylinder("Bar", 0.009, 0.10, location=(0, 0.055, 0),
                   rotation=(0, math.radians(90), 0), vertices=24)
    bevel(bar, 0.002, segments=2, angle=50)
    parts.append(shade(bar, brass))
    foot = cylinder("Foot", 0.016, 0.006, location=(0, 0.003, 0),
                    rotation=(math.radians(90), 0, 0), vertices=24)
    parts.append(shade(foot, brass))

    handle = join("Handle", parts)
    handle.data.name = "Handle"
    return handle


def main():
    reset_scene()
    export([build_plate()], os.path.join(ROOT, "CapacitorPlate.usdz"))

    reset_scene()
    export([build_handle()], os.path.join(ROOT, "SlabHandle.usdz"))


if __name__ == "__main__":
    main()
