# Decisions

A running log of consequential decisions — architectural, physical, or product — and why they were made. Newest first. One entry per decision.

## Format

```markdown
## YYYY-MM-DD — Short title

**Decision:** What was decided, in one or two sentences.

**Context:** What prompted it — the problem, constraint, or alternative on the table.

**Consequences:** What this commits us to, and what it rules out.
```

(The template sat stranded at line 309, mid-log between two 2026-07-29 entries, until 2026-08-01.)

## 2026-08-07 — The Time Capsule: pause becomes a place you can walk around in

**Decision:** Every module continuously records the last 30 seconds of
its own state. Pausing unfolds a **Time Rail** in front of the
apparatus whose bead is "seconds ago"; dragging it restores the whole
room to a recorded instant, three plates step one physics tick at a
time and resume, and un-pausing runs forward FROM the scrubbed instant,
discarding the future it replaced. The mechanism is **recorded
snapshots**, never reverse integration.

**Context:** The owner asked for one feature that lifts the whole app
rather than a seventh module — something a user would pay for that
genuinely needs the headset's space. Three candidates were weighed (a
spatial graphing instrument, a universal measurement kit, this); the
owner chose this one. It earns the room in a way a flat scrubber never
could: the recorded past is not a timeline widget, it is the experiment
standing still while you walk into it. Everything it needs already
existed — `FrozenVectors` sculpts velocity and force onto paused
bodies, `captureReadings` reads live model state, `SpatialTrackControl`
is a bead on a rail, `TubeMesh` draws walkable paths — so the feature
is mostly the act of connecting them.

**Why snapshots and not reverse integration.** Gravity Lab already runs
time backwards: Verlet is time-symmetric and its clock picker includes
−1× and −20×. It was tempting to generalise that. It does not
generalise. Magnetism's glide and Electric Fields' drift are
overdamped, pendulum and circuit damping are dissipative, and every
module crosses discrete events — bounces, merges, an LED burning out —
that destroy the information a backward step would need. Recording is
the only mechanism that is uniform across six benches, and it is also
the honest one: **a restored snapshot is exact recorded state, not a
re-derivation.** The only re-simulation anywhere in the feature is the
forward run after resume, and the truncation discloses it.

**Recording at the full physics rate (~90 Hz), not decimated.** The
alternative was 30 Hz with interpolation between frames, which is
cheaper and wrong. A 12 m/s ball moves 13 cm per 90 Hz tick and 40 cm
per 30 Hz snapshot, so frame-stepping through a wall contact — the
thing the feature is for — would land on either side of the event and
never on it. And interpolation cannot be defined for most of what is
stored: circuit transients, entity-set changes, `status` enums, a
merge. Full-rate recording deletes the question. Scrub resolution IS
the tick, and every restored state is one that genuinely occurred.
Memory, measured from the structs: 2–4 KB per frame worst case, 2700
frames, so ~7–11 MB for the heaviest module and 2–5 MB typically, one
module recording at a time. The two unbounded arrays in the app —
Gravity Lab's orbit trails and Electric Fields' probe trail — are
excluded from snapshots and rebuilt from the capsule instead, which is
both cheaper and more honest than storing a growing copy per frame.

**The snapshot is the experiment, not the observer.** Dynamical state,
entity sets and physics clocks go in; display layers, bank flags,
selections and anything a hand is holding stay out — scrubbing must not
flip a layer the user just lit, and must never drag a magnet out of a
hand. One module breaks the rule and says so: Electric Fields'
`capacitorOn`, `magneticFieldOn` and `chargesRespond` are not display
layers, they decide the field the recorded motion happened in, and a
cyclotron circle scrubbed back into a room with B switched off would
be a lie about what you watched.

**This is not the retired time-scale rail.** 2026-08-02 retired
Pendulums' g and clock with "this bench stands on Earth, at 1×", and
that entry is still in force. Scrubbing operates only while paused,
only over the recorded past, in units of seconds-ago; it never changes
how fast physics runs. A wearer still cannot ask Pendulums for 0.5×.
Gravity Lab's picker and the rail answer different questions — how time
runs versus what already happened — and the capsule simply records
wall-clock frames of whatever the picker produced, at any sign or
scale.

**The coverage lesson, applied before the defect rather than after.**
Six modules have shipped a `reset()` that forgot a flag, and each fix
was a test LISTING the flags somebody had thought of — the same act of
attention that missed them. A forgotten snapshot field is that defect's
next costume: invisible until a scrub quietly lies. So the guard is
behavioural, not a list. `TimeCapsuleRoundTripTests` restores to
mid-window and re-steps with the identical dt sequence; any dynamical
field missing from a snapshot makes the replay diverge measurably.
That is what caught Pendulums' substep `accumulator` (drop it and every
restore re-enters the swing up to 1.4 ms out of phase) and what keeps
Magnetism's angular-velocity map in, without which a scrubbed inertial
needle comes back at rest and the overshoot the mode exists to show
disappears exactly when you look at it.

**Consequences.** `ModuleDescriptor` gains a non-optional `timeScrub`,
so a seventh module cannot forget to answer for it. Every module's
pause petal now routes through `togglePauseRespectingScrub`. Circuits'
save-to-disk is gated on not being scrubbed, or a rewind you were only
inspecting would become the bench you find next launch. Renderers get a
`scrubNonce` to reseed presentation caches across a discontinuous
state jump. And the rail's placement was got wrong three times in a
row by reasoning about it — the fix came from logging `visualBounds`
and discovering the control had been in the room, enabled and opaque,
below the frame, the whole time. **APP_STORE.md is deliberately
untouched: nothing is sold before it has been judged on device.**

## 2026-08-03 — The gallery gets a grab bar; the Settings "Gallery" section dies

**Decision:** The hub gallery is moved by a native-style grab bar — a
slim glass capsule under the pad — dragged like a visionOS window bar,
with a tap recentring it toward the wearer. Position and yaw persist
(`GalleryPlacement`, `hub.galleryOffset`/`hub.galleryYaw`) so the room
opens exactly where it was left. The Settings window's whole "Gallery"
section (distance/height sliders, Recenter) is deleted, along with
`arcDistance`/`arcHeight`/`hubYaw`/`layoutVersion` on AppSettings.
Placement is a per-frame transform on `HubScene.root`; `build()` is
idempotent as insurance.

**Context:** The owner found the sliders DUPLICATED the gallery: each
commit bumped `layoutVersion`, which rebuilt the RealityView over a
`@State` scene that survived the teardown — `build()` was additive, so
every reposition stacked a second gallery on the first. The fix the
owner asked for was the native one: "add some way the user can change
its position in the actual home, just like how the AVP has a little bar
underneath native UI … and have the program remember its position."

**Consequences:** Moving the gallery never rebuilds anything, so the
duplication bug is structurally gone. Settings shrinks again, in line
with the no-flat-controls doctrine — a position is a spatial fact, not
a slider. The focus math converts the look ray through the full root
transform now (translation included), which the orientation-only
inverse would have broken.

## 2026-08-03 — The invisible walls come down; only the simulation stays fenced

**Decision:** No hand-drag in the app meets an invisible wall. Electric
Fields' `clampToStation` comes off `moveCharge` and `movePlate`, and the
escort mechanism dies with it; Magnetism's drag clamp likewise. The one
boundary a hand still meets is the real floor. What survives is a
room-scale SAFETY box per module (~2.6 m half-extents) applied only to
the free simulation — drifting charges, gliding magnets — so nothing
integrates off to infinity. This supersedes the ARCHITECTURE.md
paragraph that said the clamps were "kept on purpose"; that paragraph
now records the split.

**Context:** The owner, on device: "I'm not a fan of these invisible
walls. Please remove them in all modules … this is a full roomscale
application; I want the user to feel like they are in the physics
itself." The walls were born when three stations shared one room; the
merged world was undone on 2026-07-30 and the walls kept enforcing
clearance from neighbours that no longer exist.

**Consequences:** A charge or capacitor can be carried anywhere in the
room. `regionHalfExtents` survives only as the nominal layout volume
that instrument clearance is measured against. `FieldClampTests` now
pins the ABSENCE of walls (a 3 m drag must land 3 m out) as well as the
safety box, so rebuilding a wall fails the build.

## 2026-08-03 — The compass grid comes out; the hand compass stays

**Decision:** Magnetism's 245-needle compass lattice is removed — the
renderer's grid, the `showCompasses` flag, and the "Compass grid" bank
plate (the bank is four plates now). The single hand-held spherical
compass stays, and gains N/S pole letters.

**Context:** The owner's on-device pass: with the field-line loops
carrying the field's shape, the lattice read as noise — and it was the
thing that visibly grew when the strength bead moved (more grid points
clearing the weak-field cull) while the loop count did not, which made
the bead look broken. The loop-count fix lands separately; the grid
would have been noise either way.

**Consequences:** The legend's "the compasses are its strength" claim
dies with the lattice. `-magLayers 0` now reaches three of the four
plates (`earthFieldOn` still has no argument).

## 2026-08-03 — The room occluder comes off the scene; sensing stays

**Decision:** The scene-reconstruction occlusion mesh — `occluder` in
`RoomModel`, mounted by `RoomOcclusionView` — is removed. The view
survives as `RoomSensingView`, a bare retain/release holder, because
the ARKit session itself is load-bearing everywhere: `lookRay` (hub
focus), hand obstacles, wall bounce, and the `bounds` every renderer
clips against all ride it. Field-line clipping to the scanned room
KEEPS working; only the drawn occlusion mesh goes.

**Context:** On device the mesh read as "strange black shadows almost
molding my room's shape" that cut off any UI behind them — the owner
asked for it to go if it served no practical purpose. Its purpose was
realism (virtual light passing behind real furniture); the cost was
whole controls vanishing behind a couch-shaped hole.

**Consequences:** Virtual content now draws over real furniture instead
of being hidden by it. If occlusion ever returns it should be selective
(physics objects only, never instruments), and it starts from this
entry's history.

## 2026-08-03 — Electric Fields slims: the flux meter and the particle bank come out

**Decision:** Two removals from the same on-device pass, at the owner's
direction. The Gauss flux meter leaves the prototype whole — the
bubble/disc surface, `GaussGrab`, both bank plates ("Flux meter" and
"Open disc"), the readout, the `-emGauss`/`-emRadius`/`-emTilt`
arguments, and the `field.gauss` experiment (replaced by
`field.cyclotron`, the circle the module still draws). The four-disc
particle bank goes too, and electron/positron mode with it: the probe is
always the 0.5 g charged ball, its sign chosen by which well mouth it
came from. The bank drops from six plates to four. `GaussSurface` and
its tests STAY in PhysicsCore — the math is portfolio work; only the
app's use of it dies.

**Context:** "GET RID OF THE FLUX METER, DISK AND UI BUTTON. I DO NOT
WANT IT IN THE PROTOTYPE" and "get rid of these 4 buttons … I don't see
the use." The electron mode existed only through those buttons, and its
whole apparatus (a second B rail, a display clock, two disclosures)
served a choice the owner never used.

**Consequences:** The 50 kT disclosure loses its "pick the electron"
escape clause and stands alone. `-emParticle` narrows to `plus|minus`.
Anyone restoring the e/m demonstration starts from the 2026-08-03
history, where the mode, its rail, its tests and its disclosures are
all intact.

## 2026-08-03 — Foucault comes out, whole

