#!/usr/bin/env python3
"""
Builds Circuit Workshop's parts cabinet, and writes it as USDZ.

    /Applications/Blender.app/Contents/MacOS/Blender --background \
        --python Tools/partsdrawer.py

Output:
    PhysicsPlayground/Models/Shell/PartsDrawer.usdz

WHY A DRAWER

The components used to stand in two columns of wells, one on each flank
of the bench, permanently. Eleven kinds of part, always in the room,
whether or not anybody was building anything — and the owner's verdict on
the bench as a whole was that it reads as clutter. The fix is the one
this app keeps arriving at: give the capability an OBJECT, and let the
object be closed until it is asked. The palette bead does it for the
labs; the reel does it for the Time Capsule; this does it for the parts.

A drawer rather than a lid, a chest or a pegboard, and the reason is the
scroll. There will be more component kinds than fit across one row, so
whatever holds them has to be longer than what you can see of it — and a
drawer is the one of those four shapes where that is obviously true
before anyone explains it. You already know a drawer goes back further
than the opening. (The other three were on the table and are recorded in
the session's memory; if this reads badly on device, the tool chest is
next.)

WHAT IS MODELLED, AND WHAT IS NOT

Only the furniture: a carcass, and a drawer that slides out of it. The
PARTS are not here — they are the same miniature previews the wells
already build from `Well.Spec.preview`, laid into the open drawer by
Swift. Modelling them would freeze the component list into an asset, and
the whole point of the scroll is that the list grows.

TWO OBJECTS, NOT ONE. `Carcass` and `Drawer` are exported as separate
prims so the Swift side can slide one inside the other by name. The reel
is a single object because a reel only ever turns; this has a moving
part.

MATERIALS. Dark machined stock throughout, no accent anywhere. The house
division is that CASINGS are neutral and VALUES carry the module's
colour, so the cabinet is furniture and the parts inside it are what
have hue. Fixing Circuit Workshop's amber into this file would also make
the asset unusable if another module ever wants a parts drawer.

SIZE. 340 mm across, 220 mm tall, 200 mm deep — a real small-parts
cabinet, and about the size of a thing you expect to be able to pull
open. Its origin is the centre of the CARCASS, so the Swift side can
hang it at a point without measuring anything.

AXES. Per `blenderprops`: Blender (x, y, z) -> RealityKit (x, z, -y).
So Blender +Z is up, and the drawer must slide toward the reader along
RealityKit +Z — which is Blender NEGATIVE Y. Every "front" face in this
file is at negative Y, and the drawer's travel is -Y.
"""

import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import bpy  # noqa: E402
import blenderprops as bp  # noqa: E402

# ── Dimensions, metres ───────────────────────────────────────────────
WIDTH = 0.340          # x
HEIGHT = 0.220         # z (up)
DEPTH = 0.200          # y (into the cabinet, away from the reader)
WALL = 0.010

# The drawer runs inside the carcass with a working clearance on each
# side. 1.5 mm: enough that the two never z-fight where they overlap,
# tight enough to still read as machined rather than as loose.
CLEARANCE = 0.0015

FRONT_Y = -DEPTH / 2   # the open face
BACK_Y = DEPTH / 2

DRAWER_W = WIDTH - 2 * WALL - 2 * CLEARANCE
DRAWER_D = DEPTH - WALL - 0.006
DRAWER_WALL = 0.006
# How deep the tray's own sides are. Low, because the parts have to be
# visible and pinchable from above once it is open — a deep tray would
# hide the short components behind its own lip.
TRAY_SIDE = 0.030
# The face panel caps the opening when the drawer is shut, so it is the
# full outer width and tall enough to cover the mouth.
FACE_H = HEIGHT - 2 * WALL - 2 * CLEARANCE
FACE_T = 0.012


def carcass(stock, rail_stock):
    """Five plates and two runners. Not a boolean difference of two
    boxes: the front has to be open on one axis only, and five plates
    say that directly while a difference needs a cutter longer than the
    solid and an argument about which face it leaves."""
    parts = []

    top = bp.box("CarcassTop", (WIDTH, DEPTH, WALL),
                 (0, 0, HEIGHT / 2 - WALL / 2))
    bottom = bp.box("CarcassBottom", (WIDTH, DEPTH, WALL),
                    (0, 0, -HEIGHT / 2 + WALL / 2))
    left = bp.box("CarcassLeft", (WALL, DEPTH, HEIGHT - 2 * WALL),
                  (-WIDTH / 2 + WALL / 2, 0, 0))
    right = bp.box("CarcassRight", (WALL, DEPTH, HEIGHT - 2 * WALL),
                   (WIDTH / 2 - WALL / 2, 0, 0))
    back = bp.box("CarcassBack", (WIDTH - 2 * WALL, WALL, HEIGHT - 2 * WALL),
                  (0, BACK_Y - WALL / 2, 0))
    for part in (top, bottom, left, right, back):
        bp.bevel(part, 0.0016)
        bp.shade(part, stock)
        parts.append(part)

    # THE RUNNERS THE DRAWER RIDES ON. Purely visual — the Swift side
    # slides the drawer along a straight line and never consults these —
    # but they are what makes the open cabinet read as a mechanism rather
    # than as a box with a tray resting in it. A drawer with no visible
    # support looks like it is floating, which is exactly what it is.
    for side in (-1, 1):
        rail = bp.box(
            "CarcassRunner%s" % ("L" if side < 0 else "R"),
            (0.004, DEPTH - WALL, 0.005),
            (side * (WIDTH / 2 - WALL - 0.002), -WALL / 2,
             -HEIGHT / 2 + WALL + TRAY_SIDE * 0.5))
        bp.bevel(rail, 0.0008)
        bp.shade(rail, rail_stock)
        parts.append(rail)

    return bp.join("Carcass", parts)


