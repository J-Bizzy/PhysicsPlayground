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
#
# STILL 0.015, AND IT WAS NEVER THE PROBLEM (2026-08-24). This was
# briefly taken to 0.022 while chasing the dotted keyline on A and Y, on
# the theory that the band was simply sub-pixel. It was sub-pixel — on
# the diagonals only — and widening it barely helped, which is the tell:
# `use_clamp_overlap` was scaling the whole glyph's bevel down to what
# its tightest acute join allowed, so a bigger request came back cut by
# the same factor. See the clamp note in `glyph`. With that fixed, every
# letter receives the full band and this number means what it says
# again, so it goes back to the value that was judged right on the
# letters that were actually getting it.
CHAMFER = 0.015

# Curve tessellation. 4 and 2 cut the mesh 3.3x against Blender's
# defaults (15.8k verts per line down to 4.9k) and move measured cap
# height by less than one part in ten thousand — at 0.6 m wide, two
# metres away, through a headset, the defaults are paying for curve
# fidelity nobody can resolve.
RESOLUTION_U = 4

# ONE FACET, NOT TWO (2026-08-24). A rounded bevel of N segments divides
# the band into N facets with DIFFERENT normals, and a highlight lands on
# whichever one happens to bisect eye and light — so two segments across
# an already sub-pixel band meant half a pixel lit and half a pixel dark,
# and which half depended on where the letter sat in the line. That is
# the non-uniformity the owner kept seeing.
#
# A single segment is a flat 45-degree chamfer with ONE normal: the whole
# band answers the light together, and the whole band is champagne. It is
# also what a chamfer tool actually leaves — the rounded profile was the
# less literal of the two readings of "milled" all along.
BEVEL_RESOLUTION = 1

# The two material slots every glyph carries, in this order. The bevel
# modifier writes CHAMFER_SLOT onto every face it creates, which is how
# `split_rim` knows the band EXACTLY rather than inferring it — see there.
SOLID_SLOT = 0
CHAMFER_SLOT = 1

# Auto-smooth threshold: edges bending harder than this shade as a hard
# crease, everything gentler stays smooth. MEASURED, not conventional —
# see `crisp` for the census that picked it.
SHARP_ANGLE = 40

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
    """Close the contour seams and drop any degenerate scraps.

    A converted text object leaves a hairline gap where each contour's
    start and end point meet — one on every outer outline, one in every
    counter. Merging by distance closes them; the vertex count drop is
    the seam duplicates going away, not detail being lost.

    The threshold is NOT delicate, and it is worth recording that it was
    once suspected of being the whole problem: swept from 1e-7 to 1e-4
    it changes the outcome by nothing at all, because the duplicates it
    exists to merge are EXACTLY coincident. See `glyph` for what the
    real defect turned out to be.
    """
    mesh = obj.data
    bm = bmesh.new()
    bm.from_mesh(mesh)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=threshold)
    bmesh.ops.dissolve_degenerate(bm, dist=1e-5, edges=bm.edges)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(mesh)
    bm.free()
    mesh.update()
    return obj


def scour(obj):
    """Drop the zero-area slivers a bevel leaves in tight corners.

    Harmless in outline — they have no area — but they carry garbage
    normals, and a smoothing pass averages garbage into its neighbours.
    Clearing them is what takes the glyphs from "closed" to clean.
    """
    mesh = obj.data
    bm = bmesh.new()
    bm.from_mesh(mesh)
    bmesh.ops.dissolve_degenerate(bm, dist=1e-7, edges=bm.edges)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(mesh)
    bm.free()
    mesh.update()
    return obj


