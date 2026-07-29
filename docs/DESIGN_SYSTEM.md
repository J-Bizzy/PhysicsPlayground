# Design System

The visual and motion language of the homescreen, **as built** — reconciled against
`Hub/HubSpaceView.swift`, `Hub/HubDomains.swift`, and `Shell/Palette.swift`
(2026-07-29; an earlier draft carried values from the v2 spec that the code had
already superseded). This governs the home space (constellation, bead, panels).
The in-lab field vocabulary is owned separately by `VectorPalette` (see
`docs/ARCHITECTURE.md` → Conventions), and all tokens live in
`DesignSystem/DesignTokens.swift`.

## Color

Color is **semantic, not decorative**. Two systems coexist, deliberately:

**Domain accents** (`HubDomains.color`) — wayfinding, four hues:

| Domain | Modules | Accent | Hex |
|---|---|---|---|
| Mechanics | kinematics, pendulums | Orange | `#FF9F0A` |
| Electricity & Magnetism | electrostatics, magnetism, circuits | Green | `#30D158` |
| Waves | waves | Cyan | `#64D2FF` |
| Fluids & Gravity | windtunnel, gravitylab | Violet | `#BF5AF2` |

**Where domain accent appears — and nowhere else:**
- The progress ring around each exhibit
- The domain chip on the focus panel

(The floating domain headers were deliberately removed — the colors carry the
grouping without captions. `HubSpaceView.swift:273`.)

**Per-module accents** (`DesignTokens.Palette.*Accent`) are a separate, older
system used by the Palette ring backing discs and the module title bar. They are
owned by `DesignTokens`, never ad hoc.

**Reserved colors:** gold is completion — an exhibit's progress ring turns gold
when every experiment in the module is done. Physics colors (red = positive,
blue = negative, etc.) are project-locked in `DesignTokens`/`VectorPalette` and
never repurposed for chrome.

**Surfaces:** panel text sits on glass (`.regularMaterial` /
`.glassBackgroundEffect`). Exhibit name plates are the exception: billboarded 3D
text in the room, shown only for the faced exhibit.

## Type

- **Wordmark.** "Physics / Playground" as a two-line 3D bubble lockup above the
  constellation center — warm ivory glyphs, champagne rim, soft dark backing,
  glossy clearcoat. Shown **on first launch only** (`hasSeenWordmark`); it bobs
  and breathes while present.
- **Name plates.** Billboarded, one per exhibit; only the faced exhibit shows its
  full name, the rest fade.
- **Module promise.** The focus panel leads with one line per module
  (`HubDomains.promise`) — what you *do*, not a syllabus entry: "Fire projectiles
  and bend their arcs with gravity and drag."
- **Minimum size.** Nothing smaller than visionOS `body`; semantic fonts only,
  via `DesignTokens.TypeScale`, so Dynamic Type works.

## Motion

All hub motion ticks from `SceneEvents.Update` (never `RealityView`'s `update:`
— see `docs/ARCHITECTURE.md`). Values live in `HubSpaceView.swift`.

| State | Behavior | Value |
|---|---|---|
| Idle exhibit | Gentle vertical bob; miniature sways rather than spinning | ~1.2 cm sine; ±0.44 rad sway |
| Idle vignette | The module's own physics runs continuously — the exhibit *is* the demo | — |
| Focus in | Nearest exhibit within the head-direction cone grows, steps toward the user, lights its halo | 26° cone with hysteresis; scale → 1.34; +0.16 m toward user |
| Focus out | Unfaced exhibits recede; their names fade | scale → 0.90 |
| Focus panel | Billboarded glass attachment above and outward of the focused exhibit | — |
| Enter | Exhibit swells toward the user with a pop sound, then the scene swaps to the room-scale module — an arrival, never a hard cut | scale 1.6, +0.22 m, 0.42 s ease-in; swap at ~420 ms |
| Palette bead | Breathes while closed, recedes while open; ring fans upward across 150°; the whole ring yaws to face the user each frame | bead radius 0.026 m |

**Selection:** gaze + pinch is the primary select (visionOS standard); focus is
driven by head direction (`RoomModel.lookRay`), not eye tracking, so it works in
the simulator and is testable.

**Reduce motion:** `scene.stillness` stills idle hub motion when *either* the
app's reduce-motion setting or the system's `accessibilityReduceMotion` is on
(`HubSpaceView.swift:46`).
