# Redesign audit — subtraction and one control language

Branch `redesign/subtraction` (cut from `release/1.0` at `d75ccde`), started
2026-10-14. This file is the plan for the pass. Each step appends a log entry
at the bottom.

**Brief.** Fewer, better things. Cut the Lab Notebook, the challenges and
progress tracking. Build one shared control language (button, toggle, slider,
"more") and use it for every control. Adjust a value by handling the object
before reaching for a control. Each lab opens on its primary interaction,
with everything secondary behind one "more". Replace the home with a
particle opening that settles into six portals. Physics code
(`Packages/PhysicsCore`) and its tests do not change.

**Module count gate: passed.** `ModuleCatalog.registry` lists exactly six:
Electric Fields (`electrostatics`), Circuit Workshop (`circuits`), Magnetism
(`magnetism`), Projectile Motion (`kinematics`), Pendulums (`pendulums`),
Orbital Mechanics (`gravitylab`).

**What was already gone.** The daily-challenge surface never shipped
(HOMESCREEN_SPEC §2 locked "no Search/Daily-Challenge surface"). The
experiments system, its progress ring and step counter were deleted on
2026-08-09. The "New" badges and `visited.modules` were deleted on
2026-10-14. What remains of "progress" is the hoop **streak / best streak**
in Projectiles (persisted under `kinematics.bestStreak`) and the per-hoop
**score**. Both are cut below.

Baseline before any change: PhysicsCore 469/469, app + UI tests 908/908, all
green (`xcodebuild test`, 125 s).

Labels used below: **Keep**, **Merge** (into another control, named),
**Replace** (with direct manipulation of the object, named), **Cut**.

---

## 1. Distinct control styles in the codebase (before)

Fourteen ways to draw a control, plus four glows that each meant something
different.

**Window / SwiftUI**

| # | Style | Where |
|---|---|---|
| 1 | `PodProminentButtonStyle` — filled accent capsule | Show in room, Enter the Gallery, Notebook Capture |
| 2 | `PodQuietButtonStyle` — tinted outline capsule | Notebook Clear, per-entry delete |
| 3 | System bordered, `.buttonBorderShape(.circle)` | module title bar icons |
| 4 | `.plain` row on `.regularMaterial` card + `.hoverEffect()` | `HubCatalogRow` |
| 5 | `.plain` text button | "Put the Gallery away" |
| 6 | `HubLoadButton` — custom capsule, accent disc, scale hover, glass | Load Lab over the podium |
| 7 | `.borderless` icons on a glass capsule | `HubUtilityBar` |
| 8 | unstyled text button | "Try Again" |

**In the room / RealityKit**

