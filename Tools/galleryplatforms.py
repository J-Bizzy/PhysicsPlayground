#!/usr/bin/env python3
"""
Builds the Gallery's three platforms, and writes them as USDZ.

    /Applications/Blender.app/Contents/MacOS/Blender --background \
        --python Tools/galleryplatforms.py

Output, all under PhysicsPlayground/Models/Hub/:
    GalleryBay.usdz     one module's width of terrace breadboard
    GalleryCap.usdz     the terrace's end block
    GalleryMount.usdz   the pedestal a miniature stands on
    GalleryCradle.usdz  the pad a lab is docked to
    GalleryLatch.usdz   one of the cradle's three latch fingers

WHY THESE ARE MODELLED AT ALL

The Gallery's furniture was four primitives: a box per terrace, a
cylinder per module, a cylinder for the pad. They were the right
placeholder — the terraces are architecture BENEATH the physics and must
never compete with it — but "must not compete" and "must have no
character" are different instructions, and the first was being used to
justify the second. Every miniature standing on those shelves is a real
instrument, modelled or procedural; the shelves were the one thing in the
room that looked like a shape rather than an object.

THE VOICE IS AN OPTICAL BENCH. Chosen (owner, 2026-08-09) from four
candidates — the others were museum vitrine plinths, levitation coils and
an equipment rack, and they are recorded in DECISIONS.md against the day
this shipped, because a decision with no alternatives written down reads
later as the only thing anyone thought of.

An optical bench earns its place three ways. It is what this apparatus
would actually stand on, so the room gains a reason rather than a
decoration. Its surface is a REGULAR GRID, which is the cheapest possible
way to make a large flat object read as machined rather than as a slab —
the eye gets scale, parallax and a hint of specular sparkle from
something that is geometrically almost nothing. And its parts are
modular by nature, which is what lets a terrace stay the width the
layout says it should be (see below).

WIDTH IS NOT BAKED IN, and this is the one constraint that shaped the
asset. `GalleryLayout` sizes a terrace from its module count:

    width = basePuckPitch · n + baseWidthMargin        (0.36 · n + 0.08)

A single fixed-width slab would either freeze the catalog at three labs
per domain or be non-uniformly stretched, and stretching a hole grid
turns every hole into an ellipse — the exact tell that says "this was
scaled". So the terrace ships as TILES: one BAY per module, 0.36 m wide,
plus two 0.04 m CAPS. The arithmetic falls out exactly — n bays and two
caps come to 0.36·n + 0.08 — so the assembled object is the width the
tested layout math already promised, and a seventh lab lands on a
terrace that grew by one real bay.

ORIGINS ARE AT THE MOUNTING FACE, not at centres of mass. Every piece
here is placed by the Swift side against a number the layout hands it —
`slabTop`, `puckTops[i]`, the pad's plate top — so each is modelled with
its TOP FACE at the origin and its material hanging below. A part whose
origin is its centre makes every call site do the same half-thickness
arithmetic, and this project has already paid for that mistake once, in
a plaque that sank into the shelf it was standing on.

The latch finger is the exception: its origin is its PIVOT, because the
only thing the Swift side ever does to it is rotate it.

AXES. Per `blenderprops`: Blender (x, y, z) -> RealityKit (x, z, -y).
For a terrace that means width along Blender X, thickness up Blender Z,
and depth along Blender Y with the front edge — the one facing the
wearer, where the domain hairline runs — at NEGATIVE Y.
"""

import os
import sys

# No .pyc beside the source — see the note in vignetteprops.py.
sys.dont_write_bytecode = True
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import math  # noqa: E402

import bpy  # noqa: E402
from mathutils import Vector  # noqa: E402
from blenderprops import (  # noqa: E402
    bevel, box, cylinder, export, join, material, reset_scene, shade,
)

ROOT = os.path.join(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
    "PhysicsPlayground", "Models", "Hub")

# ---------------------------------------------------------------------
# Dimensions. Every one of these is a number `GalleryLayout` already
# publishes, and the two must not drift — a bay wider than the puck pitch
# tiles into a terrace longer than the layout reserved space for, and the
# neighbouring domain's slab is 28 degrees away.
# ---------------------------------------------------------------------

