# Circuit Workshop — Design Review (2026-08-06)

> ## TRIAGED 2026-08-26 — mostly declined for v1. Verdict per number.
>
> This document sat untriaged for twenty days: it was written to be
> reacted to per-number in the headset, nothing in `DECISIONS.md` adopted
> any of it, and an un-triaged review doc is a standing implication that
> work is owed. Here is the answer, so it stops being one.
>
> | # | Verdict |
> |---|---|
> | **C1** ghost landing disc | **Declined for v1.** A new affordance, and `alignment(for:)` + the ghosted `pendingJoins` wires already answer "where will this land" at the moment it matters. |
> | **C2** terminal gravity / dashed preview | **Declined for v1.** Superseded in spirit by the lead-pull rewrite (2026-08-11), which previews the wire *and* its refusal a frame before release. |
> | **C3** armed terminal glows | **MOOT.** Tap-tap wiring was deleted on 2026-08-11; there is no armed terminal to glow. |
> | **C4** wire-length label on the grip hand | **MOOT.** The end grips were deleted on 2026-08-11 — the copper lead is the only thing at an end. |
> | **C5** name the rack flanks SOURCES / LOADS | **Declined for v1.** Two more standing labels in a room whose rule is that the apparatus explains itself. |
> | **C6** glass shelf per rack column | **Declined for v1.** It was to be judged last, and the rack moved on 2026-08-26; judge the geometry on device before adding furniture to it. |
> | **C7** reset re-holsters the probes | **DONE 2026-08-26** — and it was a correctness bug, not polish. Reset reached only the model, so the meter stayed out with its probes wherever you dropped them. See `DECISIONS.md`. |
> | **C8** meter face adopts `BackedLabel` | **Declined for v1.** `setScreen` works and has its own rate limiter; this is a refactor with no user-visible change. |
> | **C9** skyline datum rides the build | **Declined for v1.** Real, but a fixed datum is legible and the fix wants device judgement about a moving baseline. |
> | **C10** ease the Electron View dive + raise dimming | **Half done, half declined.** The easing landed (`CircuitsRenderer`); the dimming raise is declined — the room's brightness is one number now (2026-08-09) and `AtmosphereCriterionTests` allows exactly one departure, already spent on Gravity Lab. |
> | **C11** fault sound on `component.failed` | **Declined for v1.** The audit's own P2-10 says `.pop` already carries seven meanings and there is no refusal sound at all; adding a fifth voice to an overloaded palette is the wrong order of operations. |
>
> The standing rule behind most of these declines: *"improve" means
> refine what exists, not add.* Nine of the eleven are new features.
>
> **2026-10-18 — the owner overrode that rule for this lab** and asked
> for every part redesigned, a better presence on the bench and wiring
> that works smoothly (DECISIONS.md, five entries that day): lab-kit
> parts, a turntable that turns and carries the circuit, joints with a
> collar, a same-net refusal that lights the connection it found, and a
> landing that glides. C1's question — where will this land — is now also
> answered by the glide; C4's "copper lead" is a brass contact.

The deferred revisit, delivered as a document. The owner's brief
(ON_DEVICE_TESTS.md, Deferred): *"Okay I want to revisit this with you
… and we will plan out how to improve this system."* The bug-class
fixes have landed across three passes (the tray→racks move, the
meter/probe frame split, the label pills, the fold sounds); what
follows is the DESIGN pass — what ships today, what reads as
unfinished, and numbered proposals to react to per-number in the
headset. **No code changed with this document.**

Sizing: **S** = an afternoon, **M** = a day-ish, **L** = a working
session with decisions in it. Every proposal keeps the standing laws:
no panels, nothing reachable only from the CLI, colliders never larger
than their visuals, readouts quantise before formatting.

---

## 1. The build flow (well → part → placement)

**Today.** Eleven `Well` sources on two flanks (drivers left, loads
right — `CircuitsPartsLayout`), parts born at the fingertips, sixteen-
component budget with the refusal fade. Placement is free-floating:
parts hang wherever the hand leaves them.

**Reads unfinished.** Nothing suggests where a part WANTS to be. First-
time builds sprawl: parts at wild depths and heights, wires crossing
through the bench volume. The racks teach what exists but nothing
teaches "put the battery down HERE, near the loop."

**Proposals.**
- **C1 (S) — a ghost landing spot.** While a part is carried, show a
  faint disc at bench height under the hand (the pad's hover-ring
  language, `HubSpaceView` podium). Purely advisory — release anywhere
  still works. Screenshot: `-openModule circuits` + carry (device).
- **C2 (M) — gentle terminal gravity.** When a carried part's terminal
  passes within ~6 cm of a free terminal, draw the would-be wire as a
  dashed preview (the `previewTargets` pulse at
  `CircuitsRenderer.swift:695` already highlights candidates — this
  extends it to a drawn preview) and snap-align on release. Makes the
  "copper ends nearly touch: they connect themselves" promise legible
  BEFORE the release.

