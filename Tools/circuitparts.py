#!/usr/bin/env python3
"""
Circuit Workshop's parts as LAB-KIT MODULES (2026-10-18), milled rather
than generated, and the turntable the floating circuit stands over.

    /Applications/Blender.app/Contents/MacOS/Blender --background \\
        --python Tools/circuitparts.py [-- Name ...]

Outputs, all under PhysicsPlayground/Models/Circuits/ (name a few after
`--` to mill only those):

    CircuitCarrier.usdz      the one carrier every part is mounted on: a
                             graphite plate with 45° chamfers front and
                             back, running end to end under the contacts,
                             and two brass traces along its top from the
                             part out to them
    CircuitBattery.usdz      a D-cell in brass clips, a raised + at −X
    CircuitACSource.usdz     a dial puck lying flat, "~" on its face (Swift
                             swings the needle with the EMF)
    CircuitResistorCaps.usdz the banded body's steel caps and bent legs —
                             the body stays procedural in Swift, because
                             its colour bands are a LIVE texture painted
                             from the value
    CircuitCapacitor.usdz    a radial electrolytic standing up, its − stripe
                             on the +X (terminal 1) side
    CircuitInductor.usdz     a copper-wound bobbin on graphite cradles
    CircuitBulb.usdz         a glass envelope on a copper screw base in a
                             champagne socket (Swift lights the filament)
    CircuitLED.usdz          a red dome on a flange and two legs
    CircuitMotor.usdz        a ribbed can on a cradle, teal faceplate and
                             shaft at +X (Swift spins the rotor)
    CircuitFuse.usdz         a glass cartridge with steel caps in brass
                             clips (Swift draws the filament, so it can blow)
    CircuitSwitch.usdz       a knife switch's block, pivot cheeks and
                             contact clip (Swift hangs the blade)
    CircuitStageDeck.usdz    the turntable's satin graphite deck
    CircuitStageRim.usdz     its knurled champagne rim

WHY LAB-KIT MODULES. The owner's choice for "improve the design of every
part". A bare component floating on two copper balls read as a diagram;
the same component mounted on a carrier, its schematic symbol inlaid in
the chamfer, wired to brass contacts by brass traces, reads as the
apparatus a physics bench hands you — one family, every part legible
from where you stand.

THE CONTRACT WITH THE RENDERER. Every part lies along X with its contacts
at ±0.085 on the axis line y = 0 — drawn in Swift as brass balls, they are
the terminals, so `CircuitsAlignmentTests` and the lead pull stand. The
carrier's top face is at y = CARRIER_TOP, and every component sits on it.
Each body, symbols included, stays inside |x| < 0.059 (the carry box's
clamp at the terminals' inner edge; `CircuitPropTests`); the carrier is
the one asset that runs past it: to the contacts' centres exactly, so two
parts snapped nose-to-tail butt their carriers end to end at the joint
rather than overlapping coplanar faces. Swift adds the moving
and lit pieces at the places named below (`CircuitsRenderer`): the bulb's
filament and glow at (0, BULB_CENTRE, 0), the LED's glow at (0, LED_GLOW,
0), the motor's rotor at (0.05, MOTOR_AXIS, 0), the switch blade pivoting
at (−0.028, SWITCH_PIVOT, 0), the resistor's body along X at (0,
RESISTOR_AXIS, 0), the fuse's filament at (0, FUSE_AXIS, 0), the
capacitor's gauge on the carrier's top in front of the can, the AC
needle on the dial at (0, AC_FACE, 0). Terminal 0 (a battery's +) is −X.

THE SYMBOL. ANSI, drawn in champagne tube on BOTH chamfers — mirrored on
the back one, so it reads from behind once the turntable turns the
circuit round.

HANDEDNESS. Blender (x, y, z) -> RealityKit (x, z, -y): up is Blender +Z,
the face toward the reader is Blender -Y, and X is X.
"""

import os
import sys

sys.dont_write_bytecode = True
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import math  # noqa: E402
import bpy  # noqa: E402
from blenderprops import (  # noqa: E402
    band, bevel, box, cone, cylinder, export, join, letter, material,
    reset_scene, shade, tube)

ROOT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                    "PhysicsPlayground", "Models", "Circuits")