BAY_WIDTH = 0.36        # GalleryLayout.basePuckPitch
CAP_WIDTH = 0.04        # GalleryLayout.baseWidthMargin / 2
DEPTH = 0.42            # GalleryLayout.slabDepth
THICKNESS = 0.055       # GalleryLayout.slabThickness
MOUNT_RADIUS = 0.085    # GalleryLayout.puckRadius
MOUNT_HEIGHT = 0.028    # GalleryLayout.puckHeight
PAD_RADIUS = 0.105      # HubScene.podiumRadius
PAD_HEIGHT = 0.028      # HubScene.podiumPlateThickness
# Where the latch posts stand. Inside the hex's apothem
# (0.105 · cos 30° = 0.0909) by more than a post's own radius — see
# `build_cradle`. Mirrored by `HubScene.latchRadius`.
POST_RADIUS = 0.082

# The bench's surface pattern: T-SLOTS, running the length of the
# terrace.
#
# THIS WAS A DRILLED HOLE GRID FIRST, 25 mm centres and 6 mm holes, the
# real imperial-metric hybrid every optical table in the world uses. It
# was cut correctly — 4,556 vertices of correctly cut — and it was
# INVISIBLE in the first screenshot, for a reason that is obvious in
# hindsight and worth writing down:
#
#   A 6 mm blind hole in a 0.09-albedo bench is a dark shape on a dark
#   surface. Real benches read because they are drilled in bright
#   anodised aluminium; this one has to stay near-black, because it is
#   drawn over somebody's living room and sits under the physics.
#
# So the geometry paid 4.5k vertices per bay to say nothing at all.
# Slots are the fix and they are better than a rescue: a long groove
# catches a SPECULAR RUN along its whole length, which reads at two
# metres where a point of shadow cannot, and running them along the
# terrace means they cross the joins between tiles — so the pattern that
# gives the bench its character is also the thing that stops it looking
# like separate panels butted together.
SLOT_WIDTH = 0.008
SLOT_DEPTH = 0.004
# Measured back from the front face. Three of them, clear of the
# hairline channel and of the mounts' 0.085 m footprint.
SLOT_INSETS = (0.105, 0.210, 0.315)

# The channel the domain hairline lies in, measured back from the front
# face. The Swift side draws the light itself — it is emissive and it
# changes colour per domain, so it cannot be baked — and this is the
# trough it sits in. Leaving 4 mm of stock in front of the channel is
# what makes it read as a machined rail rather than as a saw cut.
CHANNEL_INSET = 0.004
CHANNEL_WIDTH = 0.011
CHANNEL_DEPTH = 0.005


def coat(mat, weight, roughness):
    """Adds a clearcoat layer to a Principled BSDF.

    `blenderprops.material` does not expose one, and the gallery's
    Swift-side alloy — `RenderKit.Materials.graphite` — is defined by
    having one: base metallic 0.10 under a 0.60 clearcoat. The first
    build of these assets skipped it and used metallic 0.18 instead,
    which is not the same thing at all: measured off the screenshots, the
    terraces came back TWICE as bright as the slabs they replaced,
    because a metallic surface reflects the room and this app is drawn
    over a real one. The furniture got louder than the physics, which is
    the one thing the terraces are not allowed to do.

    Named for the input Blender used to call it; 4.x renamed the sockets
    to "Coat", and both are tried so this survives a Blender upgrade
    without silently doing nothing.
    """
    bsdf = mat.node_tree.nodes["Principled BSDF"]
    for key, value in (("Coat Weight", weight), ("Clearcoat", weight),
                       ("Coat Roughness", roughness),
                       ("Clearcoat Roughness", roughness)):
        if key in bsdf.inputs:
            bsdf.inputs[key].default_value = value
    return mat


def stocks():
    """The alloys, shared by every piece so the platforms are visibly one
    system. Values track `RenderKit.Materials.graphite` at the gallery's
    own `slabTint` — the Swift recipe these replace — rather than being
    picked afresh, because the terraces sit in shot with the pad and any
    difference between them reads as a mistake rather than as variety."""
    return {
        # The bench itself: near-black anodised, barely metallic. The
        # gallery is drawn over a real room and a mirror-bright shelf
        # would carry that room's reflections into the exhibit.
        "bench": coat(material("GalleryBench", (0.088, 0.090, 0.096),
                               roughness=0.30, metallic=0.10),
                      0.60, 0.25),
        # Fasteners and the balls of the kinematic mounts: real steel,
        # and the only bright thing on any of these parts. They are what
        # gives the eye a highlight to find the object by.
        "steel": material("GallerySteel", (0.60, 0.61, 0.64),
                          roughness=0.22, metallic=0.95),
        # The pocket a lab is docked into, and the latch pads: a shade
        # lighter than the bench so the recess reads as a recess rather
        # than as a shadow.
        "pocket": material("GalleryPocket", (0.145, 0.148, 0.156),
                           roughness=0.44, metallic=0.10),
    }


