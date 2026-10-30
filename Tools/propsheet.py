#!/usr/bin/env python3
"""
Circuit Workshop's parts rendered headless, as the wearer sees them, so a
design can be judged from a picture before anybody is asked for a
screenshot or a device pass.

    /Applications/Blender.app/Contents/MacOS/Blender --background \\
        --python Tools/propsheet.py -- <mode> [options]

Modes:

    sheet               every circuit part as the bench builds it, plus the
                        multimeter and a probe, each through the SAME camera,
                        so their sizes compare truly
    turntable [Name …]  each named asset (every one, if none is named) from
                        four sides — 0°, 90°, 180°, 270° about the vertical
                        (front, end, back, end)
    loop                the starter loop over its turntable, from the
                        wearer's eye at 1.6 m, as the lab opens on it
    stats               triangles, vertices, materials, textures, bounds and
                        the contract checks for every USDZ, as stats.md
    frames Prefix ...   every <Prefix>*.usdz in --src, in name order, through
                        one close camera: a storyboard of posed assemblies
    all                 stats, sheet, loop and a turntable of every asset

Options:

    --src DIR      where the USDZ files are (default the app's
                   Models/Circuits; Phase 2's throwaway parts live elsewhere)
    --label NAME   the output folder's name (default "current")
    --out DIR      the output folder (default Tools/propsheets/<label>)
    --light L      room, studio or both (default both)
    --bare         the USDZ alone, without the pieces Swift adds
    --parts a,b    the sheet's and turntable's parts (default every one)
    --samples N    Cycles samples per tile (default 48)

A folder given by --src may hold a contract.json overriding the numbers
read from the sources — `terminalOffset`, `wireCore`, `wireJacket`, any
mount — which is how a direction that moves its contacts is drawn
wired at the right places.

Everything lands in Tools/propsheets/, which git ignores: a render is
regenerated from this script, never kept. Nothing is written under
Models/, and no asset is milled here.

THE TWO CAMERAS. The wearer's tile is 0.9 m from the part and 20° above
it, the distance the starter loop stands from the eye, rendered at
HEADSET_PPD pixels per degree so that a stroke one pixel wide here is
about one pixel wide in the headset. The close tile is the wearer leaning
in to 25 cm, at a size to inspect detail rather than to judge legibility.

THE TWO LIGHTS. Both carry `RenderKit.Lighting.keyLight` — warm white,
from the upper front-left. `room` puts it in bright, neutral surroundings
before a pale wall, because passthrough is a bright medium and contours
beat glows indoors (DESIGN_SYSTEM.md); `studio` is Deep space's
near-black with a faint fill.

WHAT IT CANNOT SHOW. RealityKit's own pieces — the brass contacts, the
resistor's ceramic and bands, the switch blade, the motor's rotor, the
filaments, the gauge, the AC needle — are drawn here as stand-ins at the
places and sizes `CircuitsRenderer.makeModule` gives them, in materials
that only approximate the app's (an unlit colour becomes an emissive one;
the GlowSprite is left out). The headset is the authority on those.

THE NUMBERS ARE READ, NOT COPIED. Mount heights come from
`circuitparts.py`'s top-level constants through `ast` — importing it
would mill every part, because it calls `main()` at module scope — and
the Swift-only ones (contact spacing and radius, the switch pivot, the
ceramic, the starter loop, the asset names, the stage) by pattern from
the Swift sources. A pattern that stops matching stops the script, rather
than letting a stand-in drift from what it stands for.

HANDEDNESS. RealityKit (x, y, z) is Blender (x, -z, y): `rk()` below.
"""

import ast
import math
import os
import re
import sys

sys.dont_write_bytecode = True

import bpy  # noqa: E402
import numpy as np  # noqa: E402
from mathutils import Euler, Matrix, Vector  # noqa: E402

TOOLS = os.path.dirname(os.path.abspath(__file__))
PROJECT = os.path.dirname(TOOLS)
APP = os.path.join(PROJECT, "PhysicsPlayground")
MODELS = os.path.join(APP, "Models", "Circuits")

# The headset's angular resolution, roughly: the figure commonly quoted
# for Apple Vision Pro is about 34 pixels per degree at the centre.
HEADSET_PPD = 34

WEARER_DISTANCE = 0.90
WEARER_ELEVATION = math.radians(20)
WEARER_FOV = (16.0, 12.0)            # degrees, wide enough for the multimeter
CLOSE_DISTANCE = 0.25
CLOSE_FOV = (46.0, 31.0)
CLOSE_SIZE = (960, 640)
CLOSE_ELEVATION = math.radians(35)  # leaning in, over the part's shoulder,
CLOSE_AZIMUTH = math.radians(30)    # so the close tile adds a view, not a zoom

EYE = (0.0, 1.6, 0.0)                # the wearer, standing, for the loop

KEY_FROM = (-0.6, 1.0, 0.7)          # `Lighting.keyLight`'s look(from:)
KEY_COLOUR = (1.0, 0.96, 0.9)


# --------------------------------------------------------------- arguments

def arguments():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    options = {"src": MODELS, "label": "current", "out": None, "light": "both",
               "bare": False, "samples": 48, "parts": None}
    words = []
    index = 0
    while index < len(argv):
        word = argv[index]
        if word == "--bare":
            options["bare"] = True
        elif word in ("--src", "--label", "--out", "--light", "--samples", "--parts"):
            options[word[2:]] = argv[index + 1]
            index += 1
        else:
            words.append(word)
        index += 1
    if not words:
        sys.exit("propsheet: name a mode — sheet, turntable <Name…>, loop, stats or all")
    options["samples"] = int(options["samples"])
    if options["parts"]:
        options["parts"] = options["parts"].split(",")
    options["out"] = options["out"] or os.path.join(TOOLS, "propsheets", options["label"])
    options["lights"] = ["room", "studio"] if options["light"] == "both" else [options["light"]]
    return words[0], words[1:], options


