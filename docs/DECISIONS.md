# Decisions

A running log of consequential decisions — architectural, physical, or product — and why they were made. Newest first. One entry per decision.

## 2026-07-29 — Two labs, not three: Waves & Optics are cut

**Decision:** Owner's call. The app aims at **two very high quality labs — Electricity & Magnetism, and Mechanics & Energy** — and Waves is archived to `Archive/Waves` with its tests, following the same convention as Springs, ElasticField and Optics. Optics stays archived rather than returning. `HubDomain.waves` is benched (empty module list), which `GalleryLayout` already handles by simply not building that terrace.

**Context:** Waves was my proposed flagship one commit ago, so this reverses that. Two things drove it. The owner could not tell what the module was for, and a measured defect explained half of why: the dot lattice samples the field every 0.30 m while λ at the opening settings is 0.333 m — **1.11 samples per wavelength, below the Nyquist limit of 2**, and 0.22 at the far end of its range. Turning the frequency control genuinely changed the field; the cloud just re-aliased, so the picture changed without informing. And it does not tune away: multiple fringes need source separation ≳ λ, so λ must stay ≲ 0.4 m, and sampling that properly across a 2.4 m region needs a 59³ lattice — 205,000 dots against a 729 budget. The region size and the density cannot both be satisfied.

**Consequences:** Two labs at high quality beats three at medium, which was the brief's own instruction from the start ("five extraordinary modules over twenty average"). The physics survives untouched and tested in `PhysicsCore/Waves` and `PhysicsCore/Optics` — 21 wave tests, the exact retarded-time Doppler, `DoubleSlit`, `RayOptics3D` — so a revival costs a module folder, not a rebuild. The general lesson is worth keeping: **check the sampling rate of a visualisation against the wavelength of what it visualises before believing it shows anything.** A field plot below Nyquist is not a dim picture of the physics, it is a picture of the sampling.

## 2026-07-29 — The dial is rejected; a continuous quantity gets a TRACK

**Decision:** Owner's call: "the dial does not do it for me." `SpatialDial` and `SpatialDialControl` are **deleted**, along with their 22 tests, and replaced by `RenderKit.SpatialTrackControl` — a labelled rail with a bead you put where you want it. This reverses the entry two above that promoted `SpatialDial` from orphan to the instrument replacing sliders.

**Context:** Trying to say *why* it did not work turned up something that also indicts `Bloom`'s grip. A dial is **relative**: it accumulates a signed change in hand angle, so the value depends on the path the hand took and nothing about the control's appearance says what it is currently set to. There is no home position on a circle. A track is **absolute**: the rail is the range laid out in the room, and the bead sits at the value, so the setting is legible from across the room and half-way along means half-way through. That is what every physical fader and thermostat already taught.

**Consequences:** The track is the app's one form for a continuous quantity, and it clears the replacement standard on all three counts — always visible, obviously draggable, and a mouse drag along the rail works in the simulator. Its test burden is also *smaller* rather than larger, which is a good sign: a dial needed testing for accumulation and for the atan2 ±π seam, and a track has nothing to accumulate, so those failure modes cannot occur. What remains worth pinning is that off-axis hand drift does not move the value, and that the same hand position always means the same value. **`Bloom`'s grip is now the odd one out** — it is relative like the dial was — and should be revisited when Mechanics is worked over.

## 2026-07-29 — The panels become READOUTS, not corpses: the exit criterion corrected

**Decision:** Phase 1's exit criterion was "`makeControls` deleted from `ModuleDescriptor`; `grep -r makeControls` returns nothing." That is wrong and is replaced by: **no `Slider`, `Picker` or `Toggle` in any module panel.** `makeControls` survives, renamed in spirit if not in code — a surface that *displays* and never *sets*.

**Context:** Counted before continuing to demolish. The eight panels hold **55 knobs and 71 readout `Text`s** — they are already more than half instrument display. Electric Fields alone has 21 readouts: E, V, F, a, speed, measured flux beside predicted flux. Deleting the panel to satisfy a grep would take the probe values, the Cp, the induced EMF and the energy tallies with it, and those have nowhere better to go: a number you *read* wants to hold still and be legible, which is exactly what a flat card is good at. The lab notebook is flat for the same reason, and nobody thinks it should be a dial.