def cut(target, cutter):
    """Boolean difference, applied and cleaned up.

    ONE cutter, always. The grid below joins 200-odd cylinders into a
    single object before this is called, because 200 sequential boolean
    modifiers is both slow and a reliable way to find the solver's
    unhappy cases — and because a joined cutter either works or fails
    once, visibly, instead of leaving one hole missing somewhere.
    """
    bpy.context.view_layer.objects.active = target
    modifier = target.modifiers.new("cut", "BOOLEAN")
    modifier.operation = "DIFFERENCE"
    modifier.object = cutter
    modifier.solver = "EXACT"
    bpy.ops.object.modifier_apply(modifier="cut")
    bpy.data.objects.remove(cutter, do_unlink=True)
    return target


def sink_to_top(measured, top=0.0, also=()):
    """Drops a finished piece so the highest point of `measured` sits at
    `top`, moving everything in `measured` and `also` by that one shift.

    This is the origin convention in one function: the Swift side places
    these against `slabTop` and `puckTops`, which are TOP faces.

    `also` exists for the cradle, whose latch posts deliberately stand
    ABOVE its docking face — measuring those would sink the whole part by
    the height of its own fittings and bury the face every number is
    referred to.
    """
    highest = max(
        (obj.matrix_world @ Vector(corner)).z
        for obj in measured
        for corner in obj.bound_box)
    for obj in list(measured) + list(also):
        obj.location.z -= highest - top


def slot_cutter(width):
    """The bench's T-slots for a piece `width` metres across, as one
    joined cutter.

    Cut OVERSIZE in X — 1.2 × the tile — so a slot reaches the tile's
    own end faces and meets its neighbour's exactly. A slot that stopped
    short would put a machined dead end at every join, which is the
    panel-seam problem the slots exist to hide, wearing a nicer hat.
    """
    bars = []
    for inset in SLOT_INSETS:
        bars.append(box(
            "slot", (width * 1.2, SLOT_WIDTH, SLOT_DEPTH * 2),
            location=(0, -DEPTH / 2 + inset, 0)))
    return join("slots", bars)


def slab(name, width, slots=True):
    """One terrace tile: a chamfered block of bench, its top face slotted
    along the terrace and its front edge channelled for the hairline."""
    plate = box(name, (width, DEPTH, THICKNESS))
    # Chamfered BEFORE the cuts. A bevel with an angle limit will happily
    # bevel every slot lip as well, which multiplies the mesh to soften
    # an edge nobody can resolve at two metres.
    #
    # 1.5 mm, down from 3.5. The wider chamfer put a bright highlight
    # down BOTH sides of every tile join, so a bench assembled from four
    # pieces read as four pieces. The chamfer has to be enough to catch a
    # light and not enough to draw a line.
    bevel(plate, 0.0015, segments=2)

    # The hairline's trough, along the front edge (−Y).
    channel = box(
        name + "Channel", (width * 1.2, CHANNEL_WIDTH, CHANNEL_DEPTH * 2),
        location=(0, -DEPTH / 2 + CHANNEL_INSET + CHANNEL_WIDTH / 2,
                  THICKNESS / 2))
    cut(plate, channel)

    if slots:
        cutter = slot_cutter(width)
        cutter.location.z = THICKNESS / 2
        cut(plate, cutter)
    return plate


def bolt(name, x, y):
    """A socket-head fastener, proud of the surface by a millimetre.

    Two per cap, at the corners. They do the same job the hole grid does
    on a bay — give the eye something of known size — on a piece too
    narrow to carry the grid.
    """
    head = cylinder(name, 0.0045, 0.004,
                    location=(x, y, THICKNESS / 2 - 0.001), vertices=6)
    return head