**Decision:** The Foucault feature is removed entirely at the owner's
direction, after the first on-device pass: the "Earth turns" bank plate,
the latitude globe, the spin rail, the Panthéon marker ring, the model's
latitude/spin/precession state, the `-penFoucault`/`-penSpin` arguments,
and — unlike previous cuts — the physics too: `EarthRotation`, the
Coriolis term in `SphericalPendulum.step`, and the sine-law recovery
tests leave PhysicsCore. Pendulums' bank has four plates now.

**Context:** The owner tried it in the room and did not like it
("Get rid of this feature entirely"). This is the one removal that takes
tested physics OUT of PhysicsCore, against the archive philosophy that
cut modules keep their math — recorded here precisely because it is the
exception. Git history holds all of it: the theorem-recovery suite
(`FoucaultTests`), the honest-exaggeration design (true rate quoted
beside a ×3000 display spin), and the marker-ring record.

**Consequences:** `SphericalPendulum.step` loses its rotating-frame
parameter and is an ordinary spherical pendulum again. The module's
signature moment is gone; the cradle cold-open, the double pendulum and
the true 3-D orbit carry the room. Anyone restoring the feature starts
from the 2026-08-03 history, not from scratch.

## 2026-08-03 — Pendulums' period labels stay bespoke, and the doc-rot audit pays its debts

**Decision:** Two things from the same audit. First, a divergence is
ratified rather than fixed: Pendulums renders its per-bob period labels
with raw `generateText` and a bespoke dictionary instead of the shared
`RenderKit.Callout`, and it stays that way. Second, a sweep of stale
counts and dead examples is corrected in place — the Palette header now
admits all four petals (capture had been left out of its own file's
story), the seven-slot arithmetic says when it was seven, HubSpaceView's
nine-exhibit comments say six, `AppModel`'s debug example names a real
module id instead of the merged-worlds-era `em`, and the app file's
header stops describing a control panel that no longer exists. The five
first-run hints that never mentioned the room-sensing prompt now do —
Kinematics was the only module warning that visionOS would ask, and the
ARKit dialog fires on FIRST module entry, whichever module that is.

**Context:** The pre-submission audit flagged the label divergence as
the one module bypassing a shared primitive. It is deliberate: a
Callout is one tethered line with its own throttling, and five bobs
each need a label that rides its bob every frame — the multi-bob case
is what the bespoke path exists for. What it costs (Callout
improvements do not reach this module) is accepted; what was missing
was this paragraph. On the doc-rot: this project polices stale prose
aggressively and still grew seven instances of it, all counts from
earlier eras. The transferable part: every one of them was a NUMBER —
counts rot faster than nouns, because a rename breaks the build and a
recount breaks nothing.

**Consequences:** Comments that reason from arithmetic now date the
arithmetic ("sized when seven slots shared the 150 degrees") rather
than silently keeping numbers a later reader will check against the
wrong catalog. A first-run wearer in any module has been told the
permission dialog is coming. And the Kinematics ball moves off its
hand-typed `SimpleMaterial` onto the material canon (`energized`,
glow 0) — the exact call-site tell the 2026-07-30 canon entry names —
with a device check added to ON_DEVICE_TESTS.md because a material
judgement is a passthrough judgement. Not unified: `syncBloom(dt:)`
vs `syncBloom(renderer:dt:)` across modules — the signatures differ
because the needs differ, and adding an unused parameter to two
modules to make a grep tidy would be the wrong kind of consistency.

## 2026-08-03 — The archived five lose their miniatures; magInertia loses its release read

**Decision:** Two removals from the pre-submission audit. The five
vignette builders for archived modules (`waves`, `windTunnel`,
`springs`, `elasticField`, `optics` — ~270 lines in `HubVignettes.swift`)
are deleted, along with the nine colour tokens only they still
referenced and the `podAccent` environment key nothing has written since
the panels went. And `MagnetismModel`'s two `magInertia` reads move
inside `#if DEBUG`, making them consistent with every other
launch-argument read in the app.

**Context:** The builders were kept so that restoring an archived module
was genuinely one line, art included — but they were the only dead code
compiled into the shipping binary, and `make(for:)` had no case that
could reach them. The restore path survives in git history, which
`Archive/README.md` now says explicitly; a restore was already "a merge,
not a `git mv`". `podAccent` was read by both house button styles but
written by nothing — `ControlPod`, its only writer, was deleted
2026-08-01 — so every button was already rendering the default and the
customization point was a fiction. The `magInertia` gating settles what
2026-08-03's inertia entry left open for v1: the mode's touching-pair
oscillation (it grows rather than settles) is PARKED, not fixed. A
release build now structurally cannot reach the defective path; the
judged-on-feel comparison the flag exists for stays available in every
DEBUG build.

**Consequences:** Restoring an archived module now starts with
`git log -- PhysicsPlayground/Hub/HubVignettes.swift` for its miniature.
The two button styles name `.accentColor` directly, and a future
module-tinted button passes its colour explicitly to `.podProminent(_:)`
— the environment route is gone, not dormant. The inertia bench's
contact damping remains an open problem with a test hook waiting in
`ON_DEVICE_TESTS.md`; fixing it is post-launch work.

## 2026-08-03 — Circuit Workshop's tray becomes two racks on the flanks

**Decision:** The parts tray is deleted. In its place, eleven `Well`
sources stand free on the two flanks — two blocks of six, each two
columns wide and three rows tall, above the bench's furniture row. Left
is what drives or interrupts a circuit (battery, AC source, switch, fuse,
wire); right is what the current does (resistor, capacitor, inductor,
bulb, LED, motor). Geometry lives in a new `CircuitsPartsLayout` with
tests, the module's first.

**Context:** User direction — put the parts at the sides of vision
instead of on a workbench. It also closes the app's last hold-out against
a decision already made everywhere else: "the glass came off"
(2026-08-01) replaced every container with the object itself, and
Circuits was the one module that never got that pass. Its tray was
therefore the one surface a visitor touches first that was still built
the old way.

Two defects came out with it, neither of them the reason for the change.
The tray hung off `viewRoot`, so it **scaled with the zoom** — at the
two-hand maximum of 8× it was eight times oversized with its centre
around y = −0.59 m, under the floor — while the meter, the layer bank and
the selected-part readout all compensate for the rig and say so. And at
the sixteen-component budget the tray's pinch **did nothing and said
nothing**; `Well` has had a refusal fade for exactly this since it was
written, because "a lab at its budget used to chirp and flinch and hand
back nothing".

**Consequences:** Parts are now born AT THE FINGERTIPS rather than at the
source and flown to the hand, so making a part and moving a part are one
gesture — the whole point of the primitive. The palette resolves by
entity through `Well.pull` instead of by parsing a `"tray-<kind>"` prefix
off an entity name, so a rename can no longer fail silently as a part
nobody can make. `makeBody` and `copperMaterial` became static so a
preview can be built before any renderer exists; the previews ARE
`makeBody`, so what you see and what you get cannot drift.

**The layout lesson, which is the transferable part.** The first build
put the columns at |x| = 1.02, z = −0.62. It passed the reach check with
3 cm to spare and was unusable: 59° off the forward axis, hard against
the edge of the frame, "Battery" reading "…ery". `FieldInstrumentLayout`
records the identical mistake at 61° and this file's own `clearAnchor`
note calls it "reachable by the arithmetic, invisible in practice" — the
third time in this project. **Reach and angle pull against each other:
pulling an instrument nearer in z buys reach and spends frame.** Checking
only the one you thought of proves nothing, so `CircuitsPartsLayout` now
declares both and the tests assert both.

## 2026-08-03 — The meter and its probes become separate objects

**Decision:** `Multimeter` splits its entity graph in two. A new `chassis`
carries the case, dial, face and nameplate, and takes BOTH of the meter's
movements — the anchor a hand drags it to, and the yaw that turns its
face toward whoever is reading it. `root` carries neither: it sits at the
renderer's identity and exists only to hold the meter's two halves side
by side, so the probes under it are expressed in a frame nothing moves. A
probe a hand has placed is moved by nothing but another hand. A probe
still in its holster is re-parked against the case every frame, so it
follows the instrument wherever it goes. The lead absorbs the difference.

**Context:** User report, from inside Circuit Workshop, in two rounds —
first that the prongs moved when the wearer moved, then that they moved
when the meter did. Both were the same defect at different depths: the
probes were children of an entity that had a job of its own, so the tips
inherited a movement nobody had asked for. And both were worse than a
cosmetic drift, because the latch is by terminal id rather than by
position: the meter went on reporting a measurement at a contact the
probe was visibly no longer touching.

The first fix moved only the yaw onto the chassis, and left the anchor on
`root` on the reasoning that leads plugged into a meter you pick up come
with it. That reasoning was wrong for this object — a probe is placed on
a terminal deliberately, and tidying the instrument is not a reason to
undo the placement. The owner's framing settles it: **treat them as
separate objects, and let a hand alter one at a time.**

**Consequences:** The rule this is an instance of: **nothing a hand can
place may live in a frame that something else moves or turns.** Two
frames, two jobs — where a thing is, and which way it faces — and
anything positionable belongs to neither, it belongs to the world.
Turning or carrying the meter now costs the jacks a transform when the
leads are drawn, which is correct and was previously free only because it
was wrong; the lead is the one part of the assembly that is supposed to
change shape. Not addressed: `reset()` drops both latches but leaves the
probes drawn wherever they were. That predates this change and now reads
worse, because a placed probe genuinely stays placed.

**A note on the tests, which is the transferable part.** The first test
written for this passed against the bug it was written to catch. It
asserted on `probeTip` — a coordinate expressed in the very frame that
was being rotated, so it never changed while the probe moved anyway. Both
new tests and the pre-existing meter-drag test now read the ENTITY's
world position instead. Any test about what a wearer sees must read the
scene graph, not the variable the scene graph was built from.

## 2026-08-03 — The podium loses its column; the pad floats

**Decision:** The gallery's docking spot is a floating plate. The 1.05 m
graphite column under it is deleted, the plate keeps the exact height the
column gave it, and a second, smaller ring of the champagne light hangs
4.5 cm below it and brightens with the pool on its face. Wearer-facing
copy says **pad**; the identifier `podium` stays throughout
`HubSpaceView` as the name of the spot.

**Context:** User direction — "get rid of the podium stand, I just want
that little disk to be floating." It also settles an inconsistency the
gallery had been carrying: everything else in the room floats (the two
terraces, the wordmark, every exhibit on its puck), and the plinth was
the one object claiming to know where the floor was. It does not know.
`y = 0` is where the wearer happened to be standing when the immersive
space opened, not their floor — the same error that killed the light pool
on 2026-07-31 — so the column's foot was planted at a guess, on the one
object the eye is asked to go to.

**Consequences:** No geometry moved: `podiumTop`, the snap radius, the
hint and the Load button are all measured from the plate's face and were
untouched by the deletion, so the carry gesture and the `-hubDock`
screenshot path behave exactly as before. The hover ring is doing real
work and is not decoration — a floating slab with nothing under it reads
as a plinth whose column failed to build, and the ring is what makes the
suspension look chosen. Anything added under the plate later must not
reach for the floor; only `RoomModel`'s scanned geometry knows where that
is.

## 2026-08-03 — The pad's Load button stops being the panel's button

**Decision:** The button hanging over the pad is its own view
(`HubLoadButton`), not a second instance of the focus panel's: the
module's own SF Symbol in a disc of its accent, "LOAD MODULE" small and
letter-spaced above the module's name at `.title2`, a trailing chevron,
and a hairline of the accent inside the glass capsule. Roughly double the
old height and about as wide as the plate it stands over. The focus
panel's button is unchanged.

