#!/usr/bin/env python3
"""
The home's three display texts, milled rather than generated.

    /Applications/Blender.app/Contents/MacOS/Blender -b -noaudio \
        --python Tools/hubtitles.py

Writes six assets into PhysicsPlayground/Models/Hub/ — one per LINE, not
one per lockup, because the flush-both-sides lockup math in
`HubSpaceView.buildBubbleTitle` and `HubDomainTitle.init` is well argued
and tested and this script has no business reimplementing it. Each line
is built at a nominal point size of 1.0 and Swift scales it to the
common width, exactly as it scales the generated meshes today.

Each asset carries TWO meshes, split by role: `Letters` — the faces and
extrusion walls — and `Rim`, the chamfer band around every stroke.
Swift anodises the faces dark and leaves the rim bright alloy, the way
a diamond-cut badge shows bare metal exactly where the tool touched it
— see `HubTitleStyle.milled` for why legibility lives on that split.

WHY THIS EXISTS AT ALL

`MeshResource.generateText` can only make a flat prism: a face, straight
extruded sides, and a sharp ninety-degree edge between them.
`HubTitleStyle.line` claims the plaque's depth cue is that "its own
extruded sides catch the light at a different angle from its face" —
true, but a square edge catches it in a hard line, which is what a
stamped part looks like. `blenderprops.bevel` already states the house
position: a machined part has no sharp corners, and the highlight
running along a bevel is most of what makes a shape read as a solid
object rather than as a box. By that standard the plaque has been a box.

The chamfer is the whole reason to bake these. It cannot be had at
runtime at any price, and it is most of what separates "extruded text"
from "milled from stock".

THE FONT IS THE SAME FONT, AND THAT TOOK WORK

Blender cannot read SF Pro's Bold. `/System/Library/Fonts/SFNS.ttf` is a
VARIABLE font and Blender's freetype loads only its default instance,
which is Regular — load it and you silently get the wrong weight, which
is the kind of defect that survives review because it still looks like
type. So the font is snapshotted at wght=700 first, with fontTools, and
Blender is handed a static face.

Pinning `opsz` is a bonus rather than a workaround. SF Pro carries an
optical-size axis, and 96 is its DISPLAY cut — tighter spacing and
slightly refined shapes, drawn for type set large. It is the correct
face for a wordmark two metres up, and `.systemFont(ofSize:weight:)`
gives no way to ask for it. So the baked type is not a substitution for
what shipped; it is the same typeface, better set.

WHAT IS DELIBERATELY NOT BAKED IN: COLOUR

Each line exports exactly one mesh, named `Letters`, and its Blender
material is a previewing convenience only. Swift assigns the real one
by mesh name, so `Materials.machined`, the accent blend and
`DesignTokens.Palette` stay the one authority on what the home is
coloured — the same reason the domain signs take an accent parameter
instead of shipping two green usdz. Bake geometry; never bake the
design system.

THERE IS NO CASING (owner, 2026-08-11). The dark shell that hugged
every glyph came off in two steps — recoloured off black, then removed
outright. See `build_line` for what the chamfer does in its place, and
why removing it only became possible once these were modelled.

AXES. See the note at the top of `blenderprops.py`. A Blender text
object lies in the XY plane facing +Z, which after the export's
orientation convert would leave the wordmark lying FACE-UP on the
floor. Every line is therefore rotated +90 degrees about X so its face
points along Blender -Y, which is RealityKit +Z — out of the wall, at
the reader.
"""

import bpy
import bmesh
import math
import os
import subprocess
import sys
import tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from blenderprops import material, export, join

# MARK: The voice's parameters, mirrored from HubTitleStyle

# A fraction of point size, so the asset stays proportional under the
# uniform scale Swift applies. `EXTRUSION` is `HubTitleStyle
# .extrusionFactor`; keep them in step or the baked lines and the
# fallback generated ones will not match.
EXTRUSION = 0.55