ALONG_X = (0, math.pi / 2, 0)   # a Blender cylinder is built along Z


def coat(mat, weight, roughness):
    """The clearcoat `RenderKit.Materials.graphite` is defined by:
    metallic alone came back twice as bright over a real room (the
    retired gallery script recorded why; see git history)."""
    bsdf = mat.node_tree.nodes["Principled BSDF"]
    for key, value in (("Coat Weight", weight), ("Clearcoat", weight),
                       ("Coat Roughness", roughness),
                       ("Clearcoat Roughness", roughness)):
        if key in bsdf.inputs:
            bsdf.inputs[key].default_value = value
    return mat


def glass(name, colour, alpha, roughness=0.06):
    """See-through, as USD carries it. Blender's USD exporter never writes
    the Alpha socket — it writes `opacity` as 1 − Transmission Weight — so
    every glass part here shipped OPAQUE until 2026-10-18 and hid the
    filament it existed to show. Alpha stays set for Blender's own view."""
    mat = material(name, colour, roughness=roughness, metallic=0.0)
    bsdf = mat.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Alpha"].default_value = alpha
    bsdf.inputs["Transmission Weight"].default_value = 1 - alpha
    if hasattr(mat, "blend_method"):
        mat.blend_method = "BLEND"
    return mat


def stocks():
    """One alloy list for every part, so the bench and the room are
    visibly one system."""
    return {
        "graphite": coat(material("CircuitGraphite", (0.088, 0.090, 0.096),
                                  roughness=0.30, metallic=0.10), 0.60, 0.25),
        "steel": material("CircuitSteel", (0.60, 0.61, 0.64),
                          roughness=0.22, metallic=0.95),
        "copper": material("CircuitCopper", (0.72, 0.42, 0.22),
                           roughness=0.35, metallic=0.92),
        "champagne": material("CircuitChampagne", (0.83, 0.70, 0.45),
                              roughness=0.30, metallic=0.85),
        "blue": coat(material("CircuitBlue", (0.10, 0.17, 0.42),
                              roughness=0.35, metallic=0.10), 0.5, 0.3),
        "pale": material("CircuitPale", (0.90, 0.90, 0.88), roughness=0.6),
        "teal": material("CircuitTeal", (0.14, 0.48, 0.52),
                         roughness=0.35, metallic=0.2),
        "bulbGlass": glass("CircuitBulbGlass", (0.95, 0.96, 1.0), 0.32),
        "fuseGlass": glass("CircuitFuseGlass", (0.95, 0.96, 1.0), 0.30),
        "ledDome": glass("CircuitLEDDome", (0.90, 0.20, 0.15), 0.75, roughness=0.15),
        # The lab kit's contacts and traces: brass, warmer than the
        # champagne trim, the way a binding post and its strap read.
        "brass": material("CircuitBrass", (0.78, 0.62, 0.32),
                          roughness=0.30, metallic=0.90),
        "cream": material("CircuitCream", (0.86, 0.83, 0.74), roughness=0.55),
    }


# ----------------------------------------------------------- the turntable

STAGE_RADIUS = 0.45      # the rim's outer edge; `CircuitsModel.stageRadius`
STAGE_THICKNESS = 0.012
RIM_DEPTH = 0.016        # the band's own radial width
KNURLS = 180


def build_stage_deck(s):
    parts = []
    deck_radius = STAGE_RADIUS - RIM_DEPTH
    disc = cylinder("StageDeck", deck_radius, STAGE_THICKNESS,
                    location=(0, 0, -STAGE_THICKNESS / 2), vertices=192)
    bevel(disc, 0.0015, segments=3)
    # Flat-shaded: smoothing blends the bevel's side normals across the cap
    # and the top breaks into wedges. And satin, not the parts' clear coat:
    # 0.9 m of glossy graphite seen at a grazing angle mirrors the room and
    # reads as a pale slab (the first still).
    satin = coat(material("StageSatinGraphite", (0.070, 0.072, 0.078),
                          roughness=0.55, metallic=0.05), 0.15, 0.45)
    parts.append(shade(disc, satin, smooth=False))
    # The keyline, two centimetres in: the milled edge every stage wears.
    key = band("StageKeyline", deck_radius - 0.020, deck_radius - 0.022, 0.0007,
               location=(0, 0, 0.00025), vertices=192)
    parts.append(shade(key, s["champagne"]))
    return join("CircuitStageDeck", parts)