| # | Style | Where |
|---|---|---|
| 9 | Layer plate — frosted-glass box, accent lamp strip, rasterised SF Symbol, extruded nameplate | `SpatialLayerBank` |
| 10 | Verb plate — machined box, lamp, symbol, nameplate, "Tap again" arming | `SpatialActionBank` (+ Time reel's three plates) |
| 11 | Folding tab — machined plate, accent glyph, summary nameplate, **energized accent glow when open** | `SummonHandle` |
| 12 | Picker disc — frosted disc, glass edge, **accent selection rim**, glyph, nameplate | `SpatialPicker` |
| 13 | Petal — dark clear-coat disc + glyph (Bloom: icon only; Palette: with nameplate, red armed lamp) | `Bloom`, `Palette` |
| 14 | Rail — track, fill, ticks, bead, value bubble, subtitle | `SpatialTrackControl` (in-room rails, Physics box, Time rail) |

**Not controls, but drawn as if they were**: the palette bead (gyroscope) and
its six accent lab discs; the gallery's exhibits on pucks, the podium latches,
the gallery grab bar.

**Glows that meant different things**: the layer lamp (on), the verb flash
(fired), the folding tab's energized accent (open), the picker rim
(selected), the hub focus pool (faced), `PickupPulse` (just grabbed).

**After**: one family in `Packages/RenderKit/Sources/RenderKit/Controls/`:
`ControlButton`, `ControlToggle`, `ControlSlider`, `MoreButton` (+ the panel
it opens). They use stock visionOS glass (`glassBackgroundEffect`), system
hover, SF Symbols, ≥ 60 pt targets. In the room they are the same SwiftUI
views, hosted on entities through `ViewAttachmentComponent` (visionOS 26).
One glow, `LiveGlow`, means "this is live": the thing in the hand, or the
value being dragged. It is a single hue, and nothing else glows.

---

## 2. Home screen

Before: two graphite terraces (slabs on legs) of live miniatures on pucks.
Domain signs "ELECTRICITY & MAGNETISM" / "MECHANICS & ENERGY". A machined
wordmark plaque. A utility bar. A podium you carry a lab to, then a Load
button. A grab bar to move the whole gallery. See `docs/redesign-shots/before-home.jpg`.

| Element | Label | Reason |
|---|---|---|
| Two terraces (slabs, pucks, hairlines) | **Cut** | They are tables; the brief bans tables and dioramas. |
| Domain signs (3-D, animated) | **Cut** | Decoration. Grouping survives as order (E&M left, mechanics right) and in the flat catalog. |
| Six exhibits (miniatures) | **Merge → portals** | The miniatures (`HubVignettes`) become each portal's looping preview. |
| Bench labels (lab names on the slab edge) | **Merge → portal label** | One short word under each portal. |
| Head-direction focus (lift, grow, pool glow) | **Cut** | Duplicates system gaze hover; the pool was a second accent glow. |
| Podium + latches + carry-to-pad | **Cut** | A two-step ceremony to open a lab. A pinch on a portal enters. |
| Load Lab button | **Cut** | Same reason. |
| Gallery grab bar (move / recentre) | **Cut** | Portals stand around the wearer, so there is nothing to move. `GalleryPlacement` goes too. |
| Wordmark plaque | **Keep** (smaller, above the arc) | Owner's call 2026-09-07 kept the plaque after two auditions. Flagged as the most debatable keep under principle 4. |
| Utility bar: Lab list | **Merge → More** | Still the flat-catalog door (the accessibility path). |
| Utility bar: Settings | **Merge → More** | |
| Utility bar: Notebook | **Cut** | Feature cut. |
| Utility bar: About | **Merge → More** | |
| Arrival choreography (wordmark flight + cascade + bell) | **Replace** | The new opening: particles that fall, swirl and ripple, then settle as portals (§10). |

**Flat window (space closed)**

| Element | Label | Reason |
|---|---|---|
| Name + one-line tagline | **Keep** | |
| "Enter the Gallery" | **Keep, renamed** "Show in Room" | Same words as a module window. There is no gallery any more. |
| Catalog rows by domain | **Keep** | The accessibility path, and what the UI tests drive. |
| "Put the Gallery away" | **Keep, renamed** "Close the Room" | |
| Room-sensing note | **Keep** | |
| "Try Again" (on failure) | **Keep** | |

Controls: **11 visible at open → 7** (six portals + More), 12 reachable → 10
(+ Lab list, Settings, About inside More).

---

## 3. Every lab: shell chrome

Before, every lab carried a six-button title bar and a palette bead. The bead
opened six lab discs and six petals. On top of that came the Physics box
(card + rails), the Time reel (reel, rail, three plates) and the lab anchor.
The bead duplicated three title-bar functions.

| Element | Label | Reason |
|---|---|---|
| Title bar: Home ‹ | **Keep** | |
| Title bar: icon + name | **Keep** | Identity, not a control. |
| Title bar: Notebook | **Cut** | Feature cut. |
| Title bar: Physics ƒ | **Merge → More** (its "Values" section) | Secondary. |
| Title bar: Place the lab | **Merge → More** ("Move lab") | Secondary. |
| Title bar: Studio Mode | **Merge → More** | Secondary. |
| Title bar: Reset + dialog | **Merge → More** | Arms then fires, like every destructive control now. |
| Title bar: room-sensing ⚠ | **Keep** | Only appears when sensing fails. |
| "Show in room" | **Keep** | Only while the space is closed. |
| Palette bead + "Labs" | **Cut** | A second navigation surface. Everything on it is elsewhere. |
| Palette: six lab discs | **Cut** | Home is one pinch away and shows the portals instantly after the first arrival. |
| Palette: Home petal | **Cut** | Duplicate of ‹. |
| Palette: Pause / Resume petal | **Merge → title bar** | Time is the one universal control, so it sits beside the name. |
| Palette: Capture petal | **Cut** | Feature cut. |
| Palette: Dim petal | **Merge → More** | |
| Palette: Settings petal | **Merge → More** | |
| Palette: Reset petal | **Merge → More** | Duplicate of the title-bar Reset. |
| Physics box card (readouts) | **Merge → More "Values"** | The live numbers, in the panel. Rows that restate what is visible in the room are dropped. |
| Physics box rails | **Merge → More sliders** | Only quantities with no physical extent keep a slider. Those with a direct path lose it. |
| Time reel | **Keep** | Appears only while paused. It is the Time Capsule. |
| Time rail | **Keep → `ControlSlider`** | |
| Back a frame / Ahead a frame | **Keep → `ControlButton`** | |
| Resume here | **Merge → title-bar Resume** | All six labs' pause already resumes from the scrubbed instant (`togglePauseRespectingScrub`). |
| Lab anchor | **Keep** | Reached from More → Move lab. |
| Module legends (Notebook window only) | **Cut** | No surface left once the Notebook goes, and they were prose. `LegendView` / `LegendItem` / `legend:` go too. |
| Two-hand scale / turn | **Keep** | Direct manipulation of the view. |

Shell controls: **7 visible at open → 3** (Home, Pause, More). **≈ 25
reachable → 13**: More holds Move lab, Studio Mode, Dim, Settings and Reset
(5), plus the reel, rail, two step buttons and the anchor.

**Settings window** — volume (slider), room tone (toggle), Time Capsule
(toggle): **Keep**, rebuilt on `ControlSlider` / `ControlToggle`.
**About window**: **Keep**.

### Studio Mode

Studio Mode is one switch plus an environment
(`Shell/StudioEnvironment.swift`). It has no controls of its own.

| Element | Label | Reason |
|---|---|---|
| The switch (title-bar moon) | **Merge → More** (`ControlToggle`) | |
| Night-sky dome | **Keep** | Without it full immersion is a black void. |
| Charcoal floor disc | **Keep** | Footing once the room is gone; a comfort requirement, not decoration. |
| Champagne stage pool on the floor | **Keep** | It is the floor's lighting. Without it the disc reads as a hole. |
| Two glowing stage rings (champagne 2.6 m, blue 5.8 m) | **Cut** | Decoration. They also glow, and the glow now means "live". |

---

## 4. Electric Fields — 17 visible / 43 reachable before

| Element | Label | Reason |
|---|---|---|
| Plate: Field lines | **Merge → More** (toggle) | Display layer; secondary. |
| Plate: Free charges | **Merge → More** (toggle) | Physics mode; secondary. |
| Plate: Capacitor | **Merge → More** (toggle) | Stands an apparatus up; secondary. |
| Plate: Uniform B | **Merge → More** (toggle) | Acts only on the probe; secondary. |
| Verb: Clear all | **Merge → More** (confirms) | Destructive, rare. |
| Verb: Deflect shot | **Merge → More** (shown only with the capacitor) | It was standing dead whenever the capacitor was off. |
| Wells: Add +, Add − | **Merge → one "Charge" well** + Flip petal on the charge's ring | Sign becomes a property of the object you hold, not a second well. |
| Wells: Test +, Test − | **Merge → one "Probe" well** + Flip petal on the probe's ring | Same. The model already flips the probe live. |
| Charge sphere (drag, tap → ring) | **Keep** | Direct. |
| Charge ring: Delete | **Keep** | |
| Charge ring: Strength grip (rail under the charge) | **Replace** with a handle on the charge's surface | Pulling it out stretches the charge. Its radius now shows \|q\|. The brief names charge. |
| Probe ring: Delete | **Keep** | |
| Probe ring: Charge grip | **Replace** with a surface handle, as above | |
| ΔV rail in the room + ΔV rail in the box | **Merge → one More slider** | A voltage has no extent to stretch. Two controls became one. |
| B rail in the room + B rail in the box | **Merge → one More slider** | Same. |
| Capacitor plates / dielectric slab / T-handle | **Keep** | Direct: gap by dragging a plate, coverage by sliding the slab. |
| Capacitor callout (C, Q, U, E) | **Keep** | The only number at the apparatus. |
| Card rows "E between plates = V/d", "On the rails" | **Cut** | The first contradicts the measured callout; the second restates labels. |
| Sign glyphs on charges | **Keep** | They carry the sign for colour-blind wearers. |

After: **5 visible** (2 wells + Home, Pause, More), **≈ 30 reachable**.

## 5. Magnetism — 12 visible / 34 reachable before

| Element | Label | Reason |
|---|---|---|
| Plates: Magnets move, Field lines, Hand compass, Earth's field | **Merge → More** (toggles; Earth's field disabled while the compass is off) | Secondary. Earth's field acted on nothing without the compass. |
| Well: Add magnet | **Keep** | |
| Magnet (drag, tap → ring) | **Keep** | |
| Ring: Flip poles | **Keep** | A 180° turn is a discrete act. Twist-to-rotate would be a new capability (see "unsure"). |
| Ring: Delete | **Keep** | |
| Ring: Strength grip | **Replace** with a handle at the magnet's north end | |
| Physics-box Magnet moment rail | **Cut** | Duplicate of the grip. |
| Compass + µT callout | **Keep** | |

