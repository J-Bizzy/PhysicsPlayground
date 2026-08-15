#!/usr/bin/env python3
"""
Builds the modeled props for the six MODULE miniatures, and writes USDZ.

    /Applications/Blender.app/Contents/MacOS/Blender --background \
        --python Tools/moduleprops.py

Outputs, all under PhysicsPlayground/Models/Hub/ (override the directory
with MODULEPROPS_OUT, which is how the preview harness renders candidates
without writing anything into the bundle):

    PendulumStand.usdz     precision lab stand: base, columns, beam, pivots
    PendulumBob.usdz       one turned-brass bob with a hanging eye
    BarMagnet.usdz         Alnico bar, blue south at -X, red north at +X
    CompassBody.usdz       brass bowl and dial, no needle
    CompassNeedle.usdz     the needle alone, pivot at its centre
    LauncherCarriage.usdz  turret base, trunnion yoke, elevation quadrant
    QuadrantPointer.usdz   the needle that rides the barrel's elevation
    TargetStand.usdz       the landing ring on a mast and base plate
    CometNucleus.usdz      bilobed comet body, 67P-dark
    ChargePlus.usdz        polished conductor sphere, moulded +
    ChargeMinus.usdz       polished conductor sphere, moulded -

WHAT IS AND IS NOT MODELED

Same contract as `vignetteprops.py`: only the SOLID parts. Cables, field
lines, orbits, the comet's tail and the trajectory all flex, so they stay
procedural in `HubVignettes.swift` — an imported mesh cannot be re-traced
when the magnets close.

Anything that ROTATES on its own ships as a separate file — the compass
needle, the quadrant pointer — because the Swift
closure must capture the moving part directly. Pulling named children out
of one loaded model is the silent failure `HubVignettes`'s header is a
post-mortem of.

ORIGINS. `HubVignettes.prop(_:longest:)` recentres every asset on its
bounding-box centre and normalises its longest dimension, so authored
origins do not survive import. The one prop whose pivot is NOT its box
centre — the pointer — gets its pivot restored in Swift by measuring the
model's bounds; the compass needle sidesteps the problem by being
symmetric about its pivot.

Circuits has no entry here on purpose: the room already defines what a
switch looks like (`CircuitSwitch.usdz` plus the renderer's own lever),
and the miniature loads THAT, the way it already loads the battery and
the bulb. A second switch design would be a map drawn from different
geometry than the place.

HANDEDNESS AND AXES. Blender (x, y, z) -> RealityKit (x, z, -y): up is
Blender +Z, and the face toward the reader is Blender -Y. The magnet's
north at +X is shared knowledge with `HubVignettes.magnetism()`, exactly
as before. The launcher's elevation plane is RealityKit XY, so the
quadrant stands in Blender's XZ plane on the -Y (reader) side.

COLOURS. The charge spheres wear the palette's `positiveUI`/`negativeUI`
(systemRed / systemBlue), converted to linear, so the miniature agrees
with `FieldRenderer.positiveColor` the same way the magnet field lines
were made to agree with `MagnetismRenderer.lineColor`.
"""

import os
import sys

sys.dont_write_bytecode = True
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import math  # noqa: E402
import bpy  # noqa: E402
from mathutils import Matrix, Vector  # noqa: E402
from blenderprops import (reset_scene, material, shade, bevel, box,  # noqa: E402
                          cylinder, cone, band, letter, join, export)

ROOT = os.environ.get(
    "MODULEPROPS_OUT",
    os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                 "PhysicsPlayground", "Models", "Hub"))


def cut(obj, cutters):
    """Boolean-difference a list of throwaway objects out of `obj`."""
    for cutter in cutters:
        bpy.context.view_layer.objects.active = obj
        modifier = obj.modifiers.new("cut", "BOOLEAN")
        modifier.operation = "DIFFERENCE"
        modifier.object = cutter
        modifier.solver = "EXACT"
        bpy.ops.object.modifier_apply(modifier="cut")
        bpy.data.objects.remove(cutter, do_unlink=True)
    return obj


