#!/usr/bin/env python3
"""The app icon: white light through a flint prism, fanned into a spectrum.

    /Applications/Blender.app/Contents/MacOS/Blender -b -noaudio \\
        --python Tools/appicon.py

Writes the three layers of `Assets.xcassets/AppIcon.solidimagestack`.
Generated rather than drawn, for the same reason `hubtitles.py` is: the
values ARE the design, and a checked-in PNG nobody can regenerate is a
decision nobody can revisit.

WHAT WAS HERE BEFORE. The orbit ring as a machined instrument — a graphite
sphere in a champagne band, drawn flat with PIL (2026-07). It was the house
palette, but a flat drawing of one lab's ring; on 2026-10-16 the owner chose
a rendered prism instead: instantly physics, and none of the stock atom.

THE PHYSICS IS THE LAB'S. The prism is Light & Optics' own: a 60° prism of
Schott SF11 flint, the same Sellmeier coefficients as `PhysicsCore.Glass`.
White light enters its left face at least deviation for 550 nm; every
wavelength is refracted by vector Snell's law at both faces with its own
index, so the fan's opening (about 7.5° from 420 to 680 nm), its order (red
least deviated) and its exit points are the glass's, not an illustrator's.
The beam has a width, so the colours overlap into white at the prism and
separate only further out — which is what a real slit beam does.

THE LAYERS CARRY THE PARALLAX HONESTLY. visionOS slides the three against
each other as the gaze moves, so the split is by depth:
  Back    graphite, lit from the centre — the house anodised ground;
  Middle  the prism, the white beam into it and the light inside it;
  Front   the spectrum leaving it, which floats nearest the wearer.
The prism is a holdout in the Front render, so the fan never paints over
glass it would be behind.

HANDEDNESS. Blender's x is right, z up; the light runs in the xz-plane at
y = 0 (the prism's mid-depth); the camera looks along +y from slightly
right of and above the axis, so the prism reads as a solid.
"""

import math
import os
import sys

sys.dont_write_bytecode = True

import bpy  # noqa: E402
import numpy as np  # noqa: E402

SIZE = 1024
OUT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                   "PhysicsPlayground", "Assets.xcassets", "AppIcon.solidimagestack")

# Schott SF11, as `PhysicsCore.Glass.sf11`. Wavelengths in micrometres.
SELLMEIER_B = (1.73759695, 0.313747346, 1.89878101)
SELLMEIER_C = (0.013188707, 0.0623068142, 155.23629)


def index(nm):
    l2 = (nm / 1000.0) ** 2
    return math.sqrt(1 + sum(b * l2 / (l2 - c) for b, c in zip(SELLMEIER_B, SELLMEIER_C)))


# The prism, in the image plane (x right, z up): side S, apex up, centroid
# at the origin — `OpticalElement.prismCorners`.
S = 1.0
APEX = math.radians(60)
H = S * math.cos(APEX / 2)
CORNERS = [(0.0, 2 * H / 3), (-S / 2, -H / 3), (S / 2, -H / 3)]   # apex, left, right
DEPTH = 0.85            # along y
BEAM = 0.036            # the beam's width
LENGTH_IN = 1.6
LENGTH_OUT = 1.25


def sub(a, b): return (a[0] - b[0], a[1] - b[1])
def add(a, b): return (a[0] + b[0], a[1] + b[1])
def mul(a, k): return (a[0] * k, a[1] * k)
def dot(a, b): return a[0] * b[0] + a[1] * b[1]
def norm(a):
    length = math.hypot(*a)
    return (a[0] / length, a[1] / length)


def outward_normal(p, q):
    """The normal of edge p→q pointing away from the centroid."""
    edge = sub(q, p)
    normal = norm((edge[1], -edge[0]))
    mid = mul(add(p, q), 0.5)
    return normal if dot(normal, mid) > 0 else mul(normal, -1)


def refract(d, normal, n1, n2):
    """Vector Snell: `normal` faces against `d`. None under TIR."""
    cos_i = -dot(normal, d)
    eta = n1 / n2
    k = 1 - eta * eta * (1 - cos_i * cos_i)
    if k < 0:
        return None
    return norm(add(mul(d, eta), mul(normal, eta * cos_i - math.sqrt(k))))


