#!/usr/bin/env python3
"""
Circuit Workshop's ten parts, milled rather than generated (2026-09-02).

    /Applications/Blender.app/Contents/MacOS/Blender --background \\
        --python Tools/circuitparts.py

Outputs, all under PhysicsPlayground/Models/Circuits/:

    CircuitBattery.usdz      anodised can, steel positive nipple at −X,
                             two champagne keyline bands
    CircuitACSource.usdz     graphite disc, champagne rim, a raised "~"
    CircuitCapacitor.usdz    deep-blue electrolytic can, pale stripe on
                             the +X (terminal 1) end, a vent cross
    CircuitInductor.usdz     graphite bobbin wound with nine copper rings
    CircuitBulb.usdz         glass envelope over a copper screw base
    CircuitLED.usdz          steel base, red dome
    CircuitMotor.usdz        graphite can, three cooling ribs, teal
                             faceplate and steel shaft stub at +X
    CircuitFuse.usdz         glass tube, steel end caps, copper filament
    CircuitSwitch.usdz       graphite base, steel pivot and contact posts
    CircuitResistorCaps.usdz steel end caps only — the ceramic body stays
                             procedural in Swift, because its colour
                             bands are a LIVE texture painted from the
                             value, and the UV layout of a RealityKit
                             cylinder is the one that texture knows.

WHY A SCRIPT. Four of these parts (battery, bulb, capacitor, switch)
shipped as hand-built assets on 2026-07-17 with no generator, before the
rule that "a PNG nobody can regenerate is a decision nobody can revisit"
(`appicon.py`). The other six were procedural cylinders. This file is the
generator for all of them, in the stocks the gallery's platforms and the
multimeter already wear — near-black anodised, steel, copper, champagne
— so the bench reads as one milled family.

THE CONTRACT WITH THE RENDERER. `CircuitsRenderer.makeBody` clones each
asset into a shell at the part's origin and adds its own moving or
lit pieces on top: the bulb's filament and glow at +y 0.012, the LED's
glow at +y 0.012, the motor's rotor at +x 0.05, the switch's lever
pivoting at (−0.028, +0.008). Every body lies along X with the terminals
at ±0.085 (drawn in Swift), and stays inside |x| < 0.059 — the carry
box's clamp at the leads' inner edge — so `CircuitsAlignmentTests` and
`ColliderCriterionTests` hold. Terminal 0 (a battery's +) is −X.

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
    reset_scene, shade)

ROOT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                    "PhysicsPlayground", "Models", "Circuits")

ALONG_X = (0, math.pi / 2, 0)   # a Blender cylinder is built along Z


def coat(mat, weight, roughness):
    """The clearcoat `RenderKit.Materials.graphite` is defined by — see
    `galleryplatforms.py` for why metallic alone came back twice as
    bright over a real room."""
    bsdf = mat.node_tree.nodes["Principled BSDF"]
    for key, value in (("Coat Weight", weight), ("Clearcoat", weight),
                       ("Coat Roughness", roughness),
                       ("Clearcoat Roughness", roughness)):
        if key in bsdf.inputs:
            bsdf.inputs[key].default_value = value
    return mat


def glass(name, colour, alpha, roughness=0.06):
    mat = material(name, colour, roughness=roughness, metallic=0.0)
    bsdf = mat.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Alpha"].default_value = alpha
    if hasattr(mat, "blend_method"):
        mat.blend_method = "BLEND"
    return mat


def stocks():
    """One alloy list for every part, tracking the gallery's platforms
    (`galleryplatforms.py`) so the bench and the room are visibly one
    system."""
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
    }


# ------------------------------------------------------------- the parts


def build_battery(s):
    parts = []
    can = cylinder("BatteryCan", 0.022, 0.104, rotation=ALONG_X)
    bevel(can, 0.0025, segments=3)
    parts.append(shade(can, s["graphite"]))
    # Keyline bands near each end: the milled edge the whole house wears.
    for x in (-0.040, 0.040):
        ring = band("BatteryBand", 0.0228, 0.0215, 0.006,
                    location=(x, 0, 0), rotation=ALONG_X)
        parts.append(shade(ring, s["champagne"]))
    # The positive nipple on the terminal-0 (−X) end; a flat steel
    # negative pad on the other.
    # The nipple stops at x −0.058: the carry box clamps a body at the
    # leads' inner edge, 0.059, and `CircuitPropTests` measures it.
    nipple = cylinder("BatteryNipple", 0.009, 0.006,
                      location=(-0.055, 0, 0), rotation=ALONG_X)
    bevel(nipple, 0.0015, segments=2)
    parts.append(shade(nipple, s["steel"]))
    pad = cylinder("BatteryPad", 0.016, 0.003, location=(0.0525, 0, 0),
                   rotation=ALONG_X)
    parts.append(shade(pad, s["steel"]))
    return join("CircuitBattery", parts)


def build_ac_source(s):
    parts = []
    disc = cylinder("ACDisc", 0.030, 0.018, rotation=ALONG_X)
    bevel(disc, 0.002, segments=3)
    parts.append(shade(disc, s["graphite"]))
    rim = band("ACRim", 0.032, 0.029, 0.020, rotation=ALONG_X)
    parts.append(shade(rim, s["champagne"]))
    # The tilde, raised on the reader-facing face (Blender −Y is the face
    # toward the reader; the disc's axis is X, so its faces look ±X — put
    # the glyph on the +X face where the rotor of a motor would be, the
    # end a builder looks at).
    tilde = letter("ACTilde", "~", 0.024, 0.002,
                   location=(0.0105, 0, 0),
                   rotation=(math.pi / 2, 0, math.pi / 2))
    parts.append(shade(tilde, s["champagne"], smooth=False))
    return join("CircuitACSource", parts)


def build_capacitor(s):
    parts = []
    can = cylinder("CapacitorCan", 0.020, 0.058, rotation=ALONG_X)
    bevel(can, 0.002, segments=3)
    parts.append(shade(can, s["blue"]))
    # The polarity stripe on the terminal-1 (+X) end, as the procedural
    # body had it — the renderer's convention, not a choice made here.
    stripe = box("CapacitorStripe", (0.006, 0.041, 0.010),
                 location=(0.017, 0, 0.016))
    parts.append(shade(stripe, s["pale"], smooth=False))
    # The vent cross scored into the +X end.
    for rot in (0, math.pi / 2):
        groove = box("CapacitorVent", (0.0015, 0.020, 0.0012),
                     location=(0.0295, 0, 0))
        groove.rotation_euler = (rot, 0, 0)
        bpy.ops.object.transform_apply(rotation=True)
        parts.append(shade(groove, s["steel"], smooth=False))
    return join("CircuitCapacitor", parts)


def build_inductor(s):
    parts = []
    core = cylinder("InductorCore", 0.013, 0.068, rotation=ALONG_X)
    bevel(core, 0.0015, segments=2)
    parts.append(shade(core, s["graphite"]))
    for x in (-0.031, 0.031):
        cheek = cylinder("InductorCheek", 0.020, 0.004,
                         location=(x, 0, 0), rotation=ALONG_X)
        bevel(cheek, 0.0008, segments=2)
        parts.append(shade(cheek, s["graphite"]))
    # Nine turns of copper between the cheeks — the windings the turn
    # count is derived from stand at 0.019 m, and these are them.
    for index in range(9):
        x = -0.024 + index * 0.006
        turn = band("InductorTurn", 0.019, 0.0135, 0.0052,
                    location=(x, 0, 0), rotation=ALONG_X)
        parts.append(shade(turn, s["copper"]))
    return join("CircuitInductor", parts)


def build_bulb(s):
    parts = []
    # Envelope centred at +z 0.012 (RealityKit +y), where the renderer
    # hangs the filament and the glow.
    bpy.ops.mesh.primitive_uv_sphere_add(radius=0.034, location=(0, 0, 0.012),
                                         segments=48, ring_count=32)
    envelope = bpy.context.active_object
    envelope.name = "BulbEnvelope"
    parts.append(shade(envelope, s["bulbGlass"]))
    # Screw base below it, threads as three copper rings.
    base = cylinder("BulbBase", 0.0125, 0.022, location=(0, 0, -0.026))
    bevel(base, 0.001, segments=2)
    parts.append(shade(base, s["copper"]))
    for z in (-0.020, -0.026, -0.032):
        thread = band("BulbThread", 0.0135, 0.012, 0.0025, location=(0, 0, z))
        parts.append(shade(thread, s["copper"]))
    foot = cylinder("BulbFoot", 0.006, 0.004, location=(0, 0, -0.039))
    parts.append(shade(foot, s["steel"]))
    return join("CircuitBulb", parts)


def build_led(s):
    parts = []
    base = cylinder("LEDBase", 0.012, 0.016)
    bevel(base, 0.0012, segments=2)
    parts.append(shade(base, s["steel"]))
    flange = band("LEDFlange", 0.0135, 0.0115, 0.002, location=(0, 0, 0.007))
    parts.append(shade(flange, s["steel"]))
    bpy.ops.mesh.primitive_uv_sphere_add(radius=0.013, location=(0, 0, 0.012),
                                         segments=40, ring_count=24)
    dome = bpy.context.active_object
    dome.name = "LEDDome"
    parts.append(shade(dome, s["ledDome"]))
    return join("CircuitLED", parts)


def build_motor(s):
    parts = []
    can = cylinder("MotorCan", 0.022, 0.066, rotation=ALONG_X)
    bevel(can, 0.002, segments=3)
    parts.append(shade(can, s["graphite"]))
    # Three cooling ribs round the can.
    for x in (-0.018, 0.0, 0.018):
        rib = band("MotorRib", 0.0235, 0.021, 0.004,
                   location=(x, 0, 0), rotation=ALONG_X)
        parts.append(shade(rib, s["graphite"]))
    # Faceplate and shaft stub on the +X end, where the rotor mounts.
    plate = cylinder("MotorPlate", 0.023, 0.005, location=(0.0355, 0, 0),
                     rotation=ALONG_X)
    bevel(plate, 0.001, segments=2)
    parts.append(shade(plate, s["teal"]))
    shaft = cylinder("MotorShaft", 0.003, 0.014, location=(0.045, 0, 0),
                     rotation=ALONG_X)
    parts.append(shade(shaft, s["steel"]))
    # A raised keyline ring on the rear end.
    rear = band("MotorRear", 0.0225, 0.019, 0.003, location=(-0.0345, 0, 0),
                rotation=ALONG_X)
    parts.append(shade(rear, s["champagne"]))
    return join("CircuitMotor", parts)


def build_fuse(s):
    parts = []
    tube = cylinder("FuseTube", 0.0115, 0.050, rotation=ALONG_X)
    parts.append(shade(tube, s["fuseGlass"]))
    for x in (-0.029, 0.029):
        cap = cylinder("FuseCap", 0.0125, 0.010, location=(x, 0, 0),
                       rotation=ALONG_X)
        bevel(cap, 0.001, segments=2)
        parts.append(shade(cap, s["steel"]))
    filament = cylinder("FuseFilament", 0.0016, 0.050, rotation=ALONG_X,
                        vertices=16)
    parts.append(shade(filament, s["copper"]))
    return join("CircuitFuse", parts)


def build_switch(s):
    parts = []
    # RealityKit (0.075 x 0.016 x 0.032) is Blender (0.075, 0.032, 0.016).
    base = box("SwitchBase", (0.075, 0.032, 0.016))
    bevel(base, 0.003, segments=3)
    parts.append(shade(base, s["graphite"]))
    lip = box("SwitchLip", (0.071, 0.028, 0.0015), location=(0, 0, 0.0085))
    parts.append(shade(lip, s["champagne"], smooth=False))
    # The pivot post at −0.028 and the contact post at +0.028: the lever
    # the renderer draws swings between them, from the pivot.
    pivot = cylinder("SwitchPivot", 0.0045, 0.006, location=(-0.028, 0, 0.011))
    bevel(pivot, 0.0008, segments=2)
    parts.append(shade(pivot, s["steel"]))
    contact = cylinder("SwitchContact", 0.004, 0.008, location=(0.028, 0, 0.012))
    bevel(contact, 0.0008, segments=2)
    parts.append(shade(contact, s["steel"]))
    return join("CircuitSwitch", parts)


def build_resistor_caps(s):
    parts = []
    for x in (-0.0355, 0.0355):
        cap = cylinder("ResistorCap", 0.0168, 0.008, location=(x, 0, 0),
                       rotation=ALONG_X)
        bevel(cap, 0.0012, segments=2)
        parts.append(shade(cap, s["steel"]))
    return join("CircuitResistorCaps", parts)


BUILDERS = {
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
}


def main():
    for name, builder in BUILDERS.items():
        reset_scene()
        s = stocks()
        part = builder(s)
        export([part], os.path.join(ROOT, name + ".usdz"))


main()