After: **4 visible** (well + 3 shell), **≈ 22 reachable**.

## 6. Projectile Motion — 16 visible / 52 reachable before

| Element | Label | Reason |
|---|---|---|
| Launcher (drag) | **Keep** | |
| Aim bead | **Keep, extended** — its distance from the launcher sets launch speed | The bead becomes the velocity vector (direction *and* magnitude). |
| Launcher ring: Fire, Balls, Clear (confirms) | **Keep** | |
| Launcher ring: speed grip | **Replace** with the aim bead's pull | Launch angle and speed are both set on the object now. |
| Ball fan (5) | **Keep**, and the current ball now lights | No disc ever lit (`selectedID` was never set). |
| Custom-mass rail under the launcher | **Merge → More slider** (only while Custom is picked) | |
| Wells: Add ball, Add hoop | **Keep** | |
| World fan (Zero-g, Moon, Earth, Jupiter) | **Merge → More gravity slider**; its readout names the world | g was set three ways. |
| g rail in the room, g rail in the box | **Merge → the same slider** | |
| Plates: Walls bounce, Air resistance | **Merge → More** (toggles) | |
| Wind rail in the room + box | **Merge → one More slider** (enabled with air) | |
| Hoop (drag, tap → ring) | **Keep** | |
| Hoop ring: Aim (→ Low / High arc fan), Drop when fired, Delete | **Keep** | |
| Hoop score number | **Cut** | Scorekeeping. The hoop still flashes and chimes on a pass. |
| Streak, best streak (+ `kinematics.bestStreak` key) | **Cut** | Progress tracking. |
| Predicted arc, apex, landing ring, protractor, flight callout, strobe dots, shadows | **Keep** | They are the physics. |