def build_stage_rim(s):
    parts = []
    inner = STAGE_RADIUS - RIM_DEPTH
    ring = band("StageRim", STAGE_RADIUS - 0.002, inner, STAGE_THICKNESS + 0.002,
                location=(0, 0, -STAGE_THICKNESS / 2), vertices=192)
    bevel(ring, 0.0010, segments=2)
    parts.append(shade(ring, s["champagne"]))
    # Knurling: the shelf crown's "this turns", in a ring of fine ridges.
    for index in range(KNURLS):
        angle = 2 * math.pi * index / KNURLS
        ridge = box("StageKnurl", (0.0042, 0.0022, STAGE_THICKNESS - 0.003),
                    location=((STAGE_RADIUS - 0.0011) * math.cos(angle),
                              (STAGE_RADIUS - 0.0011) * math.sin(angle),
                              -STAGE_THICKNESS / 2))
        ridge.rotation_euler = (0, 0, angle + math.pi / 2)
        parts.append(shade(ridge, s["champagne"], smooth=False))
    # The foot, set back under the deck so its edge floats over a shadow line.
    foot = band("StageFoot", STAGE_RADIUS - 0.050, STAGE_RADIUS - 0.064, 0.004,
                location=(0, 0, -STAGE_THICKNESS - 0.002), vertices=192)
    parts.append(shade(foot, s["champagne"]))
    return join("CircuitStageRim", parts)


# ------------------------------------------------------------ the carrier

CARRIER_TOP = -0.012        # RealityKit y of the top face every part sits on
CARRIER_BOTTOM = -0.026
CARRIER_HALF_X = 0.085      # to the contacts' centres (terminalOffset)
CARRIER_HALF_DEPTH = 0.030
CHAMFER = 0.009             # 45°: a face 12.7 mm wide for the symbol
TRACE_INNER = 0.010         # the traces start this far off centre...
TRACE_OUTER = 0.080         # ...and end under the contact at 0.085
TRACE_WIDTH = 0.008
TRACE_THICKNESS = 0.0015

# Where Swift mounts the live pieces (see the docstring), RealityKit y.
BULB_CENTRE = 0.024
LED_GLOW = 0.013
MOTOR_AXIS = 0.008
SWITCH_PIVOT = 0.004
RESISTOR_AXIS = 0.006
FUSE_AXIS = 0.000
AC_FACE = -0.0018


def prism_x(name, profile, x0, x1, mat):
    """A plate along X with a cross-section `profile` [(y, z), ...] in
    Blender's y-z plane, counter-clockwise seen from +X."""
    verts = [(x0, y, z) for y, z in profile] + [(x1, y, z) for y, z in profile]
    n = len(profile)
    faces = [list(reversed(range(n))), list(range(n, 2 * n))]
    for i in range(n):
        j = (i + 1) % n
        faces.append([i, j, n + j, n + i])
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(verts, [], faces)
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    return shade(obj, mat, smooth=False)


def build_carrier(s):
    parts = []
    # RealityKit y is Blender z; the reader's side is Blender −y.
    top, bottom, d, c = CARRIER_TOP, CARRIER_BOTTOM, CARRIER_HALF_DEPTH, CHAMFER
    profile = [(-d, bottom), (d, bottom), (d, top - c), (d - c, top),
               (-(d - c), top), (-d, top - c)]
    plate = prism_x("Carrier", profile, -CARRIER_HALF_X, CARRIER_HALF_X, s["graphite"])
    bevel(plate, 0.0012, segments=2, angle=30)
    parts.append(plate)
    for side in (-1, 1):
        length = TRACE_OUTER - TRACE_INNER
        trace = box("CarrierTrace", (length, TRACE_WIDTH, TRACE_THICKNESS),
                    location=(side * (TRACE_INNER + length / 2), 0,
                              top + TRACE_THICKNESS / 2))
        bevel(trace, 0.0005, segments=1)
        parts.append(shade(trace, s["brass"]))
        rivet = cylinder("CarrierRivet", 0.0024, 0.0012,
                         location=(side * 0.064, 0, top + TRACE_THICKNESS + 0.0006),
                         vertices=24)
        parts.append(shade(rivet, s["brass"]))
    return join("CircuitCarrier", parts)


