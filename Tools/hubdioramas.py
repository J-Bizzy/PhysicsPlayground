#!/usr/bin/env python3
"""
The home's dioramas: the stage every lab stands on in its portal, and the
one apparatus the labs do not already mill — the cradle's frame.

    /Applications/Blender.app/Contents/MacOS/Blender -b -noaudio \\
        --python Tools/hubdioramas.py [-- HubStage HubCradle]

Writes, under PhysicsPlayground/Models/Hub/:

    HubStage.usdz     the plinth: a miniature of Circuit Workshop's
                      turntable (`circuitparts.py`) — a satin graphite deck
                      with a champagne keyline, in a knurled champagne rim,
                      on a set-back foot
    HubCradle.usdz    Newton's cradle's frame: two bent champagne tubes on
                      turned feet, the balls' rails at their tops

WHY A STAGE. Seven labs drawn seven ways read as seven pictures; the same
plinth under each, the same size in every portal, makes them one set — a
row of exhibits, each standing on its own disc. Since 2026-10-19 nothing
frames them (the glass circles and their champagne rings are gone, owner's
call), so the plinth is the exhibit's whole base and is milled as the
turntable the owner chose for Circuit Workshop: the same satin deck, the
same knurled rim, at a sixth of the size — the home stands each lab on the
thing the labs are handled on. House alloys only (`pickupcoil.py`'s
stocks): graphite, champagne metal, nothing else.

THE CONTRACT WITH `HubVignettes`. Diorama space is metres, y up, the
stage's TOP face at y = 0 and its centre on the axis; `STAGE_RADIUS` is
what the Swift side scales every lab's stage to. The cradle's rails run
along x at `RAIL_HEIGHT` above the stage, at z = ±`RAIL_OFFSET`; the five
balls hang between them on threads Swift draws. `VignettePropTests`
measures both files against these numbers.

HANDEDNESS. Blender (x, y, z) -> RealityKit (x, z, -y): up is Blender +Z.
"""

import math
import os
import sys

sys.dont_write_bytecode = True
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import bpy  # noqa: E402
from blenderprops import band, bevel, box, cylinder, export, join, material, reset_scene, shade, tube  # noqa: E402

ROOT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                    "PhysicsPlayground", "Models", "Hub")

# The stage, metres of diorama space (the home draws it 1.6 times this:
# `PortalLayout.plinthRadius` over `HubVignettes.stageRadius`).
STAGE_RADIUS = 0.100
STAGE_THICKNESS = 0.010
FOOT_HEIGHT = 0.003
RIM_DEPTH = 0.005            # the knurled band's own radial width
# Fine, and shallower than the band: at 0.014 thick with 144 full-height
# ridges the first still read as a gear's teeth, not a knurl.
KNURLS = 240

# The cradle's frame, metres, on the stage's top face.
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
        # The turntable's satin deck: a glossy coat at a grazing angle
        # mirrors the room and reads as a pale slab.
        "satin": coat(material("StageSatinGraphite", (0.070, 0.072, 0.078),
                               roughness=0.55, metallic=0.05), 0.15, 0.45),
    }


def build_stage(s):
    parts = []
    deck_radius = STAGE_RADIUS - RIM_DEPTH
    # The deck, its top at z = 0. Flat-shaded, as the turntable's is:
    # smoothing blends the bevel's side normals across the cap.
    deck = cylinder("StageDeck", deck_radius, STAGE_THICKNESS,
                    location=(0, 0, -STAGE_THICKNESS / 2), vertices=160)
    bevel(deck, 0.0010, segments=3)
    parts.append(shade(deck, s["satin"], smooth=False))
    # The keyline, eight millimetres in: the milled edge every stage wears.
    key = band("StageKeyline", deck_radius - 0.008, deck_radius - 0.0092, 0.0006,
               location=(0, 0, 0.0002), vertices=160)
    parts.append(shade(key, s["champagne"]))
    # The rim: a champagne band round the deck, a hair proud of it, and
    # knurled — the turntable's "this turns", which the home's slow sway
    # shows it does.
    ring = band("StageRim", STAGE_RADIUS - 0.0008, deck_radius, STAGE_THICKNESS + 0.0004,
                location=(0, 0, -STAGE_THICKNESS / 2 + 0.0002), vertices=160)
    bevel(ring, 0.0006, segments=2)
    parts.append(shade(ring, s["champagne"]))
    for index in range(KNURLS):
        angle = 2 * math.pi * index / KNURLS
        ridge = box("StageKnurl", (0.0014, 0.0008, STAGE_THICKNESS - 0.004),
                    location=((STAGE_RADIUS - 0.0004) * math.cos(angle),
                              (STAGE_RADIUS - 0.0004) * math.sin(angle),
                              -STAGE_THICKNESS / 2))
        ridge.rotation_euler = (0, 0, angle + math.pi / 2)
        parts.append(shade(ridge, s["champagne"], smooth=False))
    # The foot, set back under the deck so its edge floats over a shadow line.
    foot = band("StageFoot", STAGE_RADIUS - 0.022, STAGE_RADIUS - 0.032, FOOT_HEIGHT,
                location=(0, 0, -STAGE_THICKNESS - FOOT_HEIGHT / 2), vertices=160)
    bevel(foot, 0.0006, segments=2)
    parts.append(shade(foot, s["champagne"]))
    return join("HubStage", parts)


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


BUILDERS = {"HubStage": build_stage, "HubCradle": build_cradle}


def main():
    # `-- HubStage` mills only that; none, both.
    wanted = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else list(BUILDERS)
    for name in wanted:
        reset_scene()
        built = BUILDERS[name](stocks())
        export([built], os.path.join(ROOT, f"{name}.usdz"))
        print(f"  {name} verts", len(built.data.vertices))


if __name__ == "__main__":
    main()
