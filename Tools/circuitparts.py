#!/usr/bin/env python3
"""
Circuit Workshop's parts as the SOLID SCHEMATIC (2026-10-30): every part
is its own schematic symbol made solid, floating on the line between two
brass dots, with no base. Milled rather than generated, with the
turntable the floating circuit stands over.

    /Applications/Blender.app/Contents/MacOS/Blender --background \\
        --python Tools/circuitparts.py [-- Name ...]

Outputs, all under PhysicsPlayground/Models/Circuits/ (name a few after
`--` to mill only those):

    CircuitBattery.usdz      the long plate a copper disc (+, the cell's
                             positive electrode) at -X, the short plate a
                             zinc disc (-), and a keylined +
    CircuitACSource.usdz     a keylined circle with a sine inside it on a
                             glass face; the child `bead` rides the sine at
                             the source's phase
    CircuitResistorCaps.usdz the banded body's steel caps and a keylined
                             zigzag across its face — the ceramic stays
                             procedural in Swift, its bands a LIVE texture
    CircuitCapacitor.usdz    two real plates, the - one (+X) dished: the
                             polarised symbol; children `plate0`, `plate1`
                             take the charge's red and blue
    CircuitInductor.usdz     a copper helix, air core: the coil symbol IS a
                             coil seen from the side
    CircuitBulb.usdz         a glass globe on the line, entered at its poles
                             through brass caps, a keylined circle round it,
                             a steel support on one diagonal; the child
                             `filament` on the other is the X's glowing stroke
    CircuitLED.usdz          the triangle as a red epoxy cone pointing from
                             the anode (-X) to a steel bar, two keylined
                             arrows; the child `core` is the cone
    CircuitMotor.usdz        the motor's circle as a steel flywheel ring in
                             the face plane round a graphite hub with a
                             keylined M; children `rotor` (one brass marker)
                             and `rotor_blur`
    CircuitFuse.usdz         a glass cartridge with brass caps — the IEC
                             symbol is a cartridge; children `fuse_glass`,
                             `fuse_left`, `fuse_bridge`, `fuse_right`
    CircuitSwitch.usdz       brass pivot and contact rings; the child `blade`
                             (pivoting at its own origin) carries an ebony
                             knob on a stem
    CircuitDot.usdz          a terminal dot, brass; Swift places two per part
                             and merges a joint's two into one junction dot
    CircuitElectron.usdz     an electron's `core` and `halo`, low-poly, for
                             the instanced flow
    CircuitStageDeck.usdz    the turntable's satin graphite deck
    CircuitStageRim.usdz     its knurled champagne rim

WHY THE SOLID SCHEMATIC. The owner's pick of three directions (DECISIONS,
2026-10-30; docs/circuits-kit-directions.md): "It goes along with the 3d
feel the best and how it can be seen as floating". From where the wearer
stands, the starter loop IS its own schematic — the textbook figure you
can grab. Where a symbol can be a solid of revolution about the line it
is one (the plates, the helix, the cartridge), so it reads from any
side; where it needs a plane (the lamp's circle, the switch, the LED's
arrows, the AC wave, the motor's ring) that plane faces the wearer, which
`CircuitsRenderer.moduleOrientation` keeps true standing or lying.

THE CONTRACT WITH THE RENDERER (docs/circuits-kit-contract.md). Every part
lies along X; its terminals are at +/-TERMINAL_OFFSET on the line y = z = 0
and Swift draws a CircuitDot there. Swift also draws each LEAD — the same
dark jacket over a voltage-coloured core as a wire, so leads and wires are
one line — from the terminal to LEAD_INNER[kind], where this element's
surface begins. Every element stays inside |x| < ELEMENT_CLAMP. The pieces
that move or light are named CHILD prims (LIVE_CHILDREN), each with its
origin where Swift turns or places it: the blade at the pivot, the rotor
at the hub, the bead at the sine's start. Terminal 0 (a battery's +, an
LED's anode) is -X. The numbers below are plain literals on purpose:
`Tools/propsheet.py` reads them with `ast` and `CircuitPropTests` holds
the Swift side to the same ones.

THE INK. A symbol's stroke is a near-black casing with a champagne
keyline riding its front — `contrastLine`'s casing-and-core in three
dimensions — so it reads against a white wall and against Deep space
(the C2 renders). Champagne is the symbol's colour (it was the chamfer's
inlay); brass stays where current enters: the dots, the caps, the rings.

HANDEDNESS. Blender (x, y, z) -> RealityKit (x, z, -y): P() below takes
RealityKit and gives Blender.
"""

