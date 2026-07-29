# Decisions

A running log of consequential decisions — architectural, physical, or product — and why they were made. Newest first. One entry per decision.

## Format

```markdown
## YYYY-MM-DD — Short title

**Decision:** What was decided, in one or two sentences.

**Context:** What prompted it — the problem, constraint, or alternative on the table.

**Consequences:** What this commits us to, and what it rules out.
```

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
