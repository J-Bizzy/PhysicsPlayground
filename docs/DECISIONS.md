# Decisions

A running log of consequential decisions — architectural, physical, or product — and why they were made. Newest first. One entry per decision.

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
