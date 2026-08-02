#!/usr/bin/env python3
"""
Builds the bench multimeter and its probe, and writes them as USDZ.

    /Applications/Blender.app/Contents/MacOS/Blender --background \
        --python Tools/multimeter.py

Outputs, both under PhysicsPlayground/Models/Circuits/:
    Multimeter.usdz   body, holster, bezel, LCD, rotary dial, two jacks
    MeterProbe.usdz   one probe: handle, finger guard, needle tip

WHY THIS IS A SCRIPT AND NOT A .BLEND

A binary asset nobody can regenerate is a liability in a project whose
whole claim is that its physics is checkable. Every dimension below is a
number in metres that can be argued with, and the mesh can be rebuilt on
any machine with Blender. It also means the meter can be re-proportioned
when a screenshot says it is wrong, which is how every other piece of
geometry in this app has been tuned.

SCALE. The body is 86 x 168 x 32 mm, which is a real handheld DMM — near
enough to a Fluke 17B that it reads as an instrument rather than a prop.
It is deliberately NOT shrunk to sit tidily on the bench: this app is 1:1
everywhere else, and a miniature meter beside full-size components would
be the one dishonest object in the room.

ORIENTATION. Blender is Z-up; RealityKit is Y-up. The exporter is told to
convert, so the meter arrives standing on its base with the screen facing
the reader and the dial below it.
"""

import bpy
import math
import os

# ---------------------------------------------------------------- helpers


def reset_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def material(name, colour, roughness=0.5, metallic=0.0, emission=None):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = (*colour, 1.0)
    bsdf.inputs["Roughness"].default_value = roughness
    bsdf.inputs["Metallic"].default_value = metallic
    if emission is not None:
        for key in ("Emission Color", "Emission"):
            if key in bsdf.inputs:
                bsdf.inputs[key].default_value = (*emission, 1.0)
                break
        if "Emission Strength" in bsdf.inputs:
            bsdf.inputs["Emission Strength"].default_value = 1.0
    return mat


def shade(obj, mat, smooth=True):
    obj.data.materials.append(mat)
    if smooth:
        for polygon in obj.data.polygons:
            polygon.use_smooth = True
    return obj


def bevel(obj, width, segments=3, angle=40):
    """Rounded edges. A moulded instrument has no sharp corners, and at
    room scale the highlight running along a bevel is most of what makes
    a shape read as a solid object rather than as a box."""
    bpy.context.view_layer.objects.active = obj
    modifier = obj.modifiers.new("bevel", "BEVEL")
    modifier.width = width
    modifier.segments = segments
    modifier.limit_method = "ANGLE"
    modifier.angle_limit = math.radians(angle)
    bpy.ops.object.modifier_apply(modifier="bevel")
    return obj


def box(name, size, location=(0, 0, 0)):
    """`size` is the FULL width, height and depth in metres.

    A unit cube from `primitive_cube_add(size=1)` already spans 1 m, so
    the scale IS the dimension. Stating that here because the first
    version of this file passed half-extents to it and every part ended
    up at half size while the offsets that placed them did not — the
    meter came out as a scatter of pieces around a body too small to hold
    them, which one render made obvious and no amount of reading would
    have."""
    bpy.ops.mesh.primitive_cube_add(size=1, location=location)
    obj = bpy.context.active_object
    obj.name = name
    obj.scale = (size[0], size[1], size[2])
    bpy.ops.object.transform_apply(scale=True)
    return obj


def cylinder(name, radius, depth, location=(0, 0, 0), rotation=(0, 0, 0),
             vertices=48):
    bpy.ops.mesh.primitive_cylinder_add(
        radius=radius, depth=depth, location=location,
        rotation=rotation, vertices=vertices)
    obj = bpy.context.active_object
    obj.name = name
    return obj


def cone(name, radius1, radius2, depth, location=(0, 0, 0), rotation=(0, 0, 0)):
    bpy.ops.mesh.primitive_cone_add(
        radius1=radius1, radius2=radius2, depth=depth,
        location=location, rotation=rotation, vertices=32)
    obj = bpy.context.active_object
    obj.name = name
    return obj