import math
import os
import sys

sys.dont_write_bytecode = True
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import bpy  # noqa: E402
import bmesh  # noqa: E402
from blenderprops import (  # noqa: E402
    band, bevel, box, cylinder, export, join, material, reset_scene, shade, tube)

ROOT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                    "PhysicsPlayground", "Models", "Circuits")

# ------------------------------------------------- the contract, as literals

TERMINAL_OFFSET = 0.085     # `CircuitsModel.terminalOffset`, unchanged
DOT_RADIUS = 0.0085         # `CircuitsRenderer.contactRadius`
WIRE_CORE = 0.0022          # a wire's and a lead's core...
WIRE_JACKET = 0.0037        # ...and its dark jacket
ELEMENT_CLAMP = 0.060       # 0.085 - 0.023 target - 0.002
CERAMIC_RADIUS = 0.012      # the procedural resistor body, Swift's
CERAMIC_LENGTH = 0.050

PART_ASSETS = {
    "battery": "CircuitBattery", "acSource": "CircuitACSource",
    "resistor": "CircuitResistorCaps", "capacitor": "CircuitCapacitor",
    "inductor": "CircuitInductor", "bulb": "CircuitBulb", "led": "CircuitLED",
    "motor": "CircuitMotor", "fuse": "CircuitFuse", "switcher": "CircuitSwitch",
}

# Where each lead stops: the element's own surface, -X end then +X end.
LEAD_INNER = {
    "battery": (-0.012, 0.014), "acSource": (-0.035, 0.035),
    "resistor": (-0.0255, 0.0255), "capacitor": (-0.007, 0.0075),
    "inductor": (-0.027, 0.027), "bulb": (-0.0345, 0.0345),
    "led": (-0.012, 0.007), "motor": (-0.014, 0.014),
    "fuse": (-0.028, 0.028), "switcher": (-0.040, 0.040),
}

LIVE_CHILDREN = {
    "acSource": ["bead"], "capacitor": ["plate0", "plate1"], "bulb": ["filament"],
    "led": ["core"], "motor": ["rotor", "rotor_blur"],
    "fuse": ["fuse_glass", "fuse_left", "fuse_bridge", "fuse_right"],
    "switcher": ["blade"],
}

SWITCH_PIVOT_X = -0.032
SWITCH_CONTACT_X = 0.032
SWITCH_OPEN_DEGREES = 30.0  # the symbol's own angle
AC_WAVE = (0.018, 0.0075, 0.0045)   # half-width, amplitude, z of the wave's plane
AC_BEAD_RADIUS = 0.0034

# The flywheel is the motor's inertia (contract D4): the model's J is the
# ring and web milled here, which `build_motor` checks before it exports.
FLYWHEEL = {"outer": 0.040, "inner": 0.026, "thickness": 0.020, "centre_z": -0.020,
            "web_thickness": 0.004, "web_z": -0.026}
STEEL_DENSITY = 7850.0
MOTOR_INERTIA = 0.000543    # kg·m², `CircuitsModel.motorInertia`

ALONG_X = (0, math.pi / 2, 0)    # a Blender cylinder is built along Z
FACING = (math.pi / 2, 0, 0)     # a Blender XY-plane primitive turned to face the wearer