After: **5 visible** (2 wells + 3 shell; launcher and aim bead are the
apparatus), **≈ 30 reachable**.

## 7. Pendulums — 13 visible / 36 reachable before

| Element | Label | Reason |
|---|---|---|
| Collars (drag) | **Keep** | |
| Collar ring: Delete, Length | **Cut** | Both duplicate the bob's ring. |
| Bobs (pull back, throw, tap → ring) | **Keep** | |
| Bob ring: Mass | **Keep** | |
| Bob ring: Delete | **Keep** | |
| Bob ring: Length grip (rail) | **Replace** with a handle below the bob, along the cable | Drag down to lengthen. |
| Wells: Add pendulum, Double pendulum | **Keep** | |
| Plates: Velocity, Force, Air resistance | **Merge → More** (toggles) | |
| Plate: Acceleration | **Cut** | Its arrow is the Force layer's net arrow divided by m. |
| Selected-bob info card | **Cut** | L, T, θ, v already show in the period tag, the grip and Values. |
| Period tag | **Keep** | |

After: **5 visible** (2 wells + 3 shell), **≈ 20 reachable**.

## 8. Circuit Workshop — 17 visible / 57 reachable before

| Element | Label | Reason |
|---|---|---|
| Views tab + five plates | **Merge → More** (toggles) | Secondary. |
| — Electron view | **Cut** | A 4× floor on the same two-hand zoom you already have. |
| — True speed | **Keep** in More, disabled unless Electron flow is on | It showed nothing without flow. |
| Clear bench | **Merge → More** (confirms) | |
| Presets tab + five preset plates | **Merge → More** ("Load a circuit", each confirms) | |
| Parts shelf, crown, 11 slots | **Keep** | Creation by pulling. |
| Multimeter | **Keep** | |
| Part body / leads / wires / switch lever | **Keep** | Direct. |
| Ring: Open or close (switch) | **Cut** | Duplicates pressing the lever. |
| Ring: Replace (failed part), Detach, Delete | **Keep** | |
| Ring: Value grip | **Replace** with a surface handle, as in every lab | |
| AC frequency rail under a source | **Keep → `ControlSlider`** | A frequency has no extent. It stays beside its part. |
| Selected-part readout card | **Keep** | The selected part's V, I, P, at the part. |
| Physics-box rows (component / wire counts, selected V/I/P) | **Cut** | Counts restate the bench; the V/I/P rows duplicate the readout card. |

