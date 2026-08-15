#!/usr/bin/env python3
"""
Builds the modeled props the hub miniatures use, and writes them as USDZ.

    /Applications/Blender.app/Contents/MacOS/Blender --background \
        --python Tools/vignetteprops.py

Outputs, all under PhysicsPlayground/Models/Hub/:
    GyroGimbalOuter.usdz   the labs emblem's outer gimbal ring
    GyroGimbalInner.usdz   the inner ring, hung inside it
    GyroRotor.usdz         the spinning mass at the centre

The six MODULE miniatures' props — the bar magnet, the pendulum stand
and bobs, the launcher carriage, the compass, the comet, the charge
spheres — moved to `Tools/moduleprops.py` when they were rebuilt from
scratch (2026-08-13). This script keeps only the labs emblem, which was
already at its final finish and out of that rebuild's scope.

WHAT IS AND IS NOT MODELED

Only the SOLID props. Everything in these miniatures that has to flex —
the field lines, the trajectory, the orbits, the wire loop, the cables —
stays procedural in `HubVignettes.swift`, because an imported mesh cannot
be re-traced when the magnets close or the orbit sweeps. Loading a model
for those is the mistake that file's header is a post-mortem of.

These three are the opposite case: they never deform, they only get
moved by a closure that captured them — and they ship as three separate
files rather than one model with named parts, for the reason on the
gimbal builder below.

ORIGINS. Every prop is centred by `HubVignettes.prop(_:longest:)` on
import, which measures the asset and normalises its longest dimension. So
nothing here has to be authored at the size it will be seen at, and no
number below is load-bearing for placement — only for proportion.
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
from blenderprops import (reset_scene, material, shade, bevel,  # noqa: E402
                          cylinder, band, join, export)

ROOT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                    "PhysicsPlayground", "Models", "Hub")

def reface(obj):
    """Drop the empty material slot a boolean leaves behind.

    Blender 5.2's boolean apply copies the cutter's material slots onto
    the result, and a cutter with no material contributes one EMPTY slot
    at index 0 — where every face already points. `shade` then appends
    the real material into slot 1, no face references it, and the part
    renders default white. Every `band`-produced ring goes through here
    before shading. (Same fix as `moduleprops.py`; earlier Blenders did
    not add the slot, which is why the first exports were fine.)"""
    obj.data.materials.clear()
    return obj


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
    parts = [shade(reface(ring), brass)]

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
    parts.append(shade(reface(rim), steel))

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
