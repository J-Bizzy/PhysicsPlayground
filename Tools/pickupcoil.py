#!/usr/bin/env python3
"""
Magnetism's pickup coil: a copper winding on a graphite bobbin, its two
leads running up to a terminal block whose socket holds the bicolour LED.

    /Applications/Blender.app/Contents/MacOS/Blender -b -noaudio \\
        --python Tools/pickupcoil.py

Writes PhysicsPlayground/Models/Magnetism/PickupCoil.usdz.

THE CONTRACT WITH THE PHYSICS. The bore runs along RealityKit X (Blender
X), centred on the origin. The winding is the coil `MagnetismModel`
traces: copper from radius WINDING_INNER to WINDING_OUTER (mean radius
0.0565 m, `MagnetismModel.coilRadius`), WINDING_LENGTH long. The bore is
BORE_RADIUS, wide enough that a bar magnet (5 cm square, 7.1 cm across
its diagonal) passes through it without touching. `PickupCoilPropTests`
measures the exported asset against these numbers.

THE CONTRACT WITH THE RENDERER. Swift draws the LED itself, because it
lights it: a dome standing in the socket, its base at RealityKit
y = LED_SEAT. Everything here is the coil's unlit body.

WHY THE OUTER LAYER IS A REAL HELIX. A coil read as a copper tube is a
diagram; forty turns of round wire catching the light one by one is the
object. Under them a copper core fills the winding so no gap shows
between turns. Thousands of turns of fine wire look exactly like this
from arm's length: the outermost layer is all you ever see of a winding.

HANDEDNESS. Blender (x, y, z) -> RealityKit (x, z, -y): up is Blender +Z.
"""

import math
import os
import sys

sys.dont_write_bytecode = True
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import bpy  # noqa: E402
from blenderprops import band, bevel, box, cylinder, export, join, material, reset_scene, shade  # noqa: E402

ROOT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                    "PhysicsPlayground", "Models", "Magnetism")

ALONG_X = (0, math.pi / 2, 0)   # a Blender cylinder is built along Z

# The physics' numbers, metres.
BORE_RADIUS = 0.048
WINDING_INNER = 0.051
WINDING_OUTER = 0.062
WINDING_LENGTH = 0.080
FLANGE_RADIUS = 0.072
FLANGE_THICKNESS = 0.006
WIRE_RADIUS = 0.0011            # the drawn outer layer, not the 0.25 mm wire
TURNS_DRAWN = 36
BLOCK = (0.034, 0.018, 0.012)   # terminal block, x by depth by height
LED_SEAT = WINDING_OUTER + BLOCK[2] + 0.003   # top of the socket


def coat(mat, weight, roughness):
    bsdf = mat.node_tree.nodes["Principled BSDF"]
    for key, value in (("Coat Weight", weight), ("Clearcoat", weight),
                       ("Coat Roughness", roughness),
                       ("Clearcoat Roughness", roughness)):
        if key in bsdf.inputs:
            bsdf.inputs[key].default_value = value
    return mat


def stocks():
    """The house alloys: the circuit bench's, so a coil in Magnetism reads
    as the same family as the inductor on the bench."""
    return {
        "graphite": coat(material("CoilGraphite", (0.088, 0.090, 0.096),
                                  roughness=0.30, metallic=0.10), 0.60, 0.25),
        "steel": material("CoilSteel", (0.60, 0.61, 0.64), roughness=0.22, metallic=0.95),
        "copper": material("CoilCopper", (0.74, 0.43, 0.22), roughness=0.26, metallic=0.95),
        "champagne": material("CoilChampagne", (0.83, 0.70, 0.45), roughness=0.30, metallic=0.85),
    }


def tube(name, points, radius, mat, resolution=6):
    """A round wire along a polyline, with capped ends."""
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
    obj = bpy.context.active_object
    return shade(obj, mat)


def bezier(a, b, c, d, samples=24):
    """A cubic Bézier from a to d, as points."""
    out = []
    for index in range(samples + 1):
        t = index / samples
        u = 1 - t
        out.append(tuple(u * u * u * a[k] + 3 * u * u * t * b[k]
                         + 3 * u * t * t * c[k] + t * t * t * d[k] for k in range(3)))
    return out


def build(s):
    parts = []
    half = WINDING_LENGTH / 2

    # The bobbin: a sleeve through the bore and a flange at each end.
    sleeve = band("CoilSleeve", WINDING_INNER, BORE_RADIUS,
                  WINDING_LENGTH + 2 * FLANGE_THICKNESS + 0.004, rotation=ALONG_X, vertices=96)
    bevel(sleeve, 0.0008, segments=2)
    parts.append(shade(sleeve, s["graphite"]))
    for side in (-1, 1):
        x = side * (half + FLANGE_THICKNESS / 2)
        flange = band("CoilFlange", FLANGE_RADIUS, BORE_RADIUS, FLANGE_THICKNESS,
                      location=(x, 0, 0), rotation=ALONG_X, vertices=96)
        bevel(flange, 0.0012, segments=3)
        parts.append(shade(flange, s["graphite"]))
        # A champagne keyline set into each flange's outer face.
        key = band("CoilKeyline", FLANGE_RADIUS - 0.003, FLANGE_RADIUS - 0.0045, 0.0008,
                   location=(x + side * (FLANGE_THICKNESS / 2 + 0.0002), 0, 0),
                   rotation=ALONG_X, vertices=96)
        parts.append(shade(key, s["champagne"]))

    # The winding: a copper core, and the outer layer as a real helix on it.
    core = band("CoilCore", WINDING_OUTER - WIRE_RADIUS, WINDING_INNER, WINDING_LENGTH - 0.001,
                rotation=ALONG_X, vertices=128)
    parts.append(shade(core, s["copper"]))
    pitch = (WINDING_LENGTH - 2 * WIRE_RADIUS) / TURNS_DRAWN
    helix = []
    steps = TURNS_DRAWN * 72
    radius = WINDING_OUTER - WIRE_RADIUS
    for index in range(steps + 1):
        t = index / steps
        angle = 2 * math.pi * TURNS_DRAWN * t
        helix.append((-half + WIRE_RADIUS + pitch * TURNS_DRAWN * t,
                      radius * math.sin(angle), radius * math.cos(angle)))
    parts.append(tube("CoilWire", helix, WIRE_RADIUS, s["copper"]))

    # The terminal block on top of the winding, and the LED's socket.
    block_z = WINDING_OUTER + BLOCK[2] / 2
    block = box("CoilBlock", BLOCK, location=(0, 0, block_z))
    bevel(block, 0.002, segments=3)
    parts.append(shade(block, s["graphite"]))
    socket = band("CoilSocket", 0.0078, 0.0058, 0.003,
                  location=(0, 0, WINDING_OUTER + BLOCK[2] + 0.0015))
    bevel(socket, 0.0004, segments=2)
    parts.append(shade(socket, s["steel"]))

    # The two leads: from the winding's ends, up and in to the block's sides.
    for side in (-1, 1):
        start = (side * (half - 0.004), 0, WINDING_OUTER + 0.0005)
        end = (side * BLOCK[0] / 2, 0, block_z)
        lead = bezier(start,
                      (start[0], 0, start[2] + 0.010),
                      (end[0] + side * 0.010, 0, end[2]),
                      end)
        parts.append(tube("CoilLead", lead, 0.0009, s["copper"]))
    return join("PickupCoil", parts)


def main():
    reset_scene()
    coil = build(stocks())
    export([coil], os.path.join(ROOT, "PickupCoil.usdz"))
    print("  PickupCoil verts", len(coil.data.vertices))


if __name__ == "__main__":
    main()