def spin(obj, angle, axis, pivot=(0, 0, 0)):
    """Rotate `obj` about `pivot` in world space, whatever its origin.

    Needed because `transform_apply(scale=True)` also applies LOCATION —
    the operator's other arguments default to True — so a `box()` has its
    origin at the world origin with the position baked into the verts,
    and `rotation_euler` on one spins it round the world origin instead
    of round itself. Composing on `matrix_world` is exact either way."""
    pivot = Vector(pivot)
    obj.matrix_world = (Matrix.Translation(pivot)
                        @ Matrix.Rotation(angle, 4, axis)
                        @ Matrix.Translation(-pivot)) @ obj.matrix_world
    return obj


def reface(obj):
    """Drop the empty material slot a boolean leaves behind.

    Blender 5.2's boolean apply copies the cutter's material slots onto
    the result, and a cutter with no material contributes one EMPTY slot
    at index 0 — where every face already points. `shade` then appends
    the real material into slot 1, no face references it, and the part
    renders default white. Every `band`- or `cut`-produced object goes
    through here before shading."""
    obj.data.materials.clear()
    return obj


# Shared finishes. One brass and one steel across every module, so the
# props read as one workshop's output rather than six vendors'.
def brass(name="Brass"):
    return material(name, (0.58, 0.44, 0.16), roughness=0.26, metallic=0.92)


def steel(name="Steel"):
    return material(name, (0.46, 0.48, 0.51), roughness=0.38, metallic=0.88)


def cast_iron(name="Cast"):
    return material(name, (0.048, 0.055, 0.068), roughness=0.52)


def ivory(name="Ivory"):
    return material(name, (0.90, 0.89, 0.84), roughness=0.48)


# ---------------------------------------------------------- pendulum stand
# A precision laboratory stand: heavy cast base on levelling feet, two
# turned columns with knurled lock collars, a crossbeam, and three real
# pivot assemblies — brass collar, clevis plates, cross pin — where the
# cables hang. The old A-frame gantry read as scaffolding; a pendulum
# module's apparatus is the thing the period formula trusts, and it
# should look like it was machined to be trusted.
#
# Width is the longest dimension, but the stand is TALL for a reason:
# the bobs must swing above the base plate — a bob dipping below the
# apparatus's own table reads as a glitch — so the cable room between
# the pins and the base is what sets the exhibit's whole vertical
# presence, and the no-streak criterion in HubVignetteTests is the
# floor under this number.

STAND_W = 0.400
STAND_H = 0.255
PIVOT_XS = (-0.124, 0.0, 0.124)   # matches the ±0.31 · width the hangs use


def build_pendulum_stand():
    base_mat = cast_iron("StandBase")
    steel_mat = steel("StandSteel")
    brass_mat = brass("StandBrass")

    parts = []

    base = box("Base", (STAND_W * 0.96, 0.130, 0.012), location=(0, 0, 0.006))
    bevel(base, 0.004, segments=3)
    parts.append(shade(base, base_mat))

    # Levelling feet, one per corner — knurled discs, which is what makes
    # a base a piece of apparatus rather than a plinth.
    for fx in (-1, 1):
        for fy in (-1, 1):
            foot = cylinder("Foot", 0.009, 0.006,
                            location=(fx * STAND_W * 0.43, fy * 0.048, -0.003),
                            vertices=18)
            parts.append(shade(foot, steel_mat))

    beam_z = STAND_H
    for side in (-1, 1):
        x = side * 0.155
        # The column stops at the beam's underside; the boss above wraps
        # both, which is how a real stand carries a crossbeam — a column
        # run straight through the joint reads as scaffolding.
        column_top = beam_z - 0.0075
        column = cylinder("Column", 0.0085, column_top - 0.012,
                          location=(x, 0, 0.012 + (column_top - 0.012) / 2))
        parts.append(shade(column, steel_mat))

        # A flange where the column lands on the base, so the joint is a
        # mounting rather than a stick in a slab.
        flange = cylinder("Flange", 0.0125, 0.0042, location=(x, 0, 0.0141),
                          vertices=28)
        bevel(flange, 0.0010, segments=2, angle=50)
        parts.append(shade(flange, steel_mat))

        # The knurled lock collar, with its thumbscrew poking out the back.
        collar = cylinder("Lock", 0.0118, 0.009, location=(x, 0, beam_z - 0.034),
                          vertices=18)
        parts.append(shade(collar, brass_mat))
        thumb = cylinder("Thumb", 0.0021, 0.009,
                         location=(x, 0.013, beam_z - 0.034),
                         rotation=(math.radians(90), 0, 0), vertices=12)
        parts.append(shade(thumb, brass_mat))

        # The boss: a vertical collar swallowing the column top and the
        # beam where they meet.
        boss = cylinder("Boss", 0.0122, 0.0235, location=(x, 0, beam_z - 0.0035),
                        vertices=28)
        bevel(boss, 0.0012, segments=2, angle=50)
        parts.append(shade(boss, cast_iron("StandBoss")))

    beam = cylinder("Beam", 0.0075, STAND_W, location=(0, 0, beam_z),
                    rotation=(0, math.radians(90), 0))
    parts.append(shade(beam, steel_mat))

    # Three pivot assemblies. The collar grips the beam; the clevis plates
    # hang below it holding the cross pin the cable's knife edge rides on.
    # The pin runs in DEPTH (Blender Y): the planar pendulums swing in the
    # reader's plane, and a pivot axis along the beam would swing them
    # into the wall instead.
    for x in PIVOT_XS:
        collar = cylinder("PivotCollar", 0.0102, 0.011,
                          location=(x, 0, beam_z),
                          rotation=(0, math.radians(90), 0), vertices=24)
        parts.append(shade(collar, brass_mat))
        for dy in (-1, 1):
            plate = box("Clevis", (0.0095, 0.0022, 0.0150),
                        location=(x, dy * 0.0042, beam_z - 0.0140))
            bevel(plate, 0.0008, segments=2)
            parts.append(shade(plate, brass_mat))
        pin = cylinder("Pin", 0.0018, 0.0135,
                       location=(x, 0, beam_z - 0.0195),
                       rotation=(math.radians(90), 0, 0), vertices=12)
        parts.append(shade(pin, steel_mat))

    return join("PendulumStand", parts)