After: **≈ 10 visible** (crown, six slots, 3 shell), **≈ 38 reachable**.

## 9. Orbital Mechanics — 13 visible / 59 reachable before

| Element | Label | Reason |
|---|---|---|
| Clock tab + six discs | **Merge → More** (a clock row) | Secondary. |
| Show tab + five plates (v, a, F, Kepler sweep, Lagrange) | **Merge → More** (toggles) | |
| — Acceleration | **Cut** | The F arrow already draws along a (`OR:1112`). |
| Worlds plate + nine-world fan | **Merge → More** ("Add a world": the nine as buttons) | |
| Twin suns | **Merge → More** (disabled once there is no single Sun) | It stayed offered after it could do nothing. |
| G rail in the room + G rail in the box | **Merge → one More slider** | |
| Star mass rail (box) | **Cut** | It wrote a different variable from the Sun's own Mass grip and went stale against it. The Sun's grip stays. |
| Add world well | **Keep** | |
| Bodies (drag, throw, tap → ring) | **Keep** | |
| Ring: Predict, Delete | **Keep** | |
| Ring: Mass grip | **Replace** with a surface handle (the body already grows ∝ m^⅓) | |
| Orbit ring + apsis beads | **Keep** | Direct reshaping of the orbit. |
| Data card | **Keep** | |
| Values rows duplicating the data card | **Cut** from Values | |

After: **4 visible** (well + 3 shell), **≈ 38 reachable**.

---

## 10. The opening (replaces the arrival choreography)

About 3.4 s. Any pinch skips to the end. With Reduce Motion it is a fade.
Every phase is a closed-form solution, so a viewer sees real gravity and a
real field, not easing curves:

1. **The room dims** to 0.3, and about 200 glowing particles fade up on a
   horizontal sheet above eye level.
2. **They fall and swirl.** It is one system: a uniform horizontal magnetic
   field crossed with gravity. A charge released from rest in crossed **g**
   and **B** traces an exact cycloid. It falls with acceleration g at first,
   is curled sideways by the Lorentz force, and comes back to rest at its
   starting height after one cyclotron period. Positive and negative charges
   drift apart in opposite directions (red and blue, the project's sign
   colours). The magnetic force does no work, so ½v² = g·(drop) exactly, and
   a test holds that.