def P(x, y, z=0.0):
    """A RealityKit point in Blender's frame."""
    return (x, -z, y)


# ------------------------------------------------------------------ stock

def coat(mat, weight, roughness):
    """The clearcoat `RenderKit.Materials.graphite` is defined by."""
    bsdf = mat.node_tree.nodes["Principled BSDF"]
    for key, value in (("Coat Weight", weight), ("Clearcoat", weight),
                       ("Coat Roughness", roughness), ("Clearcoat Roughness", roughness)):
        if key in bsdf.inputs:
            bsdf.inputs[key].default_value = value
    return mat


def glass(name, colour, alpha, roughness=0.06):
    """See-through, as USD carries it: the exporter never writes Alpha and
    writes opacity as 1 - Transmission Weight (2026-10-18)."""
    mat = material(name, colour, roughness=roughness, metallic=0.0)
    bsdf = mat.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Alpha"].default_value = alpha
    bsdf.inputs["Transmission Weight"].default_value = 1 - alpha
    if hasattr(mat, "blend_method"):
        mat.blend_method = "BLEND"
    return mat


def stocks():
    """One alloy list for every part. Every element wears at most five."""
    return {
        "ink": coat(material("CircuitInk", (0.025, 0.024, 0.026), roughness=0.25), 0.8, 0.12),
        "graphite": coat(material("CircuitGraphite", (0.088, 0.090, 0.096),
                                  roughness=0.30, metallic=0.10), 0.60, 0.25),
        "champagne": material("CircuitChampagne", (0.83, 0.70, 0.45), roughness=0.30, metallic=0.85),
        "brass": material("CircuitBrass", (0.78, 0.62, 0.32), roughness=0.30, metallic=0.90),
        "copper": material("CircuitCopper", (0.72, 0.42, 0.22), roughness=0.32, metallic=0.92),
        "zinc": material("CircuitZinc", (0.52, 0.55, 0.58), roughness=0.55, metallic=0.80),
        "steel": material("CircuitSteel", (0.60, 0.61, 0.64), roughness=0.22, metallic=0.95),
        # Dark aluminium: a pale plate vanished against a white wall at rest.
        "plate": material("CircuitPlate", (0.32, 0.33, 0.35), roughness=0.45, metallic=0.5),
        "glass": glass("CircuitGlass", (0.95, 0.96, 1.0), 0.22),
        "epoxy": glass("CircuitEpoxy", (0.90, 0.20, 0.15), 0.80, roughness=0.15),
        "filament": material("CircuitFilament", (0.30, 0.28, 0.26), roughness=0.4, metallic=0.6),
        "blur": glass("CircuitRotorBlur", (0.60, 0.61, 0.64), 0.30, roughness=0.4),
        "electron": material("CircuitElectron", (0.20, 0.80, 0.95), roughness=0.5),
    }


# --------------------------------------------------------------- helpers

def apply(obj):
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    return obj


def origin_at(obj, point):
    """Moves an object's origin to a Blender point, leaving its mesh put:
    a child Swift turns or places has its origin where it turns."""
    apply(obj)
    bpy.context.scene.cursor.location = point
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.origin_set(type="ORIGIN_CURSOR")
    bpy.context.scene.cursor.location = (0, 0, 0)
    return obj


def rod(name, a, b, radius, mat, resolution=6):
    return tube(name, [P(*a), P(*b)], radius, mat, resolution=resolution)


def disc_x(name, radius, thickness, centre, mat, chamfer=0.0, vertices=64):
    """A disc or short cylinder on the line (axis RealityKit X)."""
    obj = cylinder(name, radius, thickness, location=P(*centre), rotation=ALONG_X, vertices=vertices)
    if chamfer:
        bevel(obj, chamfer, segments=3, angle=60)
    return shade(obj, mat)