def join(name, objects):
    bpy.ops.object.select_all(action="DESELECT")
    for obj in objects:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = objects[0]
    bpy.ops.object.join()
    joined = bpy.context.active_object
    joined.name = name
    return joined


def export(objects, path):
    bpy.ops.object.select_all(action="DESELECT")
    for obj in objects:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = objects[0]
    os.makedirs(os.path.dirname(path), exist_ok=True)
    bpy.ops.wm.usd_export(
        filepath=path,
        selected_objects_only=True,
        export_materials=True,
        convert_orientation=True,
        export_global_forward_selection="NEGATIVE_Z",
        export_global_up_selection="Y",
    )
    print("wrote", path)


# ------------------------------------------------------------ dimensions
# Metres throughout. A real handheld DMM, not a shrunken prop.

BODY_W, BODY_H, BODY_D = 0.086, 0.168, 0.032
SCREEN_W, SCREEN_H = 0.066, 0.038
DIAL_R = 0.024
# The face, as one column of clearances rather than three independent
# guesses. Screen 21…59 mm above centre, dial plate −50…+10, jacks
# −74…−62 — so ~11 mm of case between the screen and the dial and ~12 mm
# between the dial and the jacks. The first attempt had the dial at 28 mm
# radius sitting at −17, which put its plate through the screen's lower
# bezel and its skirt over both jacks.
SCREEN_Y = 0.040
DIAL_Y = -0.020
JACK_Y = -0.068
ROOT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                    "PhysicsPlayground", "Models", "Circuits")


def build_meter():
    case = material("MeterCase", (0.085, 0.095, 0.115), roughness=0.62)
    boot = material("MeterBoot", (0.68, 0.22, 0.05), roughness=0.88)
    bezel_mat = material("MeterBezel", (0.04, 0.04, 0.05), roughness=0.32)
    lcd = material("MeterLCD", (0.60, 0.68, 0.56), roughness=0.22,
                   emission=(0.14, 0.17, 0.12))
    knob = material("MeterKnob", (0.13, 0.14, 0.16), roughness=0.42)
    marks = material("MeterMarks", (0.90, 0.90, 0.88), roughness=0.5)
    brass = material("MeterJack", (0.76, 0.60, 0.22), roughness=0.26,
                     metallic=0.9)

    parts = []

    # The case.
    body = box("Body", (BODY_W, BODY_H, BODY_D))
    bevel(body, 0.005, segments=4)
    parts.append(shade(body, case))

    # The rubber holster every field meter wears. Two bands rather than a
    # full sleeve: enough to break the silhouette and put one warm colour
    # on an otherwise dark object, which is what stops it disappearing
    # against a dark bench.
    for y in (BODY_H / 2 - 0.008, -BODY_H / 2 + 0.008):
        band = box("Boot", (BODY_W + 0.0044, 0.012, BODY_D + 0.0044),
                   location=(0, y, 0))
        bevel(band, 0.003, segments=3)
        parts.append(shade(band, boot))

    # The screen: a recessed bezel with the LCD sitting inside it, so the
    # glass reads as being BELOW the case surface. A flat rectangle on the
    # front would read as a sticker.
    bezel = box("Bezel", (SCREEN_W + 0.008, SCREEN_H + 0.008, 0.004),
                location=(0, SCREEN_Y, BODY_D / 2 - 0.001))
    bevel(bezel, 0.0015, segments=3)
    parts.append(shade(bezel, bezel_mat))

    screen = box("Screen", (SCREEN_W, SCREEN_H, 0.0016),
                 location=(0, SCREEN_Y, BODY_D / 2 + 0.0008))
    parts.append(shade(screen, lcd, smooth=False))

    # The rotary dial. A real one is a knurled disc with a pointer; the
    # pointer is what tells you which mode you are in from across the
    # bench, so it is a raised bar rather than a printed line.
    # NO rotation on any of these. The case's front face is +Z and a
    # cylinder's default axis is already +Z, so the first version's
    # `rotation=(90°, 0, 0)` stood the dial and both jacks on edge — a
    # disc sticking out of the side of the meter like a saw blade. One
    # render, immediately obvious; unreadable from the source alone.
    dial_plate = cylinder("DialPlate", DIAL_R + 0.006, 0.0016,
                          location=(0, DIAL_Y, BODY_D / 2 - 0.0004))
    parts.append(shade(dial_plate, bezel_mat))

    dial = cylinder("Dial", DIAL_R, 0.008,
                    location=(0, DIAL_Y, BODY_D / 2 + 0.0035))
    bevel(dial, 0.0015, segments=3, angle=60)
    parts.append(shade(dial, knob))

    pointer = box("DialPointer", (0.0038, DIAL_R * 1.1, 0.0022),
                  location=(0, DIAL_Y + DIAL_R * 0.38,
                            BODY_D / 2 + 0.0076))
    parts.append(shade(pointer, marks))

    # Detents around the dial: eight positions, which is what a meter of
    # this class actually has. They are geometry rather than a texture so
    # they catch the light as the meter turns.
    for index in range(8):
        angle = math.radians(-125 + index * (250 / 7))
        radius = DIAL_R + 0.0105
        tick = box("DialTick", (0.0026, 0.0075, 0.0014),
                   location=(radius * math.sin(angle),
                             DIAL_Y + radius * math.cos(angle),
                             BODY_D / 2 + 0.0004))
        tick.rotation_euler = (0, 0, -angle)
        bpy.ops.object.transform_apply(rotation=True)
        parts.append(shade(tick, marks, smooth=False))

    # Two banana jacks: COM and VΩmA. Recessed sockets, not studs — a
    # probe plugs INTO a meter.
    for x, name in ((-0.019, "JackCOM"), (0.019, "JackVolt")):
        surround = cylinder(name + "Ring", 0.0062, 0.0030,
                            location=(x, JACK_Y,
                                      BODY_D / 2 - 0.0006), vertices=24)
        parts.append(shade(surround, bezel_mat))
        socket = cylinder(name, 0.0038, 0.0060,
                          location=(x, JACK_Y,
                                    BODY_D / 2 - 0.0034), vertices=24)
        parts.append(shade(socket, brass))

    return join("Multimeter", parts)