**Context:** User direction — bigger, and better looking. Both buttons
were `Label(…, systemImage:) / .callout / .borderedProminent`, which made
the delightful path (carry a lab across the room and set it down) end in
exactly the furniture of the reachable path (pinch a button on a card).
The two buttons are not the same job: one sits in the type rhythm of six
rows on a crowded panel, the other hangs alone in the air over a single
object and is the payoff for the carry.

**Consequences:** `.buttonStyle(.plain)` buys the custom look by giving
up the platform's hover highlight, so the view carries
`.contentShape(.hoverEffect, Capsule())` and `.hoverEffect()`
explicitly. On visionOS that highlight is not decoration — it is the only
signal that your gaze is on the button and a pinch will land, and a
prettier button you cannot tell you are aiming at is a worse button.
`podiumButtonLift` went 0.20 → 0.23 m for the same reason the original
0.34 → 0.20 happened: the gap that matters is to the card's bottom edge,
and that edge dropped when the card grew.

**The five entries below were written on 2026-08-03, after this log had
fallen twelve commits behind.** Everything in them is drawn from the
commit messages and the code; where reasoning is reconstructed rather
than quoted it is marked *(inferred)*, and the owner should correct or
strike those lines. The lesson is its own entry at the bottom.

## 2026-08-03 — The magnets get mass, behind a flag, and it does not settle at contact

**Decision:** `PhysicsCore.DipoleDynamics` gives a bar magnet mass and
rotational inertia, and `MagnetismModel` gains `inertiaOn`, reached by
`-magInertia 1`. **The overdamped glide remains the default.** Both
benches ship at once so the owner can judge them side by side on device.

**Context.** `MagneticField` has always returned the exact dipole B,
force and torque — it even swaps in a finite two-pole bar where a point
dipole would be wrong near the poles. The bench then moved its magnets by
a MOBILITY law: velocity proportional to force, angular rate proportional
to torque, both capped by two tuned gains. Exact fields, quasi-static
motion. The consequence is one specific thing a magnetism lab is expected
to show and this one could not: **a needle released at an angle swings
PAST north and rings back.** Nothing without inertia can overshoot.

**THE MASS IS DERIVED, NOT INVENTED**, which is what separates this from a
second set of tuned constants. A permanent magnet's moment is its
saturation magnetisation times its volume, so m = M_s·V fixes the volume,
the length fixes the cross-section and radius, and the alloy's density
fixes the mass and hence I = m(3r² + L²)/12. A magnet you make stronger
becomes a bigger, heavier bar — and therefore slower to turn. Nothing in
the file is free to be tuned for feel except the damping, which is stated
as the one tunable number and is defended as what a lab does anyway
(a needle on a jewelled pivot in oil settles in a few swings, not
minutes).

The numbers that fall out are a sanity check in themselves: the bench's
6 A·m² magnet is a 16 cm bar, 7 mm across, weighing 45 g, with a period
of about 3.5 s in Earth's field. Those are all plausible objects, and a
test says so — because every relation above can hold while the derivation
still produces something absurd.

**Tests are theorem recovery.** Nothing asserts that
`smallOscillationPeriod` returns 2π√(I/mB); a swing is integrated and its
period measured, at three field strengths, and the 1/√B scaling is the
real claim. Energy is conserved undamped and falls monotonically damped —
the latter is why the drag is applied as a decay factor rather than
−γv·dt, which at a coarse step can overshoot into negative velocity and
pump energy back in.

**AND IT DOES NOT SETTLE AT CONTACT. Stated here because it is the reason
this is behind a flag rather than the reason it should not ship.**
Two inertial magnets touching keep moving: the angle's variation over the
last second GROWS from 1.28 rad at t = 10 s to 2.82 rad at t = 300 s.
Measured, not suspected. The damping is not the culprit — at 0.9 s⁻¹ over
five minutes any free rotation is gone many times over. The driver is the
contact: `separated()` resolves an overlap by MOVING a magnet, which does
work against an attraction that is enormous at that range, and the field
pulls it straight back. `killVelocityIntoContacts` removes the closing
velocity and does not stop the positional pump. It is the same standoff
`softenedAtContact` was written to defeat for the glide, met again where
a projection-based contact and a real inertia collide.

So the inertial bench is honest in free field and unfinished at contact.
`MagnetismInertiaTests` asserts what is actually true — bounded, inside
the station, finite, with the moment's magnitude surviving any amount of
rotation — and its name says it does not settle, so nobody reads a
passing suite as a claim that it does.

**Consequences.** Whichever bench wins, the legend gained a disclosure in
the same pass saying the default one glides rather than accelerates,
because that had never been said. If the inertial bench is adopted, the
contact pump has to be fixed first and this entry is where the reason
lives. If it is rejected, `DipoleDynamics` is tested physics with no
app-side caller, which is the standing this project already gives
`CurrentLoop`, `Induction` and everything in `Archive/`.

## 2026-08-02 — Pendulums' right-hand column comes out; g and the clock are RETIRED

**Decision:** Owner's call. The "Resonance ×5" verb plate, the three
world discs, and the two rails under them (g and the time scale) all come
off the wall. `loadResonancePreset` is deleted outright. What is left in
the room is the swing, the two well mouths that make one, the five-plate
layer bank, and Foucault's globe and spin rail — which appear only while
the Earth is turning.

**Context:** The furniture came out in the same commit that fixed the
module's dead side controls, and the cause there is worth keeping
separately: Pendulums was the only module attaching its tap as a plain
`.gesture` after a `DragGesture(minimumDistance: 0)`
`.simultaneousGesture`. A zero-distance drag claims the touch the instant
it lands, so a plain `.gesture` tap composed against it never resolves —
every plate, disc and rail died while the bobs, which are *dragged*, went
on working. **What settled it was the owner's observation that only ONE
module was affected, which turned a guess into a comparison.** Two
earlier explanations (a sibling tap recogniser, then attachment
colliders) were wrong, were fixed on their own merits, and were not the
cause.

**Consequences, and this is the part that needed writing down.**
`gravity` and `timeScale` are still real properties of the model and
still driven by `-penGravity` / `-penTime`, so it is tempting to record
this as "the physics stayed, only the furniture went". Stated that way it
collides with the standing rule that **nothing may be reachable only from
the CLI**. It does not actually break that rule, and the precise reason
is the entry: these are **retired capabilities, not hidden ones.** A
wearer is not offered g or the clock at all — this bench stands on Earth,
at 1×, and the two arguments exist so a screenshot can put it somewhere
else. The rule forbids a capability the user is meant to have and cannot
reach; it does not forbid deciding they should not have one. Anyone
restoring either must restore its rail in the same commit.

`loadResonancePreset` is **a grave, not a missing door** — the
five-length beat demonstration was decided against, not left half-built.
Its deletion took two comments with it, and the commit says why: *"a
comment naming a function that does not exist is the doc-rot this project
keeps catching."* That instinct was right and did not go far enough. Six
further places still promised "five-pendulum resonance" the next day —
`README.md`, `docs/APP_STORE.md` (**App Store submission copy**),
`docs/ON_DEVICE_TESTS.md` (a manual test step for a deleted control),
`CLAUDE.md`, and `PendulumsModule.blurb`, which is also the hub exhibit's
VoiceOver label and is therefore *read aloud*. All corrected 2026-08-03.
**The generalisable rule: deleting a feature is not done when the code
compiles; it is done when nothing in the repository still sells it.**

## 2026-08-02 — Pendulums opens with a cradle, and gains a chaotic cousin

**Decision:** Newton's cradle becomes the module's cold open, and the
double pendulum gets its own well mouth. `PhysicsCore` gains
`DoublePendulum` (exact Euler–Lagrange, RK4) and `BobCollision`
(1-D elastic along the line of centres, resolved pairwise **in order**).

**Context:** The cradle *asks a question before it demonstrates
anything* — almost nobody who has seen one can say why ONE ball leaves
rather than two slower ones. That is a better first sentence than the
five-length resonance wave it replaces, which demonstrates beautifully
and asks nothing. Five identical bobs, because equal masses swap
velocities exactly and a cradle of mismatched balls does something much
less tidy.

**The "one ball out" behaviour is not written anywhere, and that is the
whole claim.** Nothing counts balls. It falls out of resolving contacts
pairwise in order along the line — the impulse crosses as a compression
wave, one contact at a time. A simultaneous five-body solve conserving
both momentum and energy *also* admits two balls leaving at reduced
speed, which is not what real cradles do. So the ordering is the physical
model, and the test asserts the consequence rather than the rule.

**Collisions are for SIMPLE pendulums only, and that is physics rather
than a shortcut:** a double pendulum's bob hangs on a rod whose reaction
to an impulse involves both angles at once, so applying a 1-D exchange to
it would inject energy through a constraint the exchange knows nothing
about.

**The double pendulum is planar, deliberately, in a module whose single
pendulum is fully 3-D.** The planar equations are exact and therefore
*checkable*; a 3-D double pendulum has no comparable closed form, so
"exact" would quietly become "plausible" — and the difference between
those two words is this project's whole claim.