def disc_z(name, radius, thickness, centre, mat, chamfer=0.0, vertices=64):
    """A disc facing the wearer (axis RealityKit Z)."""
    obj = cylinder(name, radius, thickness, location=P(*centre), rotation=FACING, vertices=vertices)
    if chamfer:
        bevel(obj, chamfer, segments=3, angle=60)
    return shade(obj, mat)


def sphere(name, radius, centre, mat, segments=40, rings=20):
    bpy.ops.mesh.primitive_uv_sphere_add(radius=radius, location=P(*centre),
                                         segments=segments, ring_count=rings)
    obj = bpy.context.active_object
    obj.name = name
    return shade(obj, mat)


def torus_z(name, radius, minor, centre, mat, segments=96, minor_segments=12):
    """A ring facing the wearer."""
    bpy.ops.mesh.primitive_torus_add(major_radius=radius, minor_radius=minor,
                                     major_segments=segments, minor_segments=minor_segments,
                                     location=P(*centre), rotation=FACING)
    obj = bpy.context.active_object
    obj.name = name
    return shade(obj, mat)


def torus_x(name, radius, minor, centre, mat, segments=72, minor_segments=10):
    """A ring round the line (axis RealityKit X)."""
    bpy.ops.mesh.primitive_torus_add(major_radius=radius, minor_radius=minor,
                                     major_segments=segments, minor_segments=minor_segments,
                                     location=P(*centre), rotation=ALONG_X)
    obj = bpy.context.active_object
    obj.name = name
    return shade(obj, mat)