def glyph(name, character, font, extrude, chamfer, slots):
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

    THE DEPTH COMES FROM SOLIDIFY, NOT FROM `Text.extrude` (2026-08-22),
    AND THAT IS THE FIX FOR THE RAGGED LETTERS.

    A bevel assumes a closed manifold solid. Blender's own text extrude
    does not reliably produce one: where a glyph's outline SELF-
    INTERSECTS — the bowl of a P crossing its stem, the diagonals of an
    M and an N meeting their verticals, the apex of an A — the fill
    tessellates into a surface with holes and edges shared by three
    faces. Measured over the eighteen letters the home says, after the
    weld:

        H O S G R E D C I T U L Y  —  closed, 0 boundary, 0 non-manifold
        P (28/4)  A (34/8)  N (16/4)  M (16/4)  B (42/6)  & (52/28)

    The bevel then walks onto those holes and tears. That is what the
    owner saw: a chewed, notched left stem on the P. It was NOT the weld
    threshold — sweeping that from 1e-7 to 1e-4 changes nothing, because
    the seam duplicates are exactly coincident (see `weld`). And it was
    hidden rather than absent before: blanket smooth shading rendered
    the tear as a soft chrome smudge, so crisping the chamfer is what
    turned a smear into visible notches. Both were the same broken mesh.

    Building the FLAT fill first, cleaning it, then giving it thickness
    with Solidify sidesteps the whole class: solidify walls an open
    surface and cannot help but close it. Measured the same way, every
    letter comes out 0 boundary, 0 non-manifold, and with `scour` after
    the bevel, 0 degenerate faces.
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
    # FLAT. The depth is Solidify's job below — see the docstring.
    data.extrude = 0.0
    data.resolution_u = RESOLUTION_U
    bpy.ops.object.convert(target="MESH")
    obj = bpy.context.active_object
    # Clean the fill BEFORE it is given thickness: solidify faithfully
    # walls whatever it is handed, degenerate scraps included.
    weld(obj)
    # Both slots, in SOLID_SLOT/CHAMFER_SLOT order, and the same two
    # datablocks on every glyph — `join` remaps indices by datablock, so
    # sharing them is what keeps the tag meaning the same thing after a
    # line is joined into one mesh.
    for slot in slots:
        obj.data.materials.append(slot)
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    # Total thickness, centred on the fill plane — the same solid
    # `Text.extrude = extrude / 2` used to describe, built soundly.
    depth = obj.modifiers.new("depth", "SOLIDIFY")
    depth.thickness = extrude
    depth.offset = 0.0
    depth.use_quality_normals = True
    bpy.ops.object.modifier_apply(modifier="depth")
    modifier = obj.modifiers.new("chamfer", "BEVEL")
    modifier.width = chamfer
    modifier.segments = BEVEL_RESOLUTION
    modifier.limit_method = "ANGLE"
    modifier.angle_limit = math.radians(40)
    modifier.miter_outer = "MITER_ARC"
    # NO GLOBAL CLAMP (2026-08-24) — AND THIS IS THE WHOLE "UNEVEN
    # HIGHLIGHT" BUG, not a tuning preference.
    #
    # `use_clamp_overlap` does not limit the bevel WHERE it would overlap.
    # It limits the bevel EVERYWHERE to whatever the tightest feature on
    # the mesh allows, so one acute join starves the entire glyph. Every
    # letter with a diagonal is built round an acute join, and the cost
    # was measured on the shipping geometry — median band width against a
    # nominal 0.03111:
    #
    #     O  0.02898     H  0.03111        (no acute join: full width)
    #     A  0.00168     Y  0.00197
    #     M  0.00168     W  0.00168
    #     N  0.00163     V  0.00168
    #     K  0.00197     Z  0.00337     X  0.00202
    #
    # An EIGHTEENTH of the intended chamfer on A, Y, M, W, N, V, K, X, Z
    # and the full band on O, H, D, U. That is why the keyline looked
    # crisp on the round letters and dotted on the diagonals, why it
    # dashed rather than dimmed, and why no amount of widening `CHAMFER`
    # or brightening the rim material fixed it — the clamp scales the
    # request down by the same factor whatever the request is.
    #
    # SAFE TO DROP BECAUSE THE MESH IS SOUND NOW. The clamp was guarding
    # the spiking that the CURVE bevel produced, and both of that bug's
    # causes are already gone: the cut is a mesh bevel (it removes the
    # corner rather than sweeping a profile round it) and the solid comes
    # from Solidify over a cleaned flat fill, so there are no holes for
    # the bevel to walk onto. Verified rather than assumed — built both
    # ways, every one of A Y M W N O H K V X Z comes out with 0
    # non-manifold and 0 boundary edges either way, and `miter_outer`
    # still arcs the outer joins. X still self-limits locally to 0.02410,
    # which is the bevel declining to overlap itself where it genuinely
    # would; that is the behaviour wanted, and it is per-feature.
    modifier.use_clamp_overlap = False
    # THE TAG. Every face the bevel creates gets the chamfer slot, so the
    # band is known by construction rather than measured back off its
    # normals afterwards. See `split_rim`.
    modifier.material = CHAMFER_SLOT
    bpy.ops.object.modifier_apply(modifier="chamfer")
    scour(obj)
    # Shading is NOT set here any more — `crisp` owns it, and it has to
    # run after `split_rim`, because which edges are interior (and so
    # shaded at all) is exactly what the split changes.
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


