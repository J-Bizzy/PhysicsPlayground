#!/usr/bin/env python3
"""
The home's dioramas: the stage every lab stands on in its portal, and the
one apparatus the labs do not already mill — the cradle's frame.

    /Applications/Blender.app/Contents/MacOS/Blender -b -noaudio \\
        --python Tools/hubdioramas.py

Writes, under PhysicsPlayground/Models/Hub/:

    HubStage.usdz     the plinth: an anodised graphite disc on a champagne
                      foot, a champagne keyline let into its top
    HubCradle.usdz    Newton's cradle's frame: two bent champagne tubes on
                      turned feet, the balls' rails at their tops

WHY A STAGE. Seven labs drawn seven ways read as seven pictures; the same
plinth under each, the same size in every portal, makes them one set — a
row of exhibits, each standing on its own disc. It is milled in the house
alloys (`pickupcoil.py`'s stocks): graphite with a clear coat, champagne
metal, nothing else.

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
from blenderprops import band, bevel, cylinder, export, join, material, reset_scene, shade  # noqa: E402

ROOT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                    "PhysicsPlayground", "Models", "Hub")

# The stage, metres.
STAGE_RADIUS = 0.100
STAGE_THICKNESS = 0.010
FOOT_HEIGHT = 0.003

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
    }


def tube(name, points, radius, mat, resolution=8):
    """A round tube along a polyline, ends capped."""
    data = bpy.data.curves.new(name, type="CURVE")
    data.dimensions = "3D"
    data.bevel_depth = radius
    data.bevel_resolution = resolution
    data.use_fill_caps = True
    spline = data.splines.new("POLY")
    spline.points.add(len(points) - 1)
    for point, co in zip(spline.points, points):
        point.co = (*co, 1.0)
    obj = bpy.data.objects.new(name, data)
    bpy.context.collection.objects.link(obj)
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.convert(target="MESH")
    return shade(bpy.context.active_object, mat)


def build_stage(s):
    parts = []
    # The disc, its top at z = 0.
    disc = cylinder("StageDisc", STAGE_RADIUS, STAGE_THICKNESS,
                    location=(0, 0, -STAGE_THICKNESS / 2), vertices=128)
    bevel(disc, 0.0022, segments=4)
    parts.append(shade(disc, s["graphite"]))
    # A champagne keyline let into the top, a few millimetres in from the edge.
    key = band("StageKeyline", STAGE_RADIUS - 0.006, STAGE_RADIUS - 0.0075, 0.0007,
               location=(0, 0, 0.00025), vertices=128)
    parts.append(shade(key, s["champagne"]))
    # The foot: a turned champagne ring the disc sits on, set back so the
    # disc's bevel catches the light above a shadow line.
    foot = band("StageFoot", STAGE_RADIUS - 0.004, STAGE_RADIUS - 0.016, FOOT_HEIGHT,
                location=(0, 0, -STAGE_THICKNESS - FOOT_HEIGHT / 2), vertices=128)
    bevel(foot, 0.0008, segments=2)
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


def main():
    reset_scene()
    s = stocks()
    stage = build_stage(s)
    export([stage], os.path.join(ROOT, "HubStage.usdz"))
    print("  HubStage verts", len(stage.data.vertices))
    reset_scene()
    s = stocks()
    cradle = build_cradle(s)
    export([cradle], os.path.join(ROOT, "HubCradle.usdz"))
    print("  HubCradle verts", len(cradle.data.vertices))


if __name__ == "__main__":
    main()