# ------------------------------------------------------------- the symbols

def _chamfer_point(u, v, back):
    """A point of a symbol drawn in (u along X, v up the chamfer), lifted a
    hair off the chamfer face; the back one mirrors u to read from behind."""
    centre_y = CARRIER_HALF_DEPTH - CHAMFER / 2
    centre_z = CARRIER_TOP - CHAMFER / 2
    lift = 0.0005
    r = math.sqrt(0.5)
    if back:
        return (-u, centre_y - v * r + lift * r, centre_z + v * r + lift * r)
    return (u, -centre_y + v * r - lift * r, centre_z + v * r + lift * r)


def _circle(cx, cy, radius, start=0.0, end=2 * math.pi, steps=24):
    return [(cx + radius * math.cos(start + (end - start) * i / steps),
             cy + radius * math.sin(start + (end - start) * i / steps))
            for i in range(steps + 1)]


def _lead(a, b):
    return [(a, 0.0), (b, 0.0)]


SYMBOLS = {
    "battery": [_lead(-0.034, -0.0035), [(-0.0035, -0.0045), (-0.0035, 0.0045)],
                [(0.0025, -0.0025), (0.0025, 0.0025)], _lead(0.0025, 0.034),
                [(-0.011, 0.0032), (-0.006, 0.0032)], [(-0.0085, 0.0008), (-0.0085, 0.0052)]],
    "acSource": [_lead(-0.034, -0.0045), _lead(0.0045, 0.034), _circle(0, 0, 0.0045),
                 [(-0.003 + 0.006 * i / 16, 0.0016 * math.sin(2 * math.pi * i / 16))
                  for i in range(17)]],
    "resistor": [[(-0.034, 0), (-0.012, 0), (-0.010, 0.003), (-0.006, -0.003), (-0.002, 0.003),
                  (0.002, -0.003), (0.006, 0.003), (0.010, -0.003), (0.012, 0), (0.034, 0)]],
    "capacitor": [_lead(-0.034, -0.0015), [(-0.0015, -0.0045), (-0.0015, 0.0045)],
                  _circle(0.0075, 0, 0.006, math.radians(132), math.radians(228), 12),
                  _lead(0.0015, 0.034)],
    "inductor": [_lead(-0.034, -0.012),
                 sum([_circle(cx, 0, 0.003, math.pi, 0, 12) for cx in (-0.009, -0.003, 0.003, 0.009)], []),
                 _lead(0.012, 0.034)],
    "bulb": [_lead(-0.034, -0.0045), _lead(0.0045, 0.034), _circle(0, 0, 0.0045),
             [(-0.0032, -0.0032), (0.0032, 0.0032)], [(-0.0032, 0.0032), (0.0032, -0.0032)]],
    "led": [_lead(-0.034, -0.003), _lead(0.003, 0.034),
            [(-0.003, -0.004), (-0.003, 0.004), (0.003, 0), (-0.003, -0.004)],
            [(0.003, -0.004), (0.003, 0.004)],
            [(0.0005, 0.0035), (0.0028, 0.0054)], [(0.0030, 0.0030), (0.0053, 0.0049)]],
    "motor": [_lead(-0.034, -0.0045), _lead(0.0045, 0.034), _circle(0, 0, 0.0045),
              [(-0.0022, -0.0022), (-0.0022, 0.0022), (0, 0), (0.0022, 0.0022), (0.0022, -0.0022)]],
    "fuse": [_lead(-0.034, 0.034),
             [(-0.008, -0.0025), (0.008, -0.0025), (0.008, 0.0025), (-0.008, 0.0025), (-0.008, -0.0025)]],
    "switcher": [_lead(-0.034, -0.0070), _circle(-0.006, 0, 0.001, steps=10),
                 [(-0.006, 0.0008), (0.0060, 0.0045)], _circle(0.007, 0, 0.001, steps=10),
                 _lead(0.0080, 0.034)],
}


