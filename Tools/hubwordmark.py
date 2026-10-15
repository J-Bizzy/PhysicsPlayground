#!/usr/bin/env python3
"""
The home's wordmark in the app's own voice: "Physics" over "Playground" in
SF Pro Rounded Semibold — the face and weight of every label in the room —
as soft white solids, one letter at a time so the home can move each.

    PYTHONPATH=<a site-packages with fontTools> \\
    /Applications/Blender.app/Contents/MacOS/Blender -b -noaudio \\
        --python Tools/hubwordmark.py

Writes `HubWordmark_Physics.usdz` and `HubWordmark_Playground.usdz` into
PhysicsPlayground/Models/Hub/. Each letter is its own mesh, `G<i>_Letter`
(`i` its index in the line). The dot of the i is cut off its stem as
`G<i>_Dot`, because the home replaces it with a particle of champagne
light — the one accent the app allows itself.

What differs from the machined plaque (`hubtitles.py`, kept and still the
fallback): title case, the rounded face at Semibold rather than SF Pro
Display Bold, a shallower body, and a ROUNDED bevel of four segments
instead of a single bright chamfer, so each letter reads as a soft solid
rather than a cut part. Colour is still not baked: Swift paints by name.

The flat-fill → weld → solidify → bevel construction, the welding and
scouring, the advance and the crease rule are `hubtitles.py`'s, reused —
see its notes for why each exists.
"""

import bpy
import bmesh
import math
import os
import subprocess
import sys
import tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import hubtitles as ht
from blenderprops import material, export

ROUNDED_FONT = "/System/Library/Fonts/SFNSRounded.ttf"
WEIGHT = 600          # Semibold — `.semibold` on every portal label

# Fractions of point size, like `hubtitles`.
DEPTH = 0.24          # a slab, not a block: the letters stand off the glass
BEVEL = 0.020         # a soft round edge all the way round every stroke
BEVEL_SEGMENTS = 4    # enough facets that the round reads as a round

LINES = [
    ("Physics", "HubWordmark_Physics"),
    ("Playground", "HubWordmark_Playground"),
]


def rounded_face():
    """SF Pro Rounded snapshotted at Semibold, as a static font Blender
    can read (see `hubtitles.bold_face` for why the snapshot is needed)."""
    out = os.path.join(tempfile.mkdtemp(prefix="hubwordmark-"),
                       "SFProRounded-Semibold.ttf")
    script = (
        "from fontTools.ttLib import TTFont\n"
        "from fontTools.varLib.instancer import instantiateVariableFont\n"
        "f = TTFont(%r)\n"
        "instantiateVariableFont(f, {'wght': %d, 'GRAD': 400}, inplace=True)\n"
        "f.save(%r)\n" % (ROUNDED_FONT, WEIGHT, out)
    )
    try:
        subprocess.run(["python3", "-c", script], check=True, capture_output=True)
    except (subprocess.CalledProcessError, FileNotFoundError) as error:
        detail = getattr(error, "stderr", b"")
        raise SystemExit("Could not snapshot SF Pro Rounded (fontTools needed in "
                         "the system python3):\n%s"
                         % (detail.decode() if isinstance(detail, bytes) else detail))
    return bpy.data.fonts.load(out)