def build_bay():
    reset_scene()
    materials = stocks()
    plate = shade(slab("GalleryBay", BAY_WIDTH), materials["bench"],
                  smooth=False)
    sink_to_top([plate])
    export([plate], os.path.join(ROOT, "GalleryBay.usdz"))


def build_cap():
    reset_scene()
    materials = stocks()
    # SLOTTED LIKE THE BAYS. A solid end block is what a real bench has,
    # and it is the wrong call here: the slots are what carry the eye
    # along the terrace and across the joins, so stopping them 4 cm short
    # of each end reinstates a seam at the two places the terrace's
    # silhouette is already busiest.
    plate = shade(slab("GalleryCap", CAP_WIDTH),
                  materials["bench"], smooth=False)
    heads = [
        shade(bolt("GalleryCapBoltA", 0, -DEPTH / 2 + 0.045),
              materials["steel"], smooth=False),
        shade(bolt("GalleryCapBoltB", 0, DEPTH / 2 - 0.045),
              materials["steel"], smooth=False),
    ]
    sink_to_top([plate] + heads)
    export([plate] + heads, os.path.join(ROOT, "GalleryCap.usdz"))


def build_mount():
    """The pedestal: a three-ball kinematic mount.

    This is the one piece here that is a real instrument rather than a
    styled shape. A kinematic mount locates a plate on three balls in a
    cone, a groove and a flat, so it returns to exactly the same place
    every time it is lifted off and set back down — which is, precisely,
    what the miniature standing on it does when a wearer carries a lab to
    the pad and it glides home again.

    Nothing in the app checks that the reference is apt. It is here
    because a portfolio project claiming its physics is real should not
    furnish itself with hardware that is not.
    """
    reset_scene()
    materials = stocks()

    # The base, sized to the puck the layout reserves.
    base = shade(cylinder("GalleryMountBase", MOUNT_RADIUS, 0.009,
                          location=(0, 0, -0.0235), vertices=48),
                 materials["bench"])
    bevel(base, 0.0015, segments=2)

    # The plate the exhibit stands over, held clear of the base.
    #
    # 0.055, DOWN FROM 0.070, and the number is the whole lesson of the
    # first render. The plate was wider than the circle of balls, so it
    # covered them: from a wearer's eye, a metre above and two metres
    # back, the mount was two stacked grey discs and the one detail that
    # makes it an instrument was underneath, lighting nothing. A part is
    # only as good as its silhouette from where the viewer stands.
    plate = shade(cylinder("GalleryMountPlate", 0.055, 0.007,
                           location=(0, 0, -0.0035), vertices=48),
                  materials["bench"])
    bevel(plate, 0.0012, segments=2)

    # The three balls, at 120 degrees, OUTSIDE the plate's rim. THIS is
    # the detail that carries the whole object: a gap with three bright
    # spheres standing in it reads as a located, kinematic thing, where a
    # solid cylinder reads as a puck.
    balls = []
    for index in range(3):
        angle = math.radians(90 + index * 120)
        bpy.ops.mesh.primitive_uv_sphere_add(
            radius=0.0090, segments=20, ring_count=12,
            location=(0.068 * math.cos(angle), 0.068 * math.sin(angle),
                      -0.0105))
        ball = bpy.context.active_object
        ball.name = "GalleryMountBall%d" % index
        balls.append(shade(ball, materials["steel"]))

    parts = [base, plate] + balls
    sink_to_top(parts)
    export([join("GalleryMount", parts)],
           os.path.join(ROOT, "GalleryMount.usdz"))