def revolve_x(name, profile, mat, segments=64):
    """A closed profile [(x, r)] revolved about the line; r = 0 is a pole."""
    bm = bmesh.new()
    rings = []
    for x, r in profile:
        if r < 1e-7:
            rings.append([bm.verts.new((x, 0, 0))])
        else:
            rings.append([bm.verts.new((x, r * math.cos(2 * math.pi * k / segments),
                                        r * math.sin(2 * math.pi * k / segments)))
                          for k in range(segments)])
    for i in range(len(rings)):
        a, b = rings[i], rings[(i + 1) % len(rings)]
        if len(a) == 1 and len(b) == 1:
            continue
        for k in range(segments):
            if len(a) == 1:
                bm.faces.new((a[0], b[k], b[(k + 1) % segments]))
            elif len(b) == 1:
                bm.faces.new((a[(k + 1) % segments], a[k], b[0]))
            else:
                bm.faces.new((a[k], b[k], b[(k + 1) % segments], a[(k + 1) % segments]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    data = bpy.data.meshes.new(name)
    bm.to_mesh(data)
    bm.free()
    obj = bpy.data.objects.new(name, data)
    bpy.context.collection.objects.link(obj)
    return shade(obj, mat)


def keyed(name, points, s, ink=0.0026, key=0.0010, lift=0.0022):
    """An ink stroke along `points` (RealityKit, in a plane facing the
    wearer) with a champagne keyline riding its front."""
    casing = tube(name, [P(*p) for p in points], ink, s["ink"], resolution=4)
    keyline = tube(name + "Key", [P(p[0], p[1], p[2] + lift) for p in points], key,
                   s["champagne"], resolution=3)
    return [casing, keyline]


def keyed_ring(name, radius, s, centre=(0, 0, 0), ink=0.0026, key=0.0010, lift=0.0022):
    return [torus_z(name, radius, ink, centre, s["ink"], segments=72, minor_segments=10),
            torus_z(name + "Key", radius, key, (centre[0], centre[1], centre[2] + lift),
                    s["champagne"], segments=72, minor_segments=6)]


def plus(name, centre, half, s, ink=0.0022, key=0.0009):
    x, y, z = centre
    return (keyed(name + "H", [(x - half, y, z), (x + half, y, z)], s, ink, key)
            + keyed(name + "V", [(x, y - half, z), (x, y + half, z)], s, ink, key))


# =============================================================== the parts

def build_battery(s):
    """The battery symbol as the cell it stands for: the long plate a copper
    disc (+) and the short one zinc (-), the gap between them the symbol's
    own. A disc seen edge-on is a line, so it reads from any side."""
    parts = [disc_x("Copper", 0.033, 0.008, (-0.008, 0, 0), s["copper"], chamfer=0.0016, vertices=96),
             disc_x("Zinc", 0.018, 0.011, (0.0085, 0, 0), s["zinc"], chamfer=0.0016, vertices=96)]
    parts += plus("Plus", (-0.026, 0.045, 0), 0.009, s)
    return [join("CircuitBattery", parts)]


def build_ac_source(s):
    """The circle with a sine in it, on a glass face. The child `bead` rides
    the sine at the source's phase, so its height is the EMF's."""
    half, amplitude, wave_z = AC_WAVE
    parts = keyed_ring("Ring", 0.030, s)
    parts.append(disc_z("Face", 0.0285, 0.004, (0, 0, -0.003), s["glass"], vertices=72))
    wave = [(-half + 2 * half * i / 32, amplitude * math.sin(2 * math.pi * i / 32), wave_z)
            for i in range(33)]
    parts += keyed("Wave", wave, s, ink=0.0018, key=0.0007, lift=0.0016)
    for side in (-1, 1):
        parts.append(disc_x("Collar", 0.0046, 0.004, (side * 0.033, 0, 0), s["brass"], chamfer=0.0008))
    bead = sphere("bead", AC_BEAD_RADIUS, (-half, 0, wave_z + 0.0024), s["brass"], segments=24, rings=12)
    origin_at(bead, P(-half, 0, wave_z + 0.0024))
    return [join("CircuitACSource", parts), bead]


def build_resistor_caps(s):
    """The procedural ceramic (Swift, live bands) is the IEC box; its steel
    caps are milled here, with the ANSI zigzag keylined across its face."""
    parts = []
    for x in (-0.0225, 0.0225):
        parts.append(disc_x("Cap", CERAMIC_RADIUS + 0.0006, 0.006, (x, 0, 0), s["steel"], chamfer=0.0010))
    zig = [(-0.018 + 0.036 * i / 8, (0 if i in (0, 8) else (0.0042 if i % 2 else -0.0042)),
            CERAMIC_RADIUS + 0.0030) for i in range(9)]
    parts += keyed("Zigzag", zig, s, ink=0.0016, key=0.0007, lift=0.0015)
    return [join("CircuitResistorCaps", parts)]


def build_capacitor(s):
    """Two real plates 8 mm apart, the - one (+X) dished like the polarised
    symbol's curved stroke. They are children so the charge can tint them."""
    plate0 = disc_x("plate0", 0.026, 0.003, (-0.0055, 0, 0), s["plate"], chamfer=0.0008, vertices=96)
    sag = 0.004

    def front(r):
        return 0.0045 + sag * (r / 0.026) ** 2
    rs = [0.026 * i / 10 for i in range(11)]
    profile = [(front(r), r) for r in rs] + [(front(r) + 0.003, r) for r in reversed(rs)]
    plate1 = revolve_x("plate1", profile, s["plate"], segments=72)
    parts = plus("Plus", (-0.019, 0.032, 0), 0.006, s, ink=0.0018, key=0.0007)
    # Each plate's edge is the symbol's stroke, inked: a plate is seen
    # nearly edge-on, and bare metal mirrored the white wall it stood in.
    for name, x in (("Rim0", -0.0055), ("Rim1", front(0.026) + 0.0015)):
        parts.append(torus_x(name, 0.0262, 0.0022, (x, 0, 0), s["ink"], segments=48, minor_segments=8))
        parts.append(torus_x(name + "Key", 0.0282, 0.0008, (x, 0, 0), s["champagne"], segments=48,
                             minor_segments=6))
    return [join("CircuitCapacitor", parts), apply(plate0), plate1]


def build_inductor(s):
    """A copper helix, eight turns, air core — the coil symbol's humps are a
    coil seen from the side. The model's L stays its own number."""
    radius, turns, x0, x1 = 0.014, 8, -0.024, 0.024
    points = [P(-0.027, 0)]
    steps = turns * 24
    for i in range(steps + 1):
        t = i / steps
        a = 2 * math.pi * turns * t
        points.append(P(x0 + (x1 - x0) * t, radius * math.cos(a), radius * math.sin(a)))
    points.append(P(0.027, 0))
    helix = tube("Helix", points, 0.0018, s["copper"], resolution=4)
    return [join("CircuitInductor", [helix])]


def build_bulb(s):
    """The circle with an X: a globe on the line, entered at its poles
    through brass caps, a keylined circle round it. One diagonal of the X
    is a steel support; the other, the child `filament`, glows."""
    parts = [sphere("Globe", 0.030, (0, 0, 0), s["glass"], segments=64, rings=32)]
    for side in (-1, 1):
        parts.append(disc_x("Cap", 0.0078, 0.008, (side * 0.0305, 0, 0), s["brass"], chamfer=0.0016))
    parts += keyed_ring("Ring", 0.0322, s)
    d = 0.0175
    parts.append(rod("Support", (-d, d, 0), (d, -d, 0), 0.0008, s["steel"]))
    parts.append(tube("InLeft", [P(-0.027, 0), P(-0.022, -0.006), P(-d, -d)], 0.0006, s["steel"],
                      resolution=3))
    parts.append(tube("InRight", [P(0.027, 0), P(0.022, 0.006), P(d, d)], 0.0006, s["steel"],
                      resolution=3))
    coil = []
    for i in range(161):
        t = i / 160
        a = 2 * math.pi * 14 * t
        along = -d + 2 * d * t
        coil.append(P(along + 0.0011 * math.cos(a) * 0.707, along - 0.0011 * math.cos(a) * 0.707,
                      0.0011 * math.sin(a)))
    filament = tube("filament", coil, 0.00045, s["filament"], resolution=3)
    return [join("CircuitBulb", parts), filament]


def build_led(s):
    """The diode's triangle as a red epoxy cone pointing from the anode
    (-X, terminal 0) to its bar; its shape says which way it conducts. The
    cone is the child `core`, lit at 625 nm only when it does."""
    cone = revolve_x("core", [(-0.012, 0), (-0.012, 0.012), (0.004, 0.0015), (0.004, 0)],
                     s["epoxy"], segments=64)
    parts = [disc_x("Bar", 0.012, 0.003, (0.0055, 0, 0), s["steel"], chamfer=0.0006)]
    for x0, y0 in ((-0.003, 0.016), (0.005, 0.014)):
        tip = (x0 + 0.010, y0 + 0.010, 0)
        parts += keyed("Arrow", [(x0, y0, 0), tip], s, ink=0.0014, key=0.0006, lift=0.0013)
        for turn in (-1, 1):
            a = math.radians(45 + 180 + turn * 30)
            parts += keyed("Head", [tip, (tip[0] + 0.004 * math.cos(a), tip[1] + 0.004 * math.sin(a), 0)],
                           s, ink=0.0014, key=0.0006, lift=0.0013)
    return [join("CircuitLED", parts), cone]


def flywheel_inertia():
    f = FLYWHEEL
    rim_mass = STEEL_DENSITY * math.pi * (f["outer"] ** 2 - f["inner"] ** 2) * f["thickness"]
    web_mass = STEEL_DENSITY * math.pi * f["inner"] ** 2 * f["web_thickness"]
    return (0.5 * rim_mass * (f["outer"] ** 2 + f["inner"] ** 2)
            + 0.5 * web_mass * f["inner"] ** 2)


def build_motor(s):
    """The motor's circle as a steel flywheel in the face plane, set behind
    the line so the leads pass in front of it into the hub. One brass
    marker, so its turn reads and nothing about it repeats (a cross aliased
    at 90 Hz; Phase 1 audit). Its inertia IS the model's (contract D4)."""
    f = FLYWHEEL
    inertia = flywheel_inertia()
    if abs(inertia - MOTOR_INERTIA) > 0.01 * MOTOR_INERTIA:
        sys.exit("circuitparts: the flywheel's inertia is %.6f, MOTOR_INERTIA says %.6f"
                 % (inertia, MOTOR_INERTIA))
    hub_back, hub_front = -0.022, 0.006
    parts = [disc_z("Hub", 0.014, hub_front - hub_back, (0, 0, (hub_back + hub_front) / 2),
                    s["graphite"], chamfer=0.0018)]
    m = [(-0.0060, -0.0055, hub_front + 0.0004), (-0.0060, 0.0055, hub_front + 0.0004),
         (0, -0.0005, hub_front + 0.0004), (0.0060, 0.0055, hub_front + 0.0004),
         (0.0060, -0.0055, hub_front + 0.0004)]
    parts += keyed("M", m, s, ink=0.0012, key=0.0005, lift=0.0010)
    parts.append(disc_z("Axle", 0.004, 0.010, (0, 0, -0.027), s["steel"], vertices=32))
    rim = cylinder("Rim", f["outer"], f["thickness"], location=P(0, 0, f["centre_z"]), rotation=FACING,
                   vertices=128)
    hole = cylinder("RimHole", f["inner"], f["thickness"] * 2.2, location=P(0, 0, f["centre_z"]),
                    rotation=FACING, vertices=128)
    bpy.context.view_layer.objects.active = rim
    cut = rim.modifiers.new("cut", "BOOLEAN")
    cut.operation = "DIFFERENCE"
    cut.object = hole
    cut.solver = "EXACT"
    bpy.ops.object.modifier_apply(modifier="cut")
    bpy.data.objects.remove(hole, do_unlink=True)
    rim.data.materials.clear()
    bevel(rim, 0.0015, segments=3, angle=50)
    shade(rim, s["steel"])
    web = disc_z("Web", f["inner"], f["web_thickness"], (0, 0, f["web_z"]), s["steel"], vertices=128)
    marker = box("Marker", (0.006, 0.002, 0.012), location=P(0, 0.033, f["centre_z"] + f["thickness"] / 2 + 0.001))
    bevel(marker, 0.0008, segments=2, angle=50)
    shade(marker, s["brass"])
    rotor = join("rotor", [rim, web, marker])
    origin_at(rotor, P(0, 0, 0))
    blur = cylinder("rotor_blur", f["outer"], 0.001, location=P(0, 0, f["centre_z"] + f["thickness"] / 2 + 0.0008),
                    rotation=FACING, vertices=128)
    blurhole = cylinder("BlurHole", f["inner"], 0.004, location=P(0, 0, f["centre_z"] + f["thickness"] / 2 + 0.0008),
                        rotation=FACING, vertices=128)
    bpy.context.view_layer.objects.active = blur
    cut = blur.modifiers.new("cut", "BOOLEAN")
    cut.operation = "DIFFERENCE"
    cut.object = blurhole
    cut.solver = "EXACT"
    bpy.ops.object.modifier_apply(modifier="cut")
    bpy.data.objects.remove(blurhole, do_unlink=True)
    blur.data.materials.clear()
    shade(blur, s["blur"])
    origin_at(blur, P(0, 0, 0))
    return [join("CircuitMotor", parts), rotor, blur]


def build_fuse(s):
    """A glass cartridge with brass caps — the IEC fuse symbol is exactly a
    cartridge seen from the side. Its wire is three children so a blown
    fuse can lose its middle, and the glass a child so it can scorch."""
    # 19 x 44 mm: the first cut, 13 x 34, was the smallest thing on the bench.
    parts = [disc_x("Cap", 0.0105, 0.008, (side * 0.024, 0, 0), s["brass"], chamfer=0.0012)
             for side in (-1, 1)]
    tube_wall = revolve_x("fuse_glass", [(-0.020, 0.0086), (0.020, 0.0086), (0.020, 0.0095),
                                         (-0.020, 0.0095)], s["glass"], segments=64)
    wires = [rod(name, (a, 0, 0), (b, 0, 0), 0.0007, s["copper"], resolution=4)
             for name, a, b in (("fuse_left", -0.020, -0.005), ("fuse_bridge", -0.005, 0.005),
                                ("fuse_right", 0.005, 0.020))]
    return [join("CircuitFuse", parts), tube_wall] + wires


def build_switch(s):
    """The symbol is the mechanism: open rings at the pivot and the contact,
    and the stroke between them is the blade. The child `blade` turns about
    its own origin, the pivot; Swift opens it to SWITCH_OPEN_DEGREES."""
    parts = [torus_z("Pivot", 0.0060, 0.0022, (SWITCH_PIVOT_X, 0, 0), s["brass"], segments=48),
             torus_z("Contact", 0.0060, 0.0022, (SWITCH_CONTACT_X, 0, 0), s["brass"], segments=48),
             disc_z("Pin", 0.0024, 0.009, (SWITCH_PIVOT_X, 0, 0), s["steel"], vertices=24)]
    stem_x = 0.024
    blade = [rod("Blade", (SWITCH_PIVOT_X, 0, 0), (SWITCH_CONTACT_X + 0.004, 0, 0), 0.0040, s["brass"]),
             rod("Stem", (stem_x, 0.003, 0), (stem_x, 0.014, 0), 0.0028, s["ink"]),
             sphere("Knob", 0.0100, (stem_x, 0.022, 0), s["ink"], segments=40, rings=20),
             torus_z("KnobKey", 0.0100, 0.0008, (stem_x, 0.022, 0), s["champagne"], segments=48,
                     minor_segments=6)]
    lever = join("blade", blade)
    origin_at(lever, P(SWITCH_PIVOT_X, 0, 0))
    return [join("CircuitSwitch", parts), lever]


def build_dot(s):
    return [sphere("CircuitDot", DOT_RADIUS, (0, 0, 0), s["brass"], segments=28, rings=14)]


def build_electron(s):
    """One electron of the flow, low-poly: the bench draws every one of them
    as an instance of these two meshes (contract D5)."""
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=3, radius=0.0026, location=(0, 0, 0))
    core = shade(bpy.context.active_object, s["electron"])
    core.name = "core"
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=2, radius=0.0045, location=(0, 0, 0))
    halo = shade(bpy.context.active_object, s["electron"])
    halo.name = "halo"
    return [core, halo]


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
    # (Drawn in graphite until 2026-10-30: band()'s empty slot.)
    key = band("StageKeyline", deck_radius - 0.020, deck_radius - 0.022, 0.0007,
               location=(0, 0, 0.00025), vertices=192)
    parts.append(shade(key, s["champagne"]))
    return [join("CircuitStageDeck", parts)]


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
    return [join("CircuitStageRim", parts)]


BUILDERS = {
    "CircuitBattery": build_battery,
    "CircuitACSource": build_ac_source,
    "CircuitResistorCaps": build_resistor_caps,
    "CircuitCapacitor": build_capacitor,
    "CircuitInductor": build_inductor,
    "CircuitBulb": build_bulb,
    "CircuitLED": build_led,
    "CircuitMotor": build_motor,
    "CircuitFuse": build_fuse,
    "CircuitSwitch": build_switch,
    "CircuitDot": build_dot,
    "CircuitElectron": build_electron,
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
        objects = builder(stocks())
        # The static element at identity, its origin the part's centre on
        # the line; each live child keeps the origin it was given.
        apply(objects[0])
        export(objects, os.path.join(ROOT, name + ".usdz"))


if __name__ == "__main__":
    main()