# ------------------------------------------------------------ pendulum bob
# A turned bob: brass sphere with spun flats at the poles, a stem, and the
# eye the cable ties to. The eye faces the reader, which is the plane the
# planar pendulums swing in.

def build_pendulum_bob():
    brass_mat = brass("BobBrass")
    steel_mat = steel("BobSteel")

    parts = []
    radius = 0.020

    bpy.ops.mesh.primitive_uv_sphere_add(radius=radius, segments=48,
                                         ring_count=24)
    body = bpy.context.active_object
    body.name = "BobBody"
    parts.append(shade(body, brass_mat))

    for z in (-1, 1):
        flat = cylinder("Flat", 0.0068, 0.0018,
                        location=(0, 0, z * (radius - 0.0004)), vertices=28)
        parts.append(shade(flat, brass_mat))

    stem = cylinder("Stem", 0.0022, 0.0075, location=(0, 0, radius + 0.0030),
                    vertices=16)
    parts.append(shade(stem, steel_mat))

    eye = band("Eye", 0.0042, 0.0024, 0.0018,
               location=(0, 0, radius + 0.0095),
               rotation=(math.radians(90), 0, 0), vertices=24)
    parts.append(shade(reface(eye), steel_mat))

    return join("PendulumBob", parts)


# -------------------------------------------------------------- bar magnet
# A real Alnico bar: 60 x 18 x 18 mm, chamfered arrises, two-tone satin
# paint with a bare-steel seam, and N/S moulded into the top face deep
# enough to catch the key light. South at -X, north at +X — shared with
# `HubVignettes.magnetism()`, exactly as before.

MAGNET_L, MAGNET_W, MAGNET_H = 0.060, 0.018, 0.018


def build_bar_magnet():
    red = material("MagnetNorth", (0.40, 0.028, 0.020), roughness=0.30)
    blue = material("MagnetSouth", (0.018, 0.065, 0.40), roughness=0.30)
    seam_mat = steel("MagnetSeam")
    marks = ivory("MagnetMarks")

    parts = []
    seam = 0.0018
    half = (MAGNET_L - seam) / 2

    south = box("South", (half, MAGNET_W, MAGNET_H),
                location=(-(seam / 2 + half / 2), 0, 0))
    bevel(south, 0.0010, segments=3)
    parts.append(shade(south, blue))

    north = box("North", (half, MAGNET_W, MAGNET_H),
                location=(seam / 2 + half / 2, 0, 0))
    bevel(north, 0.0010, segments=3)
    parts.append(shade(north, red))

    girdle = box("Seam", (seam, MAGNET_W + 0.0002, MAGNET_H + 0.0002))
    parts.append(shade(girdle, seam_mat))

    for character, x in (("S", -MAGNET_L * 0.27), ("N", MAGNET_L * 0.27)):
        glyph = letter("Mark" + character, character, size=0.0140,
                       extrude=0.0009,
                       location=(x, 0, MAGNET_H / 2 - 0.0002))
        parts.append(shade(glyph, marks, smooth=False))

    return join("BarMagnet", parts)


