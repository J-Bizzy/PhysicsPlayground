# Decisions

A running log of consequential decisions — architectural, physical, or product — and why they were made. Newest first. One entry per decision.

## Format

```markdown
## YYYY-MM-DD — Short title

**Decision:** What was decided, in one or two sentences.

**Context:** What prompted it — the problem, constraint, or alternative on the table.

**Consequences:** What this commits us to, and what it rules out.
```

## 2026-07-29 — A third petal on the bead: settings

**Decision:** The palette bead gains exactly one more petal — a gear, centered between pause and reset, that opens the new settings window and folds the bead. This amends locked decision 4's "two petals" (`HOMESCREEN_SPEC.md` §2.4), which otherwise stands.

**Context:** The settings window (spec §3 item 3) has to open from somewhere that exists in every lab, and the bead is deliberately the app's only permanent interface — there is nowhere else. The alternatives were a persistent chrome affordance (exactly what decision 4 killed) or burying settings in the per-module title bar (absent from the hub, where the arc sliders and recenter matter most).

**Consequences:** The petal layout is now count-generalized (constant 0.17 m span), so adding a petal is mechanically cheap — which is precisely why the bar for a fourth stays where decision 4 set it: a petal must be something you reach for from *any* lab without breaking off what you are doing. This entry does **not** decide §3 item 1's notebook-trigger question.

## 2026-07-29 — Homescreen spec rewritten to v3, design system reconciled to code

**Decision:** Replaced `HOMESCREEN_SPEC.md` v2 wholesale with v3: §1 documents the homescreen as built, §2 locks the nine decisions where the rebuild deliberately diverged from v2 (constellation not arc, shell-free exhibits not cards, no domain headers, the Palette bead not a dock, no Quick Demo, head-direction focus not gaze-hover values, one-shot wordmark, no Search/Daily-Challenge surface, procedural vignettes + `RoomModel` + `SceneEvents.Update`), §3 keeps the surviving open work (notebook surface, coach-mark rendering, settings window, slot-wrap fix). `DESIGN_SYSTEM.md` was rewritten to carry the code's actual color/type/motion values instead of v2's.

**Context:** v2 was written from a screenshot of the pre-rebuild homescreen with no knowledge of the codebase. A full conflict analysis (2026-07-29) found the rebuild had already solved every problem in v2's §1, usually in a different shape, with rationale recorded in code comments — so the spec and the first design-system draft both prescribed values the code had superseded.

**Consequences:** v2's proposals are formally rejected, not merely unimplemented; reopening any locked decision in v3 §2 requires a new entry in this file saying what changed. v3 §3 is the authoritative homescreen backlog. Docs describing visuals must be sourced from code, not from the retired spec.