# --------------------------------------------------------- the contract

def python_constants():
    """`circuitparts.py`'s top-level numbers, by reading, never importing."""
    with open(os.path.join(TOOLS, "circuitparts.py")) as handle:
        tree = ast.parse(handle.read())
    found = {}
    for node in tree.body:
        if isinstance(node, ast.Assign) and len(node.targets) == 1 \
                and isinstance(node.targets[0], ast.Name):
            try:
                found[node.targets[0].id] = ast.literal_eval(node.value)
            except ValueError:
                pass
    return found


def swift(relative, pattern, flags=0):
    with open(os.path.join(APP, relative)) as handle:
        match = re.search(pattern, handle.read(), flags)
    if not match:
        sys.exit("propsheet: %s no longer matches /%s/ — update the pattern, "
                 "not the number" % (relative, pattern))
    return match


def contract():
    model = "Modules/Circuits/CircuitsModel.swift"
    renderer = "Modules/Circuits/CircuitsRenderer.swift"
    tokens = "DesignSystem/DesignTokens.swift"
    py = python_constants()
    c = {key: py[key] for key in ("CARRIER_TOP", "BULB_CENTRE", "LED_GLOW", "MOTOR_AXIS",
                                  "SWITCH_PIVOT", "RESISTOR_AXIS", "FUSE_AXIS", "AC_FACE")}
    number = r"(-?[0-9.]+)"
    c["terminalOffset"] = float(swift(model, r"static let terminalOffset = " + number).group(1))
    c["stageRadius"] = float(swift(model, r"static let stageRadius = " + number).group(1))
    c["stageTop"] = float(swift(model, r"homeStage = Stage\(.*?top: " + number, re.S).group(1))
    c["contactRadius"] = float(swift(renderer, r"static let contactRadius: Float = " + number).group(1))
    c["wireCore"] = float(swift(renderer, r"core = ModelEntity\(\s*mesh: Primitives\.cylinder\("
                                          r"height: 1, radius: " + number).group(1))
    c["wireJacket"] = float(swift(renderer, r"jacket = ModelEntity\(\s*mesh: Primitives\.cylinder\("
                                            r"height: 1, radius: " + number).group(1))
    c["switchPivotX"] = float(swift(renderer, r"static let switchPivot = SIMD3<Float>\(" + number).group(1))
    c["ceramicRadius"] = float(swift(renderer, r"static let ceramicRadius: Float = " + number).group(1))
    c["ceramicLength"] = float(swift(renderer, r"static let ceramicLength: Float = " + number).group(1))

    def colour(name):
        rgb = swift(tokens, r"static let %s = UIColor\(red: %s, green: %s, blue: %s"
                    % (name, number, number, number))
        return tuple(float(rgb.group(i)) for i in (1, 2, 3))
    c["brass"] = colour("contactBrassUI")
    c["copper"] = colour("copperUI")
    c["motorAccent"] = colour("motorAccentUI")

    block = swift(renderer, r"static let bodyAssetNames[^=]*= \[(.*?)\]", re.S).group(1)
    c["bodies"] = dict(re.findall(r"\.(\w+): \"(\w+)\"", block))
    c["resistorCaps"] = swift(renderer, r"resistorCapsAssetName = \"(\w+)\"").group(1)
    c["carrier"] = swift(renderer, r"carrierAssetName = \"(\w+)\"").group(1)

    kinds = swift(model, r"enum ComponentKind.*?\n((?:\s*case [\w, ]+\n)+)", re.S).group(1)
    c["kinds"] = re.findall(r"\w+", kinds.replace("case", ""))
    missing = [k for k in c["kinds"] if k != "resistor" and k not in c["bodies"]]
    if missing:
        sys.exit("propsheet: no asset named for %s" % missing)

    starter = swift(model, r"static let starterParts.*?\n    \]", re.S).group(0)
    c["starter"] = [(kind, tuple(map(float, p.split(","))), tuple(map(float, a.split(","))))
                    for kind, p, a in re.findall(
                        r"\(\.(\w+), SIMD3\(([^)]*)\), SIMD3\(([^)]*)\)\)", starter)]
    wires = swift(model, r"static let starterWires.*?\n    \]", re.S).group(0)
    c["starterWires"] = [((int(a), int(b)), (int(d), int(e))) for a, b, d, e in
                         re.findall(r"\(\((\d), (\d)\), \((\d), (\d)\)\)", wires)]
    if len(c["starter"]) < 2 or not c["starterWires"]:
        sys.exit("propsheet: could not read the starter loop")
    return c


# --------------------------------------------------------------- geometry

def rk(x, y, z):
    """A RealityKit point in Blender's frame."""
    return Vector((x, -z, y))


ALONG_X = Euler((0, math.pi / 2, 0))     # a Blender cylinder is built along Z


def linear(rgb):
    """A UIColor's or CGColor's sRGB components as Blender's linear ones.
    The milled assets need none of this: `circuitparts.py` writes linear
    values and USD carries them linear."""
    return tuple(c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4 for c in rgb)


def material(name, colour, metallic=0.0, roughness=0.5, alpha=1.0, emission=0.0):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = (*colour, 1)
    bsdf.inputs["Metallic"].default_value = metallic
    bsdf.inputs["Roughness"].default_value = roughness
    bsdf.inputs["Alpha"].default_value = alpha
    if emission:
        bsdf.inputs["Emission Color"].default_value = (*colour, 1)
        bsdf.inputs["Emission Strength"].default_value = emission
    return mat