## 2. The wiring gesture

**Today.** Tap terminal, tap terminal: wired (`CircuitsSpaceView
handleTap`, :644). Terminals swell when probed/previewed; the armed
first-tap state pulses (`pendingPulsePhase`).

**Reads unfinished.** The armed state lives only on the tapped
terminal's swell — from two metres, which terminal you armed is a
guess. And there is no way to CANCEL an armed terminal except tapping
something wireable (a tap on empty space folds rings but does not
disarm the terminal).

**Proposals.**
- **C3 (S) — the armed terminal glows in the wire's colour** and a
  faint dashed line follows the gaze-side hand from it, so "you are
  half-way through wiring" is visible from anywhere. Cancel by tapping
  empty space (symmetry with the ring fold, which now ticks).
- **C4 (S) — wire-length feedback while stretching.** The end-grip pull
  already resizes wires; the wire's pill label already shows length.
  Elevate: while a grip is held, the label follows the grip hand
  (Callout-style) instead of hanging at the part's midpoint.

## 3. The racks

**Today.** Two 2×3 blocks above the furniture row, both at reach-AND-
angle-checked positions (`CircuitsPartsLayout`, tests enforce both).

**Reads unfinished.** The blocks are visually bare — twelve floating
miniatures with pills. Nothing groups them; the drivers/loads split
(the layout's whole thesis) is invisible.

**Proposals.**
- **C5 (S) — name the flanks.** One `namePlate` header per block
  ("SOURCES", "LOADS" — or the owner's words), in the module accent,
  small, above each block. Two entities, zero mechanics.
- **C6 (M) — a glass shelf per column.** The frosted-glass language
  (`Materials.frostedGlass`) as a thin backplate behind each block, so
  the racks read as furniture the way the bank does. Risk: more glass
  in a module that already has the bank + meter; judge against C5
  alone first.

## 4. The multimeter

**Today.** Chassis/probe frame split is correct and tested; probes
latch by terminal id; the face reads volts/amps/ohms with a fault line.

**Reads unfinished.** `reset()` drops the latches but leaves the probes
DRAWN where they were (recorded in DECISIONS 2026-08-03 as "reads
worse now"). And the face's recessed-LCD text is the one bench readout
not on the shared label system (`Multimeter.swift:433-444`).

**Proposals.**
- **C7 (S) — reset re-holsters the probes.** Reset is the one moment a
  deliberate placement is void by definition; park both probes against
  the case. Closes the DECISIONS loose end.
- **C8 (S) — the face adopts `BackedLabel`** for its two lines (keeping
  the bezel), unifying the last bespoke text path on the bench and
  retiring the duplicate mesh cache + rate limiter
  (`Multimeter.swift:416-461` duplicates `Callout`).

## 5. The voltage skyline

**Today.** `-skyline 1` / the bank plate raises translucent towers,
volt pills at the caps (backed since 2026-08-05), threads to nodes.

**Reads unfinished.** The skyline datum (y = 1.62) is a fixed height:
on a tall build the towers start inside the circuit; the threads then
cross the parts they explain.

**Proposals.**
- **C9 (M) — datum rides the build.** Datum = (highest component y +
  clearance), recomputed on component moves (cheap: max over ≤16).
  Threads shorten, towers never intersect the loop.

## 6. Electron View and true speed

**Today.** `-electronView 1` shrinks the bench into the copper; true-
speed mode shows the real mm/s drift; the 50 kT disclosure stands
alone since the particle bank left.

**Reads unfinished.** Entering Electron View is a hard scale jump — no
transition, and the room's dimming does not change, so the copper
interior renders against a bright room.

**Proposals.**
- **C10 (M) — ease the dive.** Animate `benchScale` over ~0.8 s into
  and out of Electron View (the zoom rig already interpolates for the
  two-hand gesture — reuse that path), and raise `preferredDimming`
  while inside, so the interior reads like an interior.

## 7. Feedback inventory (post-2026-08-06)

Sound: parts pop from wells, switches pop, rings pop/tick, grabs tick,
releases answer, faults? — **silent**. C11 (S): a soft low buzz-thud
when a fuse blows or an LED burns out (`component.failed` edges),
volume from the event. Visual: the fault already swaps the nameplate;
sound would make it noticeable while looking elsewhere — this is the
one event on the bench that happens BEHIND your attention.

---

## Suggested order, if all accepted

C7, C3, C5 (the three smallest, each closing a visible gap) → C1/C2
(the build-flow pair) → C8, C11 → C9 → C10 → C6 (judged last, against
the calmer bench the rest produce).

Screenshot staging per proposal: `-openModule circuits -seedCircuits 1`
(bench), `-seedMotor 1` (motor build), `-circuitVoltageHeights 1`
(skyline), `-electronView 1` (the dive), `-circClear 1` (armed plate).
The wiring/carry proposals (C1–C4) are gesture work — headset only.
