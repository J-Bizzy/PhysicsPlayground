#!/usr/bin/env python3
"""
Builds the modeled props the hub miniatures use, and writes them as USDZ.

    /Applications/Blender.app/Contents/MacOS/Blender --background \
        --python Tools/vignetteprops.py

Outputs, all under PhysicsPlayground/Models/Hub/:
    BarMagnet.usdz         one bar magnet, blue south at -X, red north at +X
    PendulumGantry.usdz    the rig the pendulums hang from
    GyroGimbalOuter.usdz   the labs emblem's outer gimbal ring
    GyroGimbalInner.usdz   the inner ring, hung inside it
    GyroRotor.usdz         the spinning mass at the centre

WHAT IS AND IS NOT MODELED

Only the SOLID props. Everything in these miniatures that has to flex —
the field lines, the trajectory, the orbits, the wire loop, the cables —
stays procedural in `HubVignettes.swift`, because an imported mesh cannot
be re-traced when the magnets close or the orbit sweeps. Loading a model
for those is the mistake that file's header is a post-mortem of.

These five are the opposite case: they never deform, they only get moved
by a closure that captured them, and they were the parts still reading as
programmer art — two rounded boxes butted together for a bar magnet, one
rounded box for a pendulum rig, and an SF Symbol floating in a glass
sphere for the app's only permanent piece of interface.

The circuit battery, the bulb and the launcher barrel are NOT here. Those
assets already ship for the rooms themselves, and the miniatures load the
very same files — the miniature is the map you arrive holding, and a map
drawn from different geometry than the place is worse than none.

ORIGINS. Every prop is centred by `HubVignettes.prop(_:longest:)` on
import, which measures the asset and normalises its longest dimension. So
nothing here has to be authored at the size it will be seen at, and no
number below is load-bearing for placement — only for proportion.

HANDEDNESS. The bar magnet's north is at +X and this is shared knowledge:
`HubVignettes.magnetism()` places both bars unflipped and relies on it to
put a north against a south. Turning the magnet round here silently turns
an attraction into a repulsion there.
"""

import os
import sys

# No .pyc beside the source. Everything under PhysicsPlayground/ is
# swept into the bundle by the synchronized project group, and Tools/ is
# a sibling of that — but a stray __pycache__ next to two checked-in
# scripts is the kind of thing that gets committed by accident once and
# then lives forever.
sys.dont_write_bytecode = True
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import math  # noqa: E402
from blenderprops import (reset_scene, material, shade, bevel, box, cylinder,  # noqa: E402
                          band, letter, join, export)

ROOT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                    "PhysicsPlayground", "Models", "Hub")

# ------------------------------------------------------------- bar magnet
# A real Alnico bar: 60 x 18 x 18 mm, painted in two halves with a visible
# seam where the paint meets. The seam is a separate sliver of bare metal
# rather than a butt joint between two coloured blocks, because a joint
# with nothing in it reads as two objects touching.

MAGNET_L, MAGNET_W, MAGNET_H = 0.060, 0.018, 0.018


def build_magnet():
    red = material("MagnetNorth", (0.62, 0.09, 0.07), roughness=0.38)
    blue = material("MagnetSouth", (0.07, 0.16, 0.58), roughness=0.38)
    steel = material("MagnetSeam", (0.55, 0.56, 0.58), roughness=0.30,
                     metallic=0.9)
    marks = material("MagnetMarks", (0.93, 0.93, 0.90), roughness=0.45)

    parts = []
    seam = 0.0022
    half = (MAGNET_L - seam) / 2

    # South at -X, north at +X. Shared with HubVignettes.magnetism().
    south = box("South", (half, MAGNET_W, MAGNET_H),
                location=(-(seam / 2 + half / 2), 0, 0))
    bevel(south, 0.0018, segments=3)
    parts.append(shade(south, blue))

    north = box("North", (half, MAGNET_W, MAGNET_H),
                location=(seam / 2 + half / 2, 0, 0))
    bevel(north, 0.0018, segments=3)
    parts.append(shade(north, red))

    # The bare band between the painted halves.
    girdle = box("Seam", (seam, MAGNET_W + 0.0004, MAGNET_H + 0.0004))
    parts.append(shade(girdle, steel))

    # N and S, moulded into the top face. Blender's +Z is the face that
    # ends up pointing up in RealityKit.
    for character, x in (("S", -MAGNET_L * 0.27), ("N", MAGNET_L * 0.27)):
        glyph = letter("Mark" + character, character, size=0.011,
                       extrude=0.0007,
                       location=(x, 0, MAGNET_H / 2 - 0.0002))
        parts.append(shade(glyph, marks, smooth=False))

    return join("BarMagnet", parts)


# ---------------------------------------------------------- pendulum rig
# An A-frame bench rig: two splayed legs on feet, a crossbeam across the
# top, and three collars on it where the cables attach. The miniature used
# ONE rounded box for all of this, which is why it read as a floating bar
# with beads under it rather than as apparatus.
#
# Width is the longest dimension, which is what the importer normalises
# on, and the height is deliberately a little under half of it so the rig
# does not eat the vertical room the pendulums need to swing in.

GANTRY_W = 0.440
GANTRY_H = 0.198
BEAM_R = 0.011