def intersect(origin, d, p, q):
    """Where the ray origin + t·d meets the segment p–q."""
    e = sub(q, p)
    denominator = d[0] * e[1] - d[1] * e[0]
    if abs(denominator) < 1e-12:
        return None
    w = sub(p, origin)
    t = (w[0] * e[1] - w[1] * e[0]) / denominator
    u = (w[0] * d[1] - w[1] * d[0]) / denominator
    return add(origin, mul(d, t)) if t > 1e-9 and 0 <= u <= 1 else None


DELTA = 2 * math.asin(index(550) * math.sin(APEX / 2)) - APEX
INCOMING = (math.cos(DELTA / 2), math.sin(DELTA / 2))
ENTRY = mul(add(CORNERS[1], CORNERS[0]), 0.5)
LEFT_NORMAL = outward_normal(CORNERS[1], CORNERS[0])
RIGHT_NORMAL = outward_normal(CORNERS[0], CORNERS[2])


def trace(nm):
    """Entry point → exit point and outgoing direction for one wavelength."""
    n = index(nm)
    inside = refract(INCOMING, LEFT_NORMAL, 1.0, n)
    exit_point = intersect(ENTRY, inside, CORNERS[0], CORNERS[2])
    out = refract(inside, mul(RIGHT_NORMAL, -1), n, 1.0)
    return exit_point, out


# CIE 1931 colour matching, Wyman, Sloan & Shirley's multi-lobe fit (as
# RenderKit's `Spectrum`), to linear sRGB.
def gauss(x, mu, s1, s2):
    s = s1 if x < mu else s2
    return math.exp(-0.5 * ((x - mu) / s) ** 2)


def photopic(nm):
    """CIE ȳ(λ), the eye's sensitivity, peak 1 near 555 nm."""
    return (0.821 * gauss(nm, 568.8, 46.9, 40.5) + 0.286 * gauss(nm, 530.9, 16.3, 31.1)) / 0.983


def linear_rgb(nm):
    x = 1.056 * gauss(nm, 599.8, 37.9, 31.0) + 0.362 * gauss(nm, 442.0, 16.0, 26.7) \
        - 0.065 * gauss(nm, 501.1, 20.4, 26.2)
    y = 0.821 * gauss(nm, 568.8, 46.9, 40.5) + 0.286 * gauss(nm, 530.9, 16.3, 31.1)
    z = 1.217 * gauss(nm, 437.0, 11.8, 36.0) + 0.681 * gauss(nm, 459.0, 26.0, 13.8)
    r = 3.2406 * x - 1.5372 * y - 0.4986 * z
    g = -0.9689 * x + 1.8758 * y + 0.0415 * z
    b = 0.0557 * x - 0.2040 * y + 1.0570 * z
    rgb = [max(c, 0.0) for c in (r, g, b)]
    top = max(rgb) or 1.0
    return tuple(c / top for c in rgb)


# --------------------------------------------------------------------------
# The scene

def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def emission_material(name, colour, strength, alpha=None):
    """Light. With `alpha`, an emission that covers what is behind it to
    that degree (the beam on the Middle layer, which must carry its own
    opacity); without, pure emission, which the Front pass adds up on
    black so overlapping colours sum to white the way light does."""
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nodes, links = mat.node_tree.nodes, mat.node_tree.links
    nodes.clear()
    out = nodes.new("ShaderNodeOutputMaterial")
    emission = nodes.new("ShaderNodeEmission")
    emission.inputs["Color"].default_value = (*colour, 1.0)
    emission.inputs["Strength"].default_value = strength
    if alpha is None:
        links.new(emission.outputs[0], out.inputs[0])
        return mat
    clear = nodes.new("ShaderNodeBsdfTransparent")
    mix = nodes.new("ShaderNodeMixShader")
    mix.inputs[0].default_value = alpha
    links.new(clear.outputs[0], mix.inputs[1])
    links.new(emission.outputs[0], mix.inputs[2])
    links.new(mix.outputs[0], out.inputs[0])
    return mat


def glass_material():
    mat = bpy.data.materials.new("Flint")
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = (0.93, 0.96, 1.0, 1.0)
    bsdf.inputs["Roughness"].default_value = 0.03
    bsdf.inputs["IOR"].default_value = index(587.56)
    for key in ("Transmission Weight", "Transmission"):
        if key in bsdf.inputs:
            bsdf.inputs[key].default_value = 1.0
    return mat


