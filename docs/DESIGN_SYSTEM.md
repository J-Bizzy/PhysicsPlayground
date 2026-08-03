# Design System

The visual, material and control language of the app, **as built** —
reconciled against `Hub/HubSpaceView.swift`, `Hub/HubDomains.swift`,
`Hub/HubTitleStyle.swift`, `Shell/Palette.swift`, `DesignSystem/*` and
`Packages/RenderKit/Sources/RenderKit/*` on 2026-08-01.

Two earlier drafts drifted, both the same way: they described a home screen
the code had already replaced. **Docs describing visuals must be sourced from
code, not from a retired spec** (DECISIONS.md, 2026-07-29). If this file and
the code disagree, the code is right and this file is a bug.

Physics colours are owned separately by `RenderKit.VectorPalette` (see
`docs/ARCHITECTURE.md` → Conventions); tokens live in
`DesignSystem/DesignTokens.swift`.

---

## The control vocabulary

This is the part the previous drafts omitted entirely, and it is now the
largest thing the design system has to say. **The interaction law**
(DECISIONS.md, 2026-07-29) governs it:

> A quantity with physical extent is changed by changing that extent; a
> quantity without extent is a discrete choice and gets a labelled object in
> the room; anything that is neither does not get to exist.

with the standard any instrument must clear: **visible without being looked
for, operable without being discovered, and reachable in the simulator.**
Nothing is revealed by gaze alone, and nothing may be the only path to a
capability.

As of 2026-08-01 there are **no module panels at all.** The exit criterion
was "no `Slider`, `Picker` or `Toggle` in a panel"; it was met by all six and
then superseded when the panels themselves were deleted, so
`PanelControlCriterionTests` was rewritten from "no knobs in a panel" to "no
panel", with a positive anchor so it cannot pass vacuously. Every readout
stands in the room.

| Shape | Type | Use it for |
|---|---|---|
| **Switch bank** | `DesignSystem/SpatialLayerBank` | Display layers, and any labelled on/off. Lit plate = on. **Never folds** — which layer is showing is information you need *while* looking at the physics, so it is control and readout at once. |
| **Rail** | `RenderKit/SpatialTrackControl` | A continuous quantity with **no extent of its own** (G, g, a clock, a wind speed). **Absolute**: the bead's place *is* the value. |
| **Standing bank of discs** | `DesignSystem/SpatialPicker(staysOpen: true)` | An N-way choice that is also a readout (worlds, clock speeds). Row layout: `FanLayout(span: ~50°, verticalScale: 0.25)` — the default 150° arc is for a menu that folds away, and reads as scattered debris as a permanent bank. |
| **Fan** | `DesignSystem/SpatialPicker` | A momentary N-way picker, opened from a petal. Never a blind cycle button. |
| **Well** | `DesignSystem/Well` | Creation as a physical act — reach in and pull the object out, born at your fingertips. |
| **Ring + grip** | `DesignSystem/Bloom`, `RingState` | Per-object controls, unfolded by **tap** (never gaze). Discrete actions are petals; the object's own extent is the grip. |
| **The object itself** | — | When the quantity *is* a size, a length, a facing, or a place: a charge's magnitude, a cable's length, the Gauss disc's radius and tilt, a latitude on a globe. |

**Rules learned the hard way, each of which cost a bug:**

- **A collider must never be larger than the thing it represents.** RealityKit
  hit-tests colliders, not visible geometry, so an oversized invisible collider
  shields everything behind it from every pinch. An app-wide input outage was
  traced to one region-sized sphere (DECISIONS.md, 2026-07-29).
- **Nothing ticks itself.** `SpatialTrackControl.refresh()` must be called by
  the mounting view every frame, or the bead shows the last value it was
  dragged to while a reset moves the model out from under it.
- **Instruments do not scale with the apparatus.** Parent them to the
  renderer's `root`, never a scaled `viewRoot`: a control that grows with a
  9× zoom puts itself out of reach exactly when you zoomed in to use it.