# THE POINT OF THE WHOLE EXERCISE — the milled edge, as a fraction of
# point size. 0.012 is about a fiftieth of cap height: enough to carry a
# highlight all the way round a stroke, small enough that the letterform
# is still the letterform and not a soft plastic sign.
#
# Since 2026-08-11 this is also the ONLY thing holding the letter's
# silhouette against the wall behind it, the dark casing having been
# removed. Thin it and the type starts to swim on a bright wall.
#
# 0.012 UNTIL 2026-08-13, when the rim became its own bright-alloy mesh
# against a dark-anodised face: the band is doing contrast work now,
# not just catching highlights, and a fiftieth of cap height was too
# thin a line to carry it. A fortieth is still unmistakably a chamfer.
CHAMFER = 0.015

# Curve tessellation. 4 and 2 cut the mesh 3.3x against Blender's
# defaults (15.8k verts per line down to 4.9k) and move measured cap
# height by less than one part in ten thousand — at 0.6 m wide, two
# metres away, through a headset, the defaults are paying for curve
# fidelity nobody can resolve.
RESOLUTION_U = 4
BEVEL_RESOLUTION = 2

# The six lines, and the file each becomes.
LINES = [
    ("Physics", "HubTitle_Physics"),
    ("Playground", "HubTitle_Playground"),
    ("Electricity", "HubTitle_Electricity"),
    ("& Magnetism", "HubTitle_Magnetism"),
    ("Mechanics", "HubTitle_Mechanics"),
    ("& Energy", "HubTitle_Energy"),
]

SYSTEM_FONT = "/System/Library/Fonts/SFNS.ttf"
WEIGHT = 700     # Bold, matching .systemFont(ofSize:weight: .bold)
OPTICAL = 96     # SF Pro's display cut


def bold_face():
    """SF Pro snapshotted at Bold, as a static font Blender can read.

    Blender ships no fontTools, so the instancing runs out-of-process in
    the system interpreter. It writes to a temp file rather than into
    the repository on purpose: this is a derived build artefact of an
    Apple system font, and checking it in would be both redundant and a
    licensing question nobody needs to answer.
    """
    out = os.path.join(tempfile.mkdtemp(prefix="hubtitles-"),
                       "SFPro-DisplayBold.ttf")
    script = (
        "from fontTools.ttLib import TTFont\n"
        "from fontTools.varLib.instancer import instantiateVariableFont\n"
        "f = TTFont(%r)\n"
        "instantiateVariableFont(f, {'wght': %d, 'opsz': %d, 'wdth': 100,\n"
        "                           'GRAD': 400}, inplace=True)\n"
        "f.save(%r)\n" % (SYSTEM_FONT, WEIGHT, OPTICAL, out)
    )
    try:
        subprocess.run(["python3", "-c", script], check=True,
                       capture_output=True)
    except (subprocess.CalledProcessError, FileNotFoundError) as error:
        detail = getattr(error, "stderr", b"")
        raise SystemExit(
            "Could not snapshot SF Pro at Bold.\n"
            "This script needs fontTools in the SYSTEM python3 (Blender's\n"
            "own interpreter does not ship it):\n\n"
            "    python3 -m pip install fonttools\n\n"
            "Without it Blender would silently load SFNS.ttf's default\n"
            "instance, which is REGULAR, and the wordmark would ship at\n"
            "the wrong weight.\n\n%s"
            % (detail.decode() if isinstance(detail, bytes) else detail))
    return bpy.data.fonts.load(out)


def weld(obj, threshold=1e-4):
    """Close the contour seams.

    A converted text object leaves a hairline gap where each contour's
    start and end point meet — one on every outer outline, one in every
    counter. At runtime nothing shows it. Here the shell is swollen and
    the faces are chamfered, and the gap opens into a black crack across
    the top of the P and a notch inside its bowl. Merging by distance
    closes them; the vertex count drop (about a fifth) is the seam
    duplicates going away, not detail being lost.
    """
    mesh = obj.data
    bm = bmesh.new()
    bm.from_mesh(mesh)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=threshold)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(mesh)
    bm.free()
    mesh.update()
    return obj