**Chaos defeats the obvious test**, so nothing stores a reference
trajectory (that would pin one machine's floating point). What chaos does
not touch is tested instead: energy conserved to a thousandth over twenty
seconds of genuinely chaotic motion, both small-angle normal modes
matching ω² = (2 ∓ √2)g/L, return-to-home after one slow-mode period, and
degeneration to a simple pendulum as the lower mass vanishes. **The
divergence test asserts AMPLIFICATION, not separation** — exponential
growth is a statement about a ratio, and the first version asked for
0.1 rad after twelve seconds against a Lyapunov exponent of ~0.6/s, so it
failed on a system diverging perfectly well. A test measuring the wrong
quantity, not a physics fault.

**Consequences:** The length bead moves to the pivot collar — cable
length is the one quantity a pivot owns, where it hangs is a drag on the
collar itself, and mass and delete belong to the bob. Three defects were
found by looking rather than reasoning: five identical bobs stacked five
identical "T = 1.49 s" labels into one smear (a crowded rig labels only
its selection now); `testFrictionToggleMakesThePendulumIdeal` swung what
is now a cradle ball and would have been asserting that a cradle does not
work; and a cradle test sampled speed at 1.2 s, where the far ball is at
the top of its swing and speed is zero — peak displacement has no phase
to get unlucky with.

## 2026-08-02 — Circuits and Magnetism stop being one apparatus

**Decision:** The coil annex is gone — `EMFieldStation`, `EMFeedLine`,
the coil switch, the cable, `-emLink`, and the whole electromagnet half
of `MagnetismModel` (`electromagnetOn`, `coilCurrent`, the dipole, the
moment, and the induction gated entirely on it). **Neither module's
directory mentions the other's model now, in either direction.** In its
place, Circuits gains a **Magnetic field layer**: every wire on the bench
carries a field.

**Context:** This closes the one exception 2026-07-30 carved out of "an
experience gets the room to itself" — the planned pair that was *wiring,
not layout*. The annex answered "a current is a magnet" by standing a
second apparatus in the room and cabling to it.

**What replaces it makes a SMALLER and truer claim.** The new layer
answers the same question with the bench you already built, and every
wire has a field around it — not just one wound into a coil. That is the
more general fact. The field is exact: `PhysicsCore.WireField` gives the
closed-form field of a finite straight segment, and a bench is a chain of
segments, carrying the currents the nodal solve put through them, signed
by direction of flow. **Take the signs out and a loop's two sides would
reinforce instead of oppose — the one error that would look plausible.**

**Two rendering faults, both caught by looking.** A volume grid at a
useful pitch is ~2,200 samples against a 260-arrow pool, and the pool
takes the first ones handed to it — so the entire budget went to the
lowest-x slab and the field appeared as a wall of arrows stacked against
the left edge of the room, nowhere near a wire. And rings around each run
beat a coarser grid: what is worth seeing is that **B circles a conductor
and reverses when the current does**, and a sparse grid samples mostly
empty room. The vector at each point is still the total field from every
segment, so nearby wires visibly reinforce or cancel.

**Recomputed every frame rather than change-gated**, unlike the electric
field module's trace: a few hundred closed-form evaluations with no mesh
work, and the field must follow a current that changes continuously as a
capacitor fills or a switch closes. Gating on "did the circuit change"
would freeze the arrows during exactly the moments worth watching.

**Consequences:** Three experiments went (`em.powered`, `em.reach`,
`em.faraday`) and four test files with them. `CurrentLoop` and
`Induction` stay exactly where they are in `PhysicsCore`, with their own
tests, having simply lost their app-side caller — the same arrangement
the archived modules have, and deliberate rather than an oversight.
`StationDebug.swift` is deleted as a **grave**: it existed only to stage
the annex.

## 2026-08-02 — The title bar loses two buttons; the legend key moves to the notebook

**Decision:** The module-switch menu and the legend's Key popover come
off the title bar. What remains is navigation, identity, and the things
you reach for *while working*: notebook, place-the-lab, studio, reset.
Four buttons, and the window frame comes back from 740 to 620 points —
"Circuit Workshop" still does not truncate, which is the name that broke
it at 560.

**Context:** Switching labs goes back through the chevron to the catalog,
which is where choosing belongs. **This project has now arrived at
"choose at the front door" three separate times from three different
directions.** Worth recording that the palette bead does *not* carry lab
switching either, despite being the obvious place to look: its four
petals are pause, capture, settings and reset, and a fifth was refused on
the record (2026-07-29).

**The legend could not simply go with its button, and the reason is
specific.** Six of its entries are **disclosures**, and nothing else in
the app carries them — Magnetism's says line density is not field
strength and that Earth's 50 µT runs 65° into the ground; Pendulums' says
the Foucault spin is exaggerated and the centrifugal term deliberately
omitted; Gravity Lab's says planet sizes are exaggerated, that the
spacetime grid is an analogy rather than a solution, and that Mercury's
extra 43 arcseconds per century needs GR, which this lab does not model.
The 2026-07-31 entry is explicit that dropping those turns a disclosed
fiction into an undisclosed one.

**Consequences:** The key moves to the Lab Notebook — already the app's
reference surface, already aware of which module is open, and exactly
where someone reading their own recorded numbers would want the key to
them. `HOMESCREEN_SPEC.md` and `DESIGN_SYSTEM.md` described the title-bar
popover until 2026-08-03.

## 2026-08-03 — The log fell twelve commits behind, and the drift followed it

**Decision:** The five entries above are written retroactively, and this
one records why they had to be.

**Context:** A review pass found `DECISIONS.md`'s newest entry was
2026-08-01 while `HEAD` was twelve commits later. In that gap: Circuits
and Magnetism were un-merged (reversing an architecture entry), the
Pendulums cold open changed, the double pendulum arrived, the module's
right-hand column and its verb plate were removed, and the legend key
moved. **Every documentation defect the pass found traces to that gap.**
`README.md`, `docs/APP_STORE.md`, `docs/ON_DEVICE_TESTS.md`, `CLAUDE.md`
and a VoiceOver-read module blurb were all still selling a feature
deleted at HEAD; `ON_DEVICE_TESTS.md` carried manual steps for three
removed controls; a dozen plate counts, line counts and file sizes were
wrong.

**And a cited test file did not exist.** `CLAUDE.md`,
`ON_DEVICE_TESTS.md` and the 2026-08-01 entry all named `StationTapTests`
as the replacement for the XCUITest reach the no-panels decision gave up.
No such file was ever in the repository — the name is from the
merged-worlds era, undone on 2026-07-30. The *pattern* survived the undo
and the *name* did not, and nobody noticed because the pattern was
genuinely there under three other names. Going looking turned up the part
that was actually missing: of the four shared types exposing
`handleTap`, **`SpatialLayerBank` — used by all six modules, the
most-tapped object in the app — and `SpatialPicker` had no tap test at
all.** `SpatialTapTests` closes it.

**Consequences:** The rule this project already applies to code now
applies to itself. A decision is not landed when it compiles and not when
it is committed, but when **nothing in the repository still describes the
world it replaced.** The cheap check is a grep for the name of whatever
was removed, run before the commit rather than a week after.

*(Also recorded: `SpatialTapTests` passed on first write, which in this
project is a reason to suspect a test rather than trust it. Deleting
`guard root.isEnabled` from `SpatialLayerBank.handleTap` left it green —
the test had hidden the bank with `setLayers([])`, which also removes
every plate, so the tap fell through for the wrong reason. Rewritten
against a bank that is fully built and merely unrevealed, it fails as it
should. Same lesson as the Coriolis sign on 2026-08-01: a test that
passes is not evidence until you have watched it fail.)*

## 2026-08-01 — The module window becomes a title bar; `makeControls` is deleted

**Decision:** `ModuleDescriptor.makeControls` is removed, the six `*ControlsPanel.swift` files are deleted, and a module's window is exactly three things: the title bar, "Show in room" while the space is closed, and the first-run hint. Every readout moves into the room as a `Callout` or a RealityView attachment on the object it describes. The seven capabilities with no spatial twin get one. The legend moves to a title-bar popover. The experiment `step` strings move to the hub's focus panel and catalog row — you read the instruction at the front door, then enter.

**Context:** This closes the arc the 2026-07-29 entry opened and the 2026-08-01 exit criterion narrowed. That criterion — "no `Slider`, `Picker` or `Toggle` in any module panel" — has been met by all six modules. What the panels held afterwards was 71 readout `Text`s, 13 buttons (six of them duplicating a control that already stands in the room), and four collapsed sections whose entire content was prose explaining *where a control had gone*. A surface whose content is directions to elsewhere is not a surface.

**This reverses 2026-07-29's "every capability must ALSO be reachable through something discoverable and simulator-operable," and the reversal is narrower than it sounds.** That standard was written against *gaze-revealed* controls — invisible in the simulator, undiscoverable on device, "I can't even move them." That world no longer exists: `LookReveal` is gone app-wide, every ring opens by tap, every instrument stands permanently visible, every one is mouse-operable in the simulator, and every one is reachable from the CLI by a launch argument. What is removed is not the discoverable path; it is the *duplicate* of a path that now exists in the room and is better.

What is genuinely given up is **XCUITest** reach — and that was never complete. XCUITest has no API for RealityKit entities, so the panel only ever proved the window's half. The replacement is the pattern this project already invented for exactly this: `handleTap` called directly against real entities, in the `StationTapTests` shape. Every control built in this change ships with one. *(Corrected 2026-08-02: **there was no `StationTapTests`** — the name is from the merged-worlds era, undone on 2026-07-30, and this entry cited a file that had already ceased to exist. The pattern was real and was carried by `SpatialActionBankTests`, `BloomPetalTests` and `MultimeterTests`; the claim that every control ships with one was not — `SpatialLayerBank`, used by all six modules, and `SpatialPicker` had no tap test at all. `SpatialTapTests` closes that. See the 2026-08-02 entry.)* VoiceOver reach is preserved by `AccessibilityComponent` on every plate, petal, disc and card — label and value both, the omission of which was caught when `SpatialTrackControl` first flew. VoiceOver reaches RealityKit entities; XCUITest does not. Those are different bars, and this entry claims the first.

**The cost, stated plainly:** the app now has no flat control surface at all, so a regression in a spatial instrument has no fallback path. That is the trade this entry makes. `PanelControlCriterionTests` — rewritten from "no knobs in a panel" to "no panels, plus a positive anchor so the check cannot pass vacuously" — is what stops it being unmade by accident. This boundary has already been re-litigated across 212 commits once.

**Consequences:** A module supplies physics and a scene, nothing else; the shell renders chrome that no module can vary. `CollapsedSection` becomes a grave (the surface was decided against, not a missing door). Every new instrument needs a debug launch argument in the same commit that adds it, because nothing automated can reach it. And the standing rule gains a clause: a control that leaves the window must arrive somewhere a person can find *without being told where it went* — if it needs a signpost, it is in the wrong place.

## 2026-08-01 — The submission sweep: gates re-verified, two open items closed

**Decision:** The three App Store gates closed on 2026-07-29 are re-verified **in the shipping bundle** rather than on disk, and the two items standing in `HOMESCREEN_SPEC.md` §3 are resolved rather than carried.

**The gates, read out of a signed Release build** for `generic/platform=visionOS` (signing identity: Apple Development) — that build, not the simulator, is the deployment gate:
- `ITSAppUsesNonExemptEncryption` = `false` (without it every upload stalls on the export-compliance interview).
- `MinimumOSVersion` = **26.0**, not 26.5. 26.5 was the newest visionOS in existence and would have been installable by almost nobody.
- `PrivacyInfo.xcprivacy` present: no tracking, no tracking domains, no collected data, one required-reason API — `NSPrivacyAccessedAPICategoryUserDefaults` / `CA92.1`.

**The manifest's load-bearing constraint still holds and was re-checked, not assumed:** the app has **no networking code at all** — zero `URLSession`/`URLRequest`/`Network` imports across the app target and both packages, and **zero remote package dependencies** in the project. Adding any means revisiting the manifest.

**Ambient volume — closed as a NON-FEATURE.** Settings ships master volume plus ambient on/off, and that is the whole honest surface: there is no gain path into the ambient loop, so a continuous slider would be a control over nothing. The app deliberately ships no dead slider. It was listed as "open work" for months when the correct entry was "decided against, for now."

**`Archive/` — DECIDED TO KEEP, explicitly.** 30 files, 464 KB, tracked, and **not referenced by the Xcode project at all**: it compiles nothing and cannot affect a submission. It holds five cut modules whose physics is still live and tested in `PhysicsCore` — ~2 600 of 6 573 lines are reachable only from there, and `swift test` exercises all of them every run. That is defensible as parked work with a documented restore path and indefensible as an accident, which is why `Archive/README.md` says which it is. **Deleting it before the repo goes public remains the owner's call, not a cleanup.** One genuine grave inside it: `Waves/EmissionTrail` has zero references anywhere, including the Archive. *(Two corrections, 2026-08-03. The figures have moved: `Archive/` is **47 files and 1.6 MB**, and PhysicsCore is **7,457 lines**, not 6,573. And the `EmissionTrail` claim was wrong when written — it is constructed twice in `PhysicsCoreTests/DoubleSlitDopplerTests.swift`, so it is tested code with no app-side caller, which is the same standing as the rest of the Archive's physics rather than a grave.)*

## 2026-08-01 — The Foucault pendulum: the physics that makes the sphere necessary

**Decision:** Pendulums gains Earth's rotation. `PhysicsCore/Oscillations/Foucault.swift` carries `EarthRotation` (Ω from latitude, the sine law, the precession period, and the plane-angle reading); `SphericalPendulum.step` gains an `angularVelocity:` parameter defaulting to `.zero` and applies the Coriolis term −2Ω × v. In the room: a **globe you touch** for latitude, a **rail** for the exaggerated spin, a bank plate to arm it, and the **Panthéon ring** of markers the swing fells as its plane sweeps round.

**Why this, out of the four candidates.** `SphericalPendulum` has been fully three-dimensional since it was written — no small-angle shortcut, a real constraint sphere — and **nothing in the module needed the third dimension for anything.** A planar pendulum would have rendered everything the bench showed. Foucault is the physics that makes the sphere necessary. It is also the one demonstration in the set where passthrough room-scale is load-bearing rather than decorative: the swing plane holds still against the stars and YOUR ROOM turns underneath it, so the user is standing inside the non-inertial frame. On a screen that is a curiosity; in a headset it is the demonstration.