def ribbon(name, a, b, width, mat, y=0.0):
    """A flat strip from a to b in the xz-plane, `width` across, facing the
    camera (its normal along −y)."""
    d = norm(sub(b, a))
    side = (-d[1] * width / 2, d[0] * width / 2)
    verts = [(a[0] + side[0], y, a[1] + side[1]), (b[0] + side[0], y, b[1] + side[1]),
             (b[0] - side[0], y, b[1] - side[1]), (a[0] - side[0], y, a[1] - side[1])]
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(verts, [], [(0, 1, 2, 3)])
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    obj.data.materials.append(mat)
    return obj


def build_prism():
    verts = []
    for y in (-DEPTH / 2, DEPTH / 2):
        for (x, z) in CORNERS:
            verts.append((x, y, z))
    faces = [(0, 1, 2), (3, 5, 4), (0, 3, 4, 1), (1, 4, 5, 2), (2, 5, 3, 0)]
    mesh = bpy.data.meshes.new("Prism")
    mesh.from_pydata(verts, [], faces)
    mesh.update()
    obj = bpy.data.objects.new("Prism", mesh)
    bpy.context.collection.objects.link(obj)
    bpy.context.view_layer.objects.active = obj
    bevel = obj.modifiers.new("bevel", "BEVEL")
    bevel.width = 0.018
    bevel.segments = 4
    bevel.limit_method = "ANGLE"
    obj.data.materials.append(glass_material())
    for polygon in obj.data.polygons:
        polygon.use_smooth = False
    return obj


def build_light():
    """The white beam in, the light inside, and the spectrum out."""
    # Every beam is a bright core in a soft sleeve of its own colour — the
    # app's own beam, and the glow a camera would see, without a compositor.
    start = sub(ENTRY, mul(INCOMING, LENGTH_IN))
    beam_in = [ribbon("BeamIn", start, ENTRY, BEAM, emission_material("White", (1, 1, 1), 3.0, alpha=0.95)),
               ribbon("BeamInSleeve", start, ENTRY, BEAM * 3.2,
                      emission_material("WhiteSleeve", (1, 1, 1), 1.0, alpha=0.16), y=0.002)]
    # Inside the glass the colours have barely parted: one white path.
    inside = [ribbon("Inside", ENTRY, trace(550)[0], BEAM * 0.9,
                     emission_material("InsideWhite", (1, 1, 1), 1.6, alpha=0.6))]
    fan = []
    wavelengths = list(range(410, 691, 5))
    for nm in wavelengths:
        exit_point, out = trace(nm)
        colour = linear_rgb(nm)
        # Each wavelength carries its share of the beam, as bright as the
        # eye finds it (the photopic curve, softened so the ends still show):
        # together, white.
        share = 9.0 / len(wavelengths) * 2.6 * photopic(nm) ** 0.55
        end = add(exit_point, mul(out, LENGTH_OUT))
        fan.append(ribbon(f"Out{nm}", exit_point, end, BEAM, emission_material(f"O{nm}", colour, share)))
        fan.append(ribbon(f"Glow{nm}", exit_point, end, BEAM * 2.6,
                          emission_material(f"G{nm}", colour, share * 0.12), y=0.002))
    return beam_in + inside, fan


def light_rig():
    world = bpy.data.worlds.new("World")
    bpy.context.scene.world = world
    world.use_nodes = True
    background = world.node_tree.nodes["Background"]
    background.inputs["Color"].default_value = (0.05, 0.05, 0.06, 1)
    background.inputs["Strength"].default_value = 0.6
    for name, location, energy, size in (("Key", (-2.2, -2.6, 2.6), 240, 2.4),
                                         ("Rim", (2.6, 2.4, 1.2), 90, 0.6),
                                         ("Fill", (0.5, -3.2, -1.4), 60, 3.0)):
        data = bpy.data.lights.new(name, "AREA")
        data.energy = energy
        data.size = size
        light = bpy.data.objects.new(name, data)
        light.location = location
        bpy.context.collection.objects.link(light)
        direction = -np.array(location, dtype=float)
        light.rotation_euler = direction_to_euler(direction)


def direction_to_euler(direction):
    from mathutils import Vector
    return Vector(direction).to_track_quat("-Z", "Y").to_euler()


def camera():
    data = bpy.data.cameras.new("Camera")
    data.lens = 85
    cam = bpy.data.objects.new("Camera", data)
    bpy.context.collection.objects.link(cam)
    # Slightly right of and above the light's plane, looking back at the
    # prism's centre: the faces read as glass, the light as a plane.
    yaw, pitch, distance = math.radians(14), math.radians(9), 6.7
    target = (0.12, 0.0, -0.06)
    cam.location = (target[0] + distance * math.sin(yaw) * math.cos(pitch),
                    -distance * math.cos(yaw) * math.cos(pitch),
                    target[2] + distance * math.sin(pitch))
    cam.rotation_euler = direction_to_euler(np.array(target) - np.array(cam.location))
    bpy.context.scene.camera = cam