def glyph(name, character, font, extrude, chamfer):
    """One character as a chamfered solid, standing up and facing out.

    THE CHAMFER IS A MESH BEVEL, NOT A CURVE BEVEL (2026-08-13). The
    first build swept the profile along the outline with `bevel_depth`,
    and a swept profile MITRES at every join — at the acute joins where
    M's diagonals meet its stems, the mitre overshot and every M grew a
    spike off its top. The docstring above already records this exact
    failure from the outline experiment ("M, A, V, W and Y all grew
    horns"); a curve bevel is the same construction one layer down, and
    widening the chamfer for the rim split pushed its horns past
    visibility. A mesh bevel is the opposite kind of cut: it REMOVES the
    corner instead of extending the profile round it, its outer mitre is
    an arc, and `use_clamp_overlap` bounds it in tight corners — it
    cannot spike, and stock being cut away is also what milling is.
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
    # Blender extrudes both ways from the plane, so this is the half.
    data.extrude = extrude / 2.0
    data.resolution_u = RESOLUTION_U
    bpy.ops.object.convert(target="MESH")
    obj = bpy.context.active_object
    # Weld BEFORE the bevel: the contour seams are open here, and a
    # bevel walking over a hairline gap treats it as a boundary edge
    # and tears the band.
    weld(obj)
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    modifier = obj.modifiers.new("chamfer", "BEVEL")
    modifier.width = chamfer
    modifier.segments = BEVEL_RESOLUTION
    modifier.limit_method = "ANGLE"
    modifier.angle_limit = math.radians(40)
    modifier.miter_outer = "MITER_ARC"
    modifier.use_clamp_overlap = True
    bpy.ops.object.modifier_apply(modifier="chamfer")
    for polygon in obj.data.polygons:
        polygon.use_smooth = True
    # Face along -Y, which the export turns into RealityKit +Z.
    obj.rotation_euler = (math.pi / 2, 0, 0)
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.transform_apply(rotation=True)
    return obj


def span(obj, axis):
    values = [getattr(v.co, axis) for v in obj.data.vertices]
    return min(values), max(values)


def inked_width(body, font):
    """The width of a string as the face would actually set it.

    Measured rather than accumulated from advances, and measured on the
    WHOLE PREFIX, so whatever the face does between a pair is in the
    number by construction — the same trick `HubTitleStyle.keylined`
    uses, for the same reason.
    """
    bpy.ops.object.text_add()
    obj = bpy.context.active_object
    data = obj.data
    data.body = body
    data.font = font
    data.size = 1.0
    data.align_x = "CENTER"
    data.align_y = "CENTER"
    data.resolution_u = RESOLUTION_U
    bpy.ops.object.convert(target="MESH")
    obj = bpy.context.active_object
    if not obj.data.vertices:
        bpy.data.objects.remove(obj, do_unlink=True)
        return 0.0
    low, high = span(obj, "x")
    bpy.data.objects.remove(obj, do_unlink=True)
    return high - low


def split_rim(body):
    """Separate the chamfer band into its own mesh, named `Rim`.

    Classified by GEOMETRIC face normal, which is exact here: the glyphs
    are prisms whose caps face ±Y (after the stand-up rotation) and
    whose extrusion walls have normals with y = 0 identically — only the
    bevel band lies in between. The thresholds are generous because the
    band's segments sit at wide angles from both.

    Two meshes rather than two material slots on one, because the USD
    round-trip into RealityKit is only contractual about NAMES —
    `HubTitleStyle.milled` finds parts by mesh name and paints them, and
    a GeomSubset's survival through `Entity.load` is nothing this
    pipeline wants to bet the wordmark on.
    """
    rim = body.copy()
    rim.data = body.data.copy()
    bpy.context.collection.objects.link(rim)
    for target, keep_band in ((body, False), (rim, True)):
        bm = bmesh.new()
        bm.from_mesh(target.data)
        doomed = [face for face in bm.faces
                  if (0.02 < abs(face.normal.y) < 0.995) != keep_band]
        bmesh.ops.delete(bm, geom=doomed, context="FACES")
        bm.to_mesh(target.data)
        bm.free()
        target.data.update()
    rim.name = "Rim"
    rim.data.name = "Rim"
    return rim


def build_line(body, font):
    """One line of display type: chamfered letters, and nothing else.

    THERE IS NO CASING (owner's call, 2026-08-11). The dark shell around
    every glyph came off in two steps — first recoloured off black, then
    removed outright — and the second ask was the honest one: an outline
    is a sticker's idea of contrast, and this type is supposed to be a
    milled object.

    What replaces it is the chamfer, which is why this is possible NOW
    and was not in August. The keyline existed because ivory metal drawn
    over somebody's cream wall had no edge, and flat extruded type has
    nothing to give it one: `MeshResource.generateText` makes a prism
    with a square corner, so the letter's silhouette is whatever the
    wall happens to contrast with. A chamfered edge carries its own
    bright specular rim all the way round every stroke, at every viewing
    angle. The silhouette is now IN the letterform.

    Two builds are recorded here because both are worth not repeating.
    A true constant-width outline via Blender's curve `offset` mitres
    its joins, so every acute apex fired off a spike — M, A, V, W and Y
    all grew horns, and widening the chamfer to round them made them
    longer. Scaling each glyph about its own centre cannot spike, and
    that is what shipped for a day. Neither survives the simpler
    question of whether the sign wanted an outline at all.
    """
    body = body.upper()          # HubTitleStyle.display

    # Right edge of glyph i is the right edge of the prefix ending at i.
    advance = [0.0]
    for index in range(len(body)):
        advance.append(inked_width(body[:index + 1], font))
    total = advance[-1]

    letters = []
    for index, character in enumerate(body):
        if character.isspace():
            continue
        letter = glyph("L%d" % index, character, font, EXTRUSION, CHAMFER)
        low, high = span(letter, "x")
        # Placed by its RIGHT edge, and vertically not at all: every
        # glyph is generated the same way, so they already share a
        # baseline. Re-centring each on its own ink is how O and S,
        # which overshoot the cap line, end up a millimetre off it.
        letter.location.x = advance[index + 1] - total / 2 - high
        letters.append(letter)

    # TWO meshes, named by role — Swift finds each by name and assigns
    # the real materials: the faces and walls anodised, the chamfer band
    # left bright alloy. Joining first also drops the entity count from
    # one per glyph to one per line.
    #
    # THE MESH DATA IS NAMED TOO, AND THAT IS NOT BELT-AND-BRACES. The
    # USD exporter writes the prim from the MESH name, not the object's,
    # so naming only the object ships a file whose parts come back as
    # `Text_007` — which loads fine, looks fine, and silently defeats
    # the lookup Swift does. Caught by re-importing the export; nothing
    # about the file on disk says otherwise.
    letter_mesh = join("Letters", letters)
    letter_mesh.data.name = "Letters"
    rim_mesh = split_rim(letter_mesh)
    letter_mesh.data.materials.append(
        material("LettersPreview", (0.13, 0.125, 0.12),
                 roughness=0.35, metallic=0.75))
    rim_mesh.data.materials.append(
        material("RimPreview", (0.95, 0.80, 0.55),
                 roughness=0.22, metallic=0.9))
    return [letter_mesh, rim_mesh]


def main():
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    out_dir = os.path.join(root, "PhysicsPlayground", "Models", "Hub")

    for body, filename in LINES:
        bpy.ops.wm.read_factory_settings(use_empty=True)
        font = bold_face()
        parts = build_line(body, font)
        path = os.path.join(out_dir, filename + ".usdz")
        export(parts, path)
        verts = sum(len(p.data.vertices) for p in parts)
        print("  %-24s %s  %d verts" % (filename, body.upper(), verts))


main()