3. **They ripple.** Every particle is at rest on the sheet again, which is
   exactly where the cycloid hands over. A deep-water gravity wave crosses
   the sheet. It uses Airy's linear solution, where surface particles trace
   circles, with the dispersion relation ω² = g k and the same g.
4. **They settle.** Each particle is pulled onto its portal's rim by a
   critically damped spring (closed form). The portals' glass fades in under
   them and the particles fade out.

The end state *is* the home screen. Six glass portals stand on an arc at eye
level, 1.75 m out, E&M on the left and mechanics on the right. Each runs its
lab's emblem in a loop (`HubVignettes`) and carries a one-word label. A pinch
enters.

---

## 11. Plan of work (each step builds, tests, screenshots and commits)

1. This audit.
2. Cut the Notebook (model, window, capture petal, title-bar and hub
   buttons, launch arguments, `LabNotebookTests`, docs), the hoop
   streak/score, and the legends.
3. Build `RenderKit/Controls` + `LiveGlow`. Migrate every control onto it with
   no behaviour change: windows, Settings, title bar, the in-room banks,
   tabs, pickers, petals, rails, Physics box, Time rail. Delete
   `PodButtonStyle` and the one-off plate/disc/petal builders.
4. The opening and the portal home.
5. Clean up the labs, most cluttered first: Circuits, then Orbits,
   Projectiles, Fields, Pendulums, Magnetism. Then the shell and Studio Mode.

New launch arguments for screenshots: `-hubIntro <s>` keeps its meaning,
pinning the opening at that instant, so 99 shows the end state. Two are
added: `-moreOpen 1` unfolds the title bar's More, and `-moreSection <name>`
scrolls it there.

---

## Log

### Step 1 — audit (2026-10-14)

Surveyed the shell, the home and all six labs (three parallel read-only
inventories, then cross-checked against the code). Nothing changed in code.
Baseline screenshots, taken with the simulator at launch defaults:
`docs/redesign-shots/before-home.jpg`, `before-electrostatics.jpg`,
`before-magnetism.jpg`, `before-kinematics.jpg`, `before-circuits.jpg`,
`before-pendulums.jpg`, `before-gravitylab.jpg`.

### Step 2 — the Notebook, the streak and the legends are cut (2026-10-14)

Removed: `LabNotebook`, `NotebookView`, the Notebook window, the capture
petal, the book buttons (title bar, home utility bar), `-notebookOpen`,
`-notebookSeed`, `LabNotebookTests`. Also the module legends, whose only
surface was the Notebook window: `LegendItem`, `LegendView`, six `legend:`
arrays. In Projectiles: the hoop streak, the persisted best streak, the
score number over each hoop and the "Hoops / Score / Best streak" rows. The
model now counts `passes`, which still drive the hoop's flash and chime.

`NotebookEntry.Reading` became `Reading`, and `captureReadings` became
`readings`, the Physics box's one list. `physicsRows` went with the
Notebook. An upgraded install forgets `notebook.entries.v1` and
`kinematics.bestStreak`.

Docs: App Store copy (count re-measured, 3,626 characters), Support,
Privacy, demo beat 9 (now the Physics box), the device checklist,
CLAUDE.md's argument list, DECISIONS. `SellingCopyCriterionTests` now bans
"Notebook", its two arguments and "best streak" from the selling copy.

Tests: PhysicsCore 469/469. App 901/901: 908 before, minus six Notebook
tests and the streak test. Screenshots:
`docs/redesign-shots/step2-home.jpg` (utility bar: Lab list, Settings,
About) and `step2-kinematics-hoops.jpg` (two hoops, aim callout, no score;
title bar without the book).

### Step 3 — one control language (2026-10-14)

Built `Packages/RenderKit/Sources/RenderKit/Controls/`: `ControlButton`
(standard / prominent / destructive, arm-then-fire), `ControlToggle`
(button and settings-row presentations), `ControlSlider`, `MoreButton` +
`ControlPanel` + `ControlSection`, `LiveGlow` + `LiveGlowTracker`, and
`ControlAttachment` / `RoomControl`. The last pair hosts the same SwiftUI
views on an entity through visionOS 26's `ViewAttachmentComponent`. Stock
glass, system hover, SF Symbols, ≥ 60 pt.