def build_probe():
    """One probe. The app instantiates it twice and tints the handle red
    or black, so the mesh carries no colour decision of its own beyond
    the metal."""
    grip = material("ProbeGrip", (0.12, 0.12, 0.13), roughness=0.72)
    guard = material("ProbeGuard", (0.06, 0.06, 0.07), roughness=0.55)
    steel = material("ProbeTip", (0.82, 0.83, 0.86), roughness=0.18,
                     metallic=1.0)

    parts = []

    # BUILT ALONG +Z, so after the Z-up→Y-up conversion the probe points
    # along +Y in the exported asset and the app rotates it to aim. The
    # handle occupies z ∈ [0, 0.096]; the needle hangs below z = 0, so
    # the model's ORIGIN is the finger guard — which is the point a hand
    # actually holds it by, and therefore the point to attach a grab to.
    handle = cone("Handle", 0.0082, 0.0062, 0.096, location=(0, 0, 0.048))
    parts.append(shade(handle, grip))

    collar = cylinder("Guard", 0.0115, 0.0035, location=(0, 0, 0.002),
                      vertices=32)
    bevel(collar, 0.0012, segments=2, angle=60)
    parts.append(shade(collar, guard))

    # The needle: 44 mm of steel. This is the part that has to read as
    # SHARP, because touching it to a terminal is the whole gesture the
    # instrument exists for.
    shank = cylinder("Shank", 0.0018, 0.030, location=(0, 0, -0.015),
                     vertices=16)
    parts.append(shade(shank, steel))

    tip = cone("Needle", 0.0018, 0.0002, 0.014, location=(0, 0, -0.037))
    parts.append(shade(tip, steel))

    return join("MeterProbe", parts)


def main():
    reset_scene()
    meter = build_meter()
    export([meter], os.path.join(ROOT, "Multimeter.usdz"))

    reset_scene()
    probe = build_probe()
    export([probe], os.path.join(ROOT, "MeterProbe.usdz"))


main()