**Latitude gets a globe, not a rail, and the distinction is the law's own.** Every other continuous quantity in the app takes a `SpatialTrackControl` because it has no extent of its own. A latitude does — it is a POSITION ON A SPHERE. So you take hold of the globe and the reading is the place your finger is, mapped through `asin` of the height, which is the sphere's geometry doing the work rather than an invented mapping: touch the top and you are at the pole because the top IS the pole. The lit band's radius is cos φ and shrinks to nothing at the poles, so the cosine visibly vanishes exactly as the sine arrives — the clearest statement of the law the module can make without printing it.

**THE EXAGGERATION IS DISCLOSED, AND THE OMISSION IS THE INTERESTING PART.** Earth turns the plane 11.3° per hour at Paris — correct, and far too slow to stand and watch — so the frame is spun faster and every readout quotes the true rate beside the shown one. Raising the spin is exactly equivalent to standing on a faster planet, which is why it is honest where a faked rotation would not be. But **centrifugal is deliberately left out and said so**: −Ω × (Ω × r) is worth ~0.3 % of g at Earth's real rate, and it scales as Ω², so an exaggerated spin would inflate it by the SQUARE of the exaggeration and swamp gravity entirely. Coriolis scales linearly and stays honest under the same exaggeration. Gravity here is the unmodified g, and the legend says it.

**Sidereal, not solar.** 86 164.09 s, because the plane is fixed against the STARS. Using 86 400 would put the polar period out by four minutes — small, invisible, and exactly the class of error this project's whole claim rests on not making.

**The ring is a RECORD, and that is a presentation argument with teeth.** Foucault's demonstration did not ask anyone to watch; it knocked over markers, so what you saw on arrival was how far the plane had come while you were elsewhere. A still frame of a rotating plane shows nothing; a still frame of eleven fallen markers shows everything. The ring covers a HALF turn, not a whole one, because a plane is the same plane whichever way the bob travels along it — the same fold `planeAngle` makes, and a full circle of markers would read double.

**TESTS ARE THEOREM RECOVERY, AND ONE OF THEM CORRECTED ME.** Nothing asserts that `precessionRate` returns Ω sin φ; every test integrates a swinging pendulum and measures what the plane did. The sine law is recovered at three latitudes, the equator is shown not to turn (with Ω non-zero but horizontal), the pole turns once per sidereal day, and the southern hemisphere reverses. Then the Coriolis sign was flipped deliberately to check the tests would catch it — **and `testCoriolisDoesNoWork` still passed.** A reversed cross product is just as perpendicular to v, so it pumps no energy; it was the recovered sine law that failed, at all three latitudes, with the rate exactly negated. The code comment claiming the energy test would catch "any sign or axis error" was therefore **wrong, and is corrected in place**: energy catches a term with a component along v, the sine law catches its direction, and neither alone is sufficient. This is the same lesson as the Jupiter-oblateness correction — an explanation that sounds right and is wrong is the expensive mistake here.

## 2026-08-01 — The criterion is met, and it becomes a test

**Decision:** Circuit Workshop's two remaining toggles become objects — a **multimeter standing on the bench** and a **one-plate switch on the cable run** to the coil. `CircuitsControlsPanel` holds zero `Slider`/`Picker`/`Toggle`, and with it **all six modules meet the exit criterion set on 2026-07-29**. `grep` over every `*ControlsPanel.swift` returns nothing but comments explaining where the controls went.

**A multimeter is not a display layer, which is why it is not on the bank.** Circuits already had a four-plate bank and adding a fifth was the cheap move. But the other four plates all answer "what is drawn"; the meter answers "what is this circuit doing here", and it is the one thing on the bench you use to ASK the circuit a question rather than to build it. It is a tool, so it is a tool: a machined casing with a lit face, standing to the left of the bench, tapped to arm. **The reading moved onto the meter** — where you are already looking when you touch the second terminal, and where a real bench meter puts it. An armed meter with nothing probed says "tap two terminals" rather than a confident 0.00 V, the same honesty the coil's "no inductor on the bench" line exists for.

**The coil switch is a bank of ONE, and here that is right where it would be wrong elsewhere.** Pendulums' air-resistance plate joined a bank of four because a lone plate beside a bank is a stray. This switch is not one of a set of view options: it summons a second apparatus and runs a cable to it. So it stands ON the run, between the bench and where the coil appears, wearing **Magnetism's accent rather than Circuits'** — the colour is the only warning you get that flicking it stands an apparatus up beside you. Throwing a switch and watching the cable it belongs to wake up is the entire reason this pair is co-present (2026-07-30: co-presence survives where it is WIRING, never layout).

**A FOURTH RESET DEFECT, AND THE WORST OF THEM.** `reset()` restored one of the four states its bank shows. Resetting from Electron View handed back a bench still swollen to 4× with three lit plates over it. That is four modules in two days — Pendulums' `frictionOn`, Magnetism's `dynamicsOn`, Kinematics' `respectRoomWalls`, and three of Circuits' four at once. Every one was invisible for months as a toggle in a collapsed card. **The pattern, stated once and for all: a model flag with no visible control drifts out of `reset()` and stays wrong, because nothing in the room contradicts it. Giving it a lamp does not create the bug — it reveals one that was always there.**

**THE CRITERION IS NOW A TEST, and it is a source-reading test on purpose.** `PanelControlCriterionTests` walks every `*ControlsPanel.swift` and fails on a `Slider(`/`Picker(`/`Toggle(` call site outside a comment, with a failure message that restates the law and the three permitted resolutions. Reading source is crude and was chosen deliberately: SwiftUI's `body` is opaque, a `Slider` nested inside a `CollapsedSection` is not reachable by reflection, and a test that silently inspected nothing would be worse than none. **Proved to fail before being trusted** — a `Toggle` was injected into Magnetism's panel, the test failed and named the file and line, and the injection was reverted. This boundary has already been re-litigated once in a full 212-commit round trip; a criterion nobody can re-check is one that silently regresses.

## 2026-07-31 — Projectiles gets an instrument wall, and the reset defect makes it three

**Decision:** Kinematics' two sliders and two toggles become a four-disc standing `SpatialPicker` of worlds, a rail for g, a two-plate `SpatialLayerBank`, and a wind rail that exists only while there is air. `KinematicsControlsPanel` holds **zero `Slider`/`Picker`/`Toggle`** — the fifth module to meet the exit criterion. Only Circuits' two toggles remain.

**Zero-g is a world here and not in Pendulums.** Same object, same grammar, one more choice: a pendulum in zero-g does not swing, so there is no period to show and `SurfaceGravity.bodies` deliberately excludes it; a projectile in zero-g flies dead straight, and the straight line is the whole lesson about what gravity was doing to the arc. The two Mechanics benches share the instrument and differ in what they offer it, which is the right kind of difference.

**The instruments do NOT ride the launcher, and the second reason is a correctness one.** The launcher is grabbable, and mounting its controls on it would put them exactly where the physics is — the doctrine's preference. But `SpatialTrackControl.adjust(hand:)` measures the hand against `root.position`, so a rail whose root is being carried would shift its own mapping mid-drag, and the whole point of a track over a dial is that the mapping is absolute. (The other reason is plainer: four instruments swinging around the room with the launcher is a lot of furniture to drag through a wall.) They stand as a wall to the left of the launcher's home, at its depth, out of the firing line — this module is 1:1 with the room and the balls genuinely go everywhere.

**Neither plate on this bank draws anything**, which is the second module in a row where that needed saying. "Walls bounce" and "Air resistance" change what the ROOM IS — whether its walls stop a ball, whether its air slows one. They earn the bank because they are still labelled discrete choices, and the labels say what they do rather than what is shown.

**The wind rail is `SpatialTrackControl.isEnabled`'s first user anywhere in the app.** That property was added during the Electric Fields pass for a case nobody had yet hit: a drag already in flight when the apparatus it belongs to is switched off. The gesture keeps delivering `onChanged` after the plate goes dark, and without the guard the rail goes on writing a wind speed nothing is applying. A test pins the model half of the same claim — with the air off, a leftover wind must move a ball not at all, to the last bit.

**A THIRD RESET DEFECT, AND THE RULE FROM THIS MORNING CAUGHT IT BEFORE ANY CODE WAS WRITTEN.** `reset()` restored `gravity`, `airResistance` and `windSpeed`, and skipped `respectRoomWalls` — so switching the walls off and pressing Reset handed back a room balls flew straight out of. That is three in one day, in three different modules, all the same shape: Pendulums' `frictionOn`, Magnetism's `dynamicsOn`, Kinematics' `respectRoomWalls`. **The rule works, and it is cheap: before converting a toggle to a plate, read `reset()` and check it covers the flag.** Every one of these was invisible for months as a toggle in a collapsed card and would have been a visibly wrong lamp the day it shipped.

**`addRing` is classified, and it is a third category.** The project's rule says every caller-less thing must say which it is — missing door (surface never built) or grave (surface decided against). Kinematics' hoop machinery is neither: model, renderer, scoring and tests are all intact and exercised, and the SURFACE was deliberately removed on 2026-07-29 because hoops read as clutter around a bench about trajectories. Calling it a grave would invite someone to delete working, tested code; calling it a missing door would invite someone to restore a feature the owner cut. It is a **mothball**, the comment now says so, and restoring it is a decision rather than a cleanup.

## 2026-07-31 — Magnetism's four switches become one bank, and a second reset defect

**Decision:** Magnetism's four panel toggles become a four-plate `SpatialLayerBank` standing to the right of the field, at the region's own depth. `MagnetismControlsPanel` keeps the Add-magnet button, the magnet count, the µT compass readout and its prose, and holds **zero `Slider`/`Picker`/`Toggle`** — the fourth module to meet the exit criterion. Two remain: Kinematics (4) and Circuits (2).

**The top plate is not a display layer, and the bank has to admit it.** Three of these switches change what is DRAWN — field lines, compass grid, hand compass. The fourth, `dynamicsOn`, decides whether the magnets glide together and swing into alignment at all, which is the difference between a field diagram and a physics lab. It takes the top plate and the label "Magnets move" rather than a drawing verb. A bank whose plates all mean *draw this*, with one meaning *run the simulation* hidden among them, would be lying by arrangement. Two tests state the pair from both sides: freezing must stop the physics however hard the magnets pull, and hiding any drawn layer must move nothing.

**The bank does not scale with the field.** It is parented to the renderer's `root`, not `viewRoot`, so the two-hand rig's 4× leaves it alone. The well and the blooms belong to the field and correctly scale with it; an instrument belongs to the room. This is the same call Gravity Lab made at 9× and for the same reason — an instrument that grows with the apparatus puts its own controls out of reach at exactly the moment you zoomed in to use them.

**A SECOND RESET DEFECT, IDENTICAL IN SHAPE TO THE ONE FOUND IN PENDULUMS THE SAME DAY.** `reset()` restored `showFieldLines`, `showCompasses`, `compassOn` and `electromagnetOn`, and silently skipped `dynamicsOn` — so freezing the magnets and pressing Reset returned a frozen bench. Pendulums' `reset()` skipped `frictionOn` in exactly the same way. **This is now a pattern worth naming: a model flag with no visible control can drift out of `reset()` and stay wrong indefinitely, because nothing in the room contradicts it. The moment it gets a lamp, the lamp makes a claim every frame, and a wrong one is visible.** Both are fixed and both are pinned by a test that lists every state its bank shows. The rule for the two modules left: when a toggle becomes a plate, check `reset()` covers it *before* looking at anything.