The interaction law never said otherwise. It governs how a quantity is **changed** — "a quantity with physical extent is changed by changing that extent" — and says nothing about how one is shown. The phrase this session kept reaching for while migrating each control is the actual rule: *the number stays here to be read; setting it is a physical act.*

**Consequences:** The remaining work is 15 sliders, 5 pickers and 35 toggles, and every one of them resolves as exactly one of three outcomes, which must be stated per control rather than assumed: (1) it becomes an instrument or a labelled object in the room; (2) it becomes a readout, because it was reporting rather than setting; or (3) it is **deleted**, because it was display chrome that the law's third clause — "anything that is neither does not get to exist" — refuses. Trail length is the type specimen of (3): three lengths of ribbon is a preference, not physics, and picking the good one is better than asking. Guarding against the opposite error too: a control is not chrome merely because it is inconvenient to make physical. Gravity Lab's time scale looks like chrome and is not — at 1× an Earth year takes two minutes, so the speed IS how an orbit becomes visible at all.

## 2026-07-29 — `SpatialScale` does NOT go to every module: where the room is the apparatus, scaling is a lie

**Decision:** The three-worlds plan's Phase 1 says "`SpatialScale` … to **every** world". That is wrong, and this entry overrides it. `SpatialScale` is a *presentation* transform — it scales a display root while the physics keeps running in true SI units — so it is safe only where **nothing compares a real-world measurement against the display**. Electric Fields, Magnetism, Circuits and Gravity Lab qualify and have it (4/8). Projectiles and Waves are **permanently excluded**. Wind Tunnel qualifies but has a prerequisite.

**Context:** Adoption looked like a box to tick, and three of the four remaining modules turn out to have specific reasons not to.

- **Projectiles must stay 1:1.** Its own header: *"physics space IS the room (1:1, immersive-space coordinates, the real floor at y = 0), so every number on the panels is literally true of what you're looking at."* Balls bounce off the user's scanned walls, are caught by real tracked fingertips, and are thrown at their real arm's m/s. Scale the display and every one of those becomes a fiction — the module that most clearly earns the headset is the one scaling would gut.
- **Waves is excluded for a sharper reason, and it is the flagship's signature moment.** `WavesRenderer` computes the listener's loudness as `WaveField.steadyAmplitude(at: listener, …)` where `listener` is the raw `room.headPosition` and the sources are in the same room coordinates — the true field at the true head. A display-only scale would move the **visible** nodal sheets while the **audible** node stayed where the physics put it. The Silence Walk works because what you see and what you hear coincide at your ears; scaling decouples exactly that. If Waves ever wants scale, the field's own coordinates have to scale with it, which is a physics change, not a view transform.
- **Wind Tunnel wants it most and cannot have it yet.** `WindTunnelRenderer.planePoint(fromWorld:)` is `world − sectionCenter`: plain arithmetic that ignores the root's transform. A constant `LabPlacement.offset` cancels (every grab moves by hand *displacement*, which a translation leaves untouched — that is why the offset has always been safe), **but a scale factor does not cancel**, so a rig would make the cylinder lag or outrun the fingers. Converting through `sectionRoot` is the prerequisite, and it belongs in its own change, verified on device with real hands.

**Consequences:** The test for any future adoption is not "does this module have a `viewRoot`" but **"does anything in this module measure the real room?"** Room-sensing consumers — walls, fingertips, head position as a probe — are the disqualifier, and `RoomModel`'s consumer list is where to check. Two of the app's best moments (a ball off your own wall, silence at your own ears) exist *because* those modules refuse the transform. Also note the general shape of the Wind Tunnel finding: a world-space coordinate helper can be correct under translation and wrong under scale, so "it already works with `LabPlacement`" is not evidence that it will work with a rig.

## 2026-07-29 — The interaction law, and the standard that has to replace a slider

