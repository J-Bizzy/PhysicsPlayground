#!/usr/bin/env python3
"""The app icon, milled from the same stock as everything else.

    python3 Tools/appicon.py

Writes the three layers of `Assets.xcassets/AppIcon.solidimagestack`.
Generated rather than drawn, for the same reason `hubtitles.py` is: the
values ARE the design, and a checked-in PNG nobody can regenerate is a
decision nobody can revisit.

WHAT WAS HERE BEFORE, AND WHY IT WENT

A Bohr atom — a white sun ringed by eight saturated marbles on crossing
orbits, over a starfield. It rendered competently and it was the wrong
icon, for three reasons that are about this app rather than about taste:

  1. It is the stock physics icon. Every app in the category has some
     version of it, so it identified the SUBJECT and not the product.
  2. It depicted one lab of six, and loosely — Gravity Lab's orrery is a
     real solar system on real orbital elements, not rainbow marbles.
  3. Its palette existed nowhere in the app. The home, the plaques, the
     podium rim and the wordmark are champagne on anodised graphite,
     with a single accent per domain. The icon shared none of it, so the
     first thing a user saw was the one surface off-canon — and the
     glow-built treatment specifically contradicts the 2026-07-26 review
     finding that indoors, contours beat surfaces and casings beat glows.

WHAT IT IS NOW

The orbit ring, as a machined instrument: an anodised body with a
champagne keyline, inside a champagne band you could have turned on a
lathe. It is Gravity Lab's documented centrepiece — tap a body and its
orbit becomes a ring you reshape by hand — and it is drawn in the app's
own material language, so the icon and the wordmark are recognisably the
same object.

THE LAYERS CARRY THE PARALLAX HONESTLY. visionOS slides the three
against each other as the wearer's gaze moves, so the split is
geometric, not decorative: the ring's FAR half sits behind the body and
its NEAR half in front. Looking around the icon walks the ring around
the body the way looking around the real one does. A front layer that
is only a soft glow — which is what shipped — parallaxes as a smudge.
"""

import math
import os

from PIL import Image, ImageDraw, ImageFilter

# Supersample, then box down. Every edge here is a curve at a shallow
# angle, which is exactly where 1x rasterising shows its staircase.
SS = 4
SIZE = 1024
W = SIZE * SS
C = W / 2

# THE HOUSE PALETTE, and not a near-miss of it. These are
# `HubTitleStyle.champagne` and `.graphite` converted from the float
# values in that file; a hand-mixed warm yellow would land a few dE away
# and read as a different brand at a glance.
CHAMPAGNE = (255, 224, 178)
GRAPHITE = (40, 38, 36)
BACKDROP = (26, 25, 29)
DEEP = (13, 13, 16)

# The ring, in icon units. `A` stays well inside the circular mask with
# room for the parallax shift — visionOS crops to a circle and then
# MOVES the layers, so the safe area is smaller than the circle.
RING_A = 0.385 * W          # semi-major
RING_B = 0.152 * W          # semi-minor: the rake the orbit is seen at
RING_TILT = math.radians(-19)
RING_BAND = 0.036 * W       # thickness of the turned band
BODY_R = 0.215 * W


def ring_point(t):
    """A point on the tilted orbit. `sin t > 0` is the near half."""
    x, y = RING_A * math.cos(t), RING_B * math.sin(t)
    cos_r, sin_r = math.cos(RING_TILT), math.sin(RING_TILT)
    return (C + x * cos_r - y * sin_r,
            C + x * sin_r + y * cos_r)


def band_polygon(t0, t1, lo, hi=None, steps=900):
    """The band as an OFFSET POLYGON, not as a stacked stroke.

    Stroking the same arc three times at three widths is the obvious way
    to get a shouldered band and it produces a saw blade: PIL's
    `joint="curve"` inserts a round join at every one of nine hundred
    segments, and where consecutive joins do not quite overlap the
    darker pass beneath shows through as a tick. The first draft of this
    icon had a visible hatch all the way round the ring.

    Offsetting the curve along its own normal and filling between the
    two sides has no joins to disagree about.

    `lo`/`hi` are SIGNED offsets across the band, so a strip along one
    edge is `band_polygon(t0, t1, +0.10, +0.30)` rather than a centred
    band nudged sideways. The nudge was the first attempt and it left a
    wedge wherever the strip ended, because translating a curve is not
    the same as offsetting it and the two ends stopped agreeing.
    """
    if hi is None:
        lo, hi = -lo, lo
    outer, inner = [], []
    for i in range(steps + 1):
        t = t0 + (t1 - t0) * i / steps
        x, y = ring_point(t)
        # Numerical tangent: the ellipse is tilted, so the analytic form
        # is a rotation away and this is exact enough at 900 samples.
        dt = 1e-4
        x1, y1 = ring_point(t + dt)
        tx, ty = x1 - x, y1 - y
        length = math.hypot(tx, ty) or 1.0
        nx, ny = -ty / length, tx / length
        outer.append((x + nx * hi, y + ny * hi))
        inner.append((x + nx * lo, y + ny * lo))
    return outer + inner[::-1]