## 2026-07-31 — Pendulums empties its panel, and the Bloom grip stays relative

**Decision:** The module's seven panel controls — the joint-largest panel left in the app, and the last one with two sliders — become four objects in the room. A five-plate `SpatialLayerBank` to the left of the swing carries the four display layers plus air resistance; a standing three-disc `SpatialPicker` of worlds and a `SpatialTrackControl` rail for g stand to the right; a second rail under them carries time. `PendulumsControlsPanel` keeps the two making buttons, two readout cards and its prose, and holds **zero `Slider`/`Picker`/`Toggle`** — the third module to meet the 2026-07-29 exit criterion, after Electric Fields and Gravity Lab.

**Why these forms.** The law says a quantity with physical extent is changed by changing that extent. This module's two quantities that HAVE extent were already grips on the object itself: the cable's length is the Bloom bead you pull, and the bob's mass is a petal that cycles it. What was left in the panel — g, the clock, and five on/off states — has no extent at all. g is not a size, it is a property of the world you are standing on, so the three worlds are three labelled objects and the continuum between them is a rail. That is the same pair of shapes Gravity Lab gives G and its clock, deliberately: someone who learns the gauge in one Mechanics bench has learned it in the other.

**Air resistance is on the display bank, and it is not a display layer.** It decides whether the swing ever stops, which is a statement about the physics rather than about what is drawn. It goes there anyway because it is still a labelled discrete choice, and one lone plate standing beside a bank of four is a worse object than one bank of five. The label says "Air resistance" rather than a drawing verb so the difference is legible.

**The bank is a readout, and so is the world picker.** The lit disc is whichever world your current g matches, read from the model every frame rather than remembered from the last tap — so dragging the rail off Earth unlights Earth, and Reset lights it again. The panel's own "g = 9.81 m/s² — Earth" line is the same comparison asked a second time, and a test pins them to one another so they cannot drift.

**A claim the module had been making was false.** `PendulumsSpaceView`'s header said gravity "is a dial you turn while watching the swing stretch out in front of you." There was no dial: `SpatialDial` was deleted on 2026-07-29 for being relative, and gravity was a `Slider` in a collapsed card. The same class of defect as Electric Fields' un-tiltable Gauss disc, found the same way — by reading the prose next to the code. It is true now. `PendulumsModel` likewise documented a time scale of "0.25× … 20×" while the slider driving it ran 0.1 … 5.0; the range is stated once now, as `timeScaleRange`, because it is the rail's range too.

**THE OPEN ITEM FROM 2026-07-29 IS CLOSED: `Bloom`'s grip stays RELATIVE.** That entry deleted `SpatialDial` for being relative and noted "`Bloom`'s grip is now the odd one out — it is relative like the dial was — and should be revisited when Mechanics is worked over." This is Mechanics being worked over, and the answer is to keep it. Three reasons, in order of weight. The owner has said on the record that he likes the pinch-pull-from-the-white-dot gesture and wanted it made *legible* rather than replaced — and it was, on 2026-07-29: a visible rail from the object's surface spanning the full range, end ticks, a bright fill to the bead, and a persistent value callout. The complaint was never that the mapping was relative; it was that nothing showed you the mapping. Second, the dial and the grip fail differently: a dial has no home position, so a twist means nothing until you have already twisted, whereas the grip starts at the object's own surface and its rail shows the whole range from the first frame. Third, it is shared by five modules, and changing a gesture that works in all of them to satisfy a symmetry is the kind of consistency this project has already paid for twice. **This question does not get asked a third time.**

**Placement, which this project keeps getting wrong.** Every instrument sits at the apparatus's own depth (z ≈ −1.08, the pivot plane) rather than at a height chosen on its own. The podium mistake has now been made three separate times — controls on a console *below* the thing they belong to, reading ~38° under the eye line and simply never seen — and being close magnifies the drop. The band that works is ~14°, which at this depth is y ≈ 1.35. **Unverified: the simulator was wedged on its boot logo for the whole of this pass, so none of these four placements has been looked at yet.** Arithmetic has passed placements before that a screenshot then rejected; this is a gate, not a formality.

**Coverage.** `PendulumsModelTests` was a single test function against a 365-line model — the thinnest in the project. It now pins what the instruments write: the rail ranges and their clamps, the lit-disc comparison, that every world lies inside the rail's range (or tapping a disc would move the bead somewhere it could not be dragged back to), that Reset restores all five layers, that the time rail actually scales how much physics runs per frame, and that `setLength` keeps the swing running through a cable edit — which the code goes to real trouble to do and nothing had ever checked. Plus T = 2π√(L/g) and its indifference to mass, which is the whole point of the mass petal.

## 2026-07-31 — Gravity Lab: the orbit becomes the object

**Decision:** Tap a body and its osculating conic is drawn as a ring around its primary, with one grabbable bead at each end of the apse line. Dragging a bead reshapes the orbit in closed form: outward and it stretches, sideways and the whole ellipse swings about the Sun, upward and the orbital plane tilts. New `PhysicsCore/Gravitation/OrbitalElements.swift` carries the math as two types — `OrbitalElements` (the classical six, for readouts) and `ApsisFrame` (p̂, ĥ, r_p, r_a — the singularity-free handle). No Kepler's equation anywhere: every question asked is geometry, and geometry is exact.

**Context:** The only way to change an orbit was to throw the planet. `release` multiplies the hand's velocity by 8.6 × 10⁴ — a number that appears nowhere in the room, that nothing displays, and that no two gestures reproduce. It was the app's last surviving RELATIVE control, of exactly the kind convicted on 2026-07-29 when `SpatialDial` was deleted: **absolute beats relative.** Meanwhile the module held 2 sliders and 5 toggles, the joint-largest panel left in the app, in the module that entry named as "the template."

**THE SCHEME AS DESIGNED WAS NOT WELL-POSED, and the corrections are the substance of the work.** Periapsis and apoapsis are collinear through the focus, so both beads report the same apse line and the two of them carry **4 of 5 degrees of freedom** — the roll of the orbital plane about that line is untouched by either. Three collinear points define a pencil of planes, not one.

The fix is a transport rule and not a third bead: `ĥ ← normalize(ĥ − (ĥ·p̂)p̂)`, applied per frame. In-plane drags leave the plane **bit-exact** (the projection short-circuits when it is already the identity — without that, an ulp per frame at ninety hertz is a random walk that visibly tilts the orbit with nothing in the gesture to explain it). Out-of-plane drags tilt by exactly the minimum rotation, so the plane follows the apse line the way a hoop follows its diameter. A hand on the orbit's pole is a **no-op, not a snap** — the same formula and the same reasoning as the Gauss disc's tilt.

And the rule is parallel transport, so it has **holonomy**: walk a bead around a closed loop and the plane comes back rotated by the enclosed solid angle. Two beads are instantaneously one degree of freedom short and **globally complete**, which is the licence for not adding a third. There is a test that walks a spherical octant and asserts the plane returns turned by exactly π/2.

The second correction: **bead identity is derived per frame, never stored.** The bead you hold is whichever apsis its distance makes it — `r_p = min(ρ, ρ_other)`. This makes "what if I drag periapsis out past apoapsis" evaporate rather than needing a rule, because the labels swap exactly at ρ = ρ_other, which is where the orbit is circular and the two ends are physically interchangeable. The state passes through smoothly: the two velocities differ by 2e·q̂, and e is zero at precisely that crossing. **The only discontinuity in the labelling is at the configuration where the labels do not matter.**

**Two physics errors the ring exposed, both invisible until something read the orbits back.** `onCircularOrbit` used √(GM/r), but the relative orbit of a two-body system obeys r̈ = −G(M+m)r̂/r², so every "circular" orbit in the app was slightly elliptical by construction — a part per million for Earth, **1.2 % for the Moon about the Earth**. And `readout` used μ = GM for the semi-major axis and the escape speed but G(M+m) for the period, so a body's size and its period described slightly different orbits. Both unified on G(M+m). A planet built circular now reads back circular, which is the invariant that caught this.

**Honesty.** The osculating ellipse is not an approximation of the trajectory; it is the exact orbit this body would follow from this instant if every other perturber vanished. The module already draws the truth beside it — **the trail is what happens, the ring is what would happen, and the gap between them is the perturbation made visible.** The beads creeping round the Sun over simulated centuries are apsidal precession, Newtonian perturbation theory rendered as a slowly walking object you could touch. A dishonest ring would be a fixed decoration; this one moves because the physics moves it. Two legend entries say so, and the second one matters: **the precession here is Newtonian, and Mercury's famous extra 43 arcseconds a century needs general relativity, which this lab does not model.** Without that line the module implies it has explained the most famous test of GR.

**The reach limit is real, measured, and disclosed rather than faked.** At 1 AU = 0.5 m with a 1.25 m grab, both beads are reachable for Mercury → Jupiter and for anything pulled from the well (born at the hand); the comet gets its near bead only; Saturn outward the ring is a readout you can see and not touch. The rig is **not** widened below 0.4× to chase it — at 0.2× Earth's orbit is 20 cm, the miniature diorama ARCHITECTURE.md bans outright. **A bead exists only where a hand could actually reach it:** no proxy handles, no tethers, no faked distance.

**Selection was unreachable, and had been the whole time.** `select(id:)` was `#if DEBUG`-gated, so the only user path to a selection was to grab a body and drag it — which freezes it and zeroes its velocity, destroying the orbit you were about to study. Selection drives the vectors, the Kepler sweep, the Predict button and the notebook rows, and the Prophet experiment's own step text reads "Tap a planet to select it," **describing an interaction that did not exist.** A tap selects now.

**The panel is empty of controls.** Five display toggles to a switch bank, joined by a sixth the panel never had — the acceleration vector, read by the renderer and defaulted to false, with its arrow, its log scaling and its legend entry all existing for something no user could turn on. The star's mass to the star's own bead, in solar masses, because mass has extent and a star measured in Earths reads "333000". G to a rail. What arrived in their place: the selected body's orbital elements, and its **energy** — four of the eleven numbers this model computes every frame were shown to nobody, and the total is the one that makes "bound" a fact rather than a label.

**The 9× walk-through was broken at both ends, and it is the module's authored thesis.** The Sun's light died at 5 m against a 15 m system; the spacetime grid stopped at Mars; the dimming shell was a 3.4 m sphere drawn through the middle of the solar system, so half the planets read against darkness and half against the wall with the seam moving as you zoomed; the field particles inhabited the inner system only; every label inflated ninefold; and the spawn well — the module's one creation affordance — ended up a 29 cm ball five metres to the left, out of reach exactly when you are inside the system and most want to add to it. **Everything that is read rather than simulated now counter-scales by 1/rig.** Reset resets the view, which `SpatialScaleRig.reset()` had been sitting there unwired to do.

**Three doors opened onto finished work.** `Lagrange.swift` solves L1–L3 as real roots of the rotating frame's quintic by bisection, places L4/L5 exactly, knows the co-rotating velocity, is tested end to end, and **had never had a caller outside those tests** — the only entrance was a mode nothing invokes. It is a display LAYER now, for the selected planet against the Sun, so it is the Trojans' points at Jupiter and JWST's at Earth; `Lagrange.points` was always written for an arbitrary pair. Nothing had to be built; something had to be connected. Reverse time cost one sign and one `abs` — velocity Verlet is time-symmetric, so running backwards integrates the same equations rather than replaying a recording, and an orbit you perturb un-perturbs (merges excepted: merging destroys information, and the legend says so). And the body budget went 12 → 16, because `reset()` puts ten bodies on screen and two spare worlds is not a lab about building systems — which first required staggering the trail uploads, twelve `MeshResource.generate` calls in one main-thread callback and the module's largest hitch.