def unlit(name, colour, alpha=1.0):
    """RealityKit's UnlitMaterial: a colour the light does not change."""
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nodes, links = mat.node_tree.nodes, mat.node_tree.links
    nodes.clear()
    out = nodes.new("ShaderNodeOutputMaterial")
    emit = nodes.new("ShaderNodeEmission")
    emit.inputs["Color"].default_value = (*colour, 1)
    if alpha < 1:
        clear = nodes.new("ShaderNodeBsdfTransparent")
        mix = nodes.new("ShaderNodeMixShader")
        mix.inputs["Fac"].default_value = alpha
        links.new(clear.outputs[0], mix.inputs[1])
        links.new(emit.outputs[0], mix.inputs[2])
        links.new(mix.outputs[0], out.inputs["Surface"])
    else:
        links.new(emit.outputs[0], out.inputs["Surface"])
    return mat


def mesh_object(name, data, mat, parent):
    obj = bpy.data.objects.new(name, data)
    bpy.context.collection.objects.link(obj)
    obj.data.materials.append(mat)
    obj.parent = parent
    obj["standin"] = True     # Swift's piece, not the asset's: never counted
    for polygon in obj.data.polygons:
        polygon.use_smooth = True
    return obj


def primitive(kind, name, mat, parent, location, rotation=(0, 0, 0), **size):
    """A RealityKit primitive, built with the data API so it needs no
    operator context: `size` is radius/height or a box's RealityKit x, y, z."""
    import bmesh
    bm = bmesh.new()
    if kind == "sphere":
        bmesh.ops.create_uvsphere(bm, u_segments=32, v_segments=16, radius=size["radius"])
    elif kind == "cylinder":
        bmesh.ops.create_cone(bm, cap_ends=True, segments=32, radius1=size["radius"],
                              radius2=size["radius"], depth=size["height"])
    else:
        x, y, z = size["size"]
        bmesh.ops.create_cube(bm, size=1)
        bmesh.ops.scale(bm, vec=(x, z, y), verts=bm.verts)
    data = bpy.data.meshes.new(name)
    bm.to_mesh(data)
    bm.free()
    obj = mesh_object(name, data, mat, parent)
    obj.location = location
    obj.rotation_euler = rotation
    return obj


def import_usd(path, parent):
    """Imports one USDZ under `parent`; returns its mesh objects."""
    before = set(bpy.data.objects)
    bpy.ops.wm.usd_import(filepath=path)
    new = [o for o in bpy.data.objects if o not in before]
    for obj in new:
        if obj.parent is None:
            obj.parent = parent
    return [o for o in new if o.type == "MESH"]


# ----------------------------------------------------------- the modules

class Kit:
    """The materials the stand-ins wear, made once per scene."""

    def __init__(self, c):
        # Every colour here is Swift's, so sRGB, made linear for Blender.
        self.brass = material("SI_Brass", linear(c["brass"]), metallic=0.62, roughness=0.28)
        self.copper = material("SI_Copper", linear(c["copper"]), metallic=0.62, roughness=0.35)
        self.ceramic = material("SI_Ceramic", linear((0.85, 0.72, 0.55)), roughness=0.6)
        self.graphite = material("SI_Graphite", linear((0.17, 0.17, 0.18)), metallic=0.2,
                                 roughness=0.4)
        self.steel = material("SI_Steel", linear((0.6, 0.6, 0.6)), metallic=0.62, roughness=0.3)
        self.filament = unlit("SI_FilamentOff", linear((0.35, 0.35, 0.35)))
        self.filamentLit = unlit("SI_FilamentLit", (6.0, 4.2, 2.2))
        self.rotor = unlit("SI_Rotor", linear(c["motorAccent"]))
        self.track = unlit("SI_GaugeTrack", linear((0.18, 0.18, 0.18)))
        self.needle = unlit("SI_Needle", linear((0.10, 0.10, 0.10)))
        # The resistor's live bands at the shelf's 470 Ω: yellow, violet,
        # brown, and gold tolerance (CircuitTextures).
        self.bands = [material("SI_Band%d" % i, linear(rgb), roughness=0.6) for i, rgb in enumerate(
            [(0.95, 0.85, 0.2), (0.55, 0.25, 0.7), (0.45, 0.26, 0.13), (0.82, 0.66, 0.22)])]


def asset_path(src, name):
    return os.path.join(src, name + ".usdz")


