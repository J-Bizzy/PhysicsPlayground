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
| `ControlButton` | Stock bordered button at extra-large size: glass platter, system hover, an SF Symbol, ≥ 60 pt. Standard, **prominent** (one per surface: the stock white platter, never tinted — a light accent under white type is unreadable) or **destructive**, which can arm first ("Tap again", red), fire on a second press within 4 s, and disarm on its own. | A momentary act. |
| `ControlToggle` | Stock button-style toggle. On is the system's **selected platter**, never a glow. `.row` presentation is a name and a system switch, for a settings list. | A display layer, a mode, an open tab, the current choice in a picker. |
| `ControlSlider` | Name, live value and a stock slider, ≥ 60 pt tall. | A quantity with no extent of its own to stretch. |
| `MoreButton` + `ControlPanel` | An ellipsis toggle, and the glass panel that holds what it opened. | Everything secondary. Nothing else folds a set of controls away. |

**In the room they are the same views.** `ControlAttachment` hangs the
family's SwiftUI view on an entity through `ViewAttachmentComponent`
(visionOS 26), on its own capsule of glass. The owning primitive (an action
bank, a fan, a ring) positions, turns and folds the entity. SwiftUI draws it,
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

As of 2026-08-01 there were **no module panels at all**, and every control
stood in the room. The 2026-10-14 subtraction pass (`docs/redesign-audit.md`)
kept the first half and reversed the second: the room holds the apparatus
and what you make it from, and **everything secondary is behind the title
bar's More** — one panel, the fallback, never the default. A value an object
can carry is changed by handling the object; only what has no object goes to
More.

| Shape | Type | Use it for |
|---|---|---|
| **The object itself** | — | When the quantity *is* a size, a length, a direction or a place: Projectiles' aim bead is the launch velocity (its direction the aim, its distance from the launcher the speed); a capacitor plate dragged sets the gap; the dielectric slab slides in. |
| **Ring + grip** | `DesignSystem/Bloom`, `RingState` | Per-object controls, unfolded by **tap** (never gaze). Discrete actions are petals (Flip, Delete, Mass, Fire…); the value is a **handle pulled out of the object** on a stalk — `Bloom.Grip.Stretch`: `.surface` for a sphere drawn with volume ∝ value (a planet's mass, a charge's \|q\|), so it swells under the hand; `.track` for an object whose size is not its value (a circuit part, a bar magnet), a stalk out of its underside toward the viewer's right; a pendulum's length runs along its own cable. |
| **Well** | `DesignSystem/Well` | Creation as a physical act — reach in and pull the object out, born at your fingertips. Given a `visibleCount`, `facing` and `windowTitle` it becomes a **shelf** (Circuit Workshop's parts): a window of slots with the title above and a hairline spine beside, and on the spine a knurled **crown** (`Models/Shell/ShelfCrown.usdz`) that is the one thing that scrolls — roll it and the column rides the hand one to one, with flick, rubber-banded ends and a detent per slot; it **turns with the column**, so at rest it is a readout of where the shelf is. Never a caret, never a scrollbar. |
| **Joint** | `CircuitsRenderer.wireGrabShape` | Where two of Circuit Workshop's contacts meet (2026-10-18): one brass junction, the two dots made one (a champagne collar until 2026-10-30), that is the one target there — the two coincident contacts withdraw theirs — and a pull on it takes the wire out of the side pulled away from. A cable's own target stops short of both its contacts, so a contact and its cable never compete for a pinch. |
| **Turntable** | `CircuitsModel.Stage`, `CircuitsRenderer.stageRoot` | Circuit Workshop's floating circuit stands over a disc that is both its container and its handle (2026-10-18; ARCHITECTURE.md's one exception to "no tables"): the knurled rim turns the whole circuit, one to one, with a detent every 30° and a coast — the same knurl that says "this turns" on the shelf's crown — and the deck's outer band carries it. Its middle takes no hand. |
| **Fan** | `DesignSystem/SpatialPicker` | A momentary N-way choice opened from a petal: Projectiles' ball fan and the hoop's Low/High arc. The current choice is lit. |
| **Rail** | `RenderKit/SpatialTrackControl` | Only where a continuous quantity has to stand at its object: the Time Capsule's scrub, and an AC source's frequency under the part. The family's slider on glass. |
| **More** | `Shell/LabMorePanel`, `ModuleDescriptor.more` | Everything secondary, as `MoreItem`s the shell draws in the family: display layers and modes (`toggle`), verbs (`action`, arming first when they throw work away), named choices (`choice`), a quantity with no object (`slider`), a set of things to add (`verbs`). A control that needs another stands under it, disabled until it is on. Below them the lab's live Values, then the room (Move, Deep space, dimming), Settings and Reset. |

## The sky (2026-10-19)

One sky serves deep space (`Shell/Sky.swift`, `PhysicsCore/Astronomy`). It served the opening's night over the room too, until the opening went on 2026-10-21.