def symbol(kind, s):
    strokes = []
    for back in (False, True):
        for index, line in enumerate(SYMBOLS[kind]):
            points = [_chamfer_point(u, v, back) for u, v in line]
            strokes.append(tube("Symbol%d" % index, points, 0.00055, s["champagne"], resolution=2))
    return strokes


# ------------------------------------------------------------- the parts


def clip(name, x, radius, height, s):
    """A brass U-clip standing on the trace: two cheeks either side of a
    cylinder of `radius` along X, its axis at `height`."""
    parts = []
    base = box(name + "Base", (0.006, 2 * radius + 0.004, 0.002),
               location=(x, 0, CARRIER_TOP + 0.001))
    parts.append(shade(base, s["brass"]))
    for side in (-1, 1):
        cheek = box(name + "Cheek", (0.006, 0.0016, height - CARRIER_TOP + 0.002),
                    location=(x, side * (radius + 0.0012), (height + CARRIER_TOP) / 2 + 0.001))
        bevel(cheek, 0.0005, segments=1)
        parts.append(shade(cheek, s["brass"]))
    return parts


def build_battery(s):
    parts = symbol("battery", s)
    radius, axis = 0.0165, CARRIER_TOP + 0.0165 + 0.004
    can = cylinder("BatteryCan", radius, 0.068, location=(0.001, 0, axis), rotation=ALONG_X)
    bevel(can, 0.0022, segments=3)
    parts.append(shade(can, s["graphite"]))
    ring = band("BatteryBand", radius + 0.0006, radius - 0.001, 0.006,
                location=(-0.024, 0, axis), rotation=ALONG_X)
    parts.append(shade(ring, s["champagne"]))
    nipple = cylinder("BatteryNipple", 0.0055, 0.004, location=(-0.035, 0, axis), rotation=ALONG_X)
    bevel(nipple, 0.001, segments=2)
    parts.append(shade(nipple, s["steel"]))
    flat = cylinder("BatteryFlat", 0.010, 0.0015, location=(0.0355, 0, axis), rotation=ALONG_X)
    parts.append(shade(flat, s["steel"]))
    plus = letter("BatteryPlus", "+", 0.010, 0.0006,
                  location=(-0.012, 0, axis + radius - 0.0002))
    parts.append(shade(plus, s["champagne"]))
    # End springs: brass tabs up from the traces to each end of the cell.
    for x in (-0.0395, 0.0375):
        tab = box("BatteryTab", (0.0015, 0.010, axis - CARRIER_TOP + 0.004),
                  location=(x, 0, (axis + CARRIER_TOP) / 2 + 0.002))
        parts.append(shade(tab, s["brass"]))
    parts += clip("BatteryClip", -0.016, radius, axis, s)
    parts += clip("BatteryClip", 0.018, radius, axis, s)
    return join("CircuitBattery", parts)


def build_ac_source(s):
    parts = symbol("acSource", s)
    puck = cylinder("ACPuck", 0.021, 0.010, location=(0, 0, CARRIER_TOP + 0.005), vertices=64)
    bevel(puck, 0.0015, segments=3)
    parts.append(shade(puck, s["graphite"]))
    rim = band("ACRim", 0.0216, 0.0190, 0.0104, location=(0, 0, CARRIER_TOP + 0.005), vertices=64)
    parts.append(shade(rim, s["champagne"]))
    face = cylinder("ACFace", 0.0185, 0.0006, location=(0, 0, AC_FACE - 0.0003), vertices=64)
    parts.append(shade(face, s["cream"]))
    # Ticks across the needle's ±60° swing, needle pointing away at rest.
    for degrees in (-60, -30, 0, 30, 60):
        a = math.radians(degrees)
        tick = box("ACTick", (0.0008, 0.003, 0.0006),
                   location=(0.0145 * math.sin(a), 0.0145 * math.cos(a), AC_FACE + 0.0002))
        tick.rotation_euler = (0, 0, -a)
        parts.append(shade(tick, s["graphite"]))
    wave = letter("ACWave", "~", 0.012, 0.0005, location=(0, -0.008, AC_FACE + 0.0001))
    parts.append(shade(wave, s["graphite"]))
    # Straps from the puck's edge onto the traces.
    for side in (-1, 1):
        strap = box("ACStrap", (0.016, 0.004, 0.0015),
                    location=(side * 0.024, 0, CARRIER_TOP + 0.0022))
        parts.append(shade(strap, s["brass"]))
    return join("CircuitACSource", parts)