def build_module(kind, c, kit, src, bare, lit=False):
    """One part as `CircuitsRenderer.makeModule` builds it, in its own frame."""
    root = bpy.data.objects.new("module-" + kind, None)
    bpy.context.collection.objects.link(root)
    missing = []
    for name in [c["carrier"], c["resistorCaps"] if kind == "resistor" else c["bodies"][kind]]:
        path = asset_path(src, name)
        if os.path.exists(path):
            import_usd(path, root)
        else:
            missing.append(name)
    if bare:
        return root, missing
    top = c["CARRIER_TOP"]
    for end in (-1, 1):
        primitive("sphere", "contact", kit.brass, root, rk(end * c["terminalOffset"], 0, 0),
                  radius=c["contactRadius"])
    if kind == "resistor":
        length, radius = c["ceramicLength"], c["ceramicRadius"]
        primitive("cylinder", "ceramic", kit.ceramic, root, rk(0, c["RESISTOR_AXIS"], 0),
                  ALONG_X, radius=radius, height=length)
        for band, fraction in zip(kit.bands, (0.22, 0.38, 0.54, 0.78)):
            primitive("cylinder", "band", band, root,
                      rk(-length / 2 + fraction * length, c["RESISTOR_AXIS"], 0), ALONG_X,
                      radius=radius + 0.0002, height=length * 12 / 128)
    elif kind == "bulb":
        primitive("cylinder", "filament", kit.filamentLit if lit else kit.filament, root,
                  rk(0, c["BULB_CENTRE"], 0), ALONG_X, radius=0.0009, height=0.010)
        if lit:
            light = bpy.data.lights.new("bulb-light", "POINT")
            light.energy = 1.2
            light.color = (1.0, 0.78, 0.5)
            light.shadow_soft_size = 0.004
            holder = bpy.data.objects.new("bulb-light", light)
            bpy.context.collection.objects.link(holder)
            holder.parent = root
            holder.location = rk(0, c["BULB_CENTRE"], 0)
    elif kind == "motor":
        at = rk(0.050, c["MOTOR_AXIS"], 0)
        primitive("sphere", "hub", kit.steel, root, at, radius=0.006)
        primitive("box", "blade", kit.rotor, root, at, size=(0.004, 0.036, 0.003))
        primitive("box", "blade", kit.rotor, root, at, (math.pi / 2, 0, 0),
                  size=(0.004, 0.036, 0.003))
    elif kind == "switcher":
        pivot = (c["switchPivotX"], c["SWITCH_PIVOT"])
        primitive("box", "blade", kit.brass, root, rk(pivot[0] + 0.033, pivot[1] + 0.0005, 0),
                  size=(0.066, 0.005, 0.0045))
        primitive("box", "grip", kit.graphite, root, rk(pivot[0] + 0.064, pivot[1] + 0.003, 0),
                  size=(0.008, 0.010, 0.008))
    elif kind == "fuse":
        for x, height in ((-0.0105, 0.012), (0, 0.009), (0.0105, 0.012)):
            primitive("cylinder", "fuse-wire", kit.copper, root, rk(x, c["FUSE_AXIS"], 0),
                      ALONG_X, radius=0.0006, height=height)
    elif kind == "capacitor":
        primitive("box", "gauge-track", kit.track, root, rk(0, top + 0.0005, 0.0175),
                  size=(0.026, 0.0010, 0.0032))
    elif kind == "acSource":
        at = (0, c["AC_FACE"] + 0.0010, 0)
        primitive("box", "needle", kit.needle, root, rk(at[0], at[1], -0.0068),
                  size=(0.0012, 0.0008, 0.0150))
        primitive("cylinder", "needle-hub", kit.brass, root, rk(*at), radius=0.0018,
                  height=0.0012)
    return root, missing


def build_asset(name, src):
    """An asset alone (the stage, the multimeter, a probe, a bare body)."""
    holder = bpy.data.objects.new("asset-" + name, None)
    bpy.context.collection.objects.link(holder)
    root = holder
    if name == "Multimeter":
        # The case is milled lying face up; `Multimeter.swift` stands it
        # with +90° about x, screen to the reader.
        root = bpy.data.objects.new("stand", None)
        bpy.context.collection.objects.link(root)
        root.parent = holder
        root.rotation_euler = (math.pi / 2, 0, 0)
    path = asset_path(src, name)
    missing = [] if os.path.exists(path) else [name]
    if not missing:
        import_usd(path, root)
    return holder, missing


def kind_for(name, c):
    for kind, asset in c["bodies"].items():
        if asset == name:
            return kind
    return "resistor" if name == c["resistorCaps"] else None


# ------------------------------------------------------------- the stage

def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def configure(samples):
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    try:
        prefs = bpy.context.preferences.addons["cycles"].preferences
        prefs.compute_device_type = "METAL"
        # No specialised kernels: Cycles compiles them on a background
        # thread, and a tile's scene reset mid-compile crashed Blender in
        # Metal's binary-archive writer.
        if hasattr(prefs, "kernel_optimization_level"):
            prefs.kernel_optimization_level = "OFF"
        prefs.get_devices()
        for device in prefs.devices:
            device.use = True
        scene.cycles.device = "GPU"
    except (KeyError, TypeError, AttributeError):
        scene.cycles.device = "CPU"
    scene.cycles.samples = samples
    scene.cycles.use_denoising = True
    scene.render.film_transparent = False
    scene.view_settings.view_transform = "AgX"
    scene.view_settings.look = "None"
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGB"


def light_room(kind):
    """`room` or `studio`, around whatever stands at the origin."""
    world = bpy.data.worlds.new(kind)
    bpy.context.scene.world = world
    world.use_nodes = True
    background = world.node_tree.nodes["Background"]
    if kind == "room":
        background.inputs["Color"].default_value = (0.80, 0.80, 0.79, 1)
        background.inputs["Strength"].default_value = 1.0
    else:
        background.inputs["Color"].default_value = (0.010, 0.011, 0.014, 1)
        background.inputs["Strength"].default_value = 1.0
    sun = bpy.data.lights.new("key", "SUN")
    sun.color = KEY_COLOUR
    sun.energy = 2.2 if kind == "room" else 3.0
    sun.angle = math.radians(8)
    key = bpy.data.objects.new("key", sun)
    bpy.context.collection.objects.link(key)
    toward = -rk(*KEY_FROM).normalized()
    key.rotation_euler = toward.to_track_quat("-Z", "Y").to_euler()
    if kind == "studio":
        fill = bpy.data.lights.new("fill", "AREA")
        fill.energy = 6
        fill.size = 1.5
        holder = bpy.data.objects.new("fill", fill)
        bpy.context.collection.objects.link(holder)
        holder.location = rk(0.9, 0.4, 1.2)
        holder.rotation_euler = (-holder.location).to_track_quat("-Z", "Y").to_euler()