# ----------------------------------------------------------------- compass
# A brass-bowl compass: rim, ivory dial with cardinal and minor ticks, a
# jewel pivot at the centre — and the needle in its own file, because the
# needle is the moving part and the Swift closure aims it along the TRUE
# local field of the two bars, using the same integrator that traces the
# lines. The needle is symmetric about its pivot on purpose: the importer
# recentres on the bounding box, and symmetry is what makes that centring
# also be the pivot.

def build_compass_body():
    brass_mat = brass("CompassBrass")
    dial_mat = ivory("CompassDial")
    dark = material("CompassMarks", (0.06, 0.065, 0.075), roughness=0.45)
    steel_mat = steel("CompassSteel")

    parts = []

    rim = band("Rim", 0.0200, 0.0155, 0.0100, vertices=64)
    bevel(rim, 0.0007, segments=2, angle=50)
    parts.append(shade(reface(rim), brass_mat))

    dial = cylinder("Dial", 0.0150, 0.0030, location=(0, 0, -0.0033),
                    vertices=64)
    parts.append(shade(dial, dial_mat))

    # Cardinal and minor ticks, radial, raised off the dial face.
    dial_top = -0.0033 + 0.0015
    for index in range(12):
        angle = index * math.pi / 6
        major = index % 3 == 0
        length = 0.0050 if major else 0.0028
        at = (math.cos(angle) * 0.0118, math.sin(angle) * 0.0118,
              dial_top + 0.0004)
        tick = box("Tick", (length, 0.0014, 0.0008), location=at)
        spin(tick, angle, "Z", pivot=at)
        parts.append(shade(tick, dark, smooth=False))

    glyph = letter("MarkN", "N", size=0.0072, extrude=0.0006,
                   location=(0, 0.0072, dial_top))
    parts.append(shade(glyph, dark, smooth=False))

    jewel = cone("Jewel", 0.0014, 0.0004, 0.0022, location=(0, 0, dial_top + 0.0008))
    parts.append(shade(jewel, steel_mat))

    foot = cylinder("Foot", 0.0065, 0.0022, location=(0, 0, -0.0056),
                    vertices=32)
    parts.append(shade(foot, brass_mat))

    return join("CompassBody", parts)


def build_compass_needle():
    red = material("NeedleNorth", (0.40, 0.028, 0.020), roughness=0.30)
    steel_mat = steel("NeedleSteel")

    parts = []
    # Two flattened four-sided spikes, tip to tip: a lozenge needle.
    for direction, mat in ((1, red), (-1, steel_mat)):
        spike = cone("Half", 0.0026, 0.0, 0.0150,
                     location=(direction * 0.0075, 0, 0),
                     rotation=(0, direction * math.radians(90), 0))
        spike.scale = (1, 1, 0.62)
        bpy.ops.object.select_all(action="DESELECT")
        spike.select_set(True)
        bpy.context.view_layer.objects.active = spike
        bpy.ops.object.transform_apply(scale=True)
        parts.append(shade(spike, mat))

    cap = cylinder("Cap", 0.0021, 0.0018, location=(0, 0, 0.0002), vertices=16)
    parts.append(shade(cap, brass("NeedleCap")))

    return join("CompassNeedle", parts)


# ------------------------------------------------------- launcher carriage
# The mount the room's own barrel sits in: a machined circular platform
# with a bolt circle, a turret, a trunnion yoke — and an elevation
# quadrant on the reader's side, ticked every ten degrees. The pointer is
# its own file and rides the Swift `aim` entity, so whatever angle the
# miniature actually launches at is the angle the instrument reads. A
# baked pointer would lie the day the launch angle changed.
#
# The trunnion centre is at z = TRUNNION_Z with the base bottom at z = 0;
# Swift places the carriage so the trunnion lands on the aim origin using
# that ratio of the total height.

