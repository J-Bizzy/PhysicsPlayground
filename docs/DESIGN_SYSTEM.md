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

## One control language (2026-10-14)

Every control the app draws is one of four, from
`Packages/RenderKit/Sources/RenderKit/Controls/`:

| Control | What it is | Use it for |
|---|---|---|
| `ControlButton` | Stock bordered button at extra-large size: glass platter, system hover, an SF Symbol, ≥ 60 pt. Standard, **prominent** (one per surface, filled in a colour) or **destructive**, which can arm first ("Tap again", red), fire on a second press within 4 s, and disarm on its own. | A momentary act. |
| `ControlToggle` | Stock button-style toggle. On is the system's **selected platter**, never a glow. `.row` presentation is a name and a system switch, for a settings list. | A display layer, a mode, an open tab, the current choice in a picker. |
| `ControlSlider` | Name, live value and a stock slider, ≥ 60 pt tall. | A quantity with no extent of its own to stretch. |
| `MoreButton` + `ControlPanel` | An ellipsis toggle, and the glass panel that holds what it opened. | Everything secondary. Nothing else folds a set of controls away. |

**In the room they are the same views.** `ControlAttachment` hangs the
family's SwiftUI view on an entity through `ViewAttachmentComponent`
(visionOS 26), on its own capsule of glass. The owning primitive (a bank, a
tab, a fan, a ring) positions, turns and folds the entity. SwiftUI draws it,
hit-tests it, hovers it and reads it to VoiceOver. So a room control has **no
mesh, no collider and no input target of its own**: the glass is the target,
and nothing invisible stands in front of the apparatus. The owner tells the
view what to show through a `RoomControl` and writes it only when it changes,
because the per-frame path must not churn SwiftUI.
`ControlLanguageCriterionTests` fails the build on a `ButtonStyle`,
`.buttonStyle(`, `.toggleStyle(`, `Slider(`, `Toggle(` or `Picker(`
anywhere in the app target. It also fails if a room control carries a mesh
or a collider.