def backdrop(kind, centre, normal_toward, distance, size):
    """The room's pale wall behind the subject; nothing in Deep space."""
    if kind != "room":
        return None
    data = bpy.data.meshes.new("wall")
    half = size / 2
    data.from_pydata([(-half, -half, 0), (half, -half, 0), (half, half, 0), (-half, half, 0)],
                     [], [(0, 1, 2, 3)])
    wall = bpy.data.objects.new("wall", data)
    bpy.context.collection.objects.link(wall)
    wall.data.materials.append(material("Wall", (0.74, 0.73, 0.71), roughness=0.9))
    direction = normal_toward.normalized()
    wall.location = centre - direction * distance
    wall.rotation_euler = direction.to_track_quat("Z", "Y").to_euler()
    return wall


def camera(target, distance, elevation, azimuth, fov, size):
    data = bpy.data.cameras.new("eye")
    data.sensor_fit = "HORIZONTAL"
    data.angle = math.radians(fov[0])
    data.clip_start = 0.005
    eye = bpy.data.objects.new("eye", data)
    bpy.context.collection.objects.link(eye)
    # From the front (RealityKit +z), raised by `elevation`, swung by `azimuth`.
    offset = rk(distance * math.cos(elevation) * math.sin(azimuth),
                distance * math.sin(elevation),
                distance * math.cos(elevation) * math.cos(azimuth))
    eye.location = target + offset
    eye.rotation_euler = (target - eye.location).to_track_quat("-Z", "Y").to_euler()
    bpy.context.scene.camera = eye
    bpy.context.scene.render.resolution_x, bpy.context.scene.render.resolution_y = size
    bpy.context.scene.render.resolution_percentage = 100
    return eye


def caption(eye, text, light, fov, size, pixels=15):
    """Small type in the frame's top-left corner, riding the camera."""
    curve = bpy.data.curves.new("caption", "FONT")
    curve.body = text
    depth = 0.02
    frame_height = 2 * depth * math.tan(math.radians(fov[0]) / 2) * size[1] / size[0]
    curve.size = frame_height * pixels / size[1]
    label = bpy.data.objects.new("caption", curve)
    bpy.context.collection.objects.link(label)
    label.parent = eye
    frame_width = frame_height * size[0] / size[1]
    label.location = (-frame_width / 2 + frame_height * 0.03,
                      frame_height / 2 - curve.size * 1.25, -depth)
    ink = (0.08, 0.08, 0.09) if light == "room" else (0.80, 0.80, 0.80)
    label.data.materials.append(unlit("Caption", ink))
    return label


def render(path):
    bpy.context.scene.render.filepath = path
    bpy.ops.render.render(write_still=True)


def fit_distance(subject, fov, margin=1.45):
    """How far back the close camera stands so `subject` fits its frame."""
    meshes = [o for o in subject.children_recursive if o.type == "MESH"]
    bounds = rk_bounds(meshes)
    if not bounds:
        return CLOSE_DISTANCE
    half = [(b - a) / 2 for a, b in zip(*bounds)]
    across = max(half[0], half[2]) / math.tan(math.radians(fov[0]) / 2)
    up = max(half[1], half[2]) / math.tan(math.radians(fov[1]) / 2)
    return max(CLOSE_DISTANCE, margin * max(across, up))


def tile(path, subject, target, light, distance, fov, size, text, close=False, fit=True):
    """One picture of `subject`, alone in the scene's render, to `path`:
    from the wearer, square on and 20° above, or leaning in close."""
    if close:
        eye = camera(target, fit_distance(subject, fov) if fit else distance,
                     CLOSE_ELEVATION, CLOSE_AZIMUTH, fov, size)
    else:
        eye = camera(target, distance, WEARER_ELEVATION, 0.0, fov, size)
    wall = backdrop(light, target, eye.location - target, 0.45, 2.0)
    label = caption(eye, text, light, fov, size, pixels=22 if close else 15)
    render(path)
    for obj in (wall, label, eye):
        if obj is not None:
            bpy.data.objects.remove(obj, do_unlink=True)


def wearer_size():
    return (round(WEARER_FOV[0] * HEADSET_PPD), round(WEARER_FOV[1] * HEADSET_PPD))


# ---------------------------------------------------------- compositing

def load_pixels(path):
    image = bpy.data.images.load(path)
    w, h = image.size
    pixels = np.array(image.pixels[:], dtype=np.float32).reshape(h, w, image.channels)
    bpy.data.images.remove(image)
    if pixels.shape[2] == 3:
        pixels = np.concatenate([pixels, np.ones((h, w, 1), np.float32)], axis=2)
    return pixels


def composite(rows, path, gap=6, ink=(0.5, 0.5, 0.5)):
    """Tiles laid out row by row (top row first), one PNG."""
    grid = [[load_pixels(p) for p in row] for row in rows]
    width = max(sum(t.shape[1] for t in row) + gap * (len(row) - 1) for row in grid)
    height = sum(max(t.shape[0] for t in row) for row in grid) + gap * (len(grid) - 1)
    canvas = np.ones((height, width, 4), np.float32)
    canvas[:, :, :3] = ink
    y = height
    for row in grid:
        row_height = max(t.shape[0] for t in row)
        y -= row_height
        x = 0
        for t in row:
            canvas[y + row_height - t.shape[0]:y + row_height, x:x + t.shape[1]] = t
            x += t.shape[1] + gap
        y -= gap
    image = bpy.data.images.new("composite", width, height, alpha=True)
    image.pixels.foreach_set(canvas.ravel())
    image.filepath_raw = path
    image.file_format = "PNG"
    image.save()
    bpy.data.images.remove(image)
    print("wrote", path)


