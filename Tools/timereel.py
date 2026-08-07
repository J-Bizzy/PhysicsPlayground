#!/usr/bin/env python3
"""
Builds the Time Capsule's reel, and writes it as USDZ.

    /Applications/Blender.app/Contents/MacOS/Blender --background \
        --python Tools/timereel.py

Output:
    PhysicsPlayground/Models/Shell/TimeReel.usdz

WHY A REEL

The Time Rail used to unfold by itself the moment a module paused — a
34 cm instrument and three plates arriving unasked, every time, in every
lab. The owner's objection was that a feature should not be permanently
on screen, and the fix is the one this app keeps reaching for: give the
capability an OBJECT, and let the object be closed until it is asked.

A reel rather than a lid or a drawer, because a reel is not a container
for the feature — it IS the feature, stated as a thing. The last thirty
seconds are wound on it; the rail is that tape drawn out. Nothing has to
label it, the extension animation is the metaphor doing its own
explaining, and the reel can TURN as you scrub, which makes the closed
object a readout rather than a switch. That is the same law the rest of
the app's controls obey — where the bead sits IS the value.

WHAT IS MODELED, AND WHAT IS NOT

Only the reel: two flanges, the hub they are spaced by, the wound tape
between them, and the axle. The RAIL is procedural and stays that way —
it is a `SpatialTrackControl`, it has to stretch to whatever window is
recorded, and an imported rail could not.

MATERIALS. Dark machined stock and near-black tape, no accent anywhere.
The house division is that CASINGS are neutral and VALUES carry the
module's colour, so the reel is the same object in all six labs and the
rail that comes out of it is the one that changes colour. Fixing an
accent into this file would break that in a way no Swift override could
tidily undo.

SIZE. 96 mm across the flanges — a real small-format reel, and about the
size of a thing you would expect to be able to pinch. Its origin is the
axle's centre, so the Swift side can hang it at a point and turn it
about Z without measuring anything.

AXES. Per `blenderprops`: Blender (x, y, z) -> RealityKit (x, z, -y). The
reel's axis must run along RealityKit's Z so its face is toward the
reader, which means building it along Blender's Y — every cylinder here
is a default +Z primitive rotated 90 degrees about X, and the flange
separation is an offset in Blender Y.
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

# The reel, in metres. Proportions matter more than absolute size (the
# Swift side scales nothing, but a reel that reads as a reel is all
# ratio): the flanges overhang the wound tape by a clear millimetre so
# there is a rim to catch the light, and the tape is deep enough to look
# wound rather than painted on.
FLANGE_RADIUS = 0.048
FLANGE_THICKNESS = 0.0035
TAPE_RADIUS = 0.038
TAPE_WIDTH = 0.017
HUB_RADIUS = 0.015
CENTRE_HOLE = 0.0085
AXLE_RADIUS = 0.005
AXLE_LENGTH = 0.040
# Three lightening holes, as every real reel has — they are also what
# lets you SEE the tape turning behind the flange, which is the whole
# reason the reel is worth modelling instead of drawing as a disc.
PORT_COUNT = 3
PORT_RADIUS = 0.0125
PORT_ORBIT = 0.029

# Half the gap between flange mid-planes, along the axis.
HALF_SPAN = (TAPE_WIDTH + FLANGE_THICKNESS) / 2

AXIS = (math.pi / 2, 0, 0)   # +Z primitive -> axis along RealityKit Z


def cut(target, tool):
    """Boolean difference, applied and cleaned up. `band()` does this
    inline for its one hole; a flange needs four, so it is a helper."""
    bpy.context.view_layer.objects.active = target
    modifier = target.modifiers.new("cut", "BOOLEAN")
    modifier.operation = "DIFFERENCE"
    modifier.object = tool
    modifier.solver = "EXACT"
    bpy.ops.object.modifier_apply(modifier="cut")
    bpy.data.objects.remove(tool, do_unlink=True)
    return target


def flange(name, offset):
    """One side plate: a disc, its centre bored for the axle, and three
    ports cut on a circle.

    Built flat (axis along Blender +Z, its own natural axis) so the
    boolean tools are trivially co-axial, then rotated onto the reel's
    axis once at the end. Cutting first and rotating after is not just
    tidier — a boolean between two rotated meshes is where EXACT starts
    producing surprises.
    """
    plate = cylinder(name, FLANGE_RADIUS, FLANGE_THICKNESS, vertices=64)
    cut(plate, cylinder(name + "Bore", CENTRE_HOLE,
                        FLANGE_THICKNESS * 4, vertices=48))
    for index in range(PORT_COUNT):
        angle = 2 * math.pi * index / PORT_COUNT
        port = cylinder(
            f"{name}Port{index}", PORT_RADIUS, FLANGE_THICKNESS * 4,
            location=(PORT_ORBIT * math.cos(angle),
                      PORT_ORBIT * math.sin(angle), 0),
            vertices=40)
        cut(plate, port)

    # A chamfer, not a fillet. 0.4 mm on a 3.5 mm plate is a machined
    # edge-break; 0.7 mm was 20% of the thickness and, once smooth
    # shading blended it into the faces, turned a milled plate into a
    # pillow. The port edges want breaking too, or they read as holes
    # punched in paper — which is why this is applied to the whole mesh
    # rather than to the rim alone.
    bevel(plate, 0.0004, segments=2)

    plate.rotation_euler = AXIS
    plate.location = (0, offset, 0)
    bpy.ops.object.select_all(action="DESELECT")
    plate.select_set(True)
    bpy.context.view_layer.objects.active = plate
    bpy.ops.object.transform_apply(rotation=True, location=True)
    return plate


def main():
    reset_scene()

    machined = material("ReelStock", (0.30, 0.31, 0.33),
                        roughness=0.34, metallic=0.85)
    # The recording itself: near-black, and NOT metallic — the one
    # non-metal on the object, so the wound tape reads as a different
    # substance from the plates that hold it rather than as a groove
    # machined into them.
    tape_stock = material("ReelTape", (0.055, 0.055, 0.062),
                          roughness=0.62, metallic=0.0)
    bright = material("ReelAxle", (0.62, 0.63, 0.66),
                      roughness=0.22, metallic=0.95)

    # FLAT-SHADED, alone among the parts here. A flange is a milled
    # plate: its faces are flat and its rim is a 64-gon, which at 96 mm
    # is already past the point where faceting shows. Smooth shading
    # averages the normals across the chamfer and the boolean cuts, and
    # the plate stops looking machined and starts looking inflated —
    # which is exactly what the first render of this asset showed.
    left = shade(flange("TimeReelFlangeA", -HALF_SPAN), machined, smooth=False)
    right = shade(flange("TimeReelFlangeB", HALF_SPAN), machined, smooth=False)

    # The round parts DO want smoothing: they are surfaces of revolution
    # with nothing flat to protect.
    hub = shade(cylinder("TimeReelHub", HUB_RADIUS, TAPE_WIDTH,
                         rotation=AXIS, vertices=48), machined)

    # The wound tape. Slightly narrower than the gap so the flanges
    # visibly hold it rather than butting against it.
    tape = shade(cylinder("TimeReelTape", TAPE_RADIUS, TAPE_WIDTH * 0.92,
                          rotation=AXIS, vertices=64), tape_stock)

    # The axle runs right through and stands proud both sides: it is what
    # says this thing is MOUNTED and turns, rather than floating.
    axle = shade(cylinder("TimeReelAxle", AXLE_RADIUS, AXLE_LENGTH,
                          rotation=AXIS, vertices=32), bright)

    reel = join("TimeReel", [left, right, hub, tape, axle])
    export([reel], os.path.join(ROOT, "TimeReel.usdz"))


main()