def build_resistor_caps(s):
    parts = symbol("resistor", s)
    for x in (-0.0225, 0.0225):
        cap = cylinder("ResistorCap", 0.0126, 0.006, location=(x, 0, RESISTOR_AXIS),
                       rotation=ALONG_X)
        bevel(cap, 0.0010, segments=2)
        parts.append(shade(cap, s["steel"]))
    # Bent legs: out of each cap and down onto the trace.
    for side in (-1, 1):
        leg = tube("ResistorLeg", [(side * 0.025, 0, RESISTOR_AXIS), (side * 0.032, 0, RESISTOR_AXIS),
                                   (side * 0.034, 0, RESISTOR_AXIS - 0.002),
                                   (side * 0.034, 0, CARRIER_TOP + 0.0015)],
                   0.0009, s["steel"], resolution=3)
        parts.append(leg)
    return join("CircuitResistorCaps", parts)


def build_capacitor(s):
    parts = symbol("capacitor", s)
    base = cylinder("CapSleeve", 0.0130, 0.003, location=(0, 0, CARRIER_TOP + 0.0015))
    parts.append(shade(base, s["graphite"]))
    can = cylinder("CapCan", 0.0125, 0.036, location=(0, 0, CARRIER_TOP + 0.003 + 0.018),
                   vertices=64)
    bevel(can, 0.0018, segments=3)
    parts.append(shade(can, s["blue"]))
    stripe = box("CapStripe", (0.0012, 0.009, 0.032),
                 location=(0.0122, 0, CARRIER_TOP + 0.003 + 0.018))
    parts.append(shade(stripe, s["pale"]))
    top = CARRIER_TOP + 0.003 + 0.036
    for angle in (0, math.pi / 2):
        vent = box("CapVent", (0.016, 0.0012, 0.0006), location=(0, 0, top + 0.0002))
        vent.rotation_euler = (0, 0, angle)
        parts.append(shade(vent, s["steel"]))
    # Legs out of the base, along the carrier to the traces.
    for side in (-1, 1):
        leg = tube("CapLeg", [(side * 0.004, 0, CARRIER_TOP + 0.002), (side * 0.004, 0, CARRIER_TOP + 0.001),
                              (side * 0.013, 0, CARRIER_TOP + 0.001)], 0.0007, s["steel"], resolution=3)
        parts.append(leg)
    return join("CircuitCapacitor", parts)


def build_inductor(s):
    parts = symbol("inductor", s)
    axis = CARRIER_TOP + 0.015 + 0.004
    core = cylinder("InductorCore", 0.008, 0.052, location=(0, 0, axis), rotation=ALONG_X)
    parts.append(shade(core, s["graphite"]))
    for x in (-0.0245, 0.0245):
        cheek = cylinder("InductorCheek", 0.015, 0.003, location=(x, 0, axis), rotation=ALONG_X)
        bevel(cheek, 0.0008, segments=2)
        parts.append(shade(cheek, s["graphite"]))
        cradle = box("InductorCradle", (0.005, 0.018, axis - 0.015 - CARRIER_TOP + 0.002),
                     location=(x, 0, (CARRIER_TOP + axis - 0.015) / 2 + 0.001))
        parts.append(shade(cradle, s["graphite"]))
    turns = 9
    for i in range(turns):
        x = -0.0205 + 0.041 * i / (turns - 1)
        ring = band("InductorTurn", 0.0128, 0.0080, 0.0038, location=(x, 0, axis), rotation=ALONG_X,
                    vertices=48)
        parts.append(shade(ring, s["copper"]))
    for side in (-1, 1):
        lead = tube("InductorLead", [(side * 0.026, 0, axis), (side * 0.032, 0, axis),
                                     (side * 0.034, 0, axis - 0.003), (side * 0.034, 0, CARRIER_TOP + 0.0015)],
                    0.0008, s["copper"], resolution=3)
        parts.append(lead)
    return join("CircuitInductor", parts)


