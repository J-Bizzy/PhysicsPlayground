#!/usr/bin/env python3
"""
Builds the parts shelf's crown — the knurled wheel that scrolls Circuit
Workshop's parts column — and writes it as USDZ.

    /Applications/Blender.app/Contents/MacOS/Blender --background \
        --python Tools/shelfcrown.py

Output:
    PhysicsPlayground/Models/Shell/ShelfCrown.usdz

WHY A CROWN

The column shows six of twelve parts and the rest are a scroll away. The
first shelf scrolled by dragging anything on it, and a hand drifting
while it took a part scrolled instead of pulling; the second put a
scrollbar's thumb on a hairline track, a 1 cm sliver a metre off that
geared the strip to twice the hand. Neither was an object. A crown is:
the wheel the headset itself scrolls with, stood beside the column. Roll
it and the parts move with your finger, one to one, and it TURNS with
the column, so a crown at rest is a readout of where the shelf is — the
same law the Time Capsule's reel obeys.

WHAT IS MODELED, AND WHAT IS NOT

Only the wheel: a straight-knurled rim, a hub standing a little proud of
each face, and the axle through it. The SPINE the crown stands on and
the gap it sits in are procedural (`Well.Rack`) — they stretch to the
window's height, and an imported rail could not.

MATERIALS. Bright machined rim, dark stock hub, bright axle — no accent.
CASINGS are neutral and VALUES carry the module's colour, and a crown is
a handle. The knurl is geometry, not a texture: thirty-six ridges, each
a facet that catches the key light as the wheel turns, which is the only
thing that tells you it is turning at all when it is seen edge-on.

SIZE. 48 mm across and 14 mm wide — a thumbwheel, about the smallest
thing that reads as one and still pinches from arm's length. Its origin
is the axle's centre, so the Swift side hangs it at a point and turns it
about X without measuring anything.

AXES. Per `blenderprops`: Blender (x, y, z) -> RealityKit (x, z, -y). The
wheel's axis must run along RealityKit's X, across the shelf, so it is
built along Blender's X — every cylinder here is a default +Z primitive
rotated 90 degrees about Y.
"""

import os
import sys

# No .pyc beside the source — see the note in vignetteprops.py.
sys.dont_write_bytecode = True
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import math  # noqa: E402

import bpy  # noqa: E402
from blenderprops import (reset_scene, material, shade, bevel, cylinder,  # noqa: E402
                          join, export)

ROOT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                    "PhysicsPlayground", "Models", "Shell")

# The crown, in metres. `Well.Rack.crownRadius` and `crownWidth` repeat
# the first two; the collider and the turn are sized from them.
RIM_RADIUS = 0.024
RIM_WIDTH = 0.014
# Ridges around the rim: a 72-gon with every other vertex pulled in is
# 36 V-grooves, a straight knurl.
KNURLS = 36
KNURL_DEPTH = 0.0012
HUB_RADIUS = 0.015
# 2 mm proud of each face: the hub is what says the rim is a wheel on a
# hub rather than a slice of rod.
HUB_LENGTH = RIM_WIDTH + 0.004
AXLE_RADIUS = 0.0035
# 11 mm proud each side — it stands out of the wheel the way the reel's
# does, which is what says MOUNTED rather than floating.
AXLE_LENGTH = RIM_WIDTH + 0.022

AXIS = (0, math.pi / 2, 0)   # +Z primitive -> axis along RealityKit X


def knurl(obj, ridges, depth):
    """Pulls every other rim vertex inward. Done on the mesh data with the
    cylinder still on its natural +Z axis, where a vertex's angle is its
    sector, so the ridges land exactly on the primitive's own vertices
    and no two faces have to be split."""
    sector = 2 * math.pi / (2 * ridges)
    scale = (RIM_RADIUS - depth) / RIM_RADIUS
    for vertex in obj.data.vertices:
        x, y = vertex.co.x, vertex.co.y
        if math.hypot(x, y) < 1e-6:
            continue
        index = round(math.atan2(y, x) / sector) % (2 * ridges)
        if index % 2:
            vertex.co.x = x * scale
            vertex.co.y = y * scale
    return obj


def aligned(obj):
    """Turns a +Z primitive onto the wheel's axis and bakes it in."""
    obj.rotation_euler = AXIS
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.transform_apply(rotation=True)
    return obj


def main():
    reset_scene()

    rim_stock = material("CrownRim", (0.56, 0.57, 0.60),
                         roughness=0.30, metallic=0.92)
    hub_stock = material("CrownStock", (0.30, 0.31, 0.33),
                         roughness=0.34, metallic=0.85)
    bright = material("CrownAxle", (0.62, 0.63, 0.66),
                      roughness=0.22, metallic=0.95)

    # FLAT-SHADED: the knurl is thirty-six facets and smoothing would
    # average them back into a cylinder. The bevel is a hair — a fifth of
    # a ridge's width — so each crest catches a highlight without the
    # crests rounding into a rope.
    rim = cylinder("ShelfCrownRim", RIM_RADIUS, RIM_WIDTH, vertices=2 * KNURLS)
    knurl(rim, KNURLS, KNURL_DEPTH)
    bevel(rim, 0.0002, segments=1)
    rim = shade(aligned(rim), rim_stock, smooth=False)

    # The round parts want smoothing: surfaces of revolution with nothing
    # flat to protect.
    hub = shade(aligned(cylinder("ShelfCrownHub", HUB_RADIUS, HUB_LENGTH,
                                 vertices=48)), hub_stock)
    axle = shade(aligned(cylinder("ShelfCrownAxle", AXLE_RADIUS, AXLE_LENGTH,
                                  vertices=32)), bright)

    crown = join("ShelfCrown", [rim, hub, axle])
    export([crown], os.path.join(ROOT, "ShelfCrown.usdz"))


main()