def soft_glyph(name, character, font, preview):
    """One character as a soft solid standing up and facing out: the flat
    fill, cleaned, given depth by Solidify, then rounded all round by a
    four-segment bevel. `hubtitles.glyph`'s construction with a round edge
    in place of a chamfer, and one step it did not need.

    THE FACE IS ONE POLYGON BEFORE IT IS BEVELLED (2026-10-14). Blender
    fills a glyph as a fan of slivers, and a bevel insets each edge by
    sliding along the unbevelled edges beside it. Along a sliver's edge,
    which meets the outline at a grazing angle, that slide is many times
    the bevel's width: the first build grew a star of spikes at every
    stroke end, poking up to 0.069 em outside the letter. Clamping the
    overlap cures it by starving the round to 0.001. Dissolving the fill
    to one polygon per piece (a counter keeps a bridge edge or two) leaves
    nothing to slide along. Measured over the fourteen letters the home
    says: no spike, the face inset by exactly the bevel, 0 non-manifold.

    The round is 0.020, not the 0.028 first tried. Past about 0.022 the
    inset folds over itself in the tight crotch where an arch leaves its
    stem (h, n, u, a, d), which renders as a nick. A curve bevel (the
    font's own `bevel_depth`) folds there at any width, and visibly.
    """
    bpy.ops.object.text_add()
    obj = bpy.context.active_object
    obj.name = name
    data = obj.data
    data.body = character
    data.font = font
    data.size = 1.0
    data.align_x = "CENTER"
    data.align_y = "CENTER"
    data.extrude = 0.0
    data.resolution_u = ht.RESOLUTION_U
    bpy.ops.object.convert(target="MESH")
    obj = bpy.context.active_object
    ht.weld(obj)
    # One polygon per piece, so the bevel has no slivers to slide along.
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    inner = [edge for edge in bm.edges if not edge.is_boundary]
    bmesh.ops.dissolve_edges(bm, edges=inner, use_verts=False, use_face_split=False)
    bm.to_mesh(obj.data)
    bm.free()
    obj.data.update()
    obj.data.materials.append(preview)
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj

    depth = obj.modifiers.new("depth", "SOLIDIFY")
    depth.thickness = DEPTH
    depth.offset = 0.0
    depth.use_quality_normals = True
    bpy.ops.object.modifier_apply(modifier="depth")

    soft = obj.modifiers.new("soft", "BEVEL")
    soft.width = BEVEL
    soft.segments = BEVEL_SEGMENTS
    soft.limit_method = "ANGLE"
    soft.angle_limit = math.radians(40)
    soft.miter_outer = "MITER_ARC"
    soft.use_clamp_overlap = False    # see `hubtitles.glyph`: a global clamp starves every letter
    bpy.ops.object.modifier_apply(modifier="soft")
    # The faces are polygons now; triangulate here rather than leave it to
    # the importer, so what was measured is what ships.
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bmesh.ops.triangulate(bm, faces=bm.faces[:], quad_method="BEAUTY",
                          ngon_method="BEAUTY")
    bm.to_mesh(obj.data)
    bm.free()
    obj.data.update()
    ht.scour(obj)

    obj.rotation_euler = (math.pi / 2, 0, 0)
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.transform_apply(rotation=True)
    return obj


def split_dot(obj, stem_name, dot_name):
    """Cut the i's tittle off its stem: the loose part that sits wholly
    above the rest. Returns (stem, dot); the dot is None if there is none.
    Which piece keeps the original object is Blender's choice, so both
    are named here explicitly."""
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.mesh.separate(type="LOOSE")
    bpy.ops.object.mode_set(mode="OBJECT")
    pieces = [o for o in bpy.context.selected_objects]
    if len(pieces) < 2:
        return obj, None
    # Blender Z is up after the stand-up rotation.
    top = max(pieces, key=lambda o: min(v.co.z for v in o.data.vertices))
    rest = [o for o in pieces if o is not top]
    stem = ht.join(stem_name, rest) if len(rest) > 1 else rest[0]
    stem.name = stem_name
    stem.data.name = stem_name
    top.name = dot_name
    top.data.name = dot_name
    return stem, top


def build_letters(body, font):
    preview = material("WordmarkPreview", (0.95, 0.95, 0.94), roughness=0.4, metallic=0.0)
    advance = [0.0]
    for index in range(len(body)):
        advance.append(ht.inked_width(body[:index + 1], font))
    total = advance[-1]

    parts = []
    for index, character in enumerate(body):
        if character.isspace():
            continue
        name = "G%d_Letter" % index
        letter = soft_glyph(name, character, font, preview)
        low, high = ht.span(letter, "x")
        centre = (low + high) / 2
        for vertex in letter.data.vertices:
            vertex.co.x -= centre
        letter.data.update()
        # Placed as `hubtitles.build_line` places it, the letter's middle
        # kept as its origin so the home can move it about that point.
        letter.location.x = advance[index + 1] - total / 2 - high + centre

        dot = None
        if character == "i":
            letter, dot = split_dot(letter, name, "G%d_Dot" % index)
        letter.name = name
        letter.data.name = name
        ht.crisp(letter)
        parts.append(letter)
        if dot is not None:
            ht.crisp(dot)
            parts.append(dot)
    return parts


def main():
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    out_dir = os.path.join(root, "PhysicsPlayground", "Models", "Hub")
    for body, filename in LINES:
        bpy.ops.wm.read_factory_settings(use_empty=True)
        font = rounded_face()
        parts = build_letters(body, font)
        path = os.path.join(out_dir, filename + ".usdz")
        export(parts, path)
        verts = sum(len(p.data.vertices) for p in parts)
        print("  %-24s %-11s %d parts  %d verts"
              % (filename, body, len(parts), verts))


if __name__ == "__main__":
    main()