# ---------------------------------------------------------------- stats

def triangles(objects):
    count = vertices = 0
    for obj in objects:
        obj.data.calc_loop_triangles()
        count += len(obj.data.loop_triangles)
        vertices += len(obj.data.vertices)
    return count, vertices


def rk_bounds(objects):
    points = [obj.matrix_world @ v.co for obj in objects for v in obj.data.vertices]
    if not points:
        return None
    lo = [min(p[i] for p in points) for i in range(3)]
    hi = [max(p[i] for p in points) for i in range(3)]
    # Blender (x, y, z) -> RealityKit (x, z, -y)
    return (lo[0], lo[2], -hi[1]), (hi[0], hi[2], -lo[1])


def usd_census(path):
    """Read straight from the USD: draw calls (one per material subset per
    mesh), faces bound to NO material, and faces outside every subset,
    which take the mesh's own binding — the exporter's first material.
    That is where `blenderprops.band()`'s rings land: its boolean leaves an
    empty slot every ring face points at, so a ring is drawn in whatever
    material happened to be first, not the one `shade()` gave it."""
    try:
        from pxr import Usd, UsdGeom, UsdShade
    except ImportError:
        return None
    stage = Usd.Stage.Open(path)
    meshes = draws = unbound = 0
    fallen = []
    textures = []
    for prim in stage.Traverse():
        if prim.IsA(UsdShade.Shader):
            for name in prim.GetPropertyNames():
                value = prim.GetAttribute(name).Get() if prim.GetAttribute(name) else None
                if hasattr(value, "path") and value.path:
                    textures.append(os.path.basename(value.path))
        if not prim.IsA(UsdGeom.Mesh):
            continue
        meshes += 1
        mesh = UsdGeom.Mesh(prim)
        faces = len(mesh.GetFaceVertexCountsAttr().Get() or [])
        binding = UsdShade.MaterialBindingAPI(prim)
        subsets = binding.GetMaterialBindSubsets()
        direct = binding.ComputeBoundMaterial()[0]
        if subsets:
            covered = set()
            for subset in subsets:
                covered.update(subset.GetIndicesAttr().Get() or [])
            draws += len(subsets)
            if len(covered) < faces:
                draws += 1
                if direct:
                    fallen.append("%d faces fall to %s" % (faces - len(covered),
                                                          direct.GetPrim().GetName()))
                else:
                    unbound += faces - len(covered)
        else:
            draws += 1
            if not direct:
                unbound += faces
    return {"meshes": meshes, "draws": draws, "unbound": unbound, "fallen": fallen,
            "textures": sorted(set(textures))}