def build_cradle():
    """The pad: a hex docking receptacle with a machined pocket.

    HEXAGONAL, against a gallery of circles, and that is the point. The
    pad is the one platform in the room that is not a shelf — it is the
    door — and it has spent its life being a slightly larger version of
    the pucks it takes labs from. A hex reads as a fitting, a mount, a
    thing made to receive something, at a glance and from any angle.
    """
    reset_scene()
    materials = stocks()

    body = cylinder("GalleryCradle", PAD_RADIUS, PAD_HEIGHT,
                    location=(0, 0, -PAD_HEIGHT / 2), vertices=6)
    bevel(body, 0.0035, segments=2)

    # The pocket: a shallower hex, turned 30 degrees off the body's so
    # the flats of one sit against the points of the other. A concentric
    # aligned hex would read as one thick edge.
    #
    # 16 mm deep rather than 12, to make room for the floor plate below.
    pocket_cutter = cylinder("GalleryCradlePocketCut", 0.072, 0.016,
                             location=(0, 0, 0),
                             rotation=(0, 0, math.radians(30)), vertices=6)
    cut(body, pocket_cutter)
    body = shade(body, materials["bench"], smooth=False)

    # The pocket's floor, as its own lighter part.
    #
    # THIS Z-FOUGHT THE SURFACE IT LIES ON, and the comment here used to
    # claim it was "sunk 1 mm under the cut" while the arithmetic put its
    # top face at z −0.006 and the cut floor at z −0.006 — the same
    # plane, to the micron. The pad shimmered.
    #
    # A comment asserting a clearance is not a clearance. The cut floor
    # is now at −0.008 and this plate floats between −0.0075 and −0.0045,
    # so it is 0.5 mm clear underneath and stands 3.5 mm proud on top:
    # a plate lying IN a pocket, with no two faces sharing a plane.
    floor = shade(cylinder("GalleryCradleFloor", 0.0715, 0.003,
                           location=(0, 0, -0.006),
                           rotation=(0, 0, math.radians(30)), vertices=6),
                  materials["pocket"], smooth=False)

    # The three posts the latch fingers pivot on, standing proud of the
    # rim. They are the only part of the cradle above its top face, and
    # they are outside the radius a docked lab occupies.
    #
    # SEATED INSIDE THE FLATS, at 0.082 rather than 0.092. A hexagon's
    # narrowest radius is its apothem — 0.105 · cos 30° = 0.0909 — and
    # the posts sit at the CENTRE of three flats, which is exactly where
    # that minimum falls. At 0.092 each post's far side reached 0.0995
    # and pushed 9 mm out through the face it was supposed to be
    # standing on. At 0.082 the far side is 0.0895 and stays inside the
    # body with 1.4 mm to spare.
    #
    # `HubScene.latchRadius` must match this, or the fingers pivot in
    # mid-air beside their own posts.
    posts = []
    for index in range(3):
        angle = math.radians(90 + index * 120)
        post = cylinder("GalleryCradlePost%d" % index, 0.0075, 0.016,
                        location=(POST_RADIUS * math.cos(angle),
                                  POST_RADIUS * math.sin(angle), 0.004),
                        vertices=16)
        posts.append(shade(post, materials["steel"]))

    # The POSTS stand above the docking face, so the piece is sunk by
    # its plate alone — the face is what every number on the Swift side
    # is measured to, and the posts ride along.
    sink_to_top([body, floor], also=posts)
    parts = [body, floor] + posts
    export([join("GalleryCradle", parts)],
           os.path.join(ROOT, "GalleryCradle.usdz"))


def build_latch():
    """One latch finger, origin at its pivot.

    Three of these ring the cradle and close over a lab when it lands.
    The closing is the arrival: a tap now flies a miniature to the pad
    from across the room, and the fingers are what turn "it stopped
    there" into "it was received". They are modelled open, at rest, and
    the Swift side rotates them — so the asset has no state and cannot
    disagree with the animation.

    Extends along +Y and pivots about X, which after the axis conversion
    is a finger reaching toward the wearer and swinging down over the
    pocket.
    """
    reset_scene()
    materials = stocks()

    arm = shade(box("GalleryLatchArm", (0.011, 0.044, 0.007),
                    location=(0, 0.022, 0)), materials["bench"], smooth=False)
    bevel(arm, 0.0012, segments=2)

    # The pad at the tip, angled in: it is the only part that would ever
    # touch a lab, so it is the part that is not the bench's alloy.
    tip = shade(box("GalleryLatchTip", (0.015, 0.010, 0.013),
                    location=(0, 0.047, -0.003)), materials["pocket"],
                smooth=False)
    bevel(tip, 0.0012, segments=2)

    # The boss it turns on, concentric with the origin — so the pivot is
    # visible as a pivot rather than being an invisible transform.
    boss = shade(cylinder("GalleryLatchBoss", 0.0062, 0.013,
                          location=(0, 0, 0),
                          rotation=(0, math.radians(90), 0), vertices=16),
                 materials["steel"])

    export([join("GalleryLatch", [arm, tip, boss])],
           os.path.join(ROOT, "GalleryLatch.usdz"))


def main():
    build_bay()
    build_cap()
    build_mount()
    build_cradle()
    build_latch()


main()