CARRIAGE_TRUNNION_Z = 0.068
CARRIAGE_TOP_Z = 0.083
QUADRANT_R = 0.040


def build_launcher_carriage():
    base_mat = cast_iron("CarriageBase")
    steel_mat = steel("CarriageSteel")
    brass_mat = brass("CarriageBrass")
    marks = ivory("CarriageMarks")

    parts = []

    base = cylinder("Platform", 0.052, 0.011, location=(0, 0, 0.0055),
                    vertices=64)
    bevel(base, 0.0022, segments=3, angle=50)
    parts.append(shade(base, base_mat))

    for index in range(6):
        angle = index * math.pi / 3 + math.pi / 6
        bolt = cylinder("Bolt", 0.0030, 0.0022,
                        location=(math.cos(angle) * 0.0445,
                                  math.sin(angle) * 0.0445, 0.0115),
                        vertices=6)
        parts.append(shade(bolt, steel_mat, smooth=False))

    turret = cylinder("Turret", 0.033, 0.011, location=(0, 0, 0.0165),
                      vertices=48)
    bevel(turret, 0.0015, segments=2, angle=50)
    parts.append(shade(turret, steel_mat))

    # The yoke: two uprights astride the barrel, trunnion bosses at the top.
    for side in (-1, 1):
        arm = box("Yoke", (0.0145, 0.0060, 0.052),
                  location=(0, side * 0.0165, 0.046))
        bevel(arm, 0.0018, segments=2)
        parts.append(shade(arm, steel_mat))
        boss = cylinder("Boss", 0.0062, 0.0052,
                        location=(0, side * 0.0200, CARRIAGE_TRUNNION_Z),
                        rotation=(math.radians(90), 0, 0), vertices=24)
        parts.append(shade(boss, brass_mat))

    # The quadrant: a 0-90° sector in the elevation plane, on the
    # reader's side, its centre on the trunnion axis. A solid sector
    # plate with a brass rim arc and raised ticks — an instrument face,
    # not a wire arc. Both discs are cut to the sector with two
    # half-space boxes.
    plate_y = -0.0230
    plate = cylinder("QuadrantPlate", QUADRANT_R - 0.0018, 0.0016,
                     location=(0, plate_y, CARRIAGE_TRUNNION_Z),
                     rotation=(math.radians(90), 0, 0), vertices=96)
    bpy.ops.object.transform_apply(rotation=True, location=True)
    cut(plate, [
        box("CutLeft", (0.30, 0.30, 0.30),
            location=(-0.15, plate_y, CARRIAGE_TRUNNION_Z)),
        box("CutLow", (0.30, 0.30, 0.30),
            location=(0, plate_y, CARRIAGE_TRUNNION_Z - 0.15)),
    ])
    parts.append(shade(reface(plate), cast_iron("QuadrantFace")))

    rim = band("QuadrantRim", QUADRANT_R, QUADRANT_R - 0.0034, 0.0026,
               rotation=(math.radians(90), 0, 0), vertices=96)
    rim.location = (0, plate_y, CARRIAGE_TRUNNION_Z)
    bpy.ops.object.select_all(action="DESELECT")
    rim.select_set(True)
    bpy.context.view_layer.objects.active = rim
    bpy.ops.object.transform_apply(location=True)
    cut(rim, [
        box("CutLeft", (0.30, 0.30, 0.30),
            location=(-0.15, plate_y, CARRIAGE_TRUNNION_Z)),
        box("CutLow", (0.30, 0.30, 0.30),
            location=(0, plate_y, CARRIAGE_TRUNNION_Z - 0.15)),
    ])
    parts.append(shade(reface(rim), brass_mat))

    # The hub carrying the plate off the trunnion boss.
    hub = cylinder("QuadrantHub", 0.0044, 0.0105,
                   location=(0, -0.0180, CARRIAGE_TRUNNION_Z),
                   rotation=(math.radians(90), 0, 0), vertices=24)
    parts.append(shade(hub, brass_mat))

    # Ticks every 10°, longer every 30°, raised off the plate's front.
    tick_y = plate_y - 0.0013
    for tens in range(10):
        angle = math.radians(tens * 10)
        major = tens % 3 == 0
        length = 0.0058 if major else 0.0034
        radius = QUADRANT_R - 0.0034 - length / 2 - 0.0008
        at = (math.cos(angle) * radius, tick_y,
              CARRIAGE_TRUNNION_Z + math.sin(angle) * radius)
        tick = box("Tick", (length, 0.0010, 0.0013), location=at)
        spin(tick, -angle, "Y", pivot=at)
        parts.append(shade(tick, marks, smooth=False))

    return join("LauncherCarriage", parts)