def build_bulb(s):
    parts = symbol("bulb", s)
    socket = cylinder("BulbSocket", 0.011, 0.010, location=(0, 0, CARRIER_TOP + 0.005))
    bevel(socket, 0.0012, segments=2)
    parts.append(shade(socket, s["champagne"]))
    screw = cylinder("BulbScrew", 0.0085, 0.010, location=(0, 0, CARRIER_TOP + 0.015))
    parts.append(shade(screw, s["copper"]))
    for z in (CARRIER_TOP + 0.012, CARRIER_TOP + 0.015, CARRIER_TOP + 0.018):
        thread = band("BulbThread", 0.0093, 0.0080, 0.0012, location=(0, 0, z), vertices=48)
        parts.append(shade(thread, s["copper"]))
    neck = cone("BulbNeck", 0.0085, 0.013, 0.008, location=(0, 0, CARRIER_TOP + 0.024))
    parts.append(shade(neck, s["bulbGlass"]))
    # The filament's two supports, up from the neck to its ends (Swift hangs
    # the filament itself between them, so it can light).
    for side in (-1, 1):
        support = tube("BulbSupport", [(side * 0.0030, 0, CARRIER_TOP + 0.024),
                                       (side * 0.0045, 0, BULB_CENTRE - 0.006),
                                       (side * 0.0050, 0, BULB_CENTRE)],
                       0.00045, s["steel"], resolution=3)
        parts.append(support)
    bpy.ops.mesh.primitive_uv_sphere_add(radius=0.018, location=(0, 0, BULB_CENTRE),
                                         segments=48, ring_count=24)
    envelope = bpy.context.active_object
    envelope.name = "BulbGlass"
    parts.append(shade(envelope, s["bulbGlass"]))
    # The socket's straps onto the traces.
    for side in (-1, 1):
        strap = box("BulbStrap", (0.006, 0.004, 0.0015),
                    location=(side * 0.0125, 0, CARRIER_TOP + 0.0022))
        parts.append(shade(strap, s["brass"]))
    return join("CircuitBulb", parts)


def build_led(s):
    parts = symbol("led", s)
    for side in (-1, 1):
        leg = tube("LEDLeg", [(side * 0.0025, 0, 0.004), (side * 0.0025, 0, CARRIER_TOP + 0.003),
                              (side * 0.0115, 0, CARRIER_TOP + 0.0015)], 0.0006, s["steel"], resolution=3)
        parts.append(leg)
    flange = cylinder("LEDFlange", 0.0064, 0.0018, location=(0, 0, 0.005), vertices=48)
    parts.append(shade(flange, s["ledDome"]))
    body = cylinder("LEDBody", 0.0055, 0.008, location=(0, 0, 0.010), vertices=48)
    parts.append(shade(body, s["ledDome"]))
    bpy.ops.mesh.primitive_uv_sphere_add(radius=0.0055, location=(0, 0, 0.014),
                                         segments=32, ring_count=16)
    dome = bpy.context.active_object
    dome.name = "LEDDome"
    parts.append(shade(dome, s["ledDome"]))
    return join("CircuitLED", parts)


def build_motor(s):
    parts = symbol("motor", s)
    axis, radius = MOTOR_AXIS, 0.016
    can = cylinder("MotorCan", radius, 0.050, location=(-0.005, 0, axis), rotation=ALONG_X)
    bevel(can, 0.0015, segments=3)
    parts.append(shade(can, s["graphite"]))
    for x in (-0.016, -0.005, 0.006):
        rib = band("MotorRib", radius + 0.0008, radius - 0.001, 0.0025,
                   location=(x, 0, axis), rotation=ALONG_X)
        parts.append(shade(rib, s["champagne"]))
    plate = cylinder("MotorFace", radius + 0.0004, 0.002, location=(0.021, 0, axis), rotation=ALONG_X)
    parts.append(shade(plate, s["teal"]))
    shaft = cylinder("MotorShaft", 0.002, 0.026, location=(0.034, 0, axis), rotation=ALONG_X)
    parts.append(shade(shaft, s["steel"]))
    rear = band("MotorRear", radius + 0.0008, radius - 0.003, 0.003,
                location=(-0.0305, 0, axis), rotation=ALONG_X)
    parts.append(shade(rear, s["champagne"]))
    for x in (-0.020, 0.010):
        cradle = box("MotorCradle", (0.006, 0.022, axis - radius - CARRIER_TOP + 0.003),
                     location=(x, 0, (CARRIER_TOP + axis - radius) / 2 + 0.0015))
        parts.append(shade(cradle, s["graphite"]))
    for side in (-1, 1):
        lead = tube("MotorLead", [(-0.031, side * 0.006, axis), (-0.034, side * 0.006, axis - 0.004),
                                  (-0.034 if side < 0 else 0.0, 0, CARRIER_TOP + 0.0015)],
                    0.0007, s["copper"], resolution=3) if side < 0 else tube(
            "MotorLead", [(0.020, 0.012, axis - 0.008), (0.024, 0.006, CARRIER_TOP + 0.003),
                          (0.034, 0, CARRIER_TOP + 0.0015)], 0.0007, s["copper"], resolution=3)
        parts.append(lead)
    return join("CircuitMotor", parts)