- **An unused primitive is not a working primitive.** `SpatialTrackControl`'s
  first real flight found three defects in 203 lines nobody had ever run.
- **When a toggle becomes a plate, check `reset()` restores the flag behind
  it.** Four modules had that defect; a flag with no visible control drifts
  out of reset and stays wrong because nothing in the room contradicts it.
  Giving it a lamp does not create the bug, it reveals one.

### Placement

**Match the apparatus's DEPTH, not just pick a height.** The comfortable band
is ~14° below eye. A console *below* the apparatus reads ~38° down and is
simply never seen — and being **close magnifies the drop**. This mistake has
been made at least three separate times with the arithmetic looking fine each
time, so **verify placement by screenshot, never by arithmetic**.

The simulator's frustum also cuts ~25° below horizontal, and crops far tighter
than the headset's field of view — so "falls off the bottom edge" in a sim
screenshot is not what a wearer sees. Tune placement *relative to the other
furniture*, not to the frame edge.

---

## Material

`RenderKit/Materials.swift` is the canon. A canon with one recipe is a
default, not a canon — so there are several, and the choice carries meaning.

| Recipe | Reads as | Use |
|---|---|---|
| `energized(_:glow:)` | Lit energy | Charges, bobs, abstract physics objects |
| `machined(_:)` | A built thing | Instruments, casings, apparatus (metallic stops at 0.62 — that is the point, not a parameter) |
| `graphite`, `glossy` | Built, matte / built, polished | Structure and finished surfaces |
| `frostedGlass(opacity:)` | visionOS glass | Plates, rails, panes |
| `contrastLine(_:)` | A line that survives passthrough | Field lines and any drawn line — returns a **two-pass** (casing, core) pair |

**Contours beat surfaces indoors, and casings beat glows.** A glowing band has
nothing to be bright *against* unless something dark sits behind it, and
passthrough is a *bright* medium. This is why `frostedGlass` is a dark,
light-scattering scrim *with* a bright specular skin — both halves are
load-bearing, and a recipe with only the second is the thing the app already
banned. It is also why `contrastLine` is two passes: a near-black casing swept
fatter than the bright core.

`contrastLine` spent a long time claiming to be "used everywhere" while
shipping in one module. It is in six call sites now (`FieldRenderer`,
`MagnetismRenderer`, `OrbitRing`, `HubVignettes`, `LatitudeGlobe`,
`SpatialActionBank`) and still absent from Circuits' and Projectiles'
renderers entirely. **If you are adding lines to a module,
this is the pass that is probably missing.**

Lighting is `RenderKit/Lighting.keyLight()` — one warm key from upper front-left,
supplementing (never replacing) the room's own image-based light.

---

## Colour

Colour is **semantic, never decorative**.

**Domain accents** (`HubDomains.color`) — wayfinding, two hues for two doors:

| Domain | Modules | Accent | Hex |
|---|---|---|---|
| Electricity & Magnetism | electrostatics, circuits, magnetism | Green | `#30D158` |
| Mechanics & Energy | kinematics, pendulums, gravitylab | Orange | `#FF9F0A` |

Domain accent appears on the terrace hairline, the door signage
(`HubDomainTitle`), the progress ring, and the focus panel's chip — nowhere
else.

**Per-module accents** (`DesignTokens.Palette.*Accent`) are a separate system
for module chrome. Owned by `DesignTokens`, never ad hoc.

**Reserved:** gold is completion. Physics colours (red = positive, blue =
negative; velocity blue / acceleration orange / force red in `VectorPalette`)
are project-locked and never repurposed for chrome.

**Borrowing another module's accent is a warning.** Circuit Workshop's coil
switch wears Magnetism's magenta, because what it summons belongs to that
bench — the colour is the only notice you get that flicking it stands an
apparatus up beside you.

---