def build_quadrant_pointer():
    """The elevation pointer, authored along +X with its pivot at the
    origin — a tapered needle, a hub, and a short counterweight tail.
    Swift restores the pivot after the importer recentres the bounds."""
    red = material("PointerRed", (0.40, 0.028, 0.020), roughness=0.30)
    steel_mat = steel("PointerSteel")

    parts = []
    needle = cone("Needle", 0.0016, 0.0, 0.0392,
                  location=(0.0196, 0, 0),
                  rotation=(0, math.radians(90), 0))
    needle.scale = (1, 1, 0.5)
    bpy.ops.object.select_all(action="DESELECT")
    needle.select_set(True)
    bpy.context.view_layer.objects.active = needle
    bpy.ops.object.transform_apply(scale=True)
    parts.append(shade(needle, red))

    hub = cylinder("Hub", 0.0036, 0.0022, location=(0, 0, 0),
                   rotation=(math.radians(90), 0, 0), vertices=24)
    parts.append(shade(hub, steel_mat))

    tail = cylinder("Tail", 0.0011, 0.0075,
                    location=(-0.00475, 0, 0),
                    rotation=(0, math.radians(90), 0), vertices=12)
    parts.append(shade(tail, steel_mat))
    weight = cylinder("Weight", 0.0026, 0.0020, location=(-0.0085, 0, 0),
                      rotation=(math.radians(90), 0, 0), vertices=20)
    parts.append(shade(weight, steel_mat))

    return join("QuadrantPointer", parts)


# ------------------------------------------------------------ target stand
# The landing hoop, mounted: a horizontal ring the ball drops through, on
# a mast clamped at the ring's far edge, over a base plate. Replaces the
# floating torus — a target that stands somewhere is a consequence of the
# room; one that floats is a UI element.
#
# The ring's centre is at (RING_X, 0, RING_Z) with the base at z = 0, and
# its inner radius is RING_INNER: Swift uses these to put the ring centre
# exactly on the computed landing point.

RING_INNER = 0.0265
RING_X = -0.0290
RING_Z = 0.0600


def build_target_stand():
    base_mat = cast_iron("TargetBase")
    steel_mat = steel("TargetSteel")
    paint = material("TargetPaint", (0.06, 0.42, 0.16), roughness=0.32)

    parts = []

    base = cylinder("Base", 0.019, 0.0055, location=(0, 0, 0.00275),
                    vertices=48)
    bevel(base, 0.0016, segments=2, angle=50)
    parts.append(shade(base, base_mat))

    mast = cylinder("Mast", 0.0036, RING_Z - 0.0055,
                    location=(0, 0, 0.0055 + (RING_Z - 0.0055) / 2),
                    vertices=24)
    parts.append(shade(mast, steel_mat))

    clamp = box("Clamp", (0.0090, 0.0068, 0.0064), location=(0, 0, RING_Z))
    bevel(clamp, 0.0012, segments=2)
    parts.append(shade(clamp, steel_mat))

    ring = band("Ring", RING_INNER + 0.0038, RING_INNER, 0.0042,
                location=(RING_X, 0, RING_Z), vertices=80)
    bevel(ring, 0.0009, segments=2, angle=50)
    parts.append(shade(reface(ring), paint))

    return join("TargetStand", parts)



# ----------------------------------------------------------- comet nucleus
# A bilobed nucleus, 67P-shaped and 67P-dark: comets are among the darkest
# bodies in the solar system, albedo a few percent. Two overlapping
# icospheres roughened by layered noise, with a few boolean craters. The
# tail is procedural in Swift — it flexes, and it points away from the
# SUN, not behind the motion, which is the fact the miniature exists to
# get right.