def split_rim(body, letters_material, rim_material):
    """Separate the chamfer band into its own mesh, named `Rim`.

    Classified by the BEVEL MODIFIER'S OWN TAG — `glyph` sets
    `modifier.material = CHAMFER_SLOT`, so every face the cut created
    says so itself. Exact by construction, and it has to be, because the
    obvious alternative is wrong in a way that looks deliberate.

    UNTIL 2026-08-21 THIS INFERRED THE BAND FROM FACE NORMALS
    (`0.02 < |n.y| < 0.995`), on the reasoning that caps face ±Y, walls
    have y = 0 identically, and only the chamfer lies in between. The
    first two clauses are true; the conclusion is not. A glyph's CORNERS
    are bevelled too — the vertical edge where two strokes meet gets a
    strip running the full depth of the extrusion, and being parallel to
    the extrusion its normal has y = 0, exactly like the wall it sits
    between. So every corner's chamfer was filed under `Letters` and
    anodised dark.

    That put 44.8% of the chamfer area on the wrong mesh, and — this is
    why it read as sloppiness rather than as a style — it did so in
    proportion to how ANGULAR each letter is. Measured across the
    eighteen letters the home actually says:

        O   0% of its band lost      (all curve, no corners)
        S  27%   C 28%   U 29%   D 26%   G 34%
        R  48%   P 46%   &  45%
        H  53%   Y 53%   T 54%   E 55%   N 58%   M 59%   A 65%

    So O came out with a clean unbroken keyline, A and M with barely a
    third of one, and every letter in between somewhere else along the
    scale. The outline was not inconsistent because the cut was uneven;
    the cut was fine. It was inconsistent because the paint was.

    Two meshes rather than two material slots on one, because the USD
    round-trip into RealityKit is only contractual about NAMES —
    `HubTitleStyle.milled` finds parts by mesh name and paints them, and
    a GeomSubset's survival through `Entity.load` is nothing this
    pipeline wants to bet the wordmark on. (Note the irony: the slots
    exist now anyway, as the tag. They are a build-time channel, and
    they are gone by export.)
    """
    rim = body.copy()
    rim.data = body.data.copy()
    bpy.context.collection.objects.link(rim)
    for target, keep_band in ((body, False), (rim, True)):
        bm = bmesh.new()
        bm.from_mesh(target.data)
        doomed = [face for face in bm.faces
                  if (face.material_index == CHAMFER_SLOT) != keep_band]
        bmesh.ops.delete(bm, geom=doomed, context="FACES")
        bm.to_mesh(target.data)
        bm.free()
        target.data.update()
    # Collapse each half back to ONE slot. The tag was scaffolding for
    # the split; leaving both behind would export a second, unused
    # material binding per part and invite exactly the GeomSubset
    # question the two-mesh design exists to avoid.
    for target, chosen in ((body, letters_material), (rim, rim_material)):
        target.data.materials.clear()
        target.data.materials.append(chosen)
        for polygon in target.data.polygons:
            polygon.material_index = 0
    rim.name = "Rim"
    rim.data.name = "Rim"
    return rim