**A design note worth keeping:** the Lagrange host is the last planet the user TAPPED, not whatever is selected. Deriving it from the live selection meant that pulling a world out of the well to park at Jupiter's L4 re-pointed the layer at the satellite mid-gesture — **the five markers you were aiming for moved the instant you made the thing to aim with.**

## 2026-07-31 — Electric Fields empties its dropdowns into the room

**Decision:** Every setting in Electric Fields becomes an object. A five-plate `SpatialLayerBank` says what exists (field lines, free charges, plates, uniform B, flux meter); three `Well` mouths make charges and the test probe; a four-way standing `SpatialPicker` says what the test particle IS; two `SpatialTrackControl` rails carry ΔV and B; and the flux meter's radius and facing become the act of grabbing its rim. `FieldControlsPanel` keeps two cards of numbers, one Clear button, and **zero `Slider`/`Picker`/`Toggle`** — the first module to meet the exit criterion set on 2026-07-29.

**Context:** The owner opened the module and said the panel had "so many dropdown boxes… you have a 3d space so use it." That is the interaction law rediscovered from the outside: six stacked disclosure cards, two of them holding no controls at all, the capacitor's voltage three levels down, and a mode switch silently swapping one slider for another behind a single label. Electric Fields held 7 toggles, 6 sliders and 2 pickers — more than any other module. Meanwhile the primitives built for exactly this went unused: `SpatialLayerBank` 1 module of 7, `Well` 4, `SpatialPicker` 2, and **`SpatialTrackControl` zero** — its only constructions were in `Archive/`, which is not in the build, so the app's decided form for a continuous quantity had never once run.

**Consequences, and most of them are things the migration EXPOSED rather than introduced.**

`SpatialTrackControl`'s first flight found three defects in code nobody had executed: its touch target was a **sphere of `length × 0.55`** — a 29 cm ball around a rail 1 cm thick, which under the capacitor would have reached up inside the plates and re-created the `SpatialScaleHandle` failure at one-eighth scale; `owns()` and `adjust()` had no enabled check, so a rail hidden mid-drag kept writing to the model; and it set an accessibility label but no value, which would have traded a slider VoiceOver could operate for one it could not. All three are fixed and pinned by `SpatialTrackControlTests`. The general lesson: **an unused primitive is not a working primitive**, and the cost of finding out is paid by whoever adopts it first.

Two claims the app was already making turned out to be false. The panel had been instructing users to "tilt it edge-on to the field and the flux falls to zero" since the Gauss disc was written, and **nothing in the app could tilt it** — `gaussSurfaceNormal` had exactly two writers, its declaration and `reset()`, both writing (0,0,1). And `SpatialPicker`'s own header said a standing bank "is also a READOUT" while rendering N identical discs with no indication of the current value. Both are true now; the picker's fix also silently repaired Gravity Lab's clock bank.

The disc's tilt is one absolute formula, and it is the nicest thing here: `n′ = normalize(n − (n·û)û)` with `û` toward the hand puts the rim under your fingertip, while `r′ = ‖hand − centre‖` sets the radius from the same hand position. Pull outward in the disc's plane and it grows; swing out of plane and it turns. No modes, nothing accumulating, one guard for the degenerate case (a hand on the axis describes every orientation equally, so the disc is left alone rather than snapped). It also exposed a latent escape: `moveGaussSurface` insets its clamp by the radius *at the time*, so growing a bubble parked against a wall pushed its skin through the station — invisible while growing meant dragging a slider, constant once growing means pulling with your hand.

Two placement lessons, both found by screenshot after the arithmetic passed. Instruments went first to the station's NEAR edge (z = −0.5), which is 61° off axis — a bank half out of frame; they belong at the apparatus's own depth. And the ΔV rail went first UNDER the plates, where a `max(y, 0.85)` floor left it threaded through the gap whenever the capacitor was carried low, and where — once that was fixed — it sat 36° below the eye at 0.6 m. It is mounted on TOP of the capacitor now, about 10° up, which is where a bench supply keeps its controls anyway. **The reach test that matters for a portable instrument is not "is it within 1.25 m of a standing head" but "is it no further away than the apparatus it belongs to."**

The layout is held by arithmetic rather than by care: every instrument stays 0.12 m clear of the station, and that number is `resolveCharge`'s proximity-fallback radius, so instrument-vs-charge contention is impossible by geometry. That fallback is itself load-bearing — the capacitor plates carry 26 cm collision spheres that overlap in the middle of the gap, so without it a charge between the plates could not be grabbed at all. The hit test also inverts: **the Gauss surface is a container, and the thing inside it is the subject.** It used to match first and win outright, so a 55 cm bubble beat everything within it and only the fallback rescued a charge inside one, by accident.

Deleted rather than migrated: `lookToPlace` and `lookReach`. "The meter rides your head ray" is the most headset-native-sounding thing in the module and it rewrote the surface's position every frame, so a hand that grabbed the meter was overruled on the next tick — a mode that disables direct manipulation is not an alternative to it. It was also device-only, so no screenshot could ever show it working.

Finally, two disclosures moved with the numbers they belong to rather than the sliders they sat under: the 50 kT "that field is fictional" paragraph and the electron-mode time-compression note. **A migration that drops those turns a disclosed fiction into an undisclosed one.**

Six modules still hold 24 panel controls between them. This one is the template.

## 2026-07-30 — The canon gains a recipe for built things

**Decision:** `RenderKit.Materials` grows a second family — `machined`, `graphite`, `glossy` — beside `energized`, and the eighteen fully-metallic surfaces across Pendulums, Magnetism and Circuits are swept onto it. `metallic` is deliberately **not** a parameter of `machined`: 0.62 is the whole point of the recipe, and a call site that wants 1.0 wants the bug the entry below diagnosed.

**Context:** `Materials.swift` called itself the material canon while offering exactly one recipe, and that recipe was for **lit energy** — a charge, a source, a bead of current. There was no shared recipe for a *built* thing: a bob, a coil, a knob, a shelf. The absence is legible in the source, because every module that needed a machined part fell back to `SimpleMaterial` with a hand-typed grey, and eighteen of them landed on `metallic = 1.0` — the exact configuration the plaque had already rejected on measured grounds one entry below, and which none of them had heard about. Meanwhile the Hub had authored good values for precisely this and kept them inline, copy-pasted across four call sites. Nothing here was invented; it was **promoted**. The same pass found `Materials.contrastLine` describing itself as "the fix used everywhere in the app" while shipping in one module of nine, and gave Magnetism's dipole loops the casing pass they had been missing.

**Consequences:** Colour is semantic in this project, and two defects that only that rule makes visible went with it. Pendulums' period label and its gravity-force arrow were the **byte-identical** `(0.55, 0.35, 0.95)` — a period readout painted in the force-vector colour — so the arrow now takes `VectorPalette.force` and the label the module's own accent. Circuits' motor blades wore a teal belonging to no palette entry at all; an unowned hue on a physics object is the state a palette exists to prevent, and it is `motorAccentUI` now. The generalisable lesson: **a canon with one recipe is not a canon, it is a default** — and the tell is a grep for hand-typed colours and materials, each of which marks a call site the shared layer failed to serve.