def configure(scene):
    scene.render.engine = "CYCLES"
    scene.cycles.samples = 192
    scene.cycles.use_denoising = True
    scene.render.resolution_x = SIZE
    scene.render.resolution_y = SIZE
    scene.render.film_transparent = True
    scene.cycles.film_transparent_glass = True
    scene.view_settings.view_transform = "Standard"
    scene.view_settings.look = "None"
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"
    try:
        prefs = bpy.context.preferences.addons["cycles"].preferences
        prefs.compute_device_type = "METAL"
        prefs.get_devices()
        for device in prefs.devices:
            device.use = True
        scene.cycles.device = "GPU"
    except Exception:
        scene.cycles.device = "CPU"


def render(path):
    scene = bpy.context.scene
    scene.render.filepath = path
    bpy.ops.render.render(write_still=True)


def light_layer(source, path):
    """Light rendered on black, as a layer: alpha is the brightest channel,
    the colour its straight (un-premultiplied) value."""
    image = bpy.data.images.load(source)
    w, h = image.size
    px = np.array(image.pixels[:], dtype=np.float64).reshape(h, w, 4)
    rgb = px[..., :3]
    alpha = np.clip(rgb.max(axis=2, keepdims=True) * 1.1, 0, 1)
    straight = np.clip(rgb / np.maximum(alpha, 1e-4), 0, 1)
    out = bpy.data.images.new("FrontLight", w, h, alpha=True)
    out.pixels = np.concatenate([straight, alpha], axis=2).astype(np.float32).ravel()
    out.filepath_raw = path
    out.file_format = "PNG"
    out.save()


def back_layer(path):
    """The anodised graphite ground, lifted at the centre where the prism
    stands, dithered so the gradient never bands."""
    y, x = np.mgrid[0:SIZE, 0:SIZE].astype(np.float64)
    r = np.hypot(x - SIZE * 0.5, y - SIZE * 0.47) / (SIZE * 0.5)
    centre = np.array([46, 44, 47]) / 255.0
    edge = np.array([13, 13, 16]) / 255.0
    t = np.clip(r, 0, 1.25) / 1.25
    t = t * t * (3 - 2 * t)
    rgb = centre[None, None, :] * (1 - t[..., None]) + edge[None, None, :] * t[..., None]
    rng = np.random.default_rng(0x1C0)
    rgb += (rng.random((SIZE, SIZE, 1)) - 0.5) / 255.0
    rgba = np.concatenate([np.clip(rgb, 0, 1), np.ones((SIZE, SIZE, 1))], axis=2)
    image = bpy.data.images.new("Back", SIZE, SIZE, alpha=False)
    # Blender's pixel rows run bottom to top.
    image.pixels = rgba[::-1].astype(np.float32).ravel()
    image.filepath_raw = path
    image.file_format = "PNG"
    image.save()


def main():
    reset()
    scene = bpy.context.scene
    configure(scene)
    light_rig()
    camera()
    prism = build_prism()
    middle_light, fan = build_light()

    layer = lambda name: os.path.join(OUT, f"{name}.solidimagestacklayer", "Content.imageset",
                                      f"{name}.png")

    # Middle: the prism, the white beam and the light inside it.
    for obj in fan:
        obj.hide_render = True
    render(layer("Middle"))

    # Front: the spectrum alone, added up on black, then turned into a light
    # layer — alpha from brightness — so where every colour still overlaps,
    # at the prism, it is white, and where they part, a rainbow.
    for obj in fan:
        obj.hide_render = False
    for obj in middle_light + [prism]:
        obj.hide_render = True
    scene.render.film_transparent = False
    scene.world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.0
    scratch = os.path.join(bpy.app.tempdir or "/tmp", "icon-front-light.png")
    render(scratch)
    light_layer(scratch, layer("Front"))

    back_layer(layer("Back"))
    spread = math.degrees(math.atan2(trace(420)[1][1], trace(420)[1][0])
                          - math.atan2(trace(680)[1][1], trace(680)[1][0]))
    print(f"  n_d {index(587.56):.4f}, δmin(550) {math.degrees(DELTA):.2f}°, "
          f"fan 420–680 nm {abs(spread):.2f}°")


if __name__ == "__main__":
    main()