## Type

- **Wordmark.** "Physics / Playground", **persistent** — it is the app's
  nameplate, not an intro. (`hasSeenWordmark` and the one-shot behaviour were
  deleted on 2026-07-29.)
- **Voice.** `HubTitleStyle.shipping` = **`.plaque`**, a machined solid,
  pinned in code (2026-07-31). The other three voices stay in the enum as what
  the choice was made *against*; there is no setting, and the specimen wall
  that auditioned them is gone. A plaque is **one solid, not a stack** — held
  by `testThePlaqueIsASingleSolid`.
- **Name plates.** Billboarded, one per exhibit; only the faced exhibit shows
  its full name. `HubScene.namePlate` returns a pill **centred on its own
  origin** — place it by its edge (`namePlateWidth`) or it straddles whatever
  it names.
- **Module promise.** One line per module (`HubDomains.promise`): what you
  *do*, never a syllabus entry.
- **Minimum size.** Nothing below visionOS `body`; semantic fonts via
  `DesignTokens.TypeScale` so Dynamic Type works.
- **Numbers.** One canon: `DesignSystem/PhysicsFormat`. Fixed-point at a
  named house precision, SI prefixes chosen by magnitude (`47.0 µT`, not
  `0.0000470 T`), angles, scientific notation, and one spelling of a
  switched state. **Every function quantises before formatting**, which
  is not tidiness — an in-room readout is rasterised, so a value that is
  not quantised to its displayed precision rebuilds its texture every
  frame. `PhysicsFormatTests` pins that property directly.
- **Readout cards** take `.readoutCard()`. It carries the padding, the
  radius and `.allowsHitTesting(false)`, and takes a material only where
  the room behind demands one — Electric Fields passes `.thickMaterial`
  because a regular panel washed out behind bright field lines until the
  50 kT disclosure was the least legible text on screen.

---

## Motion

All hub motion ticks from `SceneEvents.Update` — never `RealityView`'s
`update:` (see `docs/ARCHITECTURE.md`). Values live in `HubSpaceView.swift`.

| State | Behaviour | Value |
|---|---|---|
| Idle exhibit | Vertical bob; the miniature sways rather than spinning | ~1.2 cm sine; ±0.44 rad |
| Idle vignette | The module's own physics runs — the exhibit **is** the demo | — |
| Focus in | Nearest exhibit in the head-direction cone lifts off its puck, grows, names itself | 26° cone with hysteresis; +0.09 m lift |
| Focus out | Unfaced exhibits recede, names fade | — |
| Arrival | The gallery **fades up** over ~0.18 s on the root, then `OpacityComponent` is removed | 0.18 s |
| Enter | The exhibit swells toward you and the scene dissolves outward — an arrival, never a hard cut | scale 1.6, +0.22 m, ~0.42 s |
| Palette bead | Breathes while closed; ring fans across 150°; yaws to face you | bead radius 0.026 m |

**Selection** is tap/pinch. Focus is driven by **head direction**
(`RoomModel.lookRay`), not eye tracking, so it works in the simulator and is
testable.

**Reduce motion** follows the **system** setting only — `accessibilityReduceMotion`.
The in-app duplicate was deleted; there is no `reduceMotion` in `AppSettings`.
Under stillness the door signs **park at a composed rest pose** rather than
freezing mid-flight, and the palette bead stops breathing.

*(Until 2026-08-03 this paragraph described the setting as app-wide while it
was read in exactly one file, `HubSpaceView` — so the bead, which is the one
object never off screen, went on breathing in every lab. The bead's UNFOLD is
deliberately not suppressed: it answers a pinch, and a control that does not
respond reads as broken rather than as calm.)*

**Emphasis is opacity, light and sound — never geometry.** A de-emphasised
station keeps solving, keeps its colliders, and keeps its panel section; if any
of those reaches zero it has become a picker again (DECISIONS.md, 2026-07-30).