def build_gantry():
    steel = material("GantrySteel", (0.42, 0.44, 0.47), roughness=0.34,
                     metallic=0.85)
    dark = material("GantryFoot", (0.10, 0.11, 0.13), roughness=0.62)
    brass = material("GantryCollar", (0.60, 0.47, 0.19), roughness=0.30,
                     metallic=0.9)

    parts = []
    top = GANTRY_H / 2

    # The crossbeam, lying along X with its axis converted to RealityKit's
    # X — a cylinder's default axis is Z, so it turns about Y.
    beam = cylinder("Beam", BEAM_R, GANTRY_W, location=(0, 0, top),
                    rotation=(0, math.radians(90), 0))
    parts.append(shade(beam, steel))

    for side in (-1, 1):
        x = side * GANTRY_W / 2

        # Two legs per end, splayed fore and aft into an A.
        for depth in (-1, 1):
            lean = math.radians(13)
            leg = cylinder("Leg", 0.0072, GANTRY_H,
                           location=(x - side * 0.010 * 0,
                                     depth * GANTRY_H * 0.16, 0),
                           rotation=(depth * lean, 0, 0), vertices=20)
            parts.append(shade(leg, steel))

        # A foot broad enough to look like it would actually stand up.
        foot = box("Foot", (0.030, 0.108, 0.010),
                   location=(x, 0, -top + 0.005))
        bevel(foot, 0.003, segments=2)
        parts.append(shade(foot, dark))

        # The cap where the beam lands on the legs.
        cap = cylinder("Cap", 0.0155, 0.014, location=(x, 0, top),
                       rotation=(0, math.radians(90), 0), vertices=24)
        parts.append(shade(cap, dark))

    # Three collars, at the three pivots the miniature hangs cables from.
    for index in range(3):
        x = (index - 1) * GANTRY_W * 0.31
        collar = cylinder("Collar", BEAM_R + 0.0028, 0.0115,
                          location=(x, 0, top),
                          rotation=(0, math.radians(90), 0), vertices=24)
        parts.append(shade(collar, brass))
        # The eyelet the cable actually passes through.
        eye = cylinder("Eye", 0.0030, 0.0075,
                       location=(x, 0, top - BEAM_R - 0.0026),
                       vertices=16)
        parts.append(shade(eye, brass))

    return join("PendulumGantry", parts)


# --------------------------------------------------------- labs emblem
# A gimballed gyroscope, at instrument scale: an 80 mm outer ring.
#
# Three separate files rather than one model with three named parts.
# `HubVignettes` assembles them so its closure can capture each moving
# piece directly — pulling named children out of one loaded model is the
# exact failure that file was rewritten to end, and it fails SILENTLY:
# the emblem would load, look right, and never turn.
#
# All three face the reader, so each is built with its axis along
# Blender's Y — see the axis note in blenderprops.

GYRO_R = 0.040
FACING = (math.radians(90), 0, 0)


def gimbal_ring(name, radius, section, depth, pivots):
    """One gimbal ring, plus the pivot screws it turns on.

    `pivots` is the angle in the ring's own plane where the two bearings
    sit — the outer ring hangs from the top and bottom, the inner one
    from the sides, which is the ninety degrees that makes a gimbal a
    gimbal rather than two hoops.
    """
    brass = material(name + "Brass", (0.58, 0.45, 0.20), roughness=0.28,
                     metallic=0.92)
    steel = material(name + "Pivot", (0.72, 0.73, 0.76), roughness=0.22,
                     metallic=1.0)

    ring = band(name, radius, radius - section, depth, rotation=FACING)
    bevel(ring, section * 0.22, segments=2, angle=50)
    parts = [shade(ring, brass)]

    for turn in (pivots, pivots + math.pi):
        screw = cylinder(name + "Screw",
                         depth * 0.42, section * 2.4,
                         location=(math.cos(turn) * radius, 0,
                                   math.sin(turn) * radius),
                         rotation=FACING, vertices=16)
        parts.append(shade(screw, steel))

    return join(name, parts)


def build_rotor():
    """The mass. A heavy rim on a thin web, which is how a real rotor is
    made — the whole point is to put the inertia as far from the axis as
    the ring will allow."""
    steel = material("RotorSteel", (0.66, 0.67, 0.70), roughness=0.24,
                     metallic=1.0)
    dark = material("RotorWeb", (0.16, 0.17, 0.19), roughness=0.44)

    radius = GYRO_R * 0.53
    parts = []

    rim = band("Rim", radius, radius * 0.74, GYRO_R * 0.17, rotation=FACING)
    bevel(rim, GYRO_R * 0.018, segments=2, angle=50)
    parts.append(shade(rim, steel))

    web = cylinder("Web", radius * 0.76, GYRO_R * 0.045, rotation=FACING,
                   vertices=48)
    parts.append(shade(web, dark))

    hub = cylinder("Hub", radius * 0.20, GYRO_R * 0.16, rotation=FACING,
                   vertices=24)
    parts.append(shade(hub, steel))

    # The axle, long enough to reach the inner ring's bearings. This is
    # the rotor's LONGEST dimension, which is the one the importer
    # normalises on — so the disc's apparent size is set by the ratio
    # between the two, not by either number alone.
    axle = cylinder("Axle", radius * 0.075, GYRO_R * 1.30, rotation=FACING,
                    vertices=16)
    parts.append(shade(axle, steel))

    return join("GyroRotor", parts)


def main():
    reset_scene()
    export([build_magnet()], os.path.join(ROOT, "BarMagnet.usdz"))

    reset_scene()
    export([build_gantry()], os.path.join(ROOT, "PendulumGantry.usdz"))

    reset_scene()
    export([gimbal_ring("GyroGimbalOuter", GYRO_R, GYRO_R * 0.085,
                        GYRO_R * 0.20, pivots=math.radians(90))],
           os.path.join(ROOT, "GyroGimbalOuter.usdz"))

    reset_scene()
    export([gimbal_ring("GyroGimbalInner", GYRO_R * 0.74, GYRO_R * 0.075,
                        GYRO_R * 0.17, pivots=0)],
           os.path.join(ROOT, "GyroGimbalInner.usdz"))

    reset_scene()
    export([build_rotor()], os.path.join(ROOT, "GyroRotor.usdz"))


main()