def turned_band(layer, near):
    """The orbit as a milled band: shoulders, flat, and a lit edge.

    Three concentric strips across the band's width, which is what a
    turned edge actually looks like — the tool leaves a flat with a
    shoulder falling away either side, and the light picks out one
    shoulder. Not a stack of centred strokes.
    """
    draw = ImageDraw.Draw(layer)
    t0, t1 = (0.0, math.pi) if near else (math.pi, 2 * math.pi)
    b = RING_BAND
    shoulder = tuple(int(c * 0.40) for c in CHAMPAGNE) + (255,)
    draw.polygon(band_polygon(t0, t1, b * 0.50), fill=shoulder)
    draw.polygon(band_polygon(t0, t1, -b * 0.34, b * 0.34), fill=CHAMPAGNE + (255,))
    draw.polygon(band_polygon(t0, t1, b * 0.06, b * 0.30),
                 fill=(255, 246, 226, 255))


def bead():
    """The apsis bead — the thing a hand actually grabs in Gravity Lab."""
    layer = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    draw = ImageDraw.Draw(layer)
    x, y = ring_point(math.radians(46))
    r = 0.040 * W
    draw.ellipse([x - r, y - r, x + r, y + r],
                 fill=tuple(int(c * 0.55) for c in CHAMPAGNE) + (255,))
    # Lit from upper left, like every other machined part in the app.
    draw.ellipse([x - r * 0.72, y - r * 0.78, x + r * 0.52, y + r * 0.46],
                 fill=CHAMPAGNE + (255,))
    draw.ellipse([x - r * 0.42, y - r * 0.52, x + r * 0.02, y - r * 0.06],
                 fill=(255, 248, 230, 255))
    return layer


def back():
    """Anodised stock: a shallow gradient and the faintest turning marks.

    NOT a starfield. Stars are noise at the size an icon is actually
    seen, and they were carrying the old icon's "space" reading, which
    is a claim about one lab rather than about the app.
    """
    layer = Image.new("RGB", (W, W), DEEP)
    draw = ImageDraw.Draw(layer)
    steps = 220
    for i in range(steps, 0, -1):
        f = i / steps
        r = f * W * 0.78
        mix = (1 - f) ** 1.4
        col = tuple(int(DEEP[c] + (BACKDROP[c] - DEEP[c]) * mix) for c in range(3))
        draw.ellipse([C - r, C - r, C + r, C + r], fill=col)
    # Turning marks: concentric passes, barely there. They give the
    # stock a surface without giving it a pattern.
    marks = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    md = ImageDraw.Draw(marks)
    for i in range(34):
        r = W * (0.10 + i * 0.017)
        md.ellipse([C - r, C - r, C + r, C + r],
                   outline=(255, 240, 214, 7), width=SS)
    marks = marks.filter(ImageFilter.GaussianBlur(SS * 1.5))
    layer = Image.alpha_composite(layer.convert("RGBA"), marks).convert("RGB")
    return layer


def middle():
    """The far half of the ring, then the body that eclipses it."""
    layer = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    # THE FAR HALF IS THE SAME BAND, AT THE SAME BRIGHTNESS. It was
    # drawn dimmer at first, on the reasoning that distance should read —
    # but the near and far halves meet at the ring's extremes, which is
    # out in open space well clear of the body, so the two brightnesses
    # butted against each other and left a visible seam at each end. A
    # real ring changes appearance where the body OCCLUDES it and
    # nowhere else, and that occlusion is already carried by the layer
    # order. Depth from the occlusion, not from a tint.
    turned_band(layer, near=False)

    body = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    draw = ImageDraw.Draw(body)
    # Anodised, with a terminator rather than a flat fill.
    steps = 150
    for i in range(steps, 0, -1):
        f = i / steps
        r = BODY_R * f
        cx = C - BODY_R * 0.20 * (1 - f)
        cy = C - BODY_R * 0.24 * (1 - f)
        # Reads as a SPHERE, not a hole. The first draft ran the
        # terminator down to 0.55x graphite, which against this backdrop
        # was within a couple of levels of the plate behind it — the body
        # vanished and the ring looked like it circled nothing.
        v = 0.55 + 1.35 * (1 - f) ** 1.5
        col = tuple(min(255, int(GRAPHITE[c] * (0.9 + v))) for c in range(3))
        draw.ellipse([cx - r, cy - r, cx + r, cy + r], fill=col + (255,))
    # THE KEYLINE, which is the whole visual argument of this app: the
    # chamfer where the tool touched, bright against the anodise.
    draw.ellipse([C - BODY_R, C - BODY_R, C + BODY_R, C + BODY_R],
                 outline=CHAMPAGNE + (255,), width=int(0.0085 * W))
    layer.alpha_composite(body)
    return layer


def front():
    """The near half of the ring, and the bead on it."""
    layer = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    turned_band(layer, near=True)
    layer.alpha_composite(bead())
    return layer


def main():
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    stack = os.path.join(root, "PhysicsPlayground", "Assets.xcassets",
                         "AppIcon.solidimagestack")
    for name, image in (("Back", back()), ("Middle", middle()), ("Front", front())):
        out = image.resize((SIZE, SIZE), Image.LANCZOS)
        path = os.path.join(stack, name + ".solidimagestacklayer",
                            "Content.imageset", name + ".png")
        # The BACK LAYER MUST BE OPAQUE. Apple composites the stack over
        # its own material, and a back layer with alpha shows it.
        out.convert("RGB" if name == "Back" else "RGBA").save(path)
        print("  %-7s %s" % (name, path))


if __name__ == "__main__":
    main()