def drawer(stock, face_stock, handle_stock):
    """A tray, a face panel, and a handle across it."""
    parts = []

    floor = bp.box("DrawerFloor", (DRAWER_W, DRAWER_D, DRAWER_WALL),
                   (0, 0, 0))
    bp.bevel(floor, 0.0012)
    bp.shade(floor, stock)
    parts.append(floor)

    side_z = DRAWER_WALL / 2 + TRAY_SIDE / 2
    for side in (-1, 1):
        wall = bp.box(
            "DrawerSide%s" % ("L" if side < 0 else "R"),
            (DRAWER_WALL, DRAWER_D, TRAY_SIDE),
            (side * (DRAWER_W / 2 - DRAWER_WALL / 2), 0, side_z))
        bp.bevel(wall, 0.001)
        bp.shade(wall, stock)
        parts.append(wall)

    back = bp.box("DrawerBack", (DRAWER_W, DRAWER_WALL, TRAY_SIDE),
                  (0, DRAWER_D / 2 - DRAWER_WALL / 2, side_z))
    bp.bevel(back, 0.001)
    bp.shade(back, stock)
    parts.append(back)

    # THE FACE. Full outer width, so a shut drawer reads as a closed
    # cabinet rather than as a tray parked in a hole. It sits proud of
    # the carcass mouth by half its own thickness.
    face = bp.box("DrawerFace", (WIDTH, FACE_T, FACE_H),
                  (0, FRONT_Y - FACE_T / 2, FACE_H / 2 - DRAWER_WALL / 2
                   - TRAY_SIDE * 0.15))
    bp.bevel(face, 0.0022)
    bp.shade(face, face_stock)
    parts.append(face)

    # A milled recess across the face, so the handle has somewhere to be
    # rather than being bolted to a flat slab.
    recess = bp.box("DrawerRecess", (WIDTH * 0.62, 0.004, 0.016),
                    (0, FRONT_Y - FACE_T - 0.001,
                     face.location[2] + FACE_H * 0.06))
    bp.bevel(recess, 0.0012)
    bp.shade(recess, stock)
    parts.append(recess)

    handle = bp.cylinder(
        "DrawerHandle", 0.0075, WIDTH * 0.52,
        location=(0, FRONT_Y - FACE_T - 0.010,
                  face.location[2] + FACE_H * 0.06),
        rotation=(0, math.pi / 2, 0))
    bp.shade(handle, handle_stock)
    parts.append(handle)

    # The two posts the handle stands on.
    for side in (-1, 1):
        post = bp.cylinder(
            "DrawerHandlePost%s" % ("L" if side < 0 else "R"),
            0.005, 0.012,
            location=(side * WIDTH * 0.24, FRONT_Y - FACE_T - 0.005,
                      face.location[2] + FACE_H * 0.06),
            rotation=(math.pi / 2, 0, 0))
        bp.shade(post, handle_stock)
        parts.append(post)

    return bp.join("Drawer", parts)


def main():
    bp.reset_scene()

    # Dark machined stock, the same alloy as every other casing in the
    # app. The face is a shade lighter so the closed cabinet still has a
    # front rather than reading as one solid block.
    stock = bp.material("CabinetStock", (0.115, 0.118, 0.125),
                        roughness=0.42, metallic=0.85)
    face_stock = bp.material("CabinetFace", (0.155, 0.158, 0.168),
                             roughness=0.36, metallic=0.88)
    handle_stock = bp.material("CabinetHandle", (0.62, 0.63, 0.65),
                               roughness=0.24, metallic=1.0)
    rail_stock = bp.material("CabinetRunner", (0.30, 0.31, 0.33),
                             roughness=0.30, metallic=0.95)

    body = carcass(stock, rail_stock)
    tray = drawer(stock, face_stock, handle_stock)

    here = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    out = os.path.join(here, "PhysicsPlayground", "Models", "Shell",
                       "PartsDrawer.usdz")
    bp.export([body, tray], out)


if __name__ == "__main__":
    main()