def crisp(obj, threshold=SHARP_ANGLE):
    """Auto-smooth: smooth along the stroke, hard across the cut.

    Blanket `use_smooth` shipped until 2026-08-21 and averaged every
    normal into its neighbours, which is what made a milled edge read as
    a soft plastic roll. The fix is a crease angle — but the threshold
    is worth measuring rather than reaching for the conventional 30, and
    the census of the six shipped lines says why:

        Letters   99.1% of edges under 20 deg, then NOTHING between 30
                  and 85, then 42 edges at 85-95. Those are cap meeting
                  wall square, where the bevel clamped out in a tight
                  corner and left no band at all. Smoothing them was
                  rounding a right angle.

        Rim       the step ACROSS the band is 45 deg, not 30. A round
                  bevel of N segments spanning a right angle puts its
                  facet normals at 90/2N and 90 - 90/2N — 22.5 and 67.5
                  for N=2 — so consecutive facets differ by 90/N. A 30
                  deg threshold would have creased nothing across the
                  band and left the roll exactly as soft as before.

    40 sits in the middle of Letters' empty gap and splits Rim between
    variation ALONG a stroke (tessellation of the contour, 5-25 deg,
    stays smooth so curves do not facet) and the step ACROSS the chamfer,
    which creases.

    SINCE `BEVEL_RESOLUTION` WENT TO 1 (2026-08-24) the Rim census above
    describes a mesh that no longer exists, and the threshold survives it
    unchanged — which is worth stating rather than leaving the reader to
    check. A single-segment bevel has one facet at 45 deg, so both of its
    steps — face-to-chamfer and chamfer-to-wall — are 45 deg, still
    comfortably over 40 and still creasing. Variation along a stroke is
    unchanged, because that is the contour tessellation and has nothing
    to do with the bevel's segment count. What comes out is a single
    clean cut that answers the light as ONE band, which is the point: two
    facets meant two normals, and a highlight that picked one of them.
    """
    limit = math.radians(threshold)
    mesh = obj.data
    bm = bmesh.new()
    bm.from_mesh(mesh)
    bm.normal_update()
    for face in bm.faces:
        face.smooth = True
    for edge in bm.edges:
        # A boundary edge has nothing to average with; leaving it smooth
        # keeps the split meshes' seams shading off their own faces,
        # which is the crispness the two-mesh split already bought.
        edge.smooth = (len(edge.link_faces) != 2
                       or edge.calc_face_angle(0.0) < limit)
    bm.to_mesh(mesh)
    bm.free()
    mesh.update()
    return obj


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

    # Made ONCE and shared by every glyph, so the slot indices survive
    # `join` — see `glyph`. These are previewing conveniences; Swift
    # assigns the real materials by mesh name.
    slots = [material("LettersPreview", (0.13, 0.125, 0.12),
                      roughness=0.35, metallic=0.75),
             material("RimPreview", (0.95, 0.80, 0.55),
                      roughness=0.22, metallic=0.9)]

    # Right edge of glyph i is the right edge of the prefix ending at i.
    advance = [0.0]
    for index in range(len(body)):
        advance.append(inked_width(body[:index + 1], font))
    total = advance[-1]

    letters = []
    for index, character in enumerate(body):
        if character.isspace():
            continue
        letter = glyph("L%d" % index, character, font, EXTRUSION, CHAMFER,
                       slots)
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
    rim_mesh = split_rim(letter_mesh, slots[SOLID_SLOT], slots[CHAMFER_SLOT])
    # After the split, so each part creases against its own geometry.
    crisp(letter_mesh)
    crisp(rim_mesh)
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