| Rule | Value | Why |
|---|---|---|
| Stars | The Yale Bright Star Catalogue, 9,096, at their J2000 places on a 45 m sphere | The real sky, not a picture of one |
| Colour | Blackbody of the star's B−V temperature, at 0.8 of its chroma | At 0.35 and 0.5 Betelgeuse read beige |
| Brightness | Flux 10^(−0.4(m − 6.5)), peak 0.2–1, 8 brightness rows × 16 temperature columns in one atlas | No vertex colours in an unlit material, so colour and brightness are cells |
| Size | Core ≥ 4.5′ (≈ 2.6 device px), ≤ 18′ | Below the floor, a star shimmers as the head moves |
| Between the stars | One flat near-black (linear 0.0035, 0.0040, 0.0070) on a 46 m dome, opaque | The Milky Way's band was drawn here until 2026-10-24; the owner found it unnecessary contrast |
| The house evening | 40° N, Orion's belt rising straight ahead 30° up | Orion over the wordmark, Polaris behind and left |
| The Sun (deep space) | Where Pluto sees it on the sky's date: a 10′ white-hot core in a 3° glare | Magnitude −19, too small for a disc |
| Draw order | One `ModelSortGroup`: the stars, then deep space's Sun, its floor pane, its platform | Each transparent layer lies over what is beyond it; the opaque dome stays out of the group so it is drawn first |
| Nothing glows | No `LiveGlow` anywhere in the sky or deep space | A glow means a hand is on something |

Retired on 2026-10-14: the switch bank (`SpatialLayerBank`), the folding tab
(`SummonHandle`), standing banks of discs (the worlds, the clock), the
in-room rails for G, g, wind, ΔV and B, and the Physics box — each now a
More item, or cut.

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

**A part shows its own state (Circuit Workshop's Solid Schematic,
2026-10-30; the lab-kit carriers of 2026-10-18 before it).**

**The part is its symbol.** Every part is its own ANSI symbol made solid:
ink with a champagne keyline, so the drawing reads against a white wall
and against space. It floats on two brass dots that are its terminals
(`DesignTokens.Palette.contactBrassUI`). Brass is where a wire goes, and
the line is the wire: a part's leads and its wires are one dark jacket
over a core in the voltage ramp's colour. Its face turns toward the
wearer.

**Its label is its number and nothing else.** What it is doing is on the
part, and every state comes from the model's value:
- **Bulb:** the filament glows at the colour of its temperature.
- **LED:** lights at its own 625 nm, and only forward.
- **Capacitor:** its plates take the physics red and blue as they charge.
- **AC source:** a bead rides its sine wave.
- **Fuse:** a blown one is broken and scorched.
- **Motor:** its marker turns as fast as it truly does, and smears to a
  band where the eye would.
- **Switch:** the blade is thrown, and the circuit closes when it lands.

A word in the room repeating what the object already shows is the
clutter the subtraction pass removed.

**Asset rules.**
- **Glass from Blender must set Transmission Weight.** The USD exporter
  writes opacity as 1 − Transmission and ignores Alpha, which is how every
  glass part shipped opaque until 2026-10-18.
- **Export triangulated.** RealityKit fans an n-gon from one corner and
  fills a boolean ring's C-shaped faces (`blenderprops.export`).

---

## Colour

Colour is **semantic, never decorative**.

**Domain accents** (`HubDomains.color`) — wayfinding, two hues for two doors:

| Domain | Modules | Accent | Hex |
|---|---|---|---|
| Electricity & Magnetism | electrostatics, circuits, magnetism | Green | `#30D158` |
| Mechanics & Energy | kinematics, pendulums, gravitylab | Orange | `#FF9F0A` |

Domain accent appears in **one** place: the dot beside each domain's name
in the flat catalog. The terrace hairlines and the door signage went with
the gallery on 2026-10-14. The home groups the domains by **order**: the
three E&M portals on the left, mechanics on the right.

**Per-module accents** (`DesignTokens.Palette.*Accent`) are a separate system
for module chrome. Owned by `DesignTokens`, never ad hoc.

**Reserved:** gold is completion. Physics colours (red = positive, blue =
negative; velocity blue / acceleration orange / force red in `VectorPalette`)
are project-locked and never repurposed for chrome.

**Borrowing another module's accent is a warning.** Circuit Workshop's
magnetic-field layer draws in Magnetism's magenta, because what it shows
belongs to that bench. (Its switch wore the magenta too while it was a
plate in the room; in More it is a stock switch like every other, and the
field it draws carries the warning.)

---

## Type

- **Wordmark.** "Physics / Playground", **persistent** — it is the app's
  nameplate, not an intro. (`hasSeenWordmark` and the one-shot behaviour were
  deleted on 2026-07-29.)