def build_comet_nucleus():
    crust = material("CometCrust", (0.052, 0.048, 0.044), roughness=0.95)

    lobes = []
    for radius, location in ((0.0110, (0.0080, 0.0006, 0.0010)),
                             (0.0085, (-0.0106, 0.0018, -0.0014))):
        bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=4, radius=radius,
                                              location=location)
        lobe = bpy.context.active_object
        lobe.name = "Lobe"
        lobes.append(lobe)
    body = join("CometNucleus", lobes)

    # Layered displacement: broad lumps, then fine rubble.
    for tex_name, tex_type, scale, strength in (
            ("CometLumps", "CLOUDS", 0.0110, 0.0044),
            ("CometCrags", "VORONOI", 0.0060, -0.0016),
            ("CometRubble", "CLOUDS", 0.0026, 0.0020)):
        texture = bpy.data.textures.new(tex_name, type=tex_type)
        texture.noise_scale = scale
        bpy.context.view_layer.objects.active = body
        modifier = body.modifiers.new("displace", "DISPLACE")
        modifier.texture = texture
        modifier.strength = strength
        bpy.ops.object.modifier_apply(modifier="displace")

    # A few craters, sunk as boolean bites.
    craters = []
    for radius, location in ((0.0042, (0.0095, -0.0080, 0.0075)),
                             (0.0030, (-0.0035, -0.0075, -0.0060)),
                             (0.0026, (-0.0125, 0.0055, 0.0058))):
        bpy.ops.mesh.primitive_uv_sphere_add(radius=radius, location=location,
                                             segments=24, ring_count=12)
        crater = bpy.context.active_object
        crater.name = "Crater"
        craters.append(crater)
    cut(body, craters)

    return shade(reface(body), crust)


# ---------------------------------------------------------- charge spheres
# The dipole's charges as physical conductors: polished metal spheres in
# the palette's own red and blue, the sign moulded proud of the surface on
# the reader's side instead of floating beside the geometry as UI.

CHARGE_R = 0.019


def build_charge(sign):
    colour = (0.62, 0.045, 0.032) if sign == "+" else (0.012, 0.130, 0.700)
    body_mat = material("Charge" + sign, colour, roughness=0.22, metallic=0.85)
    mark = ivory("ChargeMark")

    parts = []
    bpy.ops.mesh.primitive_uv_sphere_add(radius=CHARGE_R, segments=48,
                                         ring_count=24)
    body = bpy.context.active_object
    body.name = "ChargeBody"
    parts.append(shade(body, body_mat))

    # The sign, rooted deep enough that its ends stay buried where the
    # sphere curves away. Reader side is -Y.
    bar_y = -(CHARGE_R - 0.0018)
    across = box("SignAcross", (0.0150, 0.0042, 0.0034),
                 location=(0, bar_y, 0))
    bevel(across, 0.0008, segments=2)
    parts.append(shade(across, mark))
    if sign == "+":
        up = box("SignUp", (0.0034, 0.0050, 0.0150),
                 location=(0, bar_y - 0.0002, 0))
        bevel(up, 0.0008, segments=2)
        parts.append(shade(up, mark))

    return join("Charge" + ("Plus" if sign == "+" else "Minus"), parts)


# ------------------------------------------------------------------- build

BUILDERS = {
    "PendulumStand": build_pendulum_stand,
    "PendulumBob": build_pendulum_bob,
    "BarMagnet": build_bar_magnet,
    "CompassBody": build_compass_body,
    "CompassNeedle": build_compass_needle,
    "LauncherCarriage": build_launcher_carriage,
    "QuadrantPointer": build_quadrant_pointer,
    "TargetStand": build_target_stand,
    "CometNucleus": build_comet_nucleus,
    "ChargePlus": lambda: build_charge("+"),
    "ChargeMinus": lambda: build_charge("-"),
}


def main():
    for name, builder in BUILDERS.items():
        reset_scene()
        built = builder()
        # Bake to an identity transform: `join` leaves the merged object
        # wearing its FIRST part's transform, and the pivot-authored
        # props (the pointer) rely on the USD origin being the authored
        # world origin. A bare transform_apply applies everything — the
        # operator's arguments default to True.
        bpy.ops.object.select_all(action="DESELECT")
        built.select_set(True)
        bpy.context.view_layer.objects.active = built
        bpy.ops.object.transform_apply()
        export([built], os.path.join(ROOT, name + ".usdz"))


if __name__ == "__main__":
    main()