**One glow, one meaning: live.** `LiveGlow` is a soft champagne aura (the
app's accent, one hue). It appears around whatever a hand is holding, or
around a slider while it is dragged, and nowhere else. The room version is
light drawn from the inside of a sphere: the body occludes the near half
and the glow shows as a rim, never as geometry. `LiveGlowTracker` keeps it
on exactly one thing. It replaced `PickupPulse`, the one-shot grab flash.
Lit lamps, open tabs, selected discs and the hub's focus pool all glowed in
different senses before. They now read through the system's selected state
or not at all.

**Retired with it:** `PodButtonStyle` (`.podProminent`, `.podQuiet`),
`PanelSection`, the machined verb plate, the frosted layer plate, the folding
tab's energized glow, the picker's accent rim, the dark clear-coat petal, the
bead-on-a-rail track and its extruded value text.

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
| **Switch bank** | `DesignSystem/SpatialLayerBank` | Display layers, and any labelled on/off. Lit plate = on. **Never folds on its own** — which layer is showing is information you need *while* looking at the physics, so it is control and readout at once. Past four plates it may stand behind a **folding tab** (`DesignSystem/SummonHandle`) whose one-line summary keeps that readout — Orbital Mechanics' Show tab and Circuit Workshop's Views tab (2026-09-04) — because five lamps read as a wall, not a state. |
| **Rail** | `RenderKit/SpatialTrackControl` | A continuous quantity with **no extent of its own** (G, g, a clock, a wind speed). **Absolute**: the bead's place *is* the value. |
| **Standing bank of discs** | `DesignSystem/SpatialPicker(staysOpen: true)` | An N-way choice that is also a readout (worlds, clock speeds). Row layout: `FanLayout(span: ~50°, verticalScale: 0.25)` — the default 150° arc is for a menu that folds away, and reads as scattered debris as a permanent bank. |
| **Fan** | `DesignSystem/SpatialPicker` | A momentary N-way picker, opened from a petal. Never a blind cycle button. |
| **Well** | `DesignSystem/Well` | Creation as a physical act — reach in and pull the object out, born at your fingertips. Given a `visibleCount`, `facing` and `windowTitle` it becomes a **shelf** (Circuit Workshop's parts): a window of slots with the title above and a hairline spine beside, and on the spine a knurled **crown** (`Models/Shell/ShelfCrown.usdz`) that is the one thing that scrolls — roll it and the column rides the hand one to one, with flick, rubber-banded ends and a detent per slot; it **turns with the column**, so at rest it is a readout of where the shelf is, and on entry the column arrives coasting into place with the crown rolling. Nothing stands behind the parts, and a drag on a part is always a pull. Never a caret, never a scrollbar. |
| **Physics box** | `Shell/PhysicsBoard` | The lab's live numbers on one readout card in the room, opened by the title bar's ƒ button, with one **rail** beside it per quantity the lab lets you set (`ModuleDescriptor.adjustables`). A readout plus rails — never a panel. |
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
| `frostedGlass(opacity:)` | A dark, light-scattering scrim | Apparatus panes (the dielectric slab). Controls stand on stock glass, not this. |
| `contrastLine(_:)` | A line that survives passthrough | Field lines and any drawn line — returns a **two-pass** (casing, core) pair |

**Contours beat surfaces indoors, and casings beat glows.** A glowing band has
nothing to be bright *against* unless something dark sits behind it, and
passthrough is a *bright* medium. This is why `frostedGlass` is a dark,
light-scattering scrim *with* a bright specular skin — both halves are
load-bearing, and a recipe with only the second is the thing the app already
banned. It is also why `contrastLine` is two passes: a near-black casing swept
fatter than the bright core.

`contrastLine` spent a long time claiming to be "used everywhere" while
shipping in one module. Its call sites as of 2026-08-05: `FieldRenderer`,
`MagnetismRenderer`, `OrbitRing`, `HubVignettes`, `SpatialActionBank`,
and `KinematicsRenderer` (the predicted arc — a pale line in the one
module that shares the real room 1:1, cased at last). `LatitudeGlobe`
left the list when Foucault did (2026-08-03). Circuits is deliberately
NOT a call site, and the reason belongs here rather than as an absence:
its only lines are the wires, which carry their own near-black
insulating jacket (the same darkness-under-light move under another
name), its bench field is arrows on rings rather than traced tubes, and
the voltage skyline is towers. **If you are adding lines to a module,
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

Domain accent appears in **two** places — the terrace hairline and the door
signage (`HubDomainTitle`) — and nowhere else.

> It listed four until 2026-08-09. The **progress ring** around each miniature
> went on 2026-08-04 and the **focus panel's chip** went with the experiments
> system on 2026-08-09; the sentence outlived both. `Hub/HubDomains.swift`
> carried the same three-place claim in its own header and is corrected too.
> Two places is also the more defensible number: the accent is wayfinding, and
> a hue that appears in four places is decoration.

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
- **Voice.** The machined plaque, and it is the only thing `HubTitleStyle` can
  draw. There is no setting and no enum: the four-case taxonomy, the
  `shipping` constant, the `current` global and the `switch` in every method
  were deleted on 2026-08-02, because a choice mechanism with one reachable
  case is not a choice. `HubTitleStyle` is a namespace now, not a type you
  pick from — the losing voices live in the git history and DECISIONS.md,
  which is where a rejected option belongs. A plaque is **one solid, not a
  stack** — held by `testThePlaqueIsASingleSolid`.
  (This said "the other three voices stay in the enum" until 2026-08-09.)
- **Bench labels (2026-10-14).** Each exhibit's name is lit into its
  terrace's dark front edge, under the mount, in the lab's accent at
  `PlateStyle.exhibitLabelSize` (`HubScene.benchLabel`). The bench is the
  backing a floating card was refused for. A label never moves: 0.78 at
  rest, full while faced, a third while its lab is on the pad.
- **Name plates.** The label voice on instruments in a lab — wells,
  plates, petals, rails. `HubScene.namePlate` returns a pill **centred on its own
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
| Focus in | Nearest exhibit in the head-direction cone lifts off its mount and grows; the pool of its accent stays on the mount; its bench label brightens | 26° cone with hysteresis; +0.09 m lift; label 0.78 → 1 |
| Focus out | Unfaced exhibits recede, names fade | — |
| Arrival | The gallery **fades up** over ~0.18 s on the root, then `OpacityComponent` is removed | 0.18 s |
| Enter | The exhibit swells toward you and the scene dissolves outward — an arrival, never a hard cut | scale 1.6, +0.22 m, ~0.42 s |
| Palette bead | Breathes while closed; ring fans across 150°; yaws to face you. Each slot is the lab's emblem (`HubVignettes`) on an accent disc | bead radius 0.026 m |

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