Migrated with no behaviour change:
- **Windows:** the module title bar, the home window and catalog rows,
  Settings, the Load button, the home utility bar.
- **In the room**, each kept its API, layout and tests' tap contract:
  - the layer bank, the action bank (and the Time reel's plates);
  - the folding tab, the picker (its fan now widens until no two choices
    touch), Bloom's petals, the palette's petals;
  - the rail (`SpatialTrackControl` is now the family's slider on glass;
    the Physics box's and Time rail's included).
- **Grabs:** in every lab, the grab flash (`PickupPulse`, deleted) became
  `LiveGlow`, which stays on what the hand holds until it lets go. Bloom's
  grip bead glows while dragged.

Deleted: `PodButtonStyle`, `PanelSection` / `ModulePanel.swift`,
`PickupPulse`, every plate, disc and petal mesh builder, and the rail's
bead, fill, ticks and extruded value text.

New criterion: `ControlLanguageCriterionTests`. It fails on any
`ButtonStyle`, `.buttonStyle(`, `.toggleStyle(`, `Slider(`, `Toggle(` or
`Picker(` in the app target, and on a room control with its own mesh or
collider. It also checks that the live glow follows the hand and is never a
target.

Tests: the 20 that asserted the old meshes were rewritten:
- child-label targets became "one target, name inside";
- entity colliders became "no collider of its own";
- entity-level VoiceOver became "the press path arms first".

Five old rail-bead tests and two plate-mesh tests were deleted.
PhysicsCore 469/469. App 898/898. Screenshots:
`docs/redesign-shots/step3-home.jpg`, `step3-electrostatics.jpg` (glass
layer toggles, red Delete petal), `step3-gravitylab.jpg` (Show tab open,
clock tab, verbs, G slider, ring petals), `step3-circuits.jpg`,
`step3-kinematics.jpg` (world picker, Physics box sliders, launcher
petals), `step3-settings.jpg`.

Not migrated, on purpose: the palette's six lab discs and the gallery's
exhibits. Both are cut in steps 4 and 5.

### Step 4 — the opening and the portal home (2026-10-14)

The gallery is gone: terraces, pucks, domain signs, bench labels, focus
pool, podium, latches, Load button, grab bar, `GalleryPlacement`,
`GalleryLayout`, `HubDomainTitle`, `HubIntro`, `-hubDock`, `-hubFocus`.

In its place, six glass portals stand on an arc at eye level (1.75 m, 20°
apart). Each runs its lab's emblem in a loop and wears a one-word label. A
pinch enters. The machined wordmark stays above and behind. One More
under it opens Lab list, Settings and About in a row. The home dims the
room to 0.3.

The opening (`Hub/Opening.swift`, about 3.1 s):
1. The particles fade up on a sheet.
2. They fall and swirl: an exact crossed-field cycloid, red and blue
   charges parting.
3. They ripple: an Airy deep-water wave, ω² = gk.
4. They settle onto the rims (critically damped) as the glass fades up,
   on the calibration bell.

Any pinch skips (a box of collider around the wearer, only while it
plays). Reduce Motion fades the portals in instead. A walk back from a lab
does not replay it.

Also: the "prominent" emphasis is now the stock white platter, never
tinted. White type on Fields' yellow or the champagne accent was
unreadable. Window copy: "Enter the Gallery" became "Show in Room", and
"Put the Gallery away" became "Close the Room".

New launch argument: `-moreOpen 1`. `-hubIntro <s>` now pins the opening
(`99` shows the home).

Tests:
- `OpeningTests` (13) checks the opening as physics: the Lorentz
  equation, no work done by B, g at release, rest-to-rest arches,
  deep-water dispersion, the ripple starting and ending at rest, no
  overshoot, no jumps, clearance from the face, landing on the bell.
- `PortalDoorTests` (8) replace `GalleryDoorTests`.

PhysicsCore 469/469. App 881/881. Screenshots:
`docs/redesign-shots/step4-swirl.jpg` (t = 0.6 s, the two streams
mid-arch), `step4-ripple.jpg` (t = 1.45 s), `step4-settle.jpg`
(t = 2.25 s, particles drawing the rims), `step4-home.jpg` (end state),
`step4-home-more.jpg`, `step4-window.jpg` (the flat catalog).

### Step 5.0 — the shell: one title bar, one More (2026-10-14)

The lab title bar is now Home, More, the lab's name, and Pause/Resume.
Pause came in from the palette bead.

More opens an ornament beside the window, on the left like every control
in the house. It holds:
- the lab's `more` items and a slider per `adjustables` entry;
- its live Values (the Physics box, folded in);
- Room: Move the lab, Studio Mode, and a dimming slider in place of the
  bead's three-step cycle;
- Settings, and a Reset that arms first instead of opening a dialog.

Removed:
- the palette bead and its six lab discs (`Palette.swift`);
- the in-room Physics box and its rails (`PhysicsBoard.swift`);
- `AppModel.cycleDimming`;
- the Time reel's "Resume here", because the title bar's Resume resumes
  from the scrub in every lab.

Dead assets removed: the gallery's five furniture models, the bead's
three gyroscope parts and the four door-sign titles. That is 12 `.usdz`
files that `PropCache` was warming at every launch. Their generators
`Tools/galleryplatforms.py` and `Tools/vignetteprops.py` went too, and
`Tools/hubtitles.py` keeps only the wordmark's two lines.

Retired arguments: `-paletteOpen`, `-paletteReset`, `-physicsOpen`. Use
`-moreOpen 1`.

Tests: `PaletteResetTests` and `PhysicsBoardTests` were removed, along
with the palette's label, collider and bead tests and the gyroscope prop
tests. `LabMoreTests` is new: every lab has Values, nothing is offered
twice, sliders clamp, the dimming slider clamps, plus Fields' and
Circuits' value rows from the old board tests. Screenshots:
`docs/redesign-shots/step5-shell-more.jpg` (Projectiles with More open)
and `step5-shell-closed.jpg`.

### Step 5.1 — Circuit Workshop (2026-10-14)

Removed from the room: the Views tab and its five plates, the Clear plate,
and the Presets tab and its five plates. In More: Electron flow, True drift
speed (disabled unless the flow is on, since it showed nothing without
it), Magnetic field, Voltage skyline, Clear the bench (confirms, red), and
Load × 5 (each confirms; not red, because loading is not the point of
throwing away).

Cut:
- **Electron view** (`CircuitsModel.electronView`, the renderer's 4× zoom
  floor, `-electronView`). It was the two-hand zoom with a floor.
- **The ring's "Open or close"** on a switch. The lever does it.

Replaced with direct manipulation (shared with every lab): Bloom's grip
was a bead on a rail hanging under the object, and is now a handle on a
stalk pulled out of the object. A part's value stalk leaves the part's
underside, clear of the leads.

Kept: the shelf and its crown, the meter, parts, leads, wires and the
lever, the Replace / Detach / Delete petals, and the AC frequency slider
under a selected source (a frequency has no extent). Values keep the bench
counts and the selected part's V/I/P. When nothing is selected they show
the first two parts, which the in-room readout card (selection only)
never does.

Retired arguments: `-electronView`, `-circViewsOpen`, `-circPresetsOpen`,
`-circClear`.

Controls: **17 visible at open → 9** (crown, six shelf slots, Home, More,
Pause, counting the shelf as 7). **57 reachable → 34.**

Tests: three clearance tests for the retired furniture are gone. The reach
criterion now counts labs whose layers live in More. Screenshots:
`docs/redesign-shots/step5-circuits.jpg`, `step5-circuits-more.jpg`,
`step5-circuits-ring.jpg` (Detach and Delete petals, the value stalk).

Noted, not changed: `CircuitsModelTests.testPresetsAndClearingAreSaved`
waits on a 1 s debounced save with a 1.3 s timer, and failed once under
the parallel run. It passes alone. It is pre-existing and timing-sensitive.
