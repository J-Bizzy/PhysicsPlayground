#!/usr/bin/env python3
"""
The home's dioramas: the one apparatus the labs do not already mill — the
cradle's frame.

    /Applications/Blender.app/Contents/MacOS/Blender -b -noaudio \\
        --python Tools/hubdioramas.py [-- HubCradle]

Writes, under PhysicsPlayground/Models/Hub/:

    HubCradle.usdz    Newton's cradle's frame: two bent champagne tubes on
                      turned feet, the balls' rails at their tops

It milled HubStage.usdz too until 2026-10-21 — the plinth each lab stood on
in the home, a miniature of Circuit Workshop's turntable. The labs float
now (owner's call); `build_stage` is in the git history.

THE CONTRACT WITH `HubVignettes`. Diorama space is metres, y up, the
stage — where a lab stands, nothing drawn — at y = 0 and its centre on the
axis. The cradle's rails run along x at `RAIL_HEIGHT` above it, at
z = ±`RAIL_OFFSET`; the five balls hang between them on threads Swift
draws. `VignettePropTests` measures the file against these numbers.

HANDEDNESS. Blender (x, y, z) -> RealityKit (x, z, -y): up is Blender +Z.
"""

import math
import os
import sys

sys.dont_write_bytecode = True
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import bpy  # noqa: E402
from blenderprops import bevel, cylinder, export, join, material, reset_scene, shade, tube  # noqa: E402

ROOT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                    "PhysicsPlayground", "Models", "Hub")

# The cradle's frame, metres, above the stage.
RAIL_HEIGHT = 0.118
RAIL_OFFSET = 0.026          # each rail's distance from the swing plane
RAIL_HALF = 0.091            # half the rail's length along x: the end ball's
                             # 0.55 rad swing clears the legs
FOOT = 0.005                 # the turned feet's radius
TUBE = 0.0024                # the frame's tube radius
BEND = 0.014                 # the radius of each top corner


def coat(mat, weight, roughness):
    bsdf = mat.node_tree.nodes["Principled BSDF"]
    for key, value in (("Coat Weight", weight), ("Clearcoat", weight),
                       ("Coat Roughness", roughness),
                       ("Clearcoat Roughness", roughness)):
        if key in bsdf.inputs:
            bsdf.inputs[key].default_value = value
    return mat


def stocks():
    """The house alloys, as `pickupcoil.py` mills them."""
    return {
        "graphite": coat(material("StageGraphite", (0.088, 0.090, 0.096),
                                  roughness=0.30, metallic=0.10), 0.60, 0.25),
        "champagne": material("StageChampagne", (0.83, 0.70, 0.45), roughness=0.28, metallic=0.9),
    }


def bent_frame(y):
    """One side of the frame: up from a foot, round a corner, along the
    rail, round the other corner and down — one continuous tube."""
    points = []
    foot_z = 0.004
    top = RAIL_HEIGHT
    # Left leg up to where the bend starts.
    points.append((-RAIL_HALF, y, foot_z))
    points.append((-RAIL_HALF, y, top - BEND))
    for step in range(1, 12):
        a = math.pi - step / 12 * (math.pi / 2)
        points.append((-RAIL_HALF + BEND + BEND * math.cos(a), y, top - BEND + BEND * math.sin(a)))
    points.append((-RAIL_HALF + BEND, y, top))
    points.append((RAIL_HALF - BEND, y, top))
    for step in range(1, 12):
        a = math.pi / 2 - step / 12 * (math.pi / 2)
        points.append((RAIL_HALF - BEND + BEND * math.cos(a), y, top - BEND + BEND * math.sin(a)))
    points.append((RAIL_HALF, y, top - BEND))
    points.append((RAIL_HALF, y, foot_z))
    return points


def build_cradle(s):
    parts = []
    for side in (-1, 1):
        y = side * RAIL_OFFSET
        parts.append(tube("CradleFrame", bent_frame(y), TUBE, s["champagne"]))
        for x in (-RAIL_HALF, RAIL_HALF):
            foot = cylinder("CradleFoot", FOOT, 0.004, location=(x, y, 0.002), vertices=32)
            bevel(foot, 0.0012, segments=3)
            parts.append(shade(foot, s["graphite"]))
    return join("HubCradle", parts)


BUILDERS = {"HubCradle": build_cradle}


def main():
    # `-- HubCradle` mills only that; none, everything.
    wanted = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else list(BUILDERS)
    for name in wanted:
        reset_scene()
        built = BUILDERS[name](stocks())
        export([built], os.path.join(ROOT, f"{name}.usdz"))
        print(f"  {name} verts", len(built.data.vertices))


if __name__ == "__main__":
    main()