**Decision:** One law governs every control in the app, promoted from `Bloom.swift`'s component rule to the app's constitution: **a quantity with physical extent is changed by changing that extent; a quantity without extent is a discrete choice and gets a labelled object in the room; anything that is neither does not get to exist.** `ModuleDescriptor.makeControls` and all eight window panels are to be deleted — removed, not deprecated, so they cannot return a ninth time. `ShapeFan` (Wind Tunnel's labelled in-room fan) is promoted to the app's only N-way picker.

**Context:** The panels-vs-spatial argument has been re-litigated across 212 commits and the app currently sits on the wrong side of it: `Phase 0 — demolition: the glass comes out` → `the object is the interface` → `dials live on the apparatus now` → … → `the controls come back` → `Every module gets its one-glance panel`. `makeControls` shipped as an explicit single-module exception and all 8/8 modules took it — 19 sliders, 35 toggles, 7 pickers, and every module has at least one knob reachable *only* as a slider. Meanwhile the primitives that make this a headset app went unadopted: `SpatialScale` 3/8, `Well` 3/8, continuous sonification 3/8, `SpatialDial` 0/8. The mundane is universal and the extraordinary is optional, which is exactly why the product reads as simulations-with-UI.

**Consequences:** The panels won for a real reason and the replacement has to beat it on that reason, not on taste. Spatial controls had been built *gaze-revealed*, which is invisible in the simulator and undiscoverable on device — the user's words were "I can't even move them." So the standard is now explicit: **an instrument must be visible without being looked for, operable without being discovered, and reachable in the simulator. Nothing may be revealed by gaze alone, and nothing may be the only path to a capability.** A slider clears that bar, which is why it kept winning; a machined dial on the apparatus clears it too; a gaze-revealed ring does not. Any future `makeControls`-shaped surface needs a new entry here saying which part of the law it breaks and why.

## 2026-07-29 — `SpatialDial` is kept and promoted, not deleted; Circuits' dark features get doors, not graves

**Decision:** Two amendments to the three-worlds plan's Phase 0, both made after reading the code the plan proposed to delete. **`SpatialDial` survives** — it is the instrument that replaces sliders, not dead weight. **Circuits' unreachable features are to be activated, not removed:** the oscilloscope buffer, the five written teaching circuits, the eight save slots, and the `electronView` flag.

**Context:** Phase 0 was written as "mostly deletion" against ~600 lines of unreachable code, on the finding that all of it was the panel half. That holds for most of it, but two items were misfiled. `SpatialDial` is 207 lines with zero callers *because* it was built for Optics, which was cut — and Optics returns in World I, the flagship; its `DialDrag` is pure, wrap-safe, unit-testable twist math, which is precisely the shape the law above demands. And `electronView` gates **Electron View**, which the same plan names the single most quotable moment in the app: electrons crawling at true drift speed while the field front laps the loop at 0.66c. Deleting the flag would delete the door to the demo reel's centrepiece.

**Consequences:** "Dead code" is not one category. Code with no caller because *the surface that should call it was never built* is a missing door, and the fix is a door. Code with no caller because *we decided against the surface* is a grave, and `PendulumsControlsView` — a six-slider window panel, the exact thing the law forbids — is the clear example. Every future deletion in this sweep has to say which of the two it is. `DialDrag` needs unit tests before anything is built on it.

## 2026-07-29 — The submission gates are closed: privacy manifest, export compliance, visionOS 26.0

**Decision:** The app carries a `PrivacyInfo.xcprivacy` declaring no tracking, no collected data, and one required-reason API — `NSPrivacyAccessedAPICategoryUserDefaults` with reason `CA92.1`. `ITSAppUsesNonExemptEncryption = false` goes in `Info.plist`. `XROS_DEPLOYMENT_TARGET` drops from 26.5 to **26.0**.

**Context:** An App Store submission stops on all three. The manifest has been mandatory since 2024 for any app touching a required-reason API, and this one touches `UserDefaults` in twenty files (settings, notebook, completed experiments, every debug launch arg). Without the encryption key every upload stalls on the export-compliance interview. And 26.5 was the newest visionOS in existence — a portfolio app installable by almost nobody. Both packages already declared `.visionOS(.v26)`, so the app target was the lone holdout.

**Consequences:** The claims in the manifest are load-bearing and must stay true: **the project has no networking code at all** — no `URLSession`, no analytics, no third-party SDK — and adding any means revisiting the manifest, not just the podfile. Room geometry and hand poses stay live-read from ARKit and are never persisted or transmitted. The floor is 26.0, so no API newer than that may be used without an availability guard; verified by a signed Release build for `generic/platform=visionOS`, which is the real gate, not the simulator.

## 2026-07-29 — The room's walls become a toggle again; containment goes with them

**Decision:** Kinematics regains a "Bounce off walls" toggle, default ON. When off, `trajectory` predicts with no walls, `strike` is skipped, **and the `contain` clamp returns early** — balls genuinely leave the room. This reverses the invariant set two commits earlier ("walls are ALWAYS on — a ball that leaves the room is a bug, not a setting").

**Context:** The always-on rule was written against a real bug: balls tunnelling out of the room read as the wall feature giving up. But it also removed the ability to watch an unobstructed parabola, which is the actual physics the module teaches — a projectile in a room is a projectile in a box.

**Consequences:** "A ball outside the room" is no longer per se a bug; it is only a bug when the toggle is on. Nothing unbounded escapes regardless: the 30 m `escapeRadius` cull is the backstop that makes the toggle safe, and it must survive any future refactor of the flight lifecycle. The toggle's hint states the consequence plainly ("Off, balls sail through the walls and ceiling") because the setting is destructive to an invariant a user may be relying on.

## 2026-07-29 — The Gallery gains a podium; a tap no longer enters

**Decision:** The hub grows a floor-standing pedestal front and centre. Drag an exhibit to it and the lab docks, turns on a slow turntable, and a "Load ⟨module⟩" button hangs above it. A **tap on an exhibit no longer enters** — it flashes the podium to teach the gesture.

**Context:** Entering by tap made the whole gallery one large accidental-activation surface while merely looking around, and carrying a lab to a pedestal to open it is the more physical grammar the app is built on.

**Consequences:** The focus panel's "Load Module" button is now the only guaranteed way in and is therefore **load-bearing** — it satisfies the standing rule (Electric Fields, 2026-07-29) that every capability stay reachable without gaze-or-gesture dexterity and operable in the simulator. The podium is the delightful path; the button is the reachable one, and neither may be deleted without the other changing. Anything aimed at an exhibit must ask where it *currently* is, not where its puck is: the gaze cone and the caption both consult `aimPosition(of:)`, which answers the podium while docked and the hand while carried.

## 2026-07-29 — The Lab Notebook goes live; the bead gains its fourth (and final) petal

**Decision:** The notebook — model complete since the rebuild, never wired — becomes a real surface: a **capture petal** on the palette bead (pencil glyph; stays open after a capture, chimes) writes the active module's live readings as a timestamped observation; a book button in every module's title bar opens the **Notebook window** (entries as disclosure cards, per-entry delete, clear-with-confirm, CSV and Markdown ShareLinks); the window carries its own Capture button as the simulator/accessibility path. This amends locked decision 4 ("the bead, not a dock") a second time — and sets its ceiling: **four petals is the bead's maximum.** Pause, capture, settings, reset are the four things reached for from any lab; a fifth would be the rail this design replaced.

**Context:** HOMESCREEN_SPEC §3 item 1, owner-approved. The reset dialog has promised "notebook entries are kept" since the settings window shipped; the promise is finally about something.

**Consequences:** Every module's `captureReadings` finally has a caller. The petal span widened 0.17 → 0.22 m. Any future permanent affordance must displace one of the four, not join them.

## 2026-07-29 — Every control ring opens by tap; LookReveal is retired

**Decision:** The gaze-revealed control gating (`LookReveal`) is deleted app-wide. Every module's per-object ring now opens the Electric Fields way — tap the object, ring unfolds; tap again, it folds — via the shared `RingState`. Gaze-driven callouts became tap-driven (Gravity's body readout follows the tapped body) or event-driven (Kinematics' speed/height readout rides the newest ball in flight); Magnetism's strength callout is deleted outright — the ring's rail already shows it. Two more oversized colliders fell to the collider-≤-visual rule: the Kinematics hoop (one 0.2 m sphere filling the opening → eight small colliders hugging the rim) and the Wind Tunnel fan (0.48 → 0.24 m).

**Context:** Gaze-gated controls were unreachable in the simulator and undiscoverable on device — four modules' add/edit capabilities effectively did not exist. The Electric Fields rebuild proved the tap grammar; this extends it everywhere.

**Consequences:** Every capability in every module is reachable with a mouse in the simulator and a pinch on device, and each module has a `-<x>Ring 1` debug arg to screenshot its ring from the CLI. Nothing in the app is revealed by gaze alone anymore.

## 2026-07-29 — Onboarding is the hint, not a coach sequence

**Decision:** The three-step coach-mark state machine (`coachStage`/`advanceCoach`) is deleted — it was write-only from birth: stages advanced, nothing ever rendered a tip. Onboarding is now exactly one surface: each module's authored `firstRunHint` sentence, rendered by the shell in the module window until dismissed (`AppSettings.seenHints`; Settings offers "Show hints again"). The shell also finally renders every module's `legend` as a collapsed section appended after `makeControls` — `LegendView` in `ModulePanel.swift`, fulfilling that file's original header.

**Context:** The App Store readiness audit found the entire guidance layer authored but dark. The hints say everything the coach script said, per module, in context, with less machinery.

**Consequences:** One onboarding mechanism to maintain. Every module's hint must name real, current controls (enforced again in the experiments-repair pass). The shell owns hint and legend presentation; modules only author strings.

## Format

```markdown
## YYYY-MM-DD — Short title

**Decision:** What was decided, in one or two sentences.

**Context:** What prompted it — the problem, constraint, or alternative on the table.

**Consequences:** What this commits us to, and what it rules out.
```

## 2026-07-29 — Electric Fields stripped to two verbs; the invisible scale plate is banned

**Decision:** Electric Fields' scene keeps exactly two interactions — drag to move, tap to select — with everything else on the window panel. The gaze-revealed Wells and Bloom are removed from this module. `SpatialScaleHandle` (the invisible region-covering input plate) is deleted from RenderKit and removed from every module that mounted one (Fields, Gravity Lab, Magnetism); two-hand scale still works by pinching the physics objects themselves.

**Context:** The plate carried an `InputTargetComponent` and a metre-plus collision sphere over the whole region. Hit-testing uses colliders, not visible geometry, so every pinch ray struck the plate's near surface before reaching anything inside — charges, wells, bloom, even the palette bead sat inside its radius. Whole modules were silently non-interactive; the user reported "I can't even move them" twice, and asked for the module to be stripped simple.

**Consequences:** Rule: an input-targetable collider must be no larger than the thing it represents — never a region. Rule: a module's interaction set must be describable in one sentence. Wells/Bloom/LookReveal remain available to other modules (Circuits, Gravity, Kinematics still use Bloom) but each must satisfy: nothing gaze-revealed may be the only path to a capability, and nothing may sit between the pinch ray and the object it decorates.

## 2026-07-29 — The Gallery replaces the constellation

**Decision:** The hub's constellation scatter is replaced by the Gallery: a crescent of four floating graphite terraces, one per physics domain, each carrying its domain's live miniatures on pedestal pucks, with the domain's colour as a lit hairline along its front edge. Geometry is pure, tested math (`GalleryLayout`). The distance/height settings scale the crescent's plan and terrace heights; recenter and the head-ray focus mechanic carry over unchanged.

**Context:** User direction: the homescreen read as "modules in their own bubbles" and should look like a flagship app. The constellation's authored scatter was designed but explained nothing — position carried no meaning a visitor could read. This reverses locked decision 1 ("constellation, not arc") and amends 3 ("no floating domain headers"): domains become physical structure, but there are still no text headers — colour lives in the hairline, the progress ring, and the focus panel chip.

**Consequences:** Domain grouping is now load-bearing geometry: a new module lands on its domain's terrace automatically, a module in no domain extends its fallback slab (the slot-wrap overlap bug is structurally impossible), and a benched domain's terrace simply doesn't build. Focus expresses as a lift off the puck plus a pool of accent light on the pedestal — architecture sits *beneath* the physics, never around it, so locked decision 2 (shell-free exhibits) stands.

## 2026-07-29 — The wordmark becomes persistent

**Decision:** The "Physics / Playground" bubble wordmark hangs permanently over the Gallery's centre, with a champagne rule beneath it. The `hasSeenWordmark` one-shot flag is dead; the settings "Reset tips" now resets only the coach sequence.

**Context:** User direction: the homescreen needs a title. The one-shot rule (locked decision 7) optimised for a calm room, but a gallery without a sign over the door reads as someone's shelf, not a place — and the calm-room concern is answered by the mark living high above the crescent rather than in it.

**Consequences:** Reverses locked decision 7. Branding budget for the room is spent: nothing else persistent gets added on its account.

## 2026-07-29 — Electric Fields regains a window control panel

**Decision:** `ModuleDescriptor` regains an *optional* `makeControls`, rendered by the shell beneath the window title bar, and Electric Fields is the first module to use it: a full labelled panel (add ±, polarity, magnitude, position, test charge, uniform fields, Gauss surface, display toggles). The spatial affordances — wells, bloom — stay, but are gated so they can never intercept a grab: the magnitude bead is interactive only when the bloom is deliberately open, its collider shrank to its visual size, and an anonymous pinch (the invisible scale plate) now falls back to the nearest charge within 12 cm of the hand.

**Context:** The rebuild's "the object is the interface" pass deleted every flat control and left the module's add/edit affordances gaze-revealed. In the simulator (no gaze ray) they effectively do not exist, and the bloom's grip bead sat on the charge's own touch target — so pinching a charge could edit its magnitude instead of moving it, or do nothing at all. The user experienced this as "I can't even move them."

**Consequences:** Spatial-first stands, but every capability must ALSO be reachable through something discoverable and simulator-operable; gaze-revealed controls are enhancement, not the only door. Other modules may opt into `makeControls` with the same bar: only for controls their spatial affordances leave undiscoverable.

## 2026-07-29 — A third petal on the bead: settings

**Decision:** The palette bead gains exactly one more petal — a gear, centered between pause and reset, that opens the new settings window and folds the bead. This amends locked decision 4's "two petals" (`HOMESCREEN_SPEC.md` §2.4), which otherwise stands.

**Context:** The settings window (spec §3 item 3) has to open from somewhere that exists in every lab, and the bead is deliberately the app's only permanent interface — there is nowhere else. The alternatives were a persistent chrome affordance (exactly what decision 4 killed) or burying settings in the per-module title bar (absent from the hub, where the arc sliders and recenter matter most).

**Consequences:** The petal layout is now count-generalized (constant 0.17 m span), so adding a petal is mechanically cheap — which is precisely why the bar for a fourth stays where decision 4 set it: a petal must be something you reach for from *any* lab without breaking off what you are doing. This entry does **not** decide §3 item 1's notebook-trigger question.

## 2026-07-29 — Homescreen spec rewritten to v3, design system reconciled to code

**Decision:** Replaced `HOMESCREEN_SPEC.md` v2 wholesale with v3: §1 documents the homescreen as built, §2 locks the nine decisions where the rebuild deliberately diverged from v2 (constellation not arc, shell-free exhibits not cards, no domain headers, the Palette bead not a dock, no Quick Demo, head-direction focus not gaze-hover values, one-shot wordmark, no Search/Daily-Challenge surface, procedural vignettes + `RoomModel` + `SceneEvents.Update`), §3 keeps the surviving open work (notebook surface, coach-mark rendering, settings window, slot-wrap fix). `DESIGN_SYSTEM.md` was rewritten to carry the code's actual color/type/motion values instead of v2's.

**Context:** v2 was written from a screenshot of the pre-rebuild homescreen with no knowledge of the codebase. A full conflict analysis (2026-07-29) found the rebuild had already solved every problem in v2's §1, usually in a different shape, with rationale recorded in code comments — so the spec and the first design-system draft both prescribed values the code had superseded.

**Consequences:** v2's proposals are formally rejected, not merely unimplemented; reopening any locked decision in v3 §2 requires a new entry in this file saying what changed. v3 §3 is the authoritative homescreen backlog. Docs describing visuals must be sourced from code, not from the retired spec.