- **Voice (2026-10-14).** The app's own: SF Pro Rounded Semibold, title
  case, soft white solids standing free (their glass plaque went on
  2026-10-21, owner's call), the i's dot a particle of champagne light (`Hub/HubTitleGlyphs`,
  milled by `Tools/hubwordmark.py`). Both lines share one type size, centred.
  The machined plaque below is the fallback, drawn only when the
  `HubWordmark_*` assets are missing.
- **The fallback.** The machined plaque, and it is the only thing `HubTitleStyle` can
  draw. There is no setting and no enum: the four-case taxonomy, the
  `shipping` constant, the `current` global and the `switch` in every method
  were deleted on 2026-08-02, because a choice mechanism with one reachable
  case is not a choice. `HubTitleStyle` is a namespace now, not a type you
  pick from — the losing voices live in the git history and DECISIONS.md,
  which is where a rejected option belongs. A plaque is **one solid, not a
  stack** — held by `testThePlaqueIsASingleSolid`.
  (This said "the other three voices stay in the enum" until 2026-08-09.)
- **Portal names.** The system's own type on a glass capsule with a dot
  of the lab's colour (`PortalLabel`). (Bench labels lit into a terrace,
  `HubScene.benchLabel`, went with the terraces.)
- **Name plates.** The label voice on instruments in a lab — wells, the
  parts shelf's header, the multimeter, the time reel.
  `HubScene.namePlate` returns a pill **centred on its own origin** — place
  it by its edge (`namePlateWidth`) or it straddles whatever it names.
- **Module promise.** One line per module (`HubDomains.promise`): what you
  *do*, never a syllabus entry.
- **Minimum size, windows.** Semantic fonts via `DesignTokens.TypeScale`
  so Dynamic Type works; nothing below `footnote`. At the accessibility
  sizes a control's name wraps (`ControlTitleLines`) and a row of
  controls stacks (`ViewThatFits`) — a name never ends in "…".
- **Spoken.** What VoiceOver says for a number goes through
  `PhysicsFormat.spoken`: "24 ohms", "6.0 microcoulombs", "3.5 times 10
  to the 22". A label is written with `SpatialActions.describe`, never a
  fresh `AccessibilityComponent` (`AccessibilityWriteCriterionTests`).
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
| Arrival | The labs rise into place one after another, left to right: each 6 cm up into its spot as it fades up and grows from 90 %, eased out with no overshoot; its name comes up as it settles; one soft tone (A4 and its octave) as the last comes to rest; the wordmark's letters fall and swing in (`Hub/Opening.swift`). No opening before it — "Birth of a System" went on 2026-10-21, owner's call. A walk back, or Reduce Motion, fades the home in | 0.1 s apart, 0.6 s each, all in by 1.2 s, done by 1.5 s |
| Idle portal | The lab's own physics loops in the air, nothing framing it and nothing under it — the portal **is** the demo; it swings slowly about its own axis so the lab shows its depth; each on its own phase (the glass circles and rings went on 2026-10-19, the plinths on 2026-10-21) | footprint 0.32 m, ±12° over 14 s |
| Wordmark | Arrives by physics (Physics drops and bounces, Playground swings in, the dot lands last), then a travelling wave a few millimetres high and a glint every 9 s; a pinch hops a letter (`Hub/HubTitleMotion.swift`) | wave 3.5 mm, hop 7 cm |
| Enter | The portal swells toward you while the rest of the home fades; it stays, swelled, until its lab has settled behind it, then the two cross-fade — an arrival, never a hard cut, and never an empty room (2026-11-02) | scale 1.35, +0.25 m, 0.42 s; cross-fade 0.22 s |
| Door | Every change of scene — home, lab, lab — holds the scene being left until the next one has settled out of sight, then cross-fades the two (`AppModel.go(to:)`, `doorTick`). Under Reduce Motion the same hold, then a cut. Deep space arrives over the room, which stays until the sky is fully up | hold ≤ 2 s (0.2–0.4 s measured), 0.22 s; sky 0.8 s |
| Live | `LiveGlow` fades up around what the hand takes and out when it lets go | 0.15 s |
| Lift and seat | A circuit part rides up while held. In the last centimetre it leans toward its seat, glides home on release, and the two dots meet with a seat sound. A pulled joint strains before it gives. All of it is drawn only (`CircuitsRenderer.displayPose`) | 6 mm, 10 mm, 0.12 s |
| Throw | `Motion.Spring`, for a part that is flung rather than eased: the switch's blade falls, bounces a couple of degrees off its contact and settles there, and swings back past open when thrown open | 7 Hz, damping 0.45; on the contact 12 Hz, 0.35 |

**Selection** is tap/pinch on the portal; hover is the system's.

**Reduce motion** follows the **system** setting only — `accessibilityReduceMotion`.
The in-app duplicate was deleted; there is no `reduceMotion` in `AppSettings`.
**Nothing flashes faster than three times a second** (WCAG 2.3.1): the AC
source stops at 1.5 Hz because a bulb on it brightens twice a cycle.
Under stillness there is no arrival — the portals fade in — the previews
park at their rest pose, and the wordmark's letters hold still.

*(Until 2026-08-03 this paragraph described the setting as app-wide while it
was read in exactly one file, `HubSpaceView` — so the bead, which is the one
object never off screen, went on breathing in every lab. The bead's UNFOLD is
deliberately not suppressed: it answers a pinch, and a control that does not
respond reads as broken rather than as calm.)*

**Emphasis is opacity, light and sound — never geometry.** A de-emphasised
station keeps solving, keeps its colliders, and keeps its panel section; if any
of those reaches zero it has become a picker again (DECISIONS.md, 2026-07-30).