def stats(c, options):
    rows = []
    names = sorted(f[:-5] for f in os.listdir(options["src"]) if f.endswith(".usdz"))
    clamp = c["terminalOffset"] - 0.026
    for name in names:
        reset()
        path = asset_path(options["src"], name)
        root = bpy.data.objects.new("root", None)
        bpy.context.collection.objects.link(root)
        objects = import_usd(path, root)
        bpy.context.view_layer.update()
        tris, verts = triangles(objects)
        materials = {slot.material.name.split(".")[0] for o in objects
                     for slot in o.material_slots if slot.material}
        bounds = rk_bounds(objects)
        census = usd_census(path) or {}
        checks = []
        kind = kind_for(name, c)
        if bounds and kind:
            (lx, ly, lz), (hx, hy, hz) = bounds
            if max(hx, -lx) >= clamp:
                checks.append("reaches its lead (|x| %.4f ≥ %.3f)" % (max(hx, -lx), clamp))
            if abs((hz + lz) / 2) > 0.004:
                checks.append("off the centre line")
        if census.get("unbound"):
            checks.append("%d faces bound to no material" % census["unbound"])
        checks += census.get("fallen", [])
        rows.append((name, tris, verts, len(materials), census.get("draws", "?"),
                     ", ".join(census.get("textures", [])) or "—",
                     os.path.getsize(path) // 1024, bounds, "; ".join(checks) or "ok"))
    os.makedirs(options["out"], exist_ok=True)
    lines = ["# Circuit assets — %s" % options["label"], "",
             "Source: `%s`. Bounds in RealityKit metres (x, y, z)." % os.path.relpath(
                 options["src"], PROJECT), "",
             "| Asset | Triangles | Vertices | Materials | Draws | Textures | KB | Bounds min → max | Checks |",
             "|---|---:|---:|---:|---:|---|---:|---|---|"]
    for name, tris, verts, mats, draws, tex, kb, bounds, check in rows:
        box = "—" if not bounds else "(%.3f, %.3f, %.3f) → (%.3f, %.3f, %.3f)" % (
            *bounds[0], *bounds[1])
        lines.append("| %s | %d | %d | %d | %s | %s | %d | %s | %s |" % (
            name, tris, verts, mats, draws, tex, kb, box, check))
    body = sum(r[1] for r in rows if kind_for(r[0], c))
    lines += ["", "Every part's carrier is `%s` (%d triangles), cloned once per part." % (
        c["carrier"], next((r[1] for r in rows if r[0] == c["carrier"]), 0)),
        "The ten bodies together: %d triangles." % body]
    with open(os.path.join(options["out"], "stats.md"), "w") as handle:
        handle.write("\n".join(lines) + "\n")
    print("\n".join(lines))


# ---------------------------------------------------------------- modes

def caption_for(name, objects_root, missing):
    meshes = [o for o in objects_root.children_recursive
              if o.type == "MESH" and not o.get("standin")]
    tris, _ = triangles(meshes)
    note = "  MISSING " + ", ".join(missing) if missing else ""
    return "%s  %s tris%s" % (name, format(tris, ","), note)


def sheet(c, options):
    names = options["parts"] or [k for k in c["kinds"]] + ["Multimeter", "MeterProbe"]
    for light in options["lights"]:
        for distance, fov, size, tag in ((WEARER_DISTANCE, WEARER_FOV, wearer_size(), "wearer"),
                                         (CLOSE_DISTANCE, CLOSE_FOV, CLOSE_SIZE, "close")):
            paths = []
            for name in names:
                reset()
                configure(options["samples"])
                light_room(light)
                if name in c["kinds"]:
                    kit = Kit(c)
                    root, missing = build_module(name, c, kit, options["src"], options["bare"])
                    target = rk(0, 0.008, 0)
                else:
                    root, missing = build_asset(name, os.path.dirname(asset_path(options["src"], name)))
                    target = Vector((0, 0, 0))
                    if name == "MeterProbe":
                        root.rotation_euler = (0, math.radians(90), 0)
                bpy.context.view_layer.update()
                path = os.path.join(options["out"], "tiles", "sheet-%s-%s-%s.png" % (tag, light, name))
                tile(path, root, target, light, distance, fov, size,
                     caption_for(name, root, missing), close=(tag == "close"))
                paths.append(path)
            per_row = 4
            composite([paths[i:i + per_row] for i in range(0, len(paths), per_row)],
                      os.path.join(options["out"], "sheet-%s-%s.png" % (tag, light)))


def turntable(c, options, names):
    for name in names:
        rows = []
        for light in options["lights"]:
            for distance, fov, size, tag in ((WEARER_DISTANCE, WEARER_FOV, wearer_size(), "wearer"),
                                             (CLOSE_DISTANCE, CLOSE_FOV, CLOSE_SIZE, "close")):
                row = []
                for degrees in (0, 90, 180, 270):
                    reset()
                    configure(options["samples"])
                    light_room(light)
                    kind = name if name in c["kinds"] else kind_for(name, c)
                    fit = True
                    if kind:
                        root, missing = build_module(kind, c, Kit(c), options["src"], options["bare"])
                        target = rk(0, 0.008, 0)
                        label = kind
                    else:
                        root, missing = build_asset(name, options["src"])
                        bpy.context.view_layer.update()
                        meshes = [o for o in root.children_recursive if o.type == "MESH"]
                        lo, hi = rk_bounds(meshes) or ((0, 0, 0), (0, 0, 0))
                        target = rk(*[(a + b) / 2 for a, b in zip(lo, hi)])
                        label = name
                        span = max(hi[0] - lo[0], hi[2] - lo[2], hi[1] - lo[1])
                        if span > 0.3 and tag == "wearer":
                            # The stage: a wider view at the same pixels per
                            # degree, from where a wearer would see it whole.
                            distance = 1.3
                            half = math.degrees(math.atan(0.6 * span / distance))
                            fov = (2 * half, 1.5 * half)
                            size = (round(fov[0] * HEADSET_PPD), round(fov[1] * HEADSET_PPD))
                        elif span > 0.3:
                            # Its close-up is the rim's near edge, knurls and all.
                            target = rk(0, (lo[1] + hi[1]) / 2, hi[2])
                            fit = False
                    root.rotation_euler = (0, 0, math.radians(degrees))
                    bpy.context.view_layer.update()
                    path = os.path.join(options["out"], "tiles", "turn-%s-%s-%s-%03d.png" % (
                        label, tag, light, degrees))
                    tile(path, root, target, light, distance, fov, size,
                         "%s  %d°  %s %s" % (label, degrees, tag, light), close=(tag == "close"),
                         fit=fit)
                    row.append(path)
                rows.append(row)
        composite(rows, os.path.join(options["out"], "turntable-%s.png" % name))


def loop(c, options):
    for light in options["lights"]:
        reset()
        configure(options["samples"])
        light_room(light)
        kit = Kit(c)
        span = c["terminalOffset"]
        ends = []
        for kind, position, axis in c["starter"]:
            root, _ = build_module(kind, c, kit, options["src"], options["bare"], lit=True)
            x = Vector(axis).normalized()
            # `moduleOrientation`: upright when the axis lies off vertical,
            # else the part's top turns to the stage's front (+z).
            up = Vector((0, 1, 0))
            top = up - up.dot(x) * x
            if top.length < 0.26:
                front = Vector((0, 0, 1))
                top = front - front.dot(x) * x
            top.normalize()
            z = x.cross(top)
            # The module is built in Blender axes: its RealityKit x, y, z are
            # Blender x, z, −y, so those are the columns that take x, top, z.
            def to_blender(v):
                return Vector((v[0], -v[2], v[1]))
            basis = Matrix((to_blender(x), -to_blender(z), to_blender(top))).transposed()
            root.matrix_world = Matrix.Translation(rk(*position)) @ basis.to_4x4()
            centre = Vector(position)
            ends.append((centre - x * span, centre + x * span))
        # Straight wires, terminal to terminal: a copper-voltage core inside
        # a dark jacket at 0.82 opacity, as `layOut` draws them. The live
        # side (from the battery's +) reads warm, the return cool.
        hot = unlit("WireHot", linear((0.97, 0.5, 0.30)))
        cold = unlit("WireCold", linear((0.35, 0.5, 0.95)))
        jacket = material("Jacket", linear((0.12, 0.12, 0.12)), roughness=0.55, alpha=0.82)
        for (a, ea), (b, eb) in c["starterWires"]:
            start, end = ends[a][ea], ends[b][eb]
            middle, along = (start + end) / 2, end - start
            hotside = (a == 0 and ea == 0) or (b == 0 and eb == 0)
            direction = Vector((along[0], -along[2], along[1])).normalized()
            rotation = direction.to_track_quat("Z", "Y").to_euler()
            primitive("cylinder", "cable", hot if hotside else cold, None, rk(*middle), rotation,
                      radius=c["wireCore"], height=along.length)
            if c["wireJacket"] > 0:   # a direction may draw the wire bare
                primitive("cylinder", "jacket", jacket, None, rk(*middle), rotation,
                          radius=c["wireJacket"], height=along.length)
        stage = bpy.data.objects.new("stage", None)
        bpy.context.collection.objects.link(stage)
        stage.location = rk(0, c["stageTop"], -0.9)
        for name in ("CircuitStageDeck", "CircuitStageRim"):
            # A direction that mills no stage of its own stands on the app's.
            for folder in (options["src"], MODELS):
                if os.path.exists(asset_path(folder, name)):
                    import_usd(asset_path(folder, name), stage)
                    break
        if light == "room":
            floor = bpy.data.meshes.new("floor")
            floor.from_pydata([(-4, -6, 0), (4, -6, 0), (4, 2, 0), (-4, 2, 0)], [], [(0, 1, 2, 3)])
            ground = bpy.data.objects.new("floor", floor)
            bpy.context.collection.objects.link(ground)
            ground.data.materials.append(material("Floor", (0.55, 0.53, 0.50), roughness=0.85))
            wall = bpy.data.meshes.new("wall")
            wall.from_pydata([(-4, 2.6, 0), (4, 2.6, 0), (4, 2.6, 3), (-4, 2.6, 3)], [], [(0, 1, 2, 3)])
            back = bpy.data.objects.new("wall", wall)
            bpy.context.collection.objects.link(back)
            back.data.materials.append(material("Wall", (0.74, 0.73, 0.71), roughness=0.9))
        fov = (58.0, 43.5)
        size = (round(fov[0] * HEADSET_PPD), round(fov[1] * HEADSET_PPD))
        data = bpy.data.cameras.new("eye")
        data.sensor_fit = "HORIZONTAL"
        data.angle = math.radians(fov[0])
        data.clip_start = 0.01
        eye = bpy.data.objects.new("eye", data)
        bpy.context.collection.objects.link(eye)
        eye.location = rk(*EYE)
        look = rk(0.10, 1.25, -0.9)
        eye.rotation_euler = (look - eye.location).to_track_quat("-Z", "Y").to_euler()
        bpy.context.scene.camera = eye
        bpy.context.scene.render.resolution_x, bpy.context.scene.render.resolution_y = size
        caption(eye, "starter loop from the eye (1.6 m, 0.9 m back)  %s" % light, light, fov, size)
        render(os.path.join(options["out"], "loop-%s.png" % light))


def overridden(c, src):
    """A direction's own numbers, from `<src>/contract.json`, over the app's."""
    import json
    path = os.path.join(src, "contract.json")
    if os.path.exists(path):
        with open(path) as handle:
            for key, value in json.load(handle).items():
                if key not in c:
                    sys.exit("propsheet: contract.json names %s, which nothing reads" % key)
                c[key] = value
    return c


def frames(options, prefixes):
    """A storyboard: posed assemblies milled elsewhere, through one camera
    fitted to the largest of them, so only the subject moves."""
    for prefix in prefixes:
        files = sorted(f[:-5] for f in os.listdir(options["src"])
                       if f.startswith(prefix) and f.endswith(".usdz"))
        if not files:
            sys.exit("propsheet: no %s*.usdz in %s" % (prefix, options["src"]))
        reset()
        spans = []
        for name in files:
            root, _ = build_asset(name, options["src"])
            bpy.context.view_layer.update()
            spans.append(rk_bounds([o for o in root.children_recursive if o.type == "MESH"]))
        lo = [min(b[0][i] for b in spans) for i in range(3)]
        hi = [max(b[1][i] for b in spans) for i in range(3)]
        target = rk(*[(a + b) / 2 for a, b in zip(lo, hi)])
        half = [(b - a) / 2 for a, b in zip(lo, hi)]
        distance = 1.25 * max(max(half[0], half[2]) / math.tan(math.radians(CLOSE_FOV[0]) / 2),
                              max(half[1], half[2]) / math.tan(math.radians(CLOSE_FOV[1]) / 2))
        rows = []
        for light in options["lights"]:
            row = []
            for name in files:
                reset()
                configure(options["samples"])
                light_room(light)
                root, _ = build_asset(name, options["src"])
                bpy.context.view_layer.update()
                path = os.path.join(options["out"], "tiles", "frame-%s-%s.png" % (name, light))
                tile(path, root, target, light, distance, CLOSE_FOV, CLOSE_SIZE,
                     name[len(prefix):].strip("_-") or name, close=True, fit=False)
                row.append(path)
            rows.append(row)
        composite(rows, os.path.join(options["out"], "frames-%s.png" % prefix))


def main():
    mode, names, options = arguments()
    c = overridden(contract(), options["src"])
    os.makedirs(os.path.join(options["out"], "tiles"), exist_ok=True)
    if mode in ("stats", "all"):
        stats(c, options)
    if mode in ("sheet", "all"):
        sheet(c, options)
    if mode in ("loop", "all"):
        loop(c, options)
    if mode == "frames":
        frames(options, names)
    if mode in ("turntable", "all"):
        if mode == "all" or not names:
            names = options["parts"] or list(c["kinds"]) + [
                c["carrier"], "CircuitStageDeck", "CircuitStageRim", "Multimeter", "MeterProbe"]
        turntable(c, options, names)


if __name__ == "__main__":
    main()