def build_fuse(s):
    parts = symbol("fuse", s)
    axis = FUSE_AXIS
    glass = cylinder("FuseGlass", 0.0062, 0.034, location=(0, 0, axis), rotation=ALONG_X, vertices=48)
    parts.append(shade(glass, s["fuseGlass"]))
    for x in (-0.020, 0.020):
        cap = cylinder("FuseCap", 0.0070, 0.007, location=(x, 0, axis), rotation=ALONG_X)
        bevel(cap, 0.0008, segments=2)
        parts.append(shade(cap, s["steel"]))
    parts += clip("FuseClip", -0.020, 0.0070, axis, s)
    parts += clip("FuseClip", 0.020, 0.0070, axis, s)
    return join("CircuitFuse", parts)


def build_switch(s):
    parts = symbol("switcher", s)
    block = box("SwitchBlock", (0.068, 0.020, 0.005), location=(0, 0, CARRIER_TOP + 0.0025))
    bevel(block, 0.0012, segments=2)
    parts.append(shade(block, s["graphite"]))
    keyline = box("SwitchKey", (0.060, 0.0012, 0.0006), location=(0, -0.0104, CARRIER_TOP + 0.004))
    parts.append(shade(keyline, s["champagne"]))
    for side in (-1, 1):
        # The pivot's cheeks at −0.028 and the contact's spring clip at +0.028.
        cheek = box("SwitchPivotCheek", (0.008, 0.0016, 0.016),
                    location=(-0.028, side * 0.0040, CARRIER_TOP + 0.005 + 0.008))
        bevel(cheek, 0.0005, segments=1)
        parts.append(shade(cheek, s["brass"]))
        spring = box("SwitchContact", (0.006, 0.0014, 0.014),
                     location=(0.028, side * 0.0030, CARRIER_TOP + 0.005 + 0.007))
        bevel(spring, 0.0004, segments=1)
        parts.append(shade(spring, s["brass"]))
    pin = cylinder("SwitchPin", 0.0012, 0.011, location=(-0.028, 0, SWITCH_PIVOT),
                   rotation=(math.pi / 2, 0, 0))
    parts.append(shade(pin, s["steel"]))
    return join("CircuitSwitch", parts)


BUILDERS = {
    "CircuitCarrier": build_carrier,
    "CircuitBattery": build_battery,
    "CircuitACSource": build_ac_source,
    "CircuitCapacitor": build_capacitor,
    "CircuitInductor": build_inductor,
    "CircuitBulb": build_bulb,
    "CircuitLED": build_led,
    "CircuitMotor": build_motor,
    "CircuitFuse": build_fuse,
    "CircuitSwitch": build_switch,
    "CircuitResistorCaps": build_resistor_caps,
    "CircuitStageDeck": build_stage_deck,
    "CircuitStageRim": build_stage_rim,
}


def main():
    # `-- CircuitStageDeck CircuitStageRim` mills only those; none, all of them.
    wanted = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    for name, builder in BUILDERS.items():
        if wanted and name not in wanted:
            continue
        reset_scene()
        s = stocks()
        part = builder(s)
        export([part], os.path.join(ROOT, name + ".usdz"))


main()