Two per-frame material allocations went in the same pass (the voltage skyline rebuilt a `PhysicallyBasedMaterial` per tower *and* per cap every frame it showed; Magnetism's induction filament rebuilt its own on every frame it burned, which is every frame a magnet is moving). Both are banked ramps now, and a bucket that has not moved writes nothing — the pattern Circuits already used twice and had simply missed here. The rule that falls out: **a continuous quantity does not need a continuous material.** The eye cannot resolve the steps, and the allocator can.

## 2026-07-30 — The home speaks in machined plaque

**Decision:** Owner's call, made off a specimen wall: the home's three display texts — the wordmark and both door signs — are set in `HubTitleStyle.plaque`. Uppercase bold, milled deep, brushed metal, the domain accents alloyed 30% toward steel so green and orange read as anodised rather than painted. The other three voices (bubble, frosted, poster) stay in the enum and stay reachable from Settings.

**Context:** Two process notes worth more than the outcome. First, **the audition had to move out of a launch flag.** It shipped behind `-titleAudition 1`, which meant the owner opening the app normally could never see it — the same undiscoverable failure this project has now diagnosed three times (gaze-revealed controls, the bench picker in a window panel, and now a developer flag), each time in a new costume. It is a Settings picker now, and a fresh install used to open on the wall so the choice presented itself in the room. Second, **the wall found bugs the single-style shots had hidden**: leading derived from the average line height (the flush lockup scales a short word up hard, so the tall line's cap height far exceeds the mean and the lines collided), and a dark backing pass rendered as a second ghosted set of letters.

**Consequences:** The plaque is **one solid, not a stack** — the only voice here that is. A dark copy behind it must sit further back than the extrusion is deep, and at 0.55 this is the deepest voice in the set, so any offset small enough to read as a shadow punched through the faces; the symptom was doubled letters, the cause was two meshes sharing a volume. A real plaque needs no drop shadow: its own extruded sides catch light at a different angle from its face, and that depth cue holds from every viewing angle, which a fixed offset never does. Held by `testThePlaqueIsASingleSolid`. Its metal also stops short of a mirror (0.62): at `metallic = 1.0` a surface shows only what it reflects, and a passthrough room offers RealityKit almost nothing, so the letters rendered muddy grey. Roughness went the other way, up to 0.42 — a polished face flips between hotspot and shadow as the head moves, while a satin one rolls between them, so light travels across a letter instead of snapping across it.

The gallery also **fades in over ~0.18 s** rather than cutting. A scene rebuild replaces the whole room between two frames, which is invisible on first entry but reads as a glitch when changing a setting rebuilds the room around you. The fade is on the ROOT, so every exhibit, sign and slab arrives on one curve, and the `OpacityComponent` is REMOVED once it lands rather than left at 1 — a permanent one forces the whole gallery down a transparency path it does not otherwise need.

## 2026-07-30 — The doors get names: animated 3-D signage over the terraces

**Decision:** Owner's call. Each terrace carries its domain's name as three-dimensional signage (`HubDomainTitle`): a flush two-line lockup in the wordmark's own bubble type, recoloured to the domain accent, with one kinetic element apiece doing that domain's physics — an electron lapping a tilted elliptical track around the E&M sign (in front across the bottom, behind across the top, which is the pass that sells the letters as solids), and a ball lobbed over the Mechanics sign on a true parabola, landing at the far end of the underline rule and launching back the other way.

**Context:** This reverses the Gallery's "no floating text headers" doctrine, and the reversal follows the geometry of the new Home Screen. Four terraces of two modules read as a crescent and colour alone could group them; two terraces of three ARE the app's two doors, the domain IS the choice the screen exists to offer, and a door without a name reads as someone's shelf — the same argument that brought the wordmark back (2026-07-29), one level down. This also amends that entry's "branding budget for the room is spent" line: the budget is re-opened by exactly these two signs and closes again behind them.

**Consequences:** The design language is inherited, not invented — `HubScene.bubbleText` face, the wordmark's measured flush-width lockup math, concentric plate/rim/letter passes, and the vignette doctrine that every animated thing in the hub does its module's physics. Cadences are signage cadences (a 4.5 s lap, a 2.8 s lob), the same licence the miniatures take; the SHAPES are the honest part and are held by `HubDomainTitleTests` — the electron never leaves its ellipse, the orbit genuinely crosses in front of and behind the letters, the lob launches and lands ON the rule, clears the letters at apex, is symmetric (a parabola, not an ease curve), and alternates direction (a ball kept in play, not a film loop rewinding). Under reduce-motion the signs PARK at a composed rest pose rather than freezing mid-flight. The domain accent's short list of appearances grows by one: hairline, progress ring, focus chip, signage.

## 2026-07-30 — The worlds are undone: two doors, six experiences, one room each

**Decision:** Owner's call, made at the orbital station's decision gate. The merged worlds (`em`, `mechanics`) are unregistered and the six experiences return as their own catalog entries, grouped behind **two domain doors on the Home Screen**: Electricity & Magnetism (Electric Fields, Circuit Workshop, Magnetism) and Mechanics & Energy (Projectile Motion, Pendulums, Gravity Lab). An experience gets the room to itself. The one planned exception is *wiring, not layout*: Circuit Workshop will bring the magnetic field with it, because the cable carrying its inductor current to a coil is a demonstration that cannot exist with one bench.

**Context — the measurement that forced it:** The E&M world fit three benches only by seating each ~1.5 m out (turn *and step*). The Mechanics world could not fit at all: the plan was to stand the benches in the orrery's empty Mars–Jupiter shell, and an exhaustive search over a 12 × 4.5 × 12 m grid found **no Sun position anywhere** — because the pendulum station's body diagonal is **2.65 m** and the whole shell is **1.84 m** thick. A box wider than the shell cannot fit inside it, wherever the Sun goes. Raising `metersPerAU` to 0.7 would have found a seat but put Neptune's orbit 42 m across with the Sun through the wall; hanging the orrery overhead put the planets out of reach in a module whose grammar is grab-a-planet.

**Consequences:** The catalog has now been burned three times, and each burn names a different failure. Fields and Oscillators died as *pickers* — a segmented control hidden in the window panel made half the module unreachable. The worlds died of *geometry* — apparatus authored to own a room does not share one. The rule that survives all three: **choosing belongs at the front door**, the most discoverable surface in the app, never inside a module's panel and not by cramming benches into an arc. What the worlds leave behind is kept deliberately: the station clamps (`FieldModel` had no lateral clamp at all; `CircuitsModel` clamped to a 3 m sphere), `PhysicsCore.StationBox`, the archive cuts, and the addressed `-viewScale`. Those were latent bugs and general tools the merge *revealed*; the sharing of space was the only part that failed. The generalisable lesson: **check whether the geometry closes before designing around it — a layout that needs every bench to shrink is the room saying no.**

## 2026-07-30 — Projectiles and Pendulums become the Mechanics world

**Decision:** `kinematics` and `pendulums` leave the catalog and become the two benches of `mechanics` ("Mechanics & Energy"): the launcher dead centre, the pendulum rig 1.75 m to its left, one focused at a time. `MechanicsWorldSpaceView` is a deliberate COPY of `EMWorldSpaceView` rather than a shared generic — about sixty lines of routing are identical and about sixty are not, and a generic host would need an escape hatch for exactly the part that differs while making the tick order harder to read.

**Context:** The two benches teach one thing — what a constant downward acceleration does to a moving body, once with the body let go and once with it held by a cable — and the gravity control on each was the same number typed twice. Setting the Moon on one bench left the other on Earth, which made the app's clearest single comparison impossible to actually see.

**Consequences:** One station in this world **may never be offset**, and that is new. Projectiles feeds `room.collisionWalls` and `room.bounds` straight into its solver and catches balls at real `room.fingertips`: its physics space IS the user's room, one to one. A display offset would leave every ball bouncing off a wall that is not where the bounce is drawn — silently, in the module whose whole claim is that this is happening in your actual room. So `offset(.projectile)` is `.zero` by construction, `testTheProjectileStationIsNeverOffset` says why in its failure message, and the pendulum rig is the station that gives way.

That forced a second departure from `EMStationLayout`: **seat and volume are separate functions here.** E&M could derive a station's box from its seat because its benches are centred on the anchors they were authored around. A pendulum is not — it hangs from a pivot at head height and swings down past your knees — so forcing the seat to be the box's centre would either drop the rig 0.8 m or declare a box through the ceiling. Two facts, two functions.

Also recorded, because someone will otherwise "fix" it: **apparatus volumes must stay apart; trajectories may cross freely.** The pendulum box is the rig's RESTING volume. A bob thrown hard sideways swings out past it — a 1.6 m cable at 90° reaches further than any box that would still leave the launcher room — and a swinging bob crossing the projectile bench is the same event as a thrown ball crossing an orbit. There is no test asserting a swinging bob stays inside, and there must not be one: it would be asserting that a pendulum cannot swing.

## 2026-07-30 — Electric Fields becomes the E&M world's centre station, and three footprints become real

**Decision:** `electrostatics` leaves the catalog and becomes `EMChargeStation`, the middle seat of `em`: charges straight ahead, the circuit bench 1.40 m to the left, the magnetic field 1.33 m to the right. The catalog is down to five entries, heading for two. Every experiment id keeps its `field.` prefix, so earned progress survives.

**Context:** A circuit makes a current, a current makes a magnet, and a charge is what both are made of — but the module that drew charges was a separate entry, so the app asserted they were one subject and then made you leave the room to check.

**Consequences, and the honest cost:** Three apparatus want about four metres of width and a room does not have four metres of *arm's reach*. The boxes are axis-aligned so one clear axis suffices, and x is the only axis available — y puts a bench on the floor or the ceiling, and separating in z is what pushed the reserved charges seat out to z = −2.25, out of reach for an apparatus whose whole grammar is drag-a-charge. So the three sit side by side and each station's **centre lands ~1.5 m away, near face ~1.1 m: you turn and take a step.** The alternative was halving the electrostatics volume (capping capacitor plate separation at 0.4 m against a range that goes to 1.0), and the physics was judged worth more than the step. `testEveryStationHasAFaceWithinOneStep` holds the bound.

The bigger finding is that **two of the three footprints were fiction.** `FieldModel.moveCharge` and `moveGaussSurface` clamped only `y` — a charge could be dragged clear across the room — and `CircuitsModel` clamped to a 3 m **sphere**. Alone in a room, both were harmless; with three benches inside 1.4 m of each other, either one parks an object inside a neighbour. Both now clamp to their station (`FieldModel.regionHalfExtents`, `CircuitsModel.buildHalfExtents`), inset by the object's own half-size so a *thing with size* stays inside rather than merely having its centre inside — which is why a charge dragged at the floor now rests its surface on the boundary instead of sinking half-way through it. The generalisable lesson: **co-presence does not create these bugs, it reveals them. A limit nothing was near is a limit nobody tested.** Free-charge drift narrows 0.715 → 0.55 and Gauss radius 0.6 → 0.55 so each still has somewhere to move once inset.

## 2026-07-30 — Focus is not a picker: emphasis without absence

**Decision:** One station of a world is **focused** at a time — lit, with its panel section open — while the others stand back at `StationEmphasis.dimFloor` (0.40) with their sections folded to a single live readout. Focus follows the hands: any tap or drag landing on a station attends to it **and is forwarded in the same event**, never consumed. It also follows the panel, since opening a section attends to its bench. This amends the entry below, which said both halves must be simultaneously *present*; the amended rule is that both halves must be simultaneously **present, live and reachable**.

**Context:** "Turn your head" carried two stations. It does not carry three, and Electric Fields is coming to the same world: three lit apparatus is a room with no subject, and three control panels stacked in one window is a wall nobody reads. The obvious fix is the one this app has undone twice, so the burden here is to show that emphasis is a different thing from a picker rather than a politer name for one.

**Consequences:** The distinction is four properties, each of which is a test rather than a claim — **if any of the four reaches zero, this is a picker again.** (1) *Still solving:* the unfocused station's solver runs in the same world tick, in the same fixed order. Pausing dim stations is forbidden permanently, **including as a performance fix** — if frames get tight, cut an unfocused station's visual work (particle budgets, trail lengths), never its physics. (2) *Still hittable:* focus never touches `CollisionComponent` or `InputTargetComponent`, and never consumes a gesture, so a drag beginning on a dim magnet moves the magnet. A dim station is dimmer, not less capable — the moment it costs an extra gesture to use, it is a picker wearing a dimmer's clothes. (3) *Still in the panel:* sections collapse, never disappear, so nothing leaves the accessibility tree or the simulator's reach. (4) *Never dark:* emphasis floors above zero, and `StationFocusTests` asserts that floor is greater than zero, quoting this entry.

And one hard rule falls out of it: **emphasis is opacity, light and sound — never geometry.** Focus must not animate a station's root transform. Every grab in this app is a `RelativeDrag` (target plus hand *displacement*), which a **constant** translation leaves untouched — precisely why lab placement and the station seats are safe — but an **animating** one does not: a station receding mid-drag would slide the held body out from under the fingers, and would make the layout's tested bounds a lie. New debug args `-focusStation <name>` (with `snap()`, so a CLI screenshot lands on settled emphasis rather than a mid-fade frame) and `-stationDim <0…1>` (`1` = no dimming, the control image). `-viewScale` becomes addressed — `-viewScale.bench` — because a bare key now zooms every station at once.

## 2026-07-30 — Circuits and Magnetism become one E&M world, co-present

**Decision:** `circuits` and `magnetism` are gone from the catalog as separate entries and are now the two **stations** of a single module, `em` ("Electricity & Magnetism"). Both benches stand in the room **at the same time** — the circuit workshop on the user's left, the magnetic field on their right — joined by a visible two-conductor cable that carries the bench's inductor current to an electromagnet standing in the field. Neither model, renderer, nor physics changed; `EMStationLayout` translates each station's display root onto an arc, and `EMWorldSpaceView` hosts both under one `RealityView` with gestures routed by which station owns the entity the hands hit. A third seat is reserved and bounds-checked for Electric Fields.

**Context:** The link already existed and was invisible. `MagnetismSpaceView` read `appModel.circuitsModel.inductorCurrent` every frame, and `CircuitsModel.inductorCurrent`'s own doc comment described the merged module as if it existed — but the two benches were separate catalog entries, so "open the switch and the electromagnet dies" was an assertion in a control panel that required leaving the room to test. A coil carrying a current *is* a magnet; keeping the coil and the current in different modules made the app's single best demonstration unwatchable.

**Consequences:** This is the third merger attempted in this app and the first that should survive, for one specific reason: **the previous two died of bench pickers.** Fields and Oscillators each hid their second half behind a segmented control that lived only in the window panel, after the controls had already moved into spatial pods — so Magnetism and Springs became unreachable and both mergers were undone. Here there is nothing to pick and nothing to find; both benches are always in the room and always solving. That is the rule worth keeping: **a merger is only a merger if both halves are simultaneously present — if the user has to choose which half exists, it is a picker, and pickers get lost.** *(Amended the same day — see "Focus is not a picker" above. The bar is now present, live **and reachable**; one station may be emphasised over the others, but none may cease to exist.)* Two geometric invariants are now tested rather than hoped for (`EMStationLayoutTests`): station volumes must stay disjoint, and each bench's clamps and grids must stay inside its own station — a magnet free to glide 0.85 m off centre would otherwise drift into the circuit bench. `MagnetismModel.regionHalfExtents.x` narrowed 0.85 → 0.62 and `regionHalfExtent` 0.85 → 0.72 for exactly that reason. Side furniture (the layers bank, the spawn well) now hangs **outboard**, since the flanks that used to be free now face each other. `-emLink 1` stages a driven coil for CLI screenshots.

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
