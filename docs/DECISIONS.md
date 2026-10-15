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

## 2026-10-14 — Pendulums couple by a spring

**Decision:** Two simple pendulums can be joined by a spring between their bobs. Coupling is a ring petal (Couple / Uncouple), a More verb hangs a ready pair, and a More slider sets the spring constant. A coupled pair is stepped jointly by `PhysicsCore.CoupledPendulums`, and More › Values shows ω₁ = √(g/L), ω₂ = √(g/L + 2k/m) and the beat 2π/(ω₂ − ω₁) for an identical pair.

**Context:** This is one of the three deeper-lab additions the owner chose for the two-week portfolio push. The single pendulum's integrator sets each bob's speed from the work-energy theorem using gravity and drag alone. A spring moves energy between the bobs, so it cannot simply be added there.

**Consequences:**
- **RATTLE.** The pair uses velocity Verlet, with each position pulled back onto its cable's sphere along the constraint gradient (SHAKE) and each velocity made tangent. This is symplectic and time-reversible: over a minute the energy wanders by 7e-6 and does not drift. `CoupledPendulumsTests` also check:
  - each mode's frequency to 1e-3;
  - a 99.5% transfer at half a beat;
  - under 1% transfer for a swing across the spring;
  - a held bob still pulling its partner.
- **A bug the tests caught before it shipped.** "Coupled pair" coupled to the *nearest* free pendulum, and the cradle's end bob (35 cm away) beat the pair's own partner (40 cm). The spring went to the cradle and wrecked it. The pair now names its partner, and coupling needs a pivot at least 30 cm away, beyond the cradle's 28 cm.
- **Collisions resolve per cluster of bobs that can touch.** One sweep over the room let any pendulum change the cradle's sort axis and iteration budget. `PendulumsCoupledTests` holds the cradle bit-identical beside a pair.
- **The force layer includes the spring.** Tension adds the spring's pull along the cable, and the net arrow includes the spring. The helix is the spring's own picture, so there is no separate spring arrow.
- **The release preview of a coupled bob simulates the pair.**

## 2026-10-14 — Light & Optics returns, in three dimensions

**Decision:** A seventh lab, Light & Optics. It has:
- a laser and a torch of white light;
- mirrors, prisms, a converging lens and a glass bar, from a well on the left.

Each piece can be carried anywhere and turned by an aim bead. The light is traced by a new `PhysicsCore.LightTracer` and lands on the room's real walls. It opens on white light through a flint prism at least deviation, fanned straight ahead into a spectrum on the wall, and the green laser turned by a mirror into the glass bar, which traps it by total internal reflection.

**Context:** The owner's two-week brief for the admissions portfolio asked for new labs as well as deeper ones, and chose optics. This reverses two calls at the owner's request:
- "Optics stays archived" (2026-07-28/29). The bench was cut for being "a line of elements in a row", so the new lab assumes no axis: every piece has a full pose and the light goes wherever the room sends it.
- "No new modules" (earlier on 2026-10-14).

**Consequences:**
- **The tracer is new physics, and is tested to the textbook.** Each glass piece is a convex solid made of half-spaces, spheres and a cylinder. A ray meets it on one interval, so one routine serves the prism, block and lens. Every face splits the light by Fresnel. Each wavelength goes through Schott's Sellmeier index. Power is accounted for to 1e-12. `LightTracerTests` check, among other things:
  - catalogue indices and Abbe numbers;
  - Fresnel's 4% at normal incidence, Brewster's angle and reciprocity;
  - Snell and the slab's exact shift at an arbitrary pose;
  - TIR switching on at n = √2 in a right-angle prism;
  - minimum deviation recovering n to 1e-7;
  - a thick lens's back focal distance and its h² spherical aberration;
  - frame invariance.
- **Two first builds got the geometry wrong, and the fixes are recorded where they live.**
  - Aimed at the prism's centroid, the torch's beam entered through the base. It now aims at the entry face's middle, the least-deviation path.
  - `-roomWall -2.6` was silently dropped, because an argument value starting with "-" is read as a key. It takes a distance now.
- **The light lands only on walls ARKit has found** (`collisionWalls`), plus the floor. It never lands on the unscanned box: a spectrum painted on a wall that is not there would be the one lie in the lab.
- **Weak reflections are off until asked for.** They are real (15% at the prism's first face), but the opening view has to read as the main path first.
- **The seventh portal stands in the middle of the arc**, in the electricity group after Magnetism. Its emblem is the lab's own prism and tracer, rocking through least deviation.
- **What changed because there are seven labs:**
  - Every test that counted six now counts seven. `AtmosphereCriterionTests` counts "all but one" rather than a number, so adding a lab cannot quietly allow a second dimming exception.
  - The VoiceOver hints no longer name a number.
  - The accent is pearl (#E6DCFF). The first choice, ice blue, failed the arrow-separation test: it was ΔE 13 from the gravity arrow.
- **The archived bench files stay archived.** `Refraction` is the one piece of the old optics code the new tracer uses.

## 2026-10-14 — The wordmark speaks the app's language

**Decision:** The home's 3-D title is now set the way every label in the
room is set: SF Pro Rounded Semibold, title case, "Physics" over
"Playground" at one type size, centred. The letters are soft white solids
with a rounded edge, standing 3 cm off a glass plaque that has the shape
and material of every panel in the app. The dot of the i is a particle of
champagne light, the colour of the opening's particles and the portals'
bezels and the one accent the title keeps. All of the motion from the
entry below stays, and the dot drops onto its i last.

**Context:** The owner did not like the machined plaque's style and asked
for the title to follow the design language of the whole app while staying
a 3-D model. That reverses the 2026-09-07 "back to the old style", at the
owner's own request. The plaque was the one surface in the app that did not
speak visionOS: uppercase SF Pro Display Bold, a milled champagne chamfer,
and no glass, where everything else is rounded system type on glass.

**Consequences:**
- `Tools/hubwordmark.py` mills the letters, one mesh each. A glyph's face
  is dissolved to one polygon before it is bevelled. Blender fills a glyph
  as a fan of slivers, and the bevel slid along them: the first build grew
  spikes up to 0.069 em at every stroke end. The round is 0.020 em, because
  past about 0.022 the inset folds in the crotch where an arch leaves its
  stem. The tool's docstring has the measurements.
- `Tools/hubtitleglyphs.py` and its `HubTitleGlyphs_*` assets are deleted.
  The per-letter machined glyphs had no other use.
- The machined plaque is still the fallback (`HubTitleStyle.milled`, with
  `hubtitles.py` and its assets untouched). Deleting `HubTitleGlyphs.swift`,
  `HubTitleMotion.swift` and the two `HubWordmark_*` assets restores the
  still machined plaque exactly.
- The plaque is a SwiftUI glass attachment and never a target. It fades in
  with the portal labels while the letters bring themselves in, and More
  stands below it. The glass now keeps white letters legible on a white
  wall, which was the chamfer's job.

## 2026-10-14 — The wordmark comes alive, letter by letter

**Decision:** The machined plaque stays exactly as it looks. What changes
is that its letters now move, each by physics (`Hub/HubTitleMotion`):
- **PHYSICS** letters are dropped from 30 cm in turn and bounce to rest
  (restitution 0.42, every arc a parabola). The line lands across the
  opening's bell.
- **PLAYGROUND** letters hang from their top edges like signs and swing
  in, each a damped physical pendulum whose ω₀² = g·(h/2)/(h²/3 + w²/12)
  comes from the letter's own size.
- **At rest**, a travelling wave a few millimetres high rolls along both
  lines, and each letter tilts with its slope.
- **A glint** runs along the champagne keylines, white-hot at its centre:
  first as the bell strikes, then every nine seconds.
- **A pinch on any letter hops it** 7 cm, and it bounces back down to
  exactly where it stood.
- **Reduce Motion** holds every letter still; a walk back from a lab
  skips the arrival.

**Context:** The owner asked for the title to look cooler and more
animated, creatively. The 2026-09-07 auditions say what not to do: they
rejected typeface swaps and novelty constructions (neon, chalkboard,
hologram) and kept the machined plaque. So the look is untouched and the
life is all motion, in the app's own language. `Tools/hubtitleglyphs.py`
exports the same milled glyphs one letter at a time, reusing
`hubtitles.py`'s recipe unchanged, so the chamfer, the font cut and the
rim split are identical; each letter gets a hinge.

**Consequences:**
- It is removable by construction. `HubScene.buildBubbleTitle` asks
  `HubTitleGlyphs` for a line first and falls back to the still milled
  line. Deleting `HubTitleGlyphs.swift`, `HubTitleMotion.swift` and the
  two `HubTitleGlyphs_*` assets restores the still wordmark exactly.
  `HubTitleStyle` and the per-line assets are untouched. (Superseded the
  same day by the entry above: the letters are now `HubWordmark_*`, and
  `hubtitleglyphs.py` and its assets are deleted.)
- Each letter is a pinch target with the system hover. Its collider is
  its ink, so the collider-fit criterion measures it.
- `HubTitleMotionTests` pins the physics: free fall, e² per bounce, the
  rod limit of the swing rate (3g/2L), the tilt being the wave's slope,
  and that everything ends at rest. `HubTitleGlyphsTests` checks the 17
  letters, the hop and stillness in the real scene.

## 2026-10-14 — The home is polished, not redesigned

**Decision:** The home keeps its layout, its opening's physics and its
wordmark, which stays exactly as chosen on 2026-09-07. What changed is
finish and motion:
- **Bezels:** each portal's rim is a fine bezel of the wordmark's
  champagne alloy (2.4 mm, 16-sided, lit as metal) where it was a
  six-sided white unlit tube.
- **Panes:** stock glass darkening toward the edge like a lens, instead
  of a flat grey fill, set in the bezel's own plane.
- **Labels:** system type on a glass capsule with the lab's colour as a
  dot, where they were extruded neon on a dark pill.
- **Previews:** 20 cm, so their square's corners clear the rim.
- **The opening's particles:** soft glowing sprites of varied size
  instead of flat beads.
- **Arrival:** the portals grow from 92 % into place as their glass
  fades up, and the wordmark rises 3.5 cm into place as it does (both
  pure functions in `Opening`, tested to end exactly at rest).
- **At rest:** the portals float ±4 mm on their own phases, never under
  stillness.
- **More** sits clear of the rule; the projectile preview's ball fades
  rather than blinking, and its hoop answers the landing.

**Context:** The owner asked for the title screen's models and animations
to be smoother, more polished and cleaner. The memory of the 2026-09-07
auditions says not to touch the wordmark unprompted, so every change is
around it. Three defects only showed in photographs:
- **The sprites first drew as pale squares.** RealityKit takes
  transparency from an opacity mask, not from a colour texture's alpha,
  and a sprite that writes depth cuts its square out of the dimming shell
  behind it. They now use a mask and `writesDepth = false`.
- **Every rim, old and new, had two dark ticks.** A tube swept round a
  vertical circle pinches where its path runs straight up or down. The
  bezel is now swept flat and rotated upright.
- **The glass pane showed parallax.** Set 3 cm behind the rim, its edge
  was the obvious suspect for the ticks and was moved into the rim's
  plane on the way to finding the real cause.

**Consequences:**
- The portal's visible parts hang off a `body`, which floats and scales.
  The anchor keeps the transform, the target and the entering swell.
- The label is a SwiftUI attachment, which visual bounds do not measure,
  so a transparent proxy of the label's measured size stands with it.
  The collider-fit criterion then checks the target against the real
  label.
- Any other transparent sprite in the app that writes depth will cut
  the same square from the dimming shell. The opening was the one place
  it showed.

## 2026-10-14 — The sound effects join the music's family

**Decision:** Every one-shot and looping tone is re-voiced in
`DesignSystem/SoundEffects`, built from the score's oscillators, filters
and room.
- **Interface sounds are in the music's key:** the grab tick on E6, the
  release on B5, the pop a glass droplet on A5, and the chime a rolled
  A-major triad of the score's FM bells.
- **Physical sounds are shaped from falling pitch and filtered, seeded
  noise:** the thud (150 → 62 Hz with a muffled contact), the whoosh (two
  swept bands, softened), the boom (a falling sub under a two-stage
  rumble).
- **The opening's swell is the score's first chord rising** through an
  opening filter under an airy crest, and it lets go as the bell strikes
  at 2.65 s.
- **Two sounds that borrowed the UI pop now have their own:** the
  cradle's `clack` (three steel-sphere modes) and the launcher's `launch`
  (a pneumatic thump).
- **The one looping tone is split in two:** `glass` sings the orbital
  chord, and `hum` (a full harmonic series, odd harmonics forward) is
  Circuits' mains.

**Context:** After the score, the owner asked for the same treatment on
the effects. A spectrogram of the old set showed full-band vertical
lines. The chirps stopped mid-cycle, so every pop and tick ended on a
click. The thud, whoosh and boom were raw white noise. Several unrelated
events shared one UI pop, and one 220 Hz loop was both a chord and a
mains hum.

**Consequences:**
- Every one-shot opens on a raised-cosine onset and closes on a
  raised-cosine fade, so none clicks; `SoundEffectsTests` holds both
  ends.
- Levels stay within a few dB of the old sounds, so the call sites'
  volumes keep their meaning. Boom is trimmed 3.4 dB because it now
  sustains, and clack is lifted because it is short.
- The cache names carry `oneShotVersion` (2) and the tones' own version.
  Older versions are deleted on launch. **Change a recipe, bump its
  version.**
- The score renders bit-for-bit as before. Its filter gained a band-pass
  output and its room a size parameter, both defaulting to what it used.

## 2026-10-14 — The house music becomes a score

**Decision:** The ambient loop is now `DesignSystem/AmbientScore`: a 64 s
seamless stereo loop of four suspended chords (Amaj9 → F♯m9 → Dmaj9♯11 →
Esus). Each chord is warm detuned saws under a soft 24 dB/oct low-pass,
with the old pad's glassy sines kept on top. A dozen soft FM bells answer
in stereo echoes, and all of it sits in a long Freeverb-style room. It
plays head-locked through `ChannelAudioComponent`, fades in over 4 s and
falls away over 1.2 s.

**Context:** The owner likes the old ambience's ethereal synth character
and asked for it more polished. The old pad was nine pure sines in one
chord, mono, with no reverb. It hung at one point a metre in front of the
wearer, so it changed as they moved, and its three bells struck at the
same moments every 36 s. The score keeps the suspended, open voicings and
the glass. What it adds is warmth, space, width and slow harmonic
motion. Every pad voice shares a tone with the next chord, and E and G♯
ring through three of the four. A first draft let the saws through a
2-pole filter at up to 2.6 kHz, and a spectrogram showed harmonics to
6 kHz only 35 dB down: buzz, not air. The cutoff is now 2.2× the note,
300–1,100 Hz, through two stages.

**Consequences:**
- The loop is rendered past its end and the overhang folded back onto
  the start. The mix is linear up to the limiter, so the seam is exactly
  what the previous pass would have left ringing.
  `AmbientScoreTests.testTheLoopHasNoSeam` holds it below an ordinary
  sample step.
- Bells are placed by a seeded generator, so every device writes the
  same file.
- Each channel is levelled to the old pad's −17.3 dBFS RMS, so the room
  is no louder.
- The file is 11 MB in Caches, rendered once in about a second, after
  the one-shots so the opening's bell never waits behind it.
- Its name carries the version (`ambient-score-1.wav`), and older
  `ambient-*` files are deleted. **Change the score, bump the name.**
- The gain stays −22 dB. Head-locked stereo and a spatial point at 1 m
  are not the same loudness, so the level is a device judgement.

## 2026-10-14 — The room holds the apparatus; More holds the rest

**Decision:** A lab's title bar is Home, More, the lab's name and
Pause/Resume. More is an ornament beside the window. It holds the lab's
own secondary controls (`ModuleDescriptor.more`), a slider for each
quantity with no object to stretch (`adjustables`), its live Values, the
room (Move, Studio Mode, dimming), Settings and Reset. The palette bead is
deleted. So is the in-room Physics box with its rails, and the Time reel's
"Resume here".

**Context:** This reverses 2026-08-01 ("there are no module panels") as
far as secondary controls go. The owner's brief makes a panel the fallback
and direct manipulation the default. It also asks that each lab open on
its primary interaction, with the secondary behind one consistent More.
The bead had duplicated the title bar three times (Home, Reset and its own
Pause next to the reel's Resume). Its lab ring duplicated the home.

**Consequences:** Nothing secondary stands in the room any more. A module
declares items, and the shell draws them in the one control family, so a
module cannot ship a one-off control. Pause is one pinch away in the
window rather than two in the room. Lab-to-lab is Home, then a portal.
After the first arrival the home appears instantly, so that is two
pinches, as the bead's ring was.

## 2026-10-14 — The home is six portals, reached through a particle opening

**Decision:** The gallery goes. That means the two terraces (tables, by the
house rule), the pucks, the domain signs, the bench labels, the
head-direction focus and its pool of accent light, the podium with its
latches and Load button, and the grab bar with `GalleryPlacement`. In their
place, six portals stand on one arc around the wearer at eye level, 1.75 m
out, 20° apart, E&M on the left and mechanics on the right. Each is a
stock-glass pane with a thin white rim. Its lab's emblem runs its own
physics in a loop in front of the pane (`HubVignettes`), and one short word
in the lab's accent sits under it. **A pinch on a portal enters the lab**:
one step where there were two. The machined wordmark stays, smaller,
behind the arc. The flat lab list, Settings and About sit behind one More
under it. The home dims the room slightly (`AppModel.homeDimming`, 0.3).

The home is the end state of **the opening** (`Hub/Opening.swift`, about
3.1 s). Particles fade up on a sheet above eye level, then:
- **Fall and swirl.** They arch in crossed uniform gravity and a
  horizontal magnetic field: an exact cycloid, at rest again after one
  cyclotron period. Positive and negative charges part in opposite
  directions.
- **Ripple.** They ride an Airy deep-water wave (ω² = gk) under a sin²
  envelope.
- **Settle.** A critically damped spring draws them onto the rims as the
  glass fades up, on the calibration bell.

Every hand-over happens with the particles at rest, so nothing is eased. A
box of collider around the wearer, there only while the opening plays,
makes any pinch skip to the end. Under Reduce Motion the portals fade in.
A walk back from a lab does not replay it. `-hubIntro <s>` pins the clock,
and `-moreOpen 1` unfolds the More.

**Context:** The owner's brief asked for an opening that "visibly obeys
physics" and a home where each portal says what its lab does without a
description. The project's physics standard asked that the opening's
motion be real. So each phase is a closed-form solution, and
`OpeningTests` checks it as physics:
- the swirl satisfies the Lorentz equation, and the field does no work;
- the ripple obeys deep-water dispersion and starts and ends at rest;
- the settle never overshoots;
- nothing jumps between phases;
- the cloud keeps clear of the wearer's face.

**Consequences:** `HubIntro`, `GalleryLayout`, `GalleryPlacement`,
`HubDomainTitle` and their tests are gone, and so are `-hubDock` and
`-hubFocus`. `PortalDoorTests` replace `GalleryDoorTests`. An upgraded
install forgets `hub.galleryOffset` and `hub.galleryYaw`.
`HOMESCREEN_SPEC.md` is marked superseded. The audit flags the wordmark as
the most debatable thing still on the home: it was kept because the owner
chose it after two auditions.

## 2026-10-14 — One control language

**Decision:** Every control is `ControlButton`, `ControlToggle`,
`ControlSlider` or `MoreButton` (`RenderKit/Controls`), in a window or in
the room. In the room, the same SwiftUI views ride entities through
`ViewAttachmentComponent`. One glow, `LiveGlow`, marks what a hand holds.
See DESIGN_SYSTEM.md › One control language.

**Context:** Fourteen control styles had grown, one feature at a time. A
machined verb plate, a frosted layer plate and a dark petal were three
private languages for "press this". The brief asked for stock glass,
system hover, SF Symbols and 60 pt targets everywhere, with a single
signature glow.

**Consequences:** In-room controls have no colliders of their own any
more. The rule that a collider never be larger than its object now governs
only objects. VoiceOver reads in-room controls as SwiftUI controls, so the
entity-level `SpatialActionComponent` survives only on objects and the
home's portals. `ControlLanguageCriterionTests` fails any app source that
starts a second language.

## 2026-10-14 — The Lab Notebook and the last progress tracking are cut

**Decision:** The owner's subtraction brief (`docs/redesign-audit.md`) cuts
the Lab Notebook, any challenges, and progress tracking. Removed with the
Notebook:
- `LabNotebook`, `NotebookView` and the Notebook window;
- the capture petal and the title bar's and home's book buttons;
- `-notebookOpen` and `-notebookSeed`;
- `LabNotebookTests`;
- the module legends (`LegendItem`, `LegendView`, every `legend:`), whose
  only surface was the Notebook window.

Removed from Projectiles: the hoop streak, the persisted best streak
(`kinematics.bestStreak`) and the score number over each hoop. A hoop
still flashes and chimes when a ball passes down through it, and the model
counts `passes`, not `score`. An upgraded install forgets the Notebook's
entries and the best streak, as it already forgot `visited.modules`.
`NotebookEntry.Reading` becomes `Reading`. `captureReadings` becomes
`readings`, the Physics box's one list; `physicsRows` existed only so the
Notebook could record more than the box showed, and goes.

**Context:** This reverses 2026-07-29 ("The Lab Notebook goes live") and
the demo's notebook beat from the release plan. No daily-challenge surface
ever shipped. The experiments system and its progress ring went on
2026-08-09. That left the streak as the last thing that counted the
wearer.

**Consequences:** Readings are now only for reading, in the Physics box.
Nothing exports. `SellingCopyCriterionTests` bans "Notebook", its two
arguments and "best streak" from the selling copy. Demo beat 9 shows the
Physics box instead. PRIVACY no longer lists notebook entries.

## 2026-10-14 — The labs answer a hand the same way, and their words agree

**Decision:** A polish pass across all six labs, no new controls. Three
kinds of change.

*Feedback.* Every lab now acknowledges a grab with the pickup flash and
grab tick and a let-go with the release tick. Projectiles, Orbital
Mechanics and Electric Fields had both coded but keyed on manipulation
flags nothing set, left from a grab system the labs no longer use; each
renderer now reads the held object off its model (`heldBodyID`,
`heldChargeID`, a ball's `.held` status) and the dead flags and their
always-true branches are gone. Magnetism had neither and gains both. A
fired petal pops, as a fired action plate does, so Delete is no longer
silent. Opening a ring on a magnet or a circuit part selects it, so the
halo and the readout name the object the ring is on. Electric Fields folds
its ring with the house tick; Pendulums' collar ring pops and ticks, folds
on a tap elsewhere, and is reachable from VoiceOver. Pendulums whooshes
only on a throw (0.25 m/s), not on a still release or the end of a length
edit. The hoop's Delete and the launcher's Clear wear destructive red like
every other petal that removes something. The palette's Pause petal reads
"Resume" with a play glyph while the lab is paused. Projectiles' ball fan
opens above and right of the launcher, tighter (`ballFanLayout`), because
at the house default its first disc stood 6° from the world row's Jupiter,
nearer the wearer and in front of it.

*Correctness that showed.* Circuit Workshop saves after Clear bench, a
preset and Reset (`commitBench`); none of the three did, so a relaunch
reopened the bench the wearer had just replaced. The save is not inside
`reset()` itself, because `init` runs it before restoring and would
write the starter loop over a bench that failed to restore. Readouts no
longer freeze on an old number: `Callout.setText` and `BackedLabel.setText`
return whether the label took the text, and the callers that cache "what
I last showed" record only what landed (the compass, the catch and flight
callouts, the arc's apex, landing and protractor labels, hoop aim and
score, the capacitor readout, the voltage towers, part labels, body
names). Twin suns no longer moves the selection onto a star. The merge
flash times out on the clock, not a 90 Hz frame count. Under Reduce
Motion the planets stop turning on their axes, an armed terminal stops
breathing, a petal does not swell, and the merge flash does not grow;
motion that is the physics itself (electron flow, the swing, the arcs)
stays.

*Words.* Notebook rows say what the plates say: Projectiles' ball is
"Golf ball", not `golfBall`; Pendulums' "Friction" is "Air resistance";
Elevation closes its degree sign up like Inclination; Orbital's "Bound:
on" is "Orbit: bound". A mass grip reads "1 Earth", "1.00 Sun", and a
comet's 3.7 × 10⁻¹¹ Earths in scientific notation rather than "0.00
Earths" (`PhysicsFormat.count`); the clock reads "−20×" with the room's
minus (`PhysicsFormat.multiplier`). The callouts that still used
`String(format:)` go through `PhysicsFormat`. "AC Source" is "AC source",
and the meter's notes say "across the battery". Wearer-facing text is
American, which is how the owner writes; the room-sensing sentences and
two VoiceOver hints say "lab" for "experiment", and the CSV header says
"lab" for "module". The Physics box's rails are spoken by their names,
not as "physics-gravity"; a ring's value readout is renamed on every
retarget, so the probe's Charge is not announced as Strength. Magnetism's
legend has one compass, as the room does.

**Context:** Owner, after the home's pass: *"keep going, polish the labs
too."* Two read-only surveys of the six labs, one of feedback and one of
words, plus simulator photographs of each lab; every finding was checked
against the code before it was changed, and several the surveys raised
were left alone on purpose: single-object deletes do not confirm in any
lab (consistent, and undo is a pull from the well), the Kinematics hoop
orbit capability with no door stays parked, and per-frame component
writes in `Bloom` and `Well` are a performance question for a device
profile, not a polish pass.

**Consequences:** `PhysicsFormatTests` gains the count and multiplier
cases; `CircuitsModelTests.testPresetsAndClearingAreSaved`;
`FanLayoutTests` lists the ball fan among the shipped fans;
`LabNotebookTests` reads the "lab" header. `SpatialTrackControl` takes an
optional `spokenName`. The device list has the checks.

## 2026-10-14 — The names go on the bench, and the last chrome inconsistencies close

**Decision:** The gallery's six exhibit names leave the air. Each is a lit
inlay on its terrace's dark front edge, directly under its mount, in the
lab's accent at the house exhibit size (`HubScene.benchLabel`). A label
never moves: it brightens while you face its exhibit, and dims to a third
while its lab stands on the pad, so an empty mount still says what belongs
there. The floating name pivots are deleted. The focus pool is
counter-lifted every frame so it lights the mount while the exhibit rises
off it. In the labs, the palette's Reset petal arms before it fires
(destructive red, "Tap again", `SpatialActionBank.armWindow`; folding the
ring disarms), and the capture petal thuds when the lab had nothing to
write down instead of chiming over an empty page. Smaller: icon-only
buttons in the title bar and the home's utility bar name themselves on
look (`.help`); the Settings volume slider gains speaker glyphs at its
ends; Orbital Mechanics' capture row "Bound: on" reads "Orbit: bound" or
"leaving", the data card's word; the home's Settings button stops
promising an onboarding section deleted on 2026-09-04; the title bar's
back button is "Home", not "the catalog"; the pad's plaque reads "LOAD
LAB" and the Reset confirmation "how the lab opened" — "module" was the
codebase's word showing through, the only two places a wearer met it; and `AppModel.visitedModuleIDs`,
which wrote every lab visited to `UserDefaults` for "New" badges deleted in
August, is deleted and its key cleared on launch.

**Context:** Owner, before release: *"make the experience as polished as
possible. Keep design consistent, make the ui look nicer"*, with the home's
platforms named, no new modules and nothing more cluttered. Simulator
photographs of the gallery found two defects the device list had not.
The names were bright accent type with no casing, the light-on-light
problem the wordmark and door signs had already been given keylines for,
and Circuit Workshop's green and Pendulums' magenta nearly vanished
against a cream wall. And a focused exhibit's name rode its 0.09 m lift
and 1.22× growth into its terrace's door sign: the sign's rule hangs about
0.465 m above the bench and the name's centre reached about 0.55 m. That
is geometry, not perspective, and the space between a lifted exhibit's top
(about 0.43 m) and the rule cannot hold a line of type. The pool of focus
light rode the same lift and hung as a smudge above the mount it was
meant to light. In the labs, a single pinch on the palette's Reset wiped
the lab, while the title bar's Reset asks and every Clear plate arms
first; Circuit Workshop's bench survives relaunch, so this was the one
unguarded path to losing it.

**Why the bench and not a fix in the air.** The owner cut a backing card
behind the gallery's type twice (the names on 2026-08-04, the wordmark on
2026-08-09) because a card blocks the room. The bench's front edge is 55 mm
of dark graphite that is already there: lit type on it gets the contrast
of a card without adding one. It also removes three tiers of floating type
down to two (the wordmark and the door signs), puts each name where a
museum puts it, and makes the dock legible from the terrace. Names stay
legible at all times, which was the owner's 2026-08-04 requirement.

**Consequences:** `GalleryLayoutTests.testEveryExhibitTitleFitsItsPitch`
measures the bench labels (3 cm of bare graphite between neighbours, and
every label clear of the face's chamfers), and
`testEveryLabelStandsUnderItsExhibitOnTheBenchFace` holds the placement.
`PaletteResetTests` drives the petal through `handleTap` and `update`:
one pinch arms and resets nothing, the second fires once, the arm runs out
after the window, folding the ring disarms, and the armed petal reads
"Tap again". `-paletteReset 1` opens the ring with Reset armed and held,
photographed armed and never fired, like `-circClear`. The capture petal's thud closes
the "refusal sound for a failed capture" item on the 2026-09-01 backlog.
Whether the inlay reads in a dim room is a device question and is on the
list.

## 2026-09-07 — The wordmark stays the machined plaque

**Decision:** The home's 3-D title keeps its machined dark plaque with the champagne chamfer, SF Pro Display Bold, milled by `Tools/hubtitles.py`. Two auditions the same day were built, photographed and reverted.

**Context:** The owner asked for three new looks, shown at once, to pick from. Round one put Futura, New York and DIN on the same plaque with per-letter hop, swing and turn motions; it was rejected as the same object in a different face. Round two changed the object — a neon script sign that ignited and hummed, a chalkboard written and wiped, a cyan wireframe hologram that drifted, scanned and glitched — and the owner chose to keep the original instead.

**Consequences:** Nothing of either round ships: no candidate assets, no per-glyph pivots, no `-titleClock` argument. What was learned and is worth keeping is in the git history and this entry: a per-glyph bake (each letter its own named part) is cheap in Blender and grouping by name in Swift takes twenty lines; fontTools can snapshot any system face, static or variable, for Blender; and the outline-as-tube trick makes a wireframe letter. If the title is revisited, start from a different object, not a different typeface — that much of round one's rejection stands.

## 2026-09-06 — The body's data card is five lines

**Decision:** The selected body's floating card is a two-column grid of
five lines at label size — r and v; a and e; q and Q; i and T; E with
the word "bound" or "leaving" — in place of fourteen footnote rows, three
energies, the orientation angles Ω, ω, ν and a paragraph explaining
their conventions. The angles and the energy split stay in the notebook
capture.

**Context:** Owner: *"condense the physics ui box on the planets and
make it easier to read."* The card stood as a tall column of tiny rows
over the planet, most of them conventions nobody reads on a floating
card, in a lab whose rule is that nothing explains itself in prose.

## 2026-09-06 — Letting go of a body puts it in orbit

**Decision:** A released body takes the circular prograde orbit at its
distance from the primary with the hand's throw laid on top as a
perturbation (`OrbitalMechanicsModel.insertionVelocity`, shared with the
well's `addBody` through `circularVelocity`). The held-body ghost shows
the same rule. The primary itself is simply thrown.

**Context:** Owner: *"the orbiting still feels weird and I cant place
them into orbit around the sun."* Release set the velocity to the
hand's alone, scaled so 0.35 m/s was orbital speed: a still hand dropped
the planet into the Sun, and an orbit needed a throw at exactly that
speed exactly along the orbit — which the checklist's own "let go
without moving your hand: it holds a circular orbit" already promised
and the code did not do.

**Consequences:** `testAStillHandPlacesABodyOnACircularOrbit`;
`testReleaseLaysTheThrowOnTheCircularOrbit` replaces the bare
hand-velocity test; a hard throw still unbinds. Lagrange capture keeps
precedence at a point.

## 2026-09-06 — Orbital Mechanics: the orbital system re-approached

**Decision:** Gravity Lab is renamed **Orbital Mechanics** (id `gravitylab`,
the `-grav*` arguments and `gravityAccent` unchanged; `shortTitle`
"Orbits"), and the orbital system is rebuilt from the integrator out.
`NBody.step` is a fourth-order symmetric symplectic composition (PEFRL:
four force evaluations, palindromic, so exactly time-reversible) with a
per-body softening floor whose potential matches its force; a held body
is `frozen` inside the step. The model keeps the system's net momentum
at zero (`settleMomentum` after every spawn, throw, edit, deletion and
split), sizes the substep from the shortest two-body timescale present
(6 h in the default system, capped at 96 per frame), checks merges every
substep, and records each body's path as `OrbitTrail` — the trailing
0.75 of its own osculating period, sampled a degree apart about the
heaviest body inside the substep loop, unwound under reverse time,
rebuilt for a scrub under the same rule with the live samples spliced
in. The renderer draws each trail as a `TrailRibbon` (`LowLevelMesh`,
rewritten in place, keyed by body id), 1.2 mm thick in the room at any
zoom, in the body's own colour, fading to nothing at the tail. The
orbit ring's tube is 1.4 mm in the room whatever the orbit or zoom and
its mesh follows the exact eccentricity. `celestialUI` names every
body's colour and the textures' base fills read it. The Moon preset is
removed (nine worlds). Arrows show the net pull.

**Context:** Owner: *"the whole orbiting system just does not feel quite
right. The colored paths of the planets orbits is inconsistent … I want
you to take a genuine reapproach at the code behind how the actual
system works."* Measured on an isolated Sun–Mercury: velocity Verlet at
the app's 1× step (8 640 s) turned the apse line 19″ per orbit, and at
the ≥5× step (21 600 s) 119″ — retrograde, 15× and 93× the real
Newtonian precession from the other planets (1.28″ per orbit,
prograde) — while conserving energy to 1e-8, which is why the existing
energy test never saw it; the device checklist told the wearer the creep
was "real Newtonian precession" and the ring–trail gap "was Jupiter"
(Jupiter moves Earth by ~0.03 mm of room). `reset()` seeded every planet
moving −z against a Sun at rest: 3.18e31 kg·m/s of net momentum, a
barycentre drifting at 16 m/s, 2.5 m of room per half hour at 100×,
trails smearing into cycloids while the ring rode the Sun. The trail
mesh rebuilt only when its point count changed, so once a body's 240
points were full the ribbon froze in space while the planet flew on
(Mercury after ~46 s at 1×); every body drew the same 1.92 m of ribbon
(Mercury 1.6 laps, Neptune 2 %); the spacing collapsed to one point per
frame at 100×; slots were positional, so a merged body's path could stay
in its colour; coalesced pipeline jobs were dropped; the tube was 1.2 mm
from Mercury to Neptune and scaled with the rig; a scrub changed every
trail's length. Four of the ten default bodies were the same teal
(Saturn, Uranus, Neptune, the comet had no colour and no texture), Earth's
trail was the velocity arrow's blue over an ocean-blue sphere, the ring
was 0.33 mm on Mercury and 27 mm on Neptune and popped in 0.03
eccentricity buckets mid-drag. The Moon preset spawned 30 mm of room
from Earth, inside the 37 mm merge distance, and merged on frame one.

| Scheme | step | evals/orbit | apsidal drift/orbit |
|---|---|---|---|
| velocity Verlet (was, 1×) | 8 640 s | 879 | −19.0″ |
| velocity Verlet (was, ≥5×) | 21 600 s | 352 | −118.7″ |
| PEFRL, equal cost | 34 560 s | 879 | −0.037″ |
| PEFRL at the ≥5× step | 21 600 s | 1 407 | −0.006″ |

Wisdom–Holman was considered and rejected: it needs a dominant primary
(Twin suns, held bodies and thrown hyperbolic bodies break the
splitting) and a universal-variable Kepler solver, for accuracy this
scene cannot display. Linear 0.5 m/AU stays (the owner's call): the
outer planets are a zoom away, not a compressed picture.

**Consequences:** `NBodyTests` gains the precession test (a mistyped
coefficient would drop the order to 2 and fail it), reversibility,
frozen-body and softening-potential tests; `OrbitTrailTests`,
`OrbitRingTests`, `GalleryLayoutTests.testEveryExhibitTitleFitsItsPitch`
and eleven model tests (frame, substeps, tunnelling, isolated
precession, trail fraction at 1× and 100×, uniform angle, a full trail
following its body, unwind, scrub, merge, the fan) are new;
`AccentAuthorityTests` holds every body's colour ΔE ≥ 12 from every
other, the ring's accent and the vector trio. `ARCHITECTURE.md`'s
per-frame rule records the one exception: a bounded `LowLevelMesh`
rewritten in place is a buffer write, not regeneration. The legend and
the checklist no longer attribute integrator error to Jupiter; the
checklist shows how to MAKE a visible gap (a 400-Earth world beside
Earth). The Sun starts on the origin and wobbles a few millimetres about
the barycentre from there — recentring the barycentre was tried and
dropped, because every hand point and test treats the Sun's start as
the origin and the millimetres buy nothing.

## 2026-09-06 — The shelf scrolls by a crown

**Decision:** Circuit Workshop's parts column scrolls by a crown: a
knurled machined thumbwheel (`Models/Shell/ShelfCrown.usdz`, from
`Tools/shelfcrown.py`) standing edge-on in a gap of the hairline spine
beside the column, at the window's middle. Roll it and the column rides
the hand one to one — flick, rubber-banded ends, a detent tick per slot
and a click on landing, all the arithmetic `RackScroll` already had —
and the crown turns with the column, arc over radius, so a crown at rest
is a readout of where the shelf is. On entering the lab the column
arrives coasting up into place with the crown rolling (`Well.arrive`,
`RackScroll.coast`); nothing under Reduce Motion. The track and its
thumb are gone.

**Context:** Owner: *"It not only does not work right now but I want it
to be something more flagship than just a basic scrollbar. However, do
not make it look too sloppy or over the top either."* It did not work
for a reason no test had exercised: the scene's one
`DragGesture(minimumDistance: 0)` reports the thumb on every frame, the
view pressed the shelf on every frame, and `Well.beginDrag` re-anchored
the grab each time — so the travel always measured zero and the thumb
never moved by hand. The same trap `PressLatch`'s header describes,
one line down from where it was described. And a thumb on a track is a
screen's idea: a 1 cm sliver a metre off, geared to move the strip
twice as far as the hand. The house already had the answer in the Time
Capsule's reel — give the capability an object, let the object turn as
a readout — and the headset itself scrolls by a crown.

**Consequences:** `Well.beginDrag` is idempotent (the first press wins,
like a latch) and the view guards it too; `WellScrollTests` presses
every frame the way the view does, which is the regression test the
thumb never had. The shelf reads the hand in the renderer's root frame,
not the zoomed bench's — it stands outside the zoom, and the old code's
bench-frame hand would have needed four times the travel in Electron
View. `Well.Rack` describes the spine and the crown's box, which joined
the clearance furniture; `ShelfCrownPropTests` holds the asset's axis
and size against the radius the Swift side turns it by. The crown's
pinch target is the collider rule's allowance and no more. The slots,
the window, the fade, VoiceOver paging on the crown and `-circScroll`
are unchanged. Whether a wearer reads a wheel as "roll me" with no
caret to prompt it is a device question, on the device list; the
arrival coast is the apparatus's own answer to it.

## 2026-09-05 — The Physics box

**Decision:** Every lab gets a Physics box: the title bar's ƒ button
unfolds a readout card in the room with the lab's live numbers, and one
house rail beside it for each quantity the lab lets you set —
`ModuleDescriptor.adjustables`. Fields: plate voltage and uniform B (the
probe's q stays on its own ring); Magnetism: the magnet's moment; Projectiles: g and wind; Gravity
Lab: G and the star's mass; Circuits and Pendulums: numbers only. It is
folded until asked and kept across labs once opened.

**Context:** Owner: *"I see the physics box in the top left of the
electricity module … I like that. But I think we should add a dedicated
UI button so that there's a physics box and the user can click it and
see all the physics values. And maybe, depending on the module … places
that change the value of the electric or magnetic field."* Electric
Fields alone had a standing readout card; the other five had their
numbers only in the notebook's capture list. That list already existed
per module (`captureReadings`), so the card is one shell view over it.

**Consequences:** `Shell/PhysicsBoard.swift` is one implementation for
six modules: a RealityView attachment (no hit testing) seated high at
`PhysicsBoard.home` with the rails in a column beside it, following the
lab placement, plus `SpatialTrackControl` rails. The first build hung
the rails under the card at 1.63 m, where the screenshots showed them
standing in Electric Fields' bank and Projectiles' wall; the card went
up to 1.93 m and the rails moved beside it, and `PhysicsBoardTests`
now checks every module's rails box against box against every
module's flank instruments and build volume rather than against three
bank tops — so it does not reopen the
2026-08-01 panel question: no `Slider`, no `Toggle`, and
`PanelControlCriterionTests` still passes. A rail on the box sets the
same value as the rail on the apparatus, both reading the model every
frame, so two handles cannot disagree. Electric Fields' own card is
deleted, its probe rows moved into that module's `readings` (so the
notebook records them too), and its one disclosure — 50 kT is fictional
— survives as the box's footnote. Circuit Workshop shows the bench and
the selected part rather than every part. Pendulums' g stays retired.
`PhysicsBoardTests` holds the dials' round trips, the reach, the
clearance over the banks and the fold; `-physicsOpen 1` photographs it.

## 2026-09-05 — Electric Fields opens with no test charge

**Decision:** The probe is no longer dropped when the lab opens. The
dipole stands alone; a test charge comes out of the Test + or Test −
well when wanted, and Reset leaves none.

**Context:** Owner: *"remove the test charge being in the electric field
module immediately. I don't want it to be there first … you should still
be able to grab it from the side."* The arrival drop (2026-08) existed so
the lab was not a still diagram; the field lines' riding arrowheads and
the wells make that argument moot.

**Consequences:** `FieldSpaceView` drops nothing on arrival;
`ColdOpenTests` asserts the lab opens probe-free and that the well is the
way in. `-emProbe 1` still stages one for a screenshot.

## 2026-09-05 — The ampersands' solids were inside-out

**Decision:** `Tools/hubtitles.py` checks each glyph's signed volume
after the bevel and reverses the shell when it is negative.

**Context:** Owner: *"the white bolt around [the ampersand] is only on
the back of it … missing on the front part of the letters."* Measured on
the built glyph: the ampersand's chamfer band had 0.0014 of its area
facing the front and 0.144 facing the wrong way; an M had 0.082 and
0.003. The ampersand's solid came out of the bevel consistently oriented
and inside-out, so RealityKit culled every face of it from the front,
the far cap showed through as a flat dark shape, and the keyline showed
only round the silhouette from behind. `recalc_face_normals` did not
cure it — it makes a shell agree with itself and can agree on the
inside.

**Consequences:** All six title assets regenerated (only the two
ampersand lines change visibly); the ampersand now measures 0.072
front, 0.003 wrong-way. The script's `main()` is behind a
`__name__` guard so a diagnostic can import its stages, and the font
snapshot needs `fontTools` importable by the system python3 (a
`PYTHONPATH` to a pip `--target` directory works without touching
either install).

## 2026-09-05 — The tiles come out; the emblems go in

**Decision:** The palette's ring of six accent discs is back exactly as it
was, and the work goes into what stands inside each disc: the six lab
miniatures are rebuilt as emblems — one bold object each, a few big
parts, lines no thinner than a cable. Two big charges with seven field
lines and riding arrowheads; a fat copper loop with a big battery and a
lit bulb; one bar magnet turning slowly with eight field loops turning
with it; a launcher on a puck, one arc, a ball and a hoop; one brass bob
on a beam, swinging in a slow ellipse; a star with one world on one
orbit. The same emblems stand on the gallery's terraces.

**Context:** Owner, an hour after the tiles shipped: *"I was talking
about the actual models inside the spheres, not you change the actual
UI … it has these stupid squares, and I don't like that. I want you to
actually change the models inside of them."* The earlier entry read the
brief as the picker; the brief was the miniatures. What they were:
dioramas — integrated dipole fields with sixteen lines, two magnets
almost snapping with a compass reading their field, a Kepler system
with two worlds and a comet, a switch with a lever, three pendulums.
Faithful, and at seven centimetres a smudge.

**Consequences:** `HubVignettes` is 800 lines instead of 1,300; the
compass, comet, launcher carriage, quadrant, target stand and pendulum
stand props are no longer used by any miniature (they stay in the
bundle and in `VignettePropTests`). `HubVignetteTests`' contract —
centred, one square, no streak, motion inside the square, actually
moving — is unchanged and still holds. `PaletteTileTests` is deleted;
no Blender was needed, the emblems are the existing props plus
primitives. The tile entry below stays as the record of a wrong reading.

## 2026-09-05 — The shelf loses its pane; a drag on a part is always a pull

**Decision:** Nothing stands behind Circuit Workshop's parts: the pane is
gone, "Parts" floats above the column, and a hairline track with a
luminous thumb stands beside it. The thumb is the one thing that scrolls
(drag it, with flick, rubber-banded ends and detents; VoiceOver pages
it). A drag that starts on a part is a pull, whichever way the hand
goes, promoted by a `PressLatch` after 12 mm so a tap spawns nothing.

**Context:** Owner: *"the bench doesn't work, and I don't like how there's
that little gray background too … let me drag out all the parts."* The
2026-09-04 shelf read every drag's direction to decide scroll or pull;
a hand that drifted along the column while taking a part scrolled it
instead, so parts could not reliably be dragged out — the one thing a
shelf is for. And the frosted pane was a grey slab in the room.

**Consequences:** `ScrollGesture` is deleted from RenderKit with its
tests; `Well.Rack` describes the track, not a pane, and
`CircuitsInstrumentClearanceTests` measures the track;
`CircuitsCarryDispatchTests`' "spent pull" trap is gone with the
mechanism that made it, replaced by the shelf refusing slot drags. The
slots, the window, the fade and `-circScroll` are unchanged.

## 2026-09-05 — A wire never lets go because of distance

**Decision:** Carrying a wired part any distance keeps its wires. The 30
cm `breakDistance` pop, the poppable-contact bookkeeping and
`beginCarry`/`endCarry` are deleted. A connection comes off only by
pulling the wire's end off its terminal, cutting it from the part's
ring, or deleting the part.

**Context:** Owner: *"when I try to move the initial capacitor, it
automatically breaks the wire connection. So I don't think that should
happen … figure out a different way."* The pop was meant as pull-apart
detach for a snapped contact; in practice moving a part of the welcome
circuit more than a hand's width broke the circuit, with no way to see
the threshold coming.

**Consequences:** `CircuitsModel.drag` is swing-or-move; a part hanging by
one lead still swings about its joint within reach and past it aims its
lead back at the joint with the wire stretching, now without end.
`CircuitsAlignmentTests` and `CircuitsModelTests` assert the keep where
they asserted the pop. The rewire gesture (lift an end, land it
elsewhere, or in open air to delete) is the deliberate way apart.

## 2026-09-05 — The lab picker is two rows of tiles

**Decision:** Pinch the palette bead and the six labs unfold above it as
two rows of three frosted tiles — the gallery's two terraces, in the
gallery's order — each carrying the lab's live miniature standing proud
of its pane, its name under the pane, and one accent rule along the
pane's foot, lit on the lab you are in and dim on the rest. The pastel
discs are gone. The grid opens toward the centre of the room from the
bead's spot at the right shoulder, so every tile is a reach rather than
a step, and VoiceOver reads the lit tile as "the lab you are in".

**Context:** Owner's brief: *"do an improvement run on all of the 6
modules spheres with icons inside of them (the things in the homescreen
and gyro sphere select ball). They look crappy … Rethink it entirely,
don't just try to slightly change them. And don't make it too
complicated: it should be simple and communicates what it will look
like."* The ring fanned six translucent accent discs across 150° with a
7 cm miniature squeezed inside each — a blob with a smudge in it, in a
material nothing else in the house wears. What communicates a lab is
the lab itself: the gallery's miniatures already exist, and the shelf's
frosted pane already solved contrast against a bright wall.

**Consequences:** `Palette.tileRest` places by `HubDomain` row and
column, so the picker cannot disagree with the gallery; `PaletteTileTests`
holds the rows, the pitch, the reach from `Palette.defaultAnchor`, the
lit rule and the miniature standing in front of its pane, and
`LabelTargetCriterionTests` still finds every name inside its tile's
target. The bead stays the gyroscope; the petal row is unchanged. No
Blender was needed: the tiles are primitives and the miniatures were
already modelled. Not measured here: whether a tile reads at arm's
length on the device, which is on the device list.

## 2026-09-05 — Primitives and materials are made once

**Decision:** Every primitive mesh and collider comes from
`RenderKit/Primitives`, which hands back one resource per shape, and
every recipe in `Materials` is memoised, with `Materials.unlit` for the
flat colour at an opacity the app builds most. `PrimitiveCanonCriterionTests`
fails a bare `generateSphere(` or a hand-built flat colour anywhere in
the app or RenderKit.

**Context:** RealityKit builds a fresh resource for every `generate*`
call and every material, and each build is a round trip that blocks the
main thread on the engine queue (`Blocking engine queue waiting for
AssetLoadRequest` in the unified log). Measured in the test host: a
sphere 0.17 ms, a physically based material 0.37 ms, an unlit material
0.67 ms, an extruded text mesh 1.9 ms. Entering Circuit Workshop paid
for about a thousand of them — a bench holds hundreds of identical
terminals, beads, plates and nameplates.

**Consequences:** 222 mesh and collider calls and 49 flat-colour
materials rerouted by script, byte-for-byte the same arguments; the hub's
bubble type is measured and built from one cached mesh instead of two.
Circuit Workshop's entry went from ~1,000 engine-queue blocks to 487 in
a forty-second window, the gallery's build from 252 to 136 (0.24 s to
0.16 s). What remains is mostly per-entity: colliders measured from
each part's own bounds and a backing plane per nameplate width. The
cache is bounded at a thousand shapes and five hundred materials, and
clearing it only stops sharing. A copied material is a value
(`PrimitivesTests` proves it), which is what makes handing out a cached
one safe.

## 2026-09-05 — The props warm six wide, and the launch says what it is doing

**Decision:** `PropCache.warmUp` loads the bundled `.usdz` files six at a
time instead of one after another, and debug builds print three
`[launch]` lines to the console: props warm, space ready, gallery built.

**Context:** Owner's report: *"Whenever I simply try to run the
simulator, it often never boots up (the actual visionOS simulator pops
up, but the app never opens), and there are just a lot of thread errors
that pop up."* Eleven Xcode runs that day were each killed after 13–65
seconds. Their consoles held only Apple's four startup lines, and the
simulator's own log of the 19:50 run showed the props finishing warming
at +5 s and then nothing for 28 s: no gallery build, no ARKit session.
That is a process stopped in the debugger, not a slow one. World
tracking is supported in the simulator, so `RoomModel.retain()` runs a
real session there and reaches the line an enabled Xcode breakpoint sat
on (`RoomModel.swift:214`, in `xcuserdata`). Under `simctl`, with no
debugger, the same cold launch reached the gallery in under ten seconds
every time — five of them spent in the sequential warm-up.

**Consequences:** Cold launch on the same machine: props warm in 0.94 s,
space ready at 1.40 s, gallery built by 1.65 s. `PropCacheTests` holds
the warm-up's contract: every bundled asset loads, concurrent callers
share one pass, an instance is a clone. The old "sequential on purpose"
note is withdrawn — 3.7 MB of assets never had a memory case, and the
parse runs off the main thread. Not changed: the ~250 synchronous mesh,
material and collider generations during the gallery build and ~1,000
on entering Circuit Workshop, each a round trip that blocks the main
thread on RealityKit's engine queue (~0.3 s and ~2 s). A primitive and
material cache is the next optimisation.

## 2026-09-04 — The parts rack is a shelf you scroll by hand

**Decision:** Circuit Workshop's part sources stand on one frosted pane,
headed "Parts" and yawed to face where the wearer stands, and the column
scrolls by dragging any slot or the pane itself: one-to-one under the
hand, carrying on after a flick, pushing back past either end and
settling on a whole slot with a tick. The two caret buttons are deleted.
A luminous thumb down the pane's edge is the only "there is more" cue,
and VoiceOver pages the window with increment/decrement on the pane.

**Context:** Owner's brief: *"make it much nicer, have a better
appearance, and maybe make it easier to scroll through the list of parts
rather than have a button."* The rack was twelve loose sources in a
column with a caret at each end, so reaching a part meant leaving the
shelf to press a button, six slots at a time, and the slots at the
window's edge popped in and out. Direct manipulation is the house rule
on every other surface (a rail's bead is the value; a lead is pulled),
and the rack was the one place left with a button that scrolled a list.

**Consequences:** `RackScroll` (RenderKit) is the arithmetic — rubber
band, flick projection, detent settle, a jump under Reduce Motion —
under `RackScrollTests`; `Well` gained a windowed shelf mode (`facing`,
`windowTitle`, the pane, `windowOpacity(at:)`) that no other well uses
yet. The slots did not move, so every placement test still holds, and
the pane's box joined the clearance furniture. `ScrollGesture.classify`
still decides scroll against pull by the direction of travel, so pulling
a part out is unchanged. `-circScroll <n>` stands in for the drag the
simulator has no hand for. Whether a hand reads "drag the shelf" with no
caret to prompt it is a device question, now on the device list.

## 2026-09-04 — Comments are cut to what the code cannot say

**Decision:** Every Swift file's comments are trimmed to a short header,
a doc line or three per declaration, and inline notes that name an
invariant, a unit, a frame or an ordering. History, dates, quoted
briefs, capitals and the graves of deleted features leave the source;
this log and git keep them.

**Context:** Owner's request: *"clean up the code of all of the dense
comments."* The tree carried essays at the point of use that repeated
this log, and in places the record of what a line used to do had
outgrown the line.

**Consequences:** 17,879 comment lines became 12,214 across 293 files,
with the non-comment text of every file byte-identical to a snapshot
taken before the pass (the shelf files above excepted, which changed on
purpose). A comment that survived is one whose absence would cost a
reader a wrong guess; a comment that wants a date or a quotation belongs
here.

## 2026-09-04 — The surface gets simpler: what stood in the room at open, and what said its name twice

**Decision:** Owner's direction — *"this app needs a lot of its clutter
just gone … pretend like you are a user, and ask yourself what you need
at your immediate disposal … be absolutely certain that no UI/models
overlap with each other in the initial starts of the modules."* Eleven
cuts and moves, judged against a baseline photograph of every module's
opening frame and re-photographed after:

1. **No description under any module's title.** The one-sentence
   first-run hint under the title bar is deleted — `firstRunHint`, the
   never-read `blurb`, `AppSettings.seenHints`, Settings › Onboarding
   and `-resetHints` with it — and so is the promise line under every
   row of the flat catalog. `HubDomain.promise` survives only as
   VoiceOver text (the exhibit's label, the catalog row's hint), where
   it costs no space. The apparatus teaches by being touched; four
   cards of words have now been rejected.
2. **One title on the pad.** A docked exhibit's own name plate goes
   quiet while the Load plaque names it, and returns the moment it
   leaves — the plate under the plaque was the same title twice.
3. **One main window, ever.** `AppModel.mainWindowCount`, kept by
   `MainWindowView`, gates the three openers (the space's sync, its
   `onDisappear`, the hub's Lab-list button). A value-less
   `WindowGroup` makes a NEW window on every `openWindow(id:)`, and two
   title bars over one lab is the other way a title duplicates.
4. **Gravity Lab loses its two analogies.** The spacetime grid and the
   field-flow particles are deleted, with their two-plate bank and the
   black platform disc the grid stood in for. Both were disclosed in the
   legend as pictures rather than measurements, in a module whose claim
   is that every other number is real; the grid also covered 2.9 m of
   floor. The orrery floats like every other apparatus here.
5. **Gravity Lab's flank is one tab.** Analysis and Vectors merge into a
   single Show tab (v, a, F, Kepler sweep, Lagrange) whose summary reads
   "v F · sweep". Its column unfolds UPWARD; the world well hangs under
   it, and the G rail moves to the foot of the fore column under Worlds
   and Twin suns (the first after-photograph had the rail under the tab,
   with the well's sightline landing on both — the well had stood over
   the Analysis tab the same way since 2026-08-07).
   The baseline photograph showed the Vectors tab standing ON the G rail
   — hung 0.23 m under the bank while the rail was 0.25 m under it —
   since the fold of 2026-08-07, with the rail's "1.00 × G" inside the
   tab. `InstrumentReachCriterionTests` now asserts the deep flank does
   not stack on itself, measures the tab on its own tight box, and the
   flank came 20 cm fore to pass that honestly (its plates were 1.36 m
   from a standing viewer and green only on the generous box).
6. **A planet says its name once.** The body's tapped callout (name,
   speed, distance) is deleted and the data card drops its name line:
   with the name plate 3 cm over the body and the card 12 cm over that,
   a selected planet said "Earth" three times. r and v lead the card.
7. **The Kepler sweep is off until asked for.** A tap on a planet
   answered with the ring, the card, two arrows, two gold sectors and
   two area callouts; the sectors and their numbers wait behind Show.
8. **The palette bead moves to (0.62, 1.50, −0.95).** At (0.72, 1.32)
   it stood 0.76 m from the Sun in the ecliptic — Mars's orbit to the
   centimetre — with its "Labs" plate at Mars's height, and brushed the
   Circuits rack along the sightline. A saved position still wins.
9. **The worlds fan opens under the title bar.** At 0.55 above the
   system it opened its ten discs straight through the window, which
   has ridden at ~1.75 m since 2026-08-30; it opens over the system's
   near edge at 1.55 now.
10. **Circuits folds its five views behind one tab**, outside the build
    volume. The five-plate bank at x −0.62 overlapped the ±0.60 volume
    by 13 cm — a finding recorded as a passing test since 2026-08-08
    and declined because the one move on offer was 47.8° off axis. A
    tab is a fifth the height, so a legal spot exists: x −0.76,
    z −0.92, 39.6° off axis, 4 cm clear of the Clear plate in depth.
    `CircuitsInstrumentClearanceTests` asserts the fix in place of the
    finding. The bench opens on a loop, a rack and three small tabs.
11. **Two more opening-frame overlaps the photographs found.** The
    Pendulums cradle hung from 2.0 m put all five cables through the
    title bar; it hangs from 1.62 (collars a hand's width under the
    bar, bobs at 1.07, both inside a standing reach). Projectiles' ball
    and hoop well previews — a 10 cm ball and a 12 cm hoop 9.5 cm apart
    — touched; the row's pitch is 0.13 and both previews are 3.5 cm
    tokens, 5 cm apart with the wells' breath allowed for.

**Context:** The 2026-08-07 fold halved Gravity Lab's standing objects
and was photographed as calmer; what it left was still two plates, two
tabs, a rail, two verbs, a clock tab and a well, with the grid under
all of it. The owner's brief on 2026-09-04 was that the surface itself
was the problem, in Gravity Lab and Circuits first. Every number here
was checked against the shared clearance rules and against a baseline
screenshot of each module's first frame — which is also how the
Pendulums bar and the Projectiles previews were found, neither of which
any test measured.

**Consequences:** `-gravShowOpen 1` and `-circViewsOpen 1` photograph
the two columns; `-resetHints` is gone. Gravity Lab's legend loses the
grid's disclosure line. `SettingsView` has no reset of any kind. The
UI test that pressed "Show hints again" now finds the room-tone switch.
Not touched, deliberately: Electric Fields' standing readout card (its
field lines cross every instrument on the flank by construction, and the
thick material is the existing answer), Magnetism, and every Time
Capsule decision of 2026-09-01. The three modules that were not
photographed as overlapping — Magnetism, Electric Fields, Projectiles'
wall — keep their layouts.

## 2026-09-02 — The ten circuit parts are milled from the same stock as the room

**Decision:** Batch H. `Tools/circuitparts.py` is the generator for all
ten parts on the bench, in the stocks the gallery's platforms and the
multimeter already wear — near-black anodised with the clearcoat
`RenderKit.Materials.graphite` is defined by, steel, copper, champagne
keylines, glass where a part has an envelope. One file per part; the
renderer's own moving and lit pieces (the bulb's filament and glow, the
LED's glow, the motor's rotor, the switch's lever) stay in Swift at the
positions they always had. The resistor's ceramic BODY stays procedural
— its colour bands are a live texture painted from the value, and the
UV layout of a RealityKit cylinder is the one that texture knows — so
only its steel end caps are milled and mounted under it.

**Context:** Four of the parts (battery, bulb, capacitor, switch) shipped
on 2026-07-17 as hand-built assets with no generator, before the rule
that a binary nobody can regenerate is a decision nobody can revisit
(`appicon.py`, 2026-08-24). The other six were procedural cylinders with
a colour on them — the one place on the bench that read as programmer
art beside a modelled meter. The owner asked for better models with the
feature work; the script is the answer that survives the next
re-proportioning.

**The contract with the renderer** is written into the script and held
by `CircuitPropTests`: every body lies along X inside |x| < 0.059 (the
carry box's clamp at the leads' inner edge, so `CircuitsAlignmentTests`
and the collider criterion keep their assumptions), the bulb and the LED
stand up with their glass above +y 0.012, the motor's shaft end is +X
where the rotor mounts, and the battery's positive nipple is −X —
terminal 0, the nodeA convention the solver and the renderer share.
The procedural bodies survive as the fallback, so a missing asset
never blanks a part.

**Consequences:** The rack previews and the hub miniature pick the new
models up unchanged (`partPreview` is `makeBody`; the miniature loads
the battery, the bulb and the switch by name). Judged by screenshot at
1× and in Electron View at 4×, where a model's edges show; the device
pass judges them under passthrough. The Blender MCP was not connected
and was not needed: the pipeline is headless scripts, as it was for
every asset before these.

## 2026-09-02 — Circuits: the coil is a magnet, a resistor can scorch, and an AC source has its own frequency

**Decision:** Batch G of the release plan — three features the owner
chose on 2026-09-01 (C1, C3, C4; C2 swap-in-place declined):

1. **The coil is a magnet.** `inductorCurrent` was integrated every
   frame and read by nothing. It now drives a `BarMagnet` through
   `CurrentLoop.magnet`, and the Magnetic-field layer samples the
   model's `magneticField(at:)` — every wire segment PLUS every coil —
   with extra rings around each carrying inductor's axis. The turn
   count is derived, not invented: for an air core of the drawn
   geometry (0.07 m long, 0.019 m windings) L = μ₀N²A/ℓ, so the default
   0.5 H is about 4,960 turns, and the card says "≈4,960 turns · air
   core". Reverse the battery and the field flips. This answers
   2026-08-02 ("Circuits and Magnetism stop being one apparatus") rather
   than reopening it: the coil is a part on the bench you built, not a
   second apparatus cabled to it.
2. **Heat.** Resistors carry a rating (2 W, stated on the card as "0.17 W
   of 2 W"); past it the excess accumulates as `thermalEnergy`, under it
   it cools, and four joules of excess scorches the part — a slow fuse,
   with a glow on the way (the body's emissive rises in four steps, then
   goes black and reads "scorched"; Replace makes it whole). Only
   resistors: the bulb's job is to run hot, the fuse and the LED already
   fail their own way, and a WIRE stays ideal — the solver treats a wire
   as a net, so a wire's I²R would need it to become an element, which
   this release does not do.
3. **AC you can tune.** Each AC source carries `acFrequency` (0.1–5 Hz,
   0.5 by default); a rail hangs under a selected source, hung off the
   renderer's root through the zoom rig so it never scales out of reach.
   Persisted as an optional stored field, so every bench written before
   today decodes at the old 0.5 Hz (`CircuitsBenchMigrationTests`).
   `Component` gains a tolerant `init(from:)` for the same reason.

**Context:** All three make the bench say more about what it is already
doing. The solver was always time-stepped, so an AC source at any
frequency is honest without new physics; the power was always solved
per part; the inductor's current was always integrated. What was
missing was a reader and, for heat, a threshold with a stated number.

**Consequences:** `-circCoil 1`, `-circHeat 1`, `-circAC <Hz>` stage the
three. Tests: `CircuitsModelTests` — the inductance implies the turn
count and recovers it; the field on the coil's axis is the loop's far
field (`CurrentLoop.axialField`) within five percent and flips with the
battery; a 10 Ω resistor on 9 V survives a spike, scorches under a
sustained overload, reads as open, and is whole after Replace while
470 Ω never warms; a 2.5 Hz source peaks a quarter period in and troughs
three quarters in, and the rail clamps. The field layer's change gate
now keys on the coils as well as the segments. `VectorFieldArrows`
normalises against the frame, so beside a five-thousand-turn coil the
wire arrows go faint — which is the physics, and the reason the coil
is the demo.

## 2026-09-02 — A table is a surface you can land on, and a hand is a thing you can swat with

**Decision:** Batch F's last item (P3). Two changes to what the ROOM is
in Projectiles, no new control:

1. **Tables and seats become finite walls.** `RoomModel.consumePlanes`
   passed only vertical planes into the wall table; a horizontal plane
   ARKit classifies as `.table` or `.seat` now goes in too, through the
   same `wall(from:)`. In the model, an upward-facing wall is a SUPPORT
   rather than something to bounce off: `supportHeight(under:)` finds the
   highest one under the ball and the floor law runs against it, so a
   ball dropped on a table bounces on the top, comes to rest on it, rolls
   along it, and — the case that makes the rest honest — rolls off its
   edge and falls (`strikeWalls` excludes upward faces so a landing is
   never double-counted as a strike). `.unknown` planes stay out: an
   unclassified horizontal plane is an invisible shelf in mid-air.
2. **Hands strike.** `RoomModel` publishes the tracked hand joints as
   `SphereStrike.Sphere`s with finite-difference velocities, and the
   model bounces a ball off them (`PhysicsCore.SphereStrike`, the wall
   contract for a moving sphere: the relative velocity reflects, the
   hand's own motion is added back). A hand moving slower than
   `swatSpeed` (1.2 m/s) is waiting, and catches as before; faster, it
   swats — the SpaceView routes the fingertips by speed.

**Context:** "1:1 with your room" stopped at four walls and a ceiling.
The room already knew about tables — every horizontal plane fed the
bounds — and about hands — nine joints as an obstacle field for a module
that no longer ships — and Projectiles read neither. `-roomTable <y>`
stands a synthetic table in the simulator, which has no furniture to
classify; the physics is proven there and by the tests, and whether
ARKit classifies YOUR table is the device judgement recorded in the
release plan's risk list.

The predicted arc still bounces off a table as a strike (it has no rest
law) — the first bounce agrees with the ball, the settling does not, and
the arc ends where a bounce budget ends it. Accepted for 1.0 and noted
here rather than hidden.

**Consequences:** `TableWallTests` pins that the strike law was always
normal-agnostic (a drop onto a table bounces, beside it falls past, the
underside is a surface); `SphereStrikeTests` pins the swat numbers (a
resting ball leaves at the hand's speed × (1 + e)); `KinematicsModelTests`
holds rest-on-the-table, roll-off-the-edge and the swat by the model's
own laws. The hand-joint velocities are the first time `RoomModel`
publishes motion rather than position.

## 2026-09-02 — Monkey and hunter, and a pause that counts from the lab

**Decision:** A hoop's ring gains "Drop when fired" (Batch F, P7). Armed,
the hoop is re-hung on its anchor and let go at the instant a shot
leaves the launcher; it falls in a vacuum, and the ball meets it
wherever the two coincide — from any side, because that meeting is the
demo. The next shot re-hangs and drops it again; disarming re-hangs it;
a hand on it ends the fall. The hoop's callout says "drops when fired"
while it is armed. The ring's three petals are now Aim (a fan of the two
arcs), Drop when fired, and Delete — the two aim petals of the earlier
entry became a fan because a momentary N-way choice is a fan and the
ring's ceiling is three.

**And `-pauseAfter` counts from the lab, not from launch.** The argument
slept from `AppModel.init`; since 2026-08-22 the space builds only once
the prop cache is warm — about fifteen seconds in a cold simulator — so
`-pauseAfter 4` paused a lab that had never run a step. The reel was
absent from every paused screenshot taken today, forced on or default,
and an instrumented run showed why: paused, a capsule two frames long,
`wantsPresence` false. The clock now starts when the module's scene
mounts (`PlaygroundSpaceView` → `AppModel.runStagedPause`), and the
staging notes budget the warm-up.

**Context:** The physics is the classic: aimed straight at the target
with no lead, hunter and monkey fall the same distance in the same time,
so the ball arrives where the hoop has fallen to — on the Moon and on
Jupiter, which the worlds picker shows in one tap. The falling hoop
ignores drag, and its callout says so, because drag on the target would
break the claim the demo exists to show. The hit test is proximity
rather than a plane crossing because in the falling frame the ball moves
in a straight line at the launch velocity, which is upward for any shot
aimed above the horizon.

**Consequences:** `Ring` carries `dropOnFire`, `falling` and
`fallSpeed`, so the capsule records them without anyone remembering to.
`-kinHunter 1` arms the first hoop, aims straight at it and fires; with
`-pauseAfter 0.6` the two are photographed meeting. `KinematicsModelTests`
holds the meeting for g = 1.62, 9.81 and 24.79 by the scoring law, that
the same line of sight misses a hoop that stays put, and the re-hang.
The `sleep 22` in every staging script became `sleep 32`.

## 2026-09-02 — Projectiles: the hoops come out of their mothball, and the launcher solves for them

**Decision:** Four features on the Projectiles bench, chosen by the
owner on 2026-09-01 (Batch F of the release plan, first half):

1. **Hoops from a well.** The hoop-and-scoring layer mothballed on
   2026-07-31 — "hoops read as clutter around a bench about
   trajectories" — is restored through a well mouth beside the ball's,
   not a plate. Nothing stands at rest: a hoop exists only once you
   pull one, is carried by the gesture that made it, and has its own
   ring (Aim low, Aim high, Delete). Reset clears them. The notebook
   writes Hoops, Score and Best streak when any stand.
2. **The aim solves for the hoop.** Tap a hoop, pinch Aim low or Aim
   high: two ghost arcs, the projectile problem run backwards —
   `ProjectileMotion.launchAngles`, tan θ = (v² ± √(v⁴ − g(gx² +
   2yv²))) / (gx), exact — and the launcher points along the one you
   chose. With the air on the roots are found by bisection over the
   simulated arc (`launchAnglesWithDrag`) and the hoop's callout says
   "with drag". The muzzle rides the aim, so each root is refined
   against its own muzzle.
3. **The custom ball, by mass.** The fifth ball kind gets its door: a
   Mass rail under the launcher while Custom is picked — a rail, not a
   grip, because one grip per ring is the vocabulary's ceiling and mass
   has no extent. Its diameter stays 10 cm on purpose: same size,
   different mass, so nothing changes without air and everything with
   it.
4. **The ghost of vacuum.** With the air on, the no-drag arc stands
   faintly beside the real one and the landing ring reads both ranges.
   The gap is drag, made visible.

**Context:** The mothball entry said restoring the hoops "is a decision
rather than a cleanup", and the decision that unlocks it is the owner's
own from 2026-08-08, reversing the parts drawer: *fold the instruments,
never the materials.* A hoop is a material — a thing you make and place —
so it comes from a well like a ball or a magnet, and the clutter
objection that put it away is answered by the count: nothing stands
until a hand asks for it. Placement was measured, not reasoned: two
mouths on the well row at Electric Fields' pitch (0.095), the hoop
outboard with its near face 1.20 m from a standing viewer against the
1.25 limit, the ball inboard with its edge 0.15 m clear of the launcher's
line; `InstrumentReachCriterionTests` holds both. Sideways toward the
launcher is the firing line, further outboard fails reach before any
height, and a sixth row would push the bank below knee height.

The ghost arcs are one mesh in the arc's own colour at 0.22 opacity,
cased like it, rebuilt only when an input changes; the solve is memoised
on its inputs because a petal's `isAvailable` asks every frame and the
drag search costs tens of simulations. The solve works in the vertical
plane through the hoop and ignores a cross-wind; the ghost is the full
three-dimensional flight, so a cross-wind miss shows as a ghost that
misses, which is the honest picture.

**Consequences:** Projectiles' standing count stays at ten — the ring
fold took one, the hoop mouth added one. New arguments: `-kinHoops <n>`,
`-kinSolve 1`, `-kinBall <kind>`, `-kinMass <kg>`, `-kinAir 1`. Tests:
`ProjectileAimTests` (PhysicsCore — both vacuum roots land within a
millimetre, maximum range collapses the roots onto 45°, straight up
needs v² ≥ 2gy, the drag roots land within a millimetre and admit
defeat out of range), `KinematicsModelTests` (a hoop born at the hand,
the well's refusal at the budget, both solutions score through the rim
by the scoring law itself, the drag solve too, out of range is a no-op,
mass changes the arc only in air, the vacuum ghost only exists in air),
`LauncherRingTests` (a hoop's tube resolves to its hoop), and the reach
criterion gains the hoop mouth. Monkey-and-hunter and the table bounce
follow as their own entries.

## 2026-09-01 — Release 1.0: the demo script sets the scope

**Decision:** Version 1.0 is planned backwards from a 180-second demo
(`docs/DEMO_SCRIPT.md`): a feature that cannot hold five seconds of it
is broken, undiscoverable or buried, and the script says which. On the
way, four owner decisions and one scope extension:

1. **The Time Capsule ships ON**, toggle kept (amends 2026-08-07).
2. **The first-run hint shows in the module window while the room is
   open** (amends 2026-08-09), gated on a screenshot per lab.
3. **The launcher's ring folds by tap** like every other ring
   (`DESIGN_SYSTEM.md`: unfolded by tap, never gaze). Only the
   launch-speed grip goes behind the tap; the aim bead is a sibling
   entity and stays free.
4. **The demo's "complete an experiment" beat is the Lab Notebook
   capture.** The experiments system stays deleted.
5. **Projectiles and Circuits each gain a batch of features**, and the
   ten circuit parts are re-milled by one checked-in script. Projectiles:
   hoops from a well (restoring the 2026-07-31 mothball — through a
   well, so nothing stands at rest, which is the answer to the 07-29
   clutter objection), the aim that solves for a hoop with both exact
   roots, a custom-mass ball at a fixed diameter, the vacuum ghost arc,
   monkey-and-hunter, and bouncing off classified tables and seats plus a
   hand swat. Circuits: the inductor's own field on the Magnetic-field
   layer (answering 2026-08-02: the bench you built, not a second
   apparatus — `inductorCurrent` was integrated every frame and read by
   nothing), I²R heat and scorch on resistors, and a frequency rail under
   the AC source. Swap-in-place, a wind vane and the launcher's carriage
   model were offered and declined for 1.0. Each lands with its own entry.

**Context:** The brief was written from the 2026-08-07 audit, and that
arc had closed on 2026-08-26. Verified against the code before planning:
the git root is the parent directory (430 commits — the brief's "no
repository, git init" would have nested a repo and orphaned them, so
the release is a branch); the twenty experiment steps, `insightText`,
`compassIsReadingEarth` and `scopeSamples` are graves, not sleepers; the
front door already answers 07-29 (a tap moves a lab, a second pinch in a
different place enters); recession and the folding handle shipped on
08-07 (Gravity Lab 18 → 9, Circuits 22 → 13), so the container refactor
the brief asked to cost is not owed; and of the eight "visibly wrong"
physics items six are fixed, one is retracted and one is parked with a
measurement. Two findings the brief could not have known: the first-run
hint had ZERO readers since the space became the launch scene on
2026-08-22 (it drew only while the space was closed), and the 2026-08-30
title-bar lift removed the occlusion that had driven it out of the
window; and the double pendulum still stamps `T = 2π√(L₁/g)` on a
system that has no period.

**Why the capsule flips to ON.** The 08-07 reasoning — a default is a
claim about what the app is; meet the labs first; the cost is honest as
a setting — was made against a build that put a 34 cm rail in every
pause. The reel (same day, later) answered "not always visible": a pause
shows one object and nothing else until it is pinched, so with ON the
first thing a user meets is still six labs. The cost (2–11 MB and one
struct copy per tick) is not a price a wearer needs to be asked about,
and the toggle remains for anyone who wants it off. What was lost by OFF
was measurable: every buyer, and App Review, met the app without its
most distinctive feature.

**Consequences:** `release/1.0` is the branch; every commit pathspec-
scoped. Batches in order: ground truth and docs → the three small code
changes → the ring fold → Projectiles → Circuits → models → the device
gate (`ON_DEVICE_TESTS.md` › *Release 1.0 gate*, in demo order) → the
take → archive and upload. Named backlog, so nothing drops silently:
Circuits' eight save slots (a missing door), Recession on the five rails
and the readout cards, Electric Fields' four wells → two, the second-
object grab for the other hand in Circuits / Electric Fields / Gravity
Lab, a refusal sound for a failed capture, the magnet force near
contact, `cyclotronRadius` at launch speed, `-magInertia` as a mode,
Dynamic Type in the room, the oscilloscope ribbon, the motor's voice.
Cut order if time is lost: table + swat first, then monkey-and-hunter,
then the models, then the ring fold; the gates never.

## 2026-08-29 — Gravity Lab arrives with nothing selected

**Decision:** `reset()` no longer pre-selects Earth. The module opens as
a quiet sky — planets, trails, labels, the curvature grid — and the
orbit ring, data card, v/a/F arrows and Kepler sweep readout appear
only when the user taps a body.

**Context:** Owner's call: the module looked "very clustered" on
arrival. All four of those overlays guard on `selectedBody`, and the
pre-selected Earth stacked every one of them on the inner system — the
busiest square metre of the scene — before the user had done anything.
The layer flags themselves (`keplerSweepOn`, the vector toggles, the
grid) keep their defaults: they are what the tap REVEALS, and the tab
summaries go on advertising them.

**Consequences:** The tap teaches — "this one", and the room answers
with everything at once, the same selection grammar as Circuits. The
opening scene is pinned by `testResetRestoresOpeningScene`
(`selectedBody == nil`). Screenshot staging is unchanged: `-selectBody`
still picks a planet and draws its ring.

## 2026-08-29 — Every control stands on the left

**Decision:** All in-room controls — banks, verb plates, tabs, pickers,
rails, wells — stand off the user's LEFT shoulder in every module. The
"what exists is on the left, what you MAKE is on the right" split that
Electric Fields and Gravity Lab shared is retired; that distinction now
runs in DEPTH on the one flank (what exists deep at the apparatus'
plane, what you make fore of it). The one exception, decided in the
same breath: Circuit Workshop's parts rack stays on the right — it is
a shelf you reach into, not a button, and its six-row reach analysis
stands.

**Context:** Owner's call, extending their own 2026-08-04 rule ("the
side buttons live on the left everywhere") from switch banks to
everything. Electric Fields had two surfaces on the right (the Clear
column and the four charge wells) and Gravity Lab two more (the
Worlds/Twin-suns verbs and the clock tab) — four controls arguing with
the rule the other rooms teach. Two placement consequences carry the
weight: Electric Fields' Clear plate lands at (−1.02, 1.23), exactly
Circuit Workshop's `clearAnchor` x and y, so the same verb sits in the
same spot in both modules that have it; and both moved columns come
FORE of their flanks rather than beside them, because a left flank —
unlike the empty right ones they left — already holds a column, and a
second column at the same depth either overlaps it or shadows its
labels from the standing viewpoint (the sightline projections are
worked in each anchor's comment).

**Consequences:** One hand rule app-wide. The
`FieldInstrumentLayoutTests` coordinate pins moved in the same commit;
Gravity Lab's reach tests read the anchors and follow. This rules out
placing any future control on the right without reopening this entry —
and it commits the fore-column depth split to being the house answer
when a flank fills up.

## 2026-08-29 — A one-wired part hangs from its joint while carried

**Decision:** A carried part with exactly one wired lead pivots on the
ANCHOR — the far terminal of its wire — with a leash rather than a mode
switch: within the body's own reach (`terminalOffset`) the lead sits
exactly on the joint and the body swings; past it the body tracks the
hand while aiming its lead back at the joint, the wire stretches, and
the existing `breakDistance` alone decides when the contact pops. The
composition (swing, else rigid move, then break) is one model verb,
`drag(id:toward:)`, and the gesture's per-frame routing is a pure
static, `carryDispatch`.

**Context:** Two shipped defects, found in one review. First, `swing`
pivoted on the part's OWN wired terminal — which moves with the part —
and the view called it after `move` with the part's just-moved centre,
so it computed the identity: the "hangs by one lead and swings"
affordance in the first-run hint never actually happened. Its test
passed by skipping the `move`. Second, the gesture dispatch consulted
the rack before the live carry; the rack holds its gesture until it
ends even after its one-shot pull is spent, so a part pulled from the
rack froze at its spawn point until release. Both defects lived in the
composed closure sequence, which nothing headless exercised — the same
gap `resolveGrab` was extracted to close.

A pure pin-the-lead swing could not simply be fixed in place: if the
wired lead never leaves the joint, the wire never lengthens and
pull-apart detach can never fire — and a hard mode-switch radius would
be a new threshold constant, the exact sin the module paid to kill
(`snapDistance` 0.13 vs the hardcoded 0.09). The leash is one
continuous formula that is a pure swing near the joint and an honest
stretch past it.

**Consequences:** The view's `applyCircuitDrag` is three lines and owns
no composition; `CircuitsAlignmentTests` drives the real sequence
through `drag`, and `CircuitsCarryDispatchTests` pins the dispatch
order plus the Well behaviour (spent pull, still dragging) that makes
the order load-bearing. This rules out re-composing carry behaviour in
the gesture closure.

## 2026-08-29 — Wires are straight; the catenary is removed

**Decision:** A circuit connection is drawn as a taut straight line
between its terminals. The catenary sag of 2026-08-11 — `Catenary.swift`
in PhysicsCore, `CircuitsModel.slack(span:)`, the seven-segment curve,
the arc-length conducting path, and the `-circSag` launch argument — is
deleted, on the owner's call: the bend was unnecessary.

**Context:** The sag was built as a "pictures are physics" flourish: a
real catenary, Newton-solved, with the electron beads riding the arc.
But it earned its keep nowhere. The bench's own tidiness rules already
kept it invisible in the common case (a snapped joint had zero slack,
and most joints on a chained bench are snapped), the multimeter's probe
leads had always been straight for per-frame-cost reasons, and the sag
had quietly introduced a real inconsistency: `conductingPathLength`
summed the arc while the true-speed field front walked straight chords,
so the readout and the front measured two different loops.

**Consequences:** A wire is one unit-cylinder segment stretched by its
transform, its grab volume one capsule on the unscaled parent, and the
conducting path is the chord sum — identical by construction to the
path the field front walks. `CatenaryTests` and `CircuitsSagTests` are
gone; `CircuitsWirePathTests` pins the chord-sum claim. This rules out
re-introducing per-wire geometry that differs from the model's straight
line — anything that bends a wire again re-opens the readout/front
disagreement this removal closed.

## 2026-08-26 — Three documents stop describing an app that no longer exists

**Decision:** `GOAL_2026-08-07.md` and `AUDIT_2026-08-07.md` get status
headers marking them CLOSED and historical, naming the reversals and the
retraction. `CIRCUITS_DESIGN_REVIEW.md` gets a per-number verdict table:
C7 done, C3 and C4 moot, C10 half, the other seven declined for v1. None
of the three is deleted.

**Context:** The repo is about to be published, and a document that
contradicts the code is worse than no document — it is a set of
instructions for undoing work.

`GOAL` was the worst of the three. About 70% of it landed, and roughly
15% landed and was then **reversed by the owner**: the experiments system
it devotes §3.1 to was deleted on 2026-08-09, the in-room teach of §1.4
was built and deleted the same day, and the flat front door of §1.1–1.2
was removed outright on 2026-08-22. Someone executing it in good faith
would rebuild three surfaces that were deliberately taken out.

`AUDIT` is mostly fixed, but carries three claims that are simply wrong
and were never marked as such: P1-24 was **retracted** (the author had
been reading the seeded welcome shot); P0's quaternion symptom was
misdiagnosed as NaN when the real defect was one visible roll; and its ΔE
figures were hand-typed approximations of UIKit system colours — the
measured numbers are different enough that one "collision" it reports was
never a collision.

`CIRCUITS_DESIGN_REVIEW` had sat untriaged for twenty days. It was
written to be reacted to per-number in the headset and never was, so it
stood as a permanent implication that eleven pieces of work were owed.
Two of its proposals had gone stale underneath it — C3 and C4 both
describe affordances the 2026-08-11 wiring rewrite deleted. One, C7, was
filed as polish and turned out to be a correctness bug.

**Consequences:** Nine of the eleven Circuits proposals are declined as
new features, under the standing rule that "improve" means refine what
exists. That is a real decision with a cost: the module keeps the
sprawling first-build problem C1 and C2 were aimed at, and the answer to
it is the snap-align and lead-pull work that landed instead.

The three documents stay in the repo because they are the record of a
real engineering arc and most of it did land — deleting them would hide
the reasoning, which is the opposite of the problem being fixed. They are
now labelled history, and `DECISIONS.md` is stated to supersede them.

## 2026-08-26 — The bench stops being a wall, and then narrows to 0.60

**Decision:** `CircuitsModel.buildHalfExtents` stops clamping hands and
becomes the layout reference `ARCHITECTURE.md` has called it since
2026-08-03; a new `safetyHalfExtents` (2.6, 1.6, 2.6) is the only clamp a
hand meets. Then, and only then, the box narrows from 0.70 to 0.60, the
parts rack comes in from x 0.82 to 0.74, and `rightVisibleRows` goes 5 → 6.
This closes the OPEN decision of 2026-08-09.

**Context:** Two problems were filed as one, and separating them is the
whole content of this entry.

*The parts teleport was never a layout bug.* A part pulled from the rack
was born at the hand — at x 0.82 — and `add` clamped it to 0.70, so it
jumped 12 cm out of your grip on the first frame (audit P1-28). The
obvious fix is to move the rack, and **it cannot work**: the clearance
rule requires `|rackX| − buildHalfExtents.x ≥ stationMargin`, so the jump
is *at least* `stationMargin` for any legal rack position at any bench
width, by construction. Narrowing the bench to 0.60 and leaving the clamp
alone would have made it 14 cm.

The actual cause is that Circuits was the last module still clamping a
hand to a nominal box. Electric Fields and Magnetism were split into
`regionHalfExtents` (layout) and `safetyHalfExtents` (the free
simulation) on 2026-08-03; `ARCHITECTURE.md` names `buildHalfExtents` in
the same sentence as a layout reference, and it simply was not one. The
doc and the code disagreed for three weeks and the doc was right.

*No data migration was needed, and that surprised me.* Narrowing a box
that saved benches live inside sounds like the `.wire` retirement all
over again. It is not: `decodeBench` → `migrated` → `apply` transforms
KINDS and assigns positions verbatim, so a bench saved at the old wall
restores exactly where it was saved. The tempting move — clamping
positions inside `migrated` — was considered and rejected. It would
reintroduce at load time the wall this entry removes, and it would
permanently and irreversibly move people's circuits (two parts at 0.70
and 0.64 collapse onto one plane) with no version stamp and no undo.
After the split, a part outside the layout box is simply legal, the way a
charge outside `FieldModel.regionHalfExtents` is legal. A test now pins
the verbatim restore so nobody adds that clamp by accident.

*The numbers.* From the viewer at (0, 1.5, 0), rack at x 0.74, z −0.77:
off-axis 43.9° (was 46.8°, against a 48° limit — two-tenths of a degree
of margin); reach to the sixth row 1.190 m (against 1.25, and a 1.23
margin line). A seventh row reaches 1.240 m and fails, so six is a
ceiling rather than a preference and the test says so. Not x 0.72, which
is `0.60 + stationMargin` exactly — `InstrumentReachCriterionTests` puts
it well: *exactly at the limit is not clearance, it is a coincidence.*

**Consequences:** The clamp vetoes in `alignment(for:)` and `swing` now
measure against the safety box, because that is the only clamp left;
against the bench they would refuse alignments nothing would then move.
`CircuitsAlignmentTests`' 4000-placement sweep was rebiased one box out
for the same reason — it exists to prove the veto is neither dead nor
insufficient, and at bench scale it had become dead.

The layers bank at −0.62 still overlaps the volume, by 0.13 m rather than
0.23. The move this file floated on 2026-08-09 (x 0.87, z −0.79) is 47.8°
against a 48° limit, which is the margin we just refused for the rack, so
it stays declined. And a finding while checking it: the multimeter's rest
position at +0.62 was justified here as "inside the volume for the same
reason", but the meter is built `isEnabled = false` and only ever moved to
a hand — nothing has ever stood there.

`CircuitsPartsLayoutTests.testTheClearanceRuleWouldCatchTheOldColumn` had
baked a bench width into a point about a margin (`0.80 - 0.70 < 0.12`) and
hard-failed at 0.60. Its witness is relative now.

## 2026-08-26 — Five owed cleanups, and the seventh reset defect

**Decision:** Five items that had been recorded as owed, plus one new
defect found while checking them, all landed together. Nothing here is a
feature; it is the list of things the code and the docs disagreed about.

- **Reset now restores the multimeter.** `Multimeter.stow()` watches
  `AppModel.resetNonce`, the `SpatialActionBank` pattern.
- **Magnetism's field lines derive from `magnetismAccent`**, via a new
  `Palette.magnetismLineUI`, the way Electric Fields' already did.
- **`LabPlacement` writes are debounced**, and `adopt` flushes first.
- **Four dead authored fields deleted**: `PendulumsModel.insightText`,
  `CircuitsModel.scopeSamples`, `MagnetismModel.compassIsReadingEarth`,
  `LabNotebook.captureNonce`.
- **`AppModel.activeModuleID` is `private(set)`**, with `go(to:)` and one
  named exception the only writers.
- **`kinematicsAccent` stays #FF9F0A**, deliberately.

**Context:**

*The multimeter* is the SEVENTH instance of the reset defect CLAUDE.md
devotes a paragraph to, and the first that `ResetCoverageTests` could not
have caught: that test reflects over `Bool`s **on models**, and this was
`root.isEnabled` plus a `Set` of carried probes on a **view** object. A
module's `reset` closure is `{ model.reset() }` in all six labs, so any
apparatus a SpaceView owns is outside the net by construction. After a
Reset the meter stayed out in mid-air with both probes where you had
dropped them, on a bench that had just claimed to be restored — against
the rule 73253af set two days ago: *reset restores the apparatus, the
SpaceView arms the experiment.* A multimeter is apparatus. The test file
now states what its reflection cannot reach, so the eighth is not found
the same way.

*Magnetism's lines* were a hardcoded lavender, ΔE 46 from the pink accent
worn by every plate and label around them — a lab in two colours, with
the one filling the room not the one on the furniture. Deriving is not
tidiness: lavender was also the closest thing in the room to the S pole's
blue (ΔE 31), so the exception cost pole legibility too. The accent is
ΔE 58 from N and 73 from S. Both facts are now assertions.

*`activeModuleID`* was settable, and `go(to:)` — which documents itself as
THE ONE DOOR and exists so every lab change runs the same dissolve — was
one of five. The hub's two enter paths and the flat catalog's row assigned
it directly and so skipped the departure fade entirely. The compile-time
enforcement was owed from the day the door was written.

*`kinematicsAccent`* is the one item here that was decided by NOT changing
anything. It sits ΔE 13.5 from the acceleration arrow, under the house bar
of 20, and both are on screen in Projectile Motion. (Two earlier figures in
this log — 5.1 for this pair and 19.5 for `gravityAccent`/velocity — were
hand-typed approximations of UIKit system colours and are wrong; the
measured values are 13.5 and 23.8, so the second pair was never a
collision.) A brute-force search over the RGB cube, kept to bright
saturated candidates, found no warm answer that clears 20: the best is a
dark olive, and clearing the bar means moving to yellow (already Electric
Fields') or green (already the E&M door). The alternative is to move
`acceleration`, a vector colour used in all six labs, to fix one lab's
furniture. The search and its losers are recorded in
`AccentAuthorityTests` so nobody runs it twice.

**Consequences:** Any instrument a SpaceView owns and a hand can move or
reveal now needs the `resetNonce` pattern and a test of its own —
`ResetCoverageTests` will not tell you. `activeModuleID` can only be set
through `go(to:)` or `closeForDismissal()`, which exists because closing
the immersive space must not wait out a fade that has no scene to land in.
The `#FF9F0A`/orange pair stays pinned at 13.5 by
`testTheKnownAccentCollisionHasNotWorsened`, and Magnetism's pink lines
want a device judgement — a simulator frame says they read; it cannot say
how a room full of hot pink feels through passthrough.

## 2026-08-24 — The app icon is milled from the same stock as everything else

**Decision:** The Bohr-atom icon is replaced by Gravity Lab's orbit ring
drawn in the house material language — an anodised body wearing a
champagne keyline, inside a turned champagne band, with the apsis bead
on it. Generated by `Tools/appicon.py`, checked in beside `hubtitles.py`
for the same reason: a PNG nobody can regenerate is a decision nobody
can revisit.

**Context:** The old icon was a white sun ringed by eight saturated
marbles on crossing orbits over a starfield. It rendered competently and
was wrong on three counts that are about this app rather than about
taste. It is the stock physics icon, so it identified the SUBJECT and
not the product. It depicted one lab of six, and loosely — the orrery
runs on real orbital elements, not rainbow marbles. And its palette
existed nowhere in the app: every other surface is champagne on anodised
graphite with one accent per domain, so the first thing a user saw was
the single surface off-canon. Its glow-built treatment also contradicts
the 2026-07-26 review finding that indoors, contours beat surfaces and
casings beat glows.

**Consequences:** The icon and the wordmark are now recognisably the
same object, which is the point. The three layers carry the parallax
geometrically rather than decoratively — the ring's far half sits behind
the body and its near half in front, so gaze walks the ring around the
body. The old front layer was a soft glow, which parallaxes as a smudge.

Three things were got wrong on the way and are recorded so they are not
re-tried. Stroking the band three times at three widths to get shoulders
produces a saw blade, because PIL inserts a round join at every one of
900 segments and the darker pass shows through where consecutive joins
do not quite overlap; the band is an offset polygon now. Nudging a
centred strip sideways to make a lit edge leaves a wedge at each end,
because translating a curve is not offsetting it; the strip is a signed
offset pair. And drawing the far half dimmer puts a visible seam where
the halves meet at the ring's extremes, which is out in open space well
clear of the body — a ring changes appearance where the body occludes it
and nowhere else, so depth comes from the occlusion the layer order
already provides.

**Judge on device.** Checked as a composite, under the circular mask,
at 180/96/56 px, and with the layers offset to approximate gaze
parallax. None of that is the same as seeing it in the Home View, where
the system adds its own specular and shadow to each layer.

## 2026-08-24 — The uneven keyline was a global bevel clamp, not the chamfer width

**Decision:** `use_clamp_overlap` comes off the glyph bevel,
`BEVEL_RESOLUTION` goes to 1, `CHAMFER` stays at 0.015, and the wordmark
materials stop using `Materials.machined`.

**Context:** The milled keyline read crisp on O, H and D and dotted or
absent on A, Y, M, N and R, and no amount of widening the chamfer or
brightening the rim fixed it. Measured on the shipping geometry, median
band width against a nominal 0.02121:

    P H I L O U D E T   0.0157 - 0.0212     (full width)
    S 0.00628   G 0.00605   C 0.00491
    B 0.00169   A 0.00168   M 0.00168
    N 0.00163   & 0.00140   R 0.00088

**Ten of eighteen letters starved, R worst at a twenty-fourth of the
intended band — a 24x spread across the line.** `use_clamp_overlap` does
not limit the bevel where it would overlap; it limits the bevel
EVERYWHERE to what the tightest feature on the mesh allows, so a single
acute join starves the whole glyph. Every letter built round a diagonal
has one. That is also why widening `CHAMFER` to 0.022 barely helped: the
clamp scales the request down by the same factor whatever it is.

Safe to drop because the mesh is sound now. The clamp was guarding the
spiking the CURVE bevel produced, and both causes went earlier — the cut
is a mesh bevel, and the solid comes from Solidify over a cleaned flat
fill (2026-08-22), so there are no holes to walk onto. Verified rather
than assumed: built both ways, every letter comes out 0 non-manifold and
0 boundary either way. Where a bevel genuinely would overlap it still
self-limits per-feature — X to 0.0241, & to 0.0143 — which is the
wanted behaviour.

**Consequences:** Band-width spread across the line goes from **24x to
1.49x**, and the rendered keyline from **3.7x to 1.5x** on PHYSICS and
**5.7x to 1.6x** on PLAYGROUND. One bevel segment rather than two is
half the bevel faces, so the six assets drop from 1.72 MB to 1.14 MB
(34%) — and one facet has ONE normal, so the whole band answers the
light together instead of a highlight picking one of two facets.

`CHAMFER` was briefly taken to 0.022 while the cause was still thought
to be a sub-pixel band. Reverted: 0.015 was judged right on O and H,
which were the letters actually receiving it, and now every letter does.

**And the walls stopped blowing out.** `Materials.machined` carries
`clearcoat = 0.55`, a second specular lobe whose Fresnel goes to ~1 at
grazing incidence whatever the base colour — and a letter's extrusion
walls are grazing by definition. Measured in studio: face luminance 3.6,
walls 119, keyline 161, with the walls covering twice the keyline's area.
The type read as a light-grey block with a dark front rather than as dark
type with a milled edge. Anodising is a matte oxide with no lacquer
layer, so the wordmark now builds its own `PhysicallyBasedMaterial` —
clearcoat 0, metal down, roughness up — and walls fall to 79. The rim
leans on its emissive floor rather than on a specular hit, because a
specular highlight cannot be uniform across letters at different rakes;
that is what a specular highlight is.

**Judge on device.** All of the above is measured off simulator captures
against both a bright wall and Studio Mode. The chamfer is a fraction of
a degree of visual angle in a headset, and whether the keyline reads as
milled metal or as a drawn outline is not a thing a screenshot settles.

## 2026-08-23 — The flat catalog gets a door, and its UI test cannot be fixed

**Decision:** `HubUtilityBar` gains a fourth button that opens the main
window, so the flat catalog is reachable from the home screen. The
guarding UI test is left running under `-uiTesting 1`, and this entry
records why that is not laziness.

**Context:** `HubView` declares the catalog "the accessibility path",
against the standing rule that nothing may be reachable only in space.
But `PlaygroundSpaceView.syncMainWindow()` dismisses the main window
whenever `activeModuleID == nil`, and the utility bar opened only
Settings, Notebook and About — so on the home screen there was no way to
summon it back. The only routes to it were the Digital Crown (which
closes the space, firing `onDisappear`, which reopens the window) or
`-uiTesting 1`. `HomeChromeUITests` asserts the catalog's buttons exist
and passed the whole time, because it launches with that argument.

**Consequences:** The affordance is real and the test still cannot
reach it. XCUITest cannot see into an immersive space — that is the
premise `-uiTesting` exists for — and the new button IS in the immersive
space, so no automated test can press it. Re-pointing
`HomeChromeUITests` at the shipping configuration would not make it
stronger; it would make it fail, because in that configuration the
catalog is only reachable through a control XCUITest is blind to.

So this is verified by hand or not at all, and it belongs on the
on-device checklist rather than in a suite: *from the gallery, press the
list button on the utility bar; the flat catalog opens in front of you;
every lab is listed; tapping one enters it.* A green suite proves
nothing about this and should not be read as if it did.

**Also here:** Circuits' `firstRunHint` described two gestures retired
on 2026-08-11 — an "orange end grip" (the grips were deleted; a lead is
the only thing at an end) and "pinch two copper terminals to wire"
(tap-tap wiring is gone; a tap selects and never wires). Rewritten to
the gestures that exist. And Settings' accessibility hint still said
"Sound, hints and progress"; the progress system was cut on 2026-08-09.

## 2026-08-23 — Nothing opens dead; reset restores the apparatus, the SpaceView arms the experiment

**Decision:** Magnetism's `reset()` seeds TWO magnets, the second
off-axis, so the pair visibly swings into alignment as a wearer arrives.
Electric Fields drops its probe and Projectiles re-fires its welcome
shot from their SpaceViews' `make`, not from `reset()`.

The split is a rule, not a coincidence: **`reset()` restores the
APPARATUS; the SpaceView arms the EXPERIMENT.** A second bar magnet is
the bench itself and must survive a Reset. A probe falling through a
dipole, or a ball in the air, is an experiment in flight — Reset is
entitled to clear it, and `make` re-arms it on the next entry.

**Context:** Two labs opened correct, handsome and completely still.
Magnetism seeded ONE magnet, whose looping field its own comment called
"the opening scene" — true, and motionless, because one magnet has
nothing to attract. Electric Fields drew a dipole with `chargesRespond`
off and no probe. `HOMESCREEN_SPEC.md` decision 5 ("every exhibit is a
perpetual live demo") is written about the gallery and applies one step
in. Magnetism's own `firstRunHint` already said "Bring two close and
watch"; the opening scene is now the sentence the module wrote about
itself.

The SpaceView is the hook that reaches a SECOND VISIT, which is the case
that was actually broken: models are retained on `AppModel`, so
`KinematicsModel.reset()`'s closing `fire()` — "one shot already in the
air" — fired once per process and every later entry opened onto a dead
range. The shell gives each module fresh view identity, so `make` runs
on every entry while the model persists.

Not `chargesRespond = true` in Electric Fields instead: the two dipole
charges would accelerate into each other and destroy the recognisable
picture within a second, over a lit plate whose claim is false at rest.

**Consequences:** Seeding the second magnet broke three existing tests,
all correctly. `testFreezingTheMagnetsStopsThemMoving` added a magnet at
a position the seed now occupies, so `addMagnet` refused;
`testASettledPairDoesNotJitter` built "a pair" that had become a trio;
`testTwoMagnetsCanBeHeldAtOnceAndReleasedIndependently` held two of
three and the free one glided through a "nothing moved" assertion. All
three shared one unstated dependency — that the model's DEFAULT
POPULATION is exactly one magnet. Each now clears the bench and builds
its own fixture, which is what they should always have done; no
assertion was weakened. A fourth test carrying the same latent
dependency was made explicit before it could bite.

`ColdOpenTests` asserts LIVENESS, not a recipe:
`testMagnetismSettlesOnItsOwn` steps the model and demands that
something moved, so an author who makes the room alive another way
passes unchanged and one who quietly makes it still again does not.
Verified by sabotage — deleting the seeded magnet fails three of its
cases by assertion.

**Pendulums was left alone, deliberately.** It looked like the same
defect and is not: `loadNewtonsCradle` sets `damping: 0` and
`bobRestitution = 1.0`, so the cradle is energy-conserving and does not
stop. The only still case is a bench the wearer disturbed, and
re-seeding that on entry would destroy an arrangement they built.

**Circuits was left alone too.** `restoreSaved: true` is a shipped
decision with `StoredBench`/`migrated(_:)` and
`CircuitsBenchMigrationTests` built to protect it. `reset()` already
calls `seedStarterLoop()`, so the live starter circuit is one pinch
away. Resetting the bench before a demo is device prep, not a code
change.

## 2026-08-23 — A lab arrives and departs, through one door

**Decision:** `AppModel.go(to:)` is the one way to change the active
module, and `isDeparting` is the flag six scenes ride. A lab's root
starts disabled and is raised and lowered by `RenderKit.Fade.tick` over
`AppModel.departure` (0.22 s); the gallery's `fadeIn` became a two-way
`fadePresence` and now leaves rather than vanishing. The transition is a
**dissolve through passthrough**, not a cross-dissolve.

**Context:** Three call sites assigned `activeModuleID` directly, so
every change of scene was a one-frame branch flip. The third —
`Palette.onSelect`, lab→lab — was missed by the first pass of this work
and is the switch a demo makes most, because it never touches the
gallery at all.

A true cross-dissolve would need both scenes alive at once, doubling
peak scene cost for every transition. It is also unnecessary: the
wearer's real room never leaves the frame, so fading one scene out and
the next in reads as continuous rather than as a cut. Nothing new was
written for it — `RenderKit/Fade.swift` already ramps an
`OpacityComponent` both ways, snaps under Reduce Motion, and drops its
clock and component once settled.

**Consequences:** Two orderings are load-bearing and both are held by
tests rather than by comments. `isDeparting` clears BEFORE the swap, or
the incoming scene mounts already invisible with nothing left to raise
it — an invisible lab is indistinguishable from a crash, and
`AppModelDoorTests.testTheFlagClearsBeforeTheSwap` asserts both facts at
one instant, since asserting them separately would let the broken order
pass. And the gallery KEEPS its `OpacityComponent` at 0 rather than
removing it on landing, or it snaps back to full opacity for the frames
before the module mounts — the hard cut arriving by the back door.

`ModuleArrivalCriterionTests` bans the shape rather than listing the
six: a SpaceView that adds a renderer root must also fade it, so a
seventh module is covered the day it is written. It is a text criterion
because `makeScene()` returns an `AnyView` that cannot be rendered
offscreen, so reflection cannot reach a module's root. It was verified
by sabotage — removing one module's `Fade.tick` fails the build, by
assertion and not by compile error.

`go(to:)` goes straight through when there is nothing to fade from,
when the space is closed, or under Reduce Motion; a delay nobody can see
is latency. Also fixed here: `HubSpaceView.enter` had no stillness
guard, so Reduce Motion skipped the arrival ceremony but not the 420 ms
enter swell — the setting was half-honoured since the day it was
written.

**Not done:** `activeModuleID` is still `var`, not `private(set)`. Two
of its eight call sites are in `HubView.swift`, which had uncommitted
work in it at the time; both are behaviourally identical through
`go(to:)` because its `isImmersiveSpaceOpen` guard makes them
synchronous. The compile-time enforcement is owed.

## 2026-08-23 — The room's brightness ramps, and the shell is not the cut

**Decision:** `roomDimming` becomes the TARGET and
`AppModel.dimmingShown` the displayed level, eased toward it by
`RoomDimmerView.step` (on `Motion.ease`, rate 9, ~0.25 s) from a
`SceneEvents.Update` tick inside the dimmer. The dimmer is mounted
unconditionally rather than behind `roomDimming > 0.01`, its dome is
built at unit radius and sized by transform rather than keyed by
`.id()`, and `AppModel.dimmingRadius` carries the radius so the ramp can
read it per frame without building a `ModuleDescriptor`.

**And, separately: the dimming shell is NOT used as a transition
medium.** A dip-to-dark cross-fade was proposed for the hub→module cut,
built toward, and rejected before it shipped.

**Context:** The level was assigned in one frame on every entry and
exit — hub 0, five labs 0.35, Gravity Lab 0.85 — so the wearer's real
living room jumped brightness twice per lab visit.
`AtmosphereCriterionTests` had already named this "the loudest
difference between two rooms that are supposed to feel like one place";
it settled the VALUES and had no way to reach the step between them.

The dip-to-dark idea failed on three counts, all checkable. The shell
cannot conceal a cut: `rampTexture` caps alpha at 235/255 under
`material.blending = .transparent(opacity: 0.9)`, so even at level 1.0
it is a heavy smoke over a translucent dome — Gravity Lab's emissive Sun
and Electric Fields' cyan lines read straight through. Ramping to 1.0 at
the default 3.4 m radius is exactly the case
`testAModuleThatDimsHeavilyAlsoMovesItsShellOut` forbids, and it would
happen transiently on entry to all six modules. And a 420 ms slam toward
black on every transition is a *larger* lurch than the snap it was meant
to cure — by the fourth cut in a demo it reads as a strobe.

**Consequences:** Entering, leaving and switching labs all ramp. The
transition dissolve is a separate mechanism (`RenderKit.Fade` on the
scene roots) and does not depend on this one. `AtmosphereRampTests`
holds the ramp, and one of its cases —
`testTheRampNeverLeavesTheInterval`, swept over levels and dt — is a
standing ban on the rejected design: the level may never leave the
interval between where it is and where it is going, so no future author
can reintroduce an excursion toward dark. Under Reduce Motion the ramp
jumps, because somebody who asks the room to stop changing brightness
wants it to stop rather than to change more smoothly.

The dimmer now does per-frame work during a transition, which its header
denied until today; the header says so now. Settled, `Motion.ease`
returns the target exactly and the write is idempotent.

## 2026-08-09 — Electric Fields' field lines wear Electric Fields' colour

**Decision:** `Palette.fieldLineUI` becomes `electrostaticsAccent`
(#FFEA05) instead of pale cyan, so the lines in the lab and in the hub
miniature match the module's own hue. Magnetism's miniature, which was
borrowing that token, is repointed at `MagnetismRenderer.lineColor`.

**Context:** Owner's call. Every other surface this module owns — the
door sign, the nameplate, the icon, the switch labels — wears
`electrostaticsAccent`, and the one thing the lab is actually about wore
an unrelated cyan. Derived FROM the accent rather than hand-mixed near
it: a hand-mixed warm yellow would land a few ΔE away, which is exactly
the "two shades of the same yellow" failure recorded against
`electrostaticsAccent` itself, and it would show most on the home screen
where the miniature's lines sit beside the nameplate.

It also un-collides the field from its own sources. Cyan lines ran
through blue negative charges — the field and one of its two poles in
the same corner of the wheel.

**Consequences:**

- **A latent mismatch surfaced and was fixed.** `fieldLineUI` was
  written as a general token and used by TWO hub vignettes, so the
  magnetism miniature drew magnetic field lines in Electric Fields'
  colour. That was already wrong — `MagnetismRenderer` draws that lab's
  lines in lavender, so the miniature advertising it never matched it —
  and a shared token merely hid it while both were neutral cyan.
  Changing the token would have turned magnets yellow.
- **The token now means what its name implies for one module.** Anything
  else wanting a field line reads its own renderer's constant, which is
  the rule that stops the next drift.
- **STILL OPEN: Magnetism has the same defect this entry fixes.** Its
  accent is pink and its field lines are lavender, in both the lab and
  now the miniature. They agree with each other, which is the bug this
  entry was about; they do not agree with the door. Left alone
  deliberately — it was not asked for, and lavender-on-pink is a closer
  pair than cyan-on-yellow ever was.

## 2026-08-09 — No card of words stands in a lab

**Decision:** Owner's call. Both dark text panels inside the modules are
deleted: the in-room first-run teach (`Shell/RoomTeach.swift`) and the
Circuits running commentary (`CircuitsInsightCard`). The teach survives
in the module WINDOW, which is where it started. The small backed
readouts on the apparatus — values, switch labels, rack names — stay.

**Context:** This reverses 2026-08-08 twice over, and the reversal is
narrower than it looks. That entry moved the teach into the room to fix
a real defect: RealityKit content renders in front of a window behind
it, so the apparatus was drawing straight through the sentence. The fix
worked. What it produced was a paragraph standing in front of the bench
instead of behind it — legible, and covering the thing it describes. A
screenshot of Circuit Workshop shows the card spanning the entire
apparatus, which is a worse trade than the one it replaced.

The room has now rejected three cards of words in three days:
`FirstRunHint` (08-08, "unnecessary and in the way"), the Gallery's
"Or carry a lab to the pad" (08-09), and `RoomTeach` (08-09). The
pattern is not about any one card's copy or placement. **A paragraph is
the wrong shape for this room.** Anything big enough to read at a
comfortable distance is big enough to cover an experiment, and this app's
whole argument is that the experiment is the explanation.

The insight card had the best case of the three and is worth recording
properly, because it was not a repeat of the hint. It said something
DIFFERENT each time, about the circuit you had just built; it was absent
when there was nothing to say; and it woke twelve authored paragraphs
that had been written and left dark since the window panels were deleted
on 2026-08-01. Its own header set the condition for its removal — "if it
ever repeats itself it is behaving like the hint and should go the same
way" — and the verdict is that the shape was wrong even though the
content was not.

**Consequences:**

- **The window is the only place a lab explains itself in words.**
  `ModuleDescriptor.firstRunHint` and `ModuleHostView` are unchanged, and
  `AppSettings.seenHints` still gates that copy. A wearer who opens the
  room without reading the window gets no sentence — which is the state
  the app was in before 2026-08-07, and the owner's judgement is that the
  apparatus teaches better than the paragraph did.
- **`CircuitsModel` loses its whole commentary layer**: `insightText`,
  `insightClock`, `insightHoldUntil`, the twelve-second `hold` that kept
  an authored paragraph from being overwritten by the live line, and
  `failureNote`, whose only reader was that layer. Deleting the card
  without them would recreate exactly the twelve-writers-no-readers
  defect the card was built to fix.
- **The five presets keep their circuits and lose their paragraphs.**
  `loadPreset` still builds series bulbs, parallel bulbs, a divider, an
  RC charger and a dead short out of ordinary rewireable parts. That is
  the teaching now.
- **`PendulumsModel.insightText` is left alone and is DEAD** — twelve
  writers, zero readers, and no card was ever built for it. It is
  outside the scope of this change and is recorded here so the next
  reader knows it is not load-bearing.
- Two test files go: `RoomTeachTests` (which asserted the card stood
  nearer than every lab's apparatus) and `CircuitsInsightTests`.

## 2026-08-09 — The home screen loses four surfaces and gains three modelled platforms

**Decision:** Owner's call, five changes to the Gallery in one pass.

1. **The experiments system is deleted outright** — `Experiments.swift`,
   `ExperimentsView`, the flask button, the progress ring behind every
   exhibit, the per-module counts in the flat catalog, the Settings
   reset, the persisted completions and streak, and all twenty authored
   steps. Not hidden behind a switch: removed.
2. **The ENTER plaque is gone**, and a tap on an exhibit now flies it to
   the pad instead of doing nothing.
3. **The "Or carry a lab to the pad" card is gone.**
4. **The wordmark's black backing plate is gone**, replaced by a dark
   keyline built per glyph.
5. **The terraces, the pucks and the pad are modelled** —
   `Tools/galleryplatforms.py`, five new USDZ assets.

**Context:** Changes 2 and 3 are one decision, and they undo the pact
recorded on 2026-07-29 ("the podium is the delightful path; the button is
the reachable one, and neither may be deleted without the other
changing"). The pact was honoured, not broken: the reachable path did
change, into a tap. What is gone is the FURNITURE that used to explain
the ceremony — a plaque standing on every terrace and a caption hanging
at the pad's rim, both of which existed to teach a gesture. A tap that
performs the gesture teaches it better and leaves nothing standing.

The 2026-07-29 objection to tap-to-enter still stands and is not
violated. That objection was that entering by tap made a shelf of six
live miniatures into one large accidental-activation surface. A tap that
MOVES a lab across the room does not enter anything; the door is still
the Load button, still a second deliberate pinch, still in a different
place. VoiceOver keeps a direct route into the lab, because the
ceremony's entire payload is visual and charging it to someone sweeping
the room by touch would be a worse deal than the plaque was.

Change 4 reverses 2026-08-08, one day old. The plate was the right
diagnosis — ivory metal over a cream wall is light-on-light, and CASINGS
BEAT GLOWS (2026-07-26) — and the wrong object: a black rectangle
hanging in the room to make some words legible. The casing now follows
the letterforms. Two earlier attempts at that had failed and both are
recorded in the code: a dark copy offset backward interpenetrates type
this deeply extruded, and a dark copy SCALED UP moves every glyph
outward from the string's centre so the shell letters land between their
own neighbours. Both fail because they treat a line as one object;
building it glyph by glyph does not.

**The platform designs, and the three that lost.** The owner chose an
optical bench from four candidates. The others are recorded because a
decision with no alternatives written down reads later as the only thing
anyone thought of:

- **Optical bench + docking cradle (chosen)** — milled breadboard
  terraces with T-slots and a lit front rail, three-ball kinematic
  mounts as pedestals, and a hexagonal docking cradle whose three latch
  fingers close on a lab when it lands.
- **Museum vitrine plinths** — terrazzo shelves with brushed-brass
  fascias, turned brass pedestal rings, and a graduated turntable for
  the pad. Closest to `HubTitleStyle`'s existing plaque voice.
- **Levitation coils** — no slab at all: a contour plate, Halbach coil
  rings with a field skirt under each hovering miniature, and a maglev
  trap for the pad. The most physics-native and the least furniture.
- **Equipment rack** — anodised rack panels with ears, vent slots and
  hex fasteners, shock-mount isolators, and a hardpoint with a captive
  fastener for the pad.

**Consequences:**

- **The app no longer tracks anything about the user's progress.** The
  hub is a launcher again, and the argument in the deleted
  `ExperimentCatalog.nextStep` — that a tally says where you are and
  nothing about where to go, so a hub carrying only a score can only
  ever be a launcher — is now a description of what shipped rather than
  a problem statement. Reopening it means designing the direction half
  first. `DesignTokens.Palette.completionGold` went with it, under this
  project's own rule that a token nobody reads is unreachable choice.
- **Nothing in the room is the only path to a lab.** Tap, carry, and the
  flat window catalog all reach every module; VoiceOver reaches them
  directly. `GalleryDoorTests` asserts all of it, and is the successor
  to `EnterPlaqueTests` — the door has been rebuilt four times now and
  two of those rebuilds shipped broken.
- **A terrace is TILES, not a slab.** `GalleryLayout` sizes terraces from
  module count (`0.36·n + 0.08`), so the asset is a 0.36 m bay plus two
  0.04 m caps and the arithmetic closes exactly. A seventh lab lands on
  a terrace one real bay longer. Nothing may be non-uniformly stretched
  to fit.
- **Two details in those assets were built, shipped to a screenshot, and
  rebuilt**, and both failures were the same failure. A drilled 25 mm
  hole grid cut correctly, cost 4,556 vertices per bay, and was
  invisible — a dark hole in a near-black bench has no contrast to show.
  The kinematic mounts' steel balls sat under a top plate wider than the
  circle they stand on, so the one detail that makes the part an
  instrument faced the floor. A part is only as good as its silhouette
  from where the viewer actually stands, and neither error is visible in
  the numbers.

## 2026-08-09 — I accused the predicted arc of a defect it does not have (RETRACTED)

**Decision:** The two entries this replaces were wrong. `ProjectileMotion`
and `KinematicsModel` agree as far as I could measure, P1-24's three
repairs hold, and the "3 m/s divergence" I recorded was my test comparing
the arc against the wrong ball. No code was changed on the strength of
the false claim; the damage was to the record, and this is the repair.

**What actually happened.** Verified directly: fire the launcher, track
the flight created by that call, and read positions at moments where the
ball's simulated time coincides with a sample of the polyline.

    t = 0.0333 s   ball (-0.1410, 1.3595)   arc (-0.1410, 1.3596)
    t = 0.0667 s   ball ( 0.0755, 1.4682)   arc ( 0.0755, 1.4682)

A tenth of a millimetre. The ball's velocity is (6.495, 3.641, 0) against
a launch vector of (6.495, 3.750, 0) — gravity, and nothing else, has
touched it.

**The four wrong turns, because each produced a confident wrong number
and the last one reached a commit message:**

1. Compared the ball's distance to the polyline over a window longer than
   the polyline. The prediction ends; the ball does not; distance to a
   finished curve grows without bound. → "9 cm and unexplained".
2. Matched wall-clock against simulated time. (`timeScale` is 1.0, so
   this one happened to be harmless.)
3. Guessed the polyline's cadence twice, in both directions — 1/60 then
   1/240 — instead of measuring it. Consecutive points are 0.1243 m apart
   at 7.5 m/s: an implied 1/60.3 s.
4. Read `flights.first`. THE MODULE SEEDS A WELCOME SHOT AT STARTUP, so
   that is somebody else's ball, launched elsewhere at another speed.
   Its velocity was (3.502, 3.393, 0) — constant x, no drag decay, which
   is what finally gave it away. This is the one I wrote up as a defect
   in shipping code.

**Consequences.** No test ships. Every version I could write was either
red for a reason I had not found or green by a tolerance I had tuned, and
after four wrong turns in one sitting I do not trust a fifth attempt made
at the same sitting. The claim is still worth a criterion and the
obstacles are now named: track the flight `fire()` creates, step at the
polyline's own cadence (`pointStride · timeStep`), stop at the end of the
arc, and expect agreement near 1e-4 m in free flight.

The general lesson is the session's, not this file's: three separate
times today a test agreed with me while a photograph or a raw dump
disagreed. Measuring the wrong relationship is the failure mode here, not
getting the arithmetic wrong, and it does not announce itself — it comes
out green.

## 2026-08-09 — Circuit Workshop's bench is too wide for its own instruments (CLOSED 2026-08-26)

**Decision:** None yet — this is a measurement placed in front of the
owner, and the code is unchanged. *(Answered on 2026-08-26: the bench
narrowed to 0.60 and the rack came in to 0.74. See that entry — and note
that the diagnosis below is half wrong, in a way worth reading: the parts
jumping inward is not caused by the rack's position and could never have
been fixed by moving it.)*

**Context:** The parts rack was found standing 0.10 m from a build volume
that ends at 0.70, inside a 0.12 m `InstrumentClearance.stationMargin`.
That one was fixable: x 0.82, z −0.77, and the on-screen window drops
from six slots to five because no depth satisfies margin, reach and
off-axis angle with six.

The layers bank on the other flank is not fixable the same way. It sits
at x −0.62, INSIDE the volume. It is 0.15 half-wide, so clearing the
margin needs its centre at |x| ≥ 0.97, and a search over x 0.82…1.30
against z 0.60…1.20 finds NO position satisfying all three rules. The
closest is x 0.97, z −0.73: reach 1.253 m against a 1.25 limit and 53.0
degrees against 48. The multimeter's rest position (+0.62) is inside the
volume for the same reason.

So the constraint that is actually binding is the bench's own width. At
`CircuitsModel.buildHalfExtents.x` = 0.60 the bank fits at x 0.87,
z −0.79 — reach 1.215, 47.8 degrees. At 0.55 it is comfortable.

**Consequences of the change, if it is made:** narrowing the volume is
one number, and it is not free. `add(_:at:)` clamps to the volume, so
every saved circuit holding a part between 0.60 and 0.70 has a component
outside its own bench on restore — a migration, not a constant. The
alternative is to fold the flanking instruments behind a `SummonHandle`
so they are not standing in the room at all, which is the answer Phase 2
already reaches for elsewhere and which changes what the bench looks
like when you walk up to it. Both are the owner's call; the measurement
is recorded at the bank's anchor in `CircuitsSpaceView` so the next
reader does not re-derive it or "fix" it by nudging.

## 2026-08-08 — The first-run teach moves into the room, and stays in the window while the room is shut

**Decision:** Each lab's `firstRunHint` is drawn as a card in the room
(`Shell/RoomTeach.swift`), standing nearer to the wearer than any lab's
apparatus and dismissed by touching it anywhere. The flat window still
draws it while the immersive space is CLOSED, and both dismissals write
the same receipt.

**Context:** The first photograph ever taken of a lab in a room
(2026-08-08, Pendulums) showed five steel bobs and four vector arrows
standing through the sentence, whole phrases unreadable: RealityKit
content renders in front of a window that happens to be behind it. The
first attempt at a fix raised the text's contrast — it was styled
`.secondary`, the app's quietest, for the most important sentence in the
lab, while the failure banner above it was plain. That was an
independently correct change and it barely moved the photograph. You
cannot win a depth argument with a colour.

This is the third occlusion of the same shape in two days — the home
wordmark behind the catalog window, the L4 paragraph inside the star,
this — and all three were fixed by putting the words in front, not by
making them brighter.

Keeping the window copy while the room is shut is not two places for one
string. The card does not exist at that moment, so they are never both
on screen; and the flat window is the accessibility path, so deleting
the hint from it would leave a wearer who never opens the room as the
only person who never reads the sentence.

**Consequences:** The shell now owns an in-room teaching surface, and
`RoomTeachCard.standoff` is a promise it can keep only because the shell
places both the card and the labs. `RoomTeachTests` asserts the card
stands nearer than each lab's apparatus, so a module that moves its
physics forward turns the build red rather than quietly going back to
being occluded. The window's hint is now conditional, which is one more
state for the title bar to be in. And the accessibility label is the
sentence itself — `SpatialActions.attach` writes that label, so the
first draft announced "First-run hint" and never read it out; a test
caught it before the commit.

## 2026-08-07 — Three accents measured against reserved hues, and two of them are a decision for the owner

**Decision:** `MaterialCanonCriterionTests` now scans `Hub/`,
`DesignSystem/` and `Shell/` as well as `Modules/` — the two directories
that DEFINE the canon were outside the only test enforcing it, and so
was the gallery, the first surface every user sees. It passes: there is
no `SimpleMaterial` in any of them.

**The colour work is NOT done, and the measurements are why.** Audit 3.5
says `electrostaticsAccent` (1.0, 0.84, 0.04) is the reserved completion
gold (1.0, 0.84, 0.25) and should be shifted. Measured in CIE Lab:

| pair | ΔE |
|---|---|
| `kinematicsAccent` ↔ `VectorPalette.acceleration` | **5.1** |
| `completionGold` ↔ `electrostaticsAccent` | 11.6 |
| `gravityAccent` (indigo) ↔ `VectorPalette.velocity` | 19.5 |

The audit named the middle one. **The worst is one it mentions only
obliquely** — Mechanics' door hue #FF9F0A and the acceleration arrow's
`.systemOrange` are 5.1 apart, which is barely a perceptible difference,
and Projectiles draws acceleration arrows in its own accent's colour.
Gravity Lab has the same problem with velocity at 19.5.

**Why none of it was changed.** Each of the three is a different kind of
decision and none of them is mine to take alone:

- Shifting `electrostaticsAccent` away from gold means moving a module's
  identity hue, and gold IS yellow — getting ΔE 20 from it while
  remaining recognisably "the yellow lab" may not be possible. The
  alternative is moving `completionGold`, which appears on every
  progress ring in the gallery.
- Fixing the acceleration collision means changing either the Mechanics
  DOOR (brand) or the acceleration arrow (a shared physics vocabulary
  used in every module). Both are wider than the defect.

A test was deliberately NOT written for these. A criterion whose
threshold has to be lowered until it passes is a listing test wearing a
criterion's clothes, and this arc has already produced four green tests
that proved nothing. The numbers are here so the decision can be taken
on evidence; the test goes in with the fix.

**Also unaddressed, and recorded rather than guessed:** audit P2-6 says
the hub hand-rolls the glass recipe the design system bans. The rule
that actually exists bans `SimpleMaterial` and explicitly permits a
`PhysicallyBasedMaterial` "whose values are a stated decision" — which
is what `HubSpaceView` builds, without the stated decision. That is a
real gap, but closing it changes how the gallery bar and podium look,
and nothing in this arc has been seen on device yet.

## 2026-08-07 — Gravity Lab folds: a tab that is both the summary and the door

**Decision:** Owner's direction — *"the gravity lab is way too cluttered
with UI. Please do a more simplistic design overhaul for this module."*
The answer is a new design-system primitive, `SummonHandle`, and Gravity
Lab is its first user.

Standing objects in that room go from about **eighteen to nine**:

| | Before | After |
|---|---|---|
| Layer plates | 7 | 2 (grid, field flow) |
| Clock | 6 discs, ~0.40 m wide | 1 tab reading "Clock · 5×" |
| Analysis | — | 1 tab (sweep, Lagrange behind it) |
| Vectors | — | 1 tab (v, a, F behind it) |
| Verb plates | 2 | 2 |
| Rail, well, card | 3 | 3 |

**Context:** `SpatialLayerBank`'s argument for never folding is right as
far as it goes — *a bank is a readout as well as a control* — and it
holds at four plates and fails at seven. It also collided with Phase 0:
re-deriving the clock fan to fit its own touch targets made it 40 cm
wide, correctly, which made the room worse.

`SummonHandle.summary` is what dissolves the argument. A plain fold
takes the readout away with the control; a fold that keeps a live
one-line summary does not. "Clock · 5×" is the same fact six discs were
carrying, in one object, and pinching it unfolds the fan to change it.

**Consequences — and one place the goal was wrong.** §2.4 says to move
velocity/acceleration/force onto the selected body's Bloom ring, on the
grounds that they are per-body annotations and the ring already exists
to hold them. The diagnosis is right and the prescription is not:
`showVelocityVector` and its two siblings are **global** flags. The
renderer draws the arrows on whichever body is selected, but the switch
is not a property of that body, so a per-body ring would mean toggling
it for Earth silently changed what Jupiter shows — a control that lies
about its own scope. They get their own group and their own door
instead. (A minor second reason: the ring already carries Predict and
Delete, and `Bloom.Petal`'s ceiling is "two or three per object, never
more".)

`Recession` and `Motion` land with it. Instruments now sit at 45%
opacity until a fingertip comes within 0.8 m — one mechanism, no
capability removed, and the precedent is the hub's own focus recession
plus "emphasis is opacity, light and sound — never geometry"
(2026-07-30). `Motion` is the app's single Reduce Motion authority,
because the setting reached two of eight animated primitives and the
tell is in one frame: the hub's terrace hairlines freeze mid-shimmer
while the door signs above them park correctly.

**Not yet done.** The `Instrument`/`InstrumentRail` protocol the goal
asks for is NOT built — `SummonHandle` is the piece of it that the
clutter actually needed, and it is a standalone primitive. The rail,
the Electric Fields pilot and deleting `FieldInstrumentLayout` remain,
as does routing the other six animated primitives through `Motion` and
the VoiceOver `systemActions` sweep. `SummonHandle` declares
`.activate` and re-publishes its value on every toggle, so the pattern
the sweep should follow is written down in one place.

**Unverified.** Every number above is a count, not a screenshot. Three
tabs in a column on the left flank, a fan that now unfolds above its own
tab, and a room at 45% until you reach for it — none of that has been
seen. Placement is what this project has got wrong three times with the
arithmetic looking fine each time.

## 2026-08-07 — The front door gets a handle; the window stops going blank

**Decision:** Phase 1 of the audit arc. Every item is a first-ninety-
seconds failure with no recovery, and each one was a capability with
zero paths or one.

- **An ENTER plaque on every puck.** A small machined slab in the
  module's accent, standing on the terrace in front of each plinth.
  Gaze plus a pinch, nothing to aim or carry. The carry-to-the-pad stays
  as the ceremony and the podium hint now teaches it rather than being
  the only instruction.
- **The window keeps a compact catalog and `AppProgressLine` at all
  times**, instead of going blank the moment the Gallery opens — which
  is half a second after launch, every launch.
- **`HubDomain.promise` finally has a reader**: one line of "what you
  actually do here" under the focused exhibit's name, gated on focus so
  at most one is ever on screen.
- **The palette bead gains `home` and `dim`**, and its petal row width
  is now DERIVED from the count.
- **The room-sensing explanation moved onto `RoomModel.Sensing`** and is
  said in the hub window — one line before the ask, the real consequence
  and its remedy after a refusal.
- **The first-run teach is mounted in the room** beside the apparatus,
  dismissed by a pinch, sharing `seenHints` with the flat one.
- **`dismissImmersiveSpace` exists.** It appeared zero times in the app
  target.

**Context:** DECISIONS 2026-07-29 removed tap-to-enter because "entering
by tap made the whole gallery one large accidental-activation surface
while merely looking around", and in the same entry made the podium and
the focus panel's Load button an explicit pair: *"the podium is the
delightful path; the button is the reachable one, and neither may be
deleted without the other changing."* The panel was deleted on
2026-08-04 and the podium did not change. For three days the only way
into a lab was a sustained ~1.1 m pinch-drag onto a 0.105 m pad, and the
flat catalog that is this app's whole answer to "nothing may be
reachable only in space" was hidden for the entire time the app was in
its normal state.

The plaque answers the 2026-07-29 objection rather than ignoring it: the
accidental-activation surface was the exhibit itself, a 0.27 m object
you are meant to look at, and this is a separate 0.11 m sign you have to
look AT. A tap on the exhibit still does not enter.

**Consequences:** Where the plaque STANDS was measured, not reasoned,
and the measurement changed the design. The puck is 0.17 m across and
the exhibit's own touch target is a 0.27 m box, so the whole puck top is
inside it — a plaque there is a plaque whose pinches the exhibit wins.
Dropping it low enough to clear vertically sinks it into the terrace, so
it stands forward of the plinth and clears on z. The new
`testGalleryExhibitTargetsDoNotOverlapEachOther` caught all of that on
the first run, and caught a later attempt to fold the name plate into
the exhibit's target (the plate carries the module TITLE, which is wider
than the 0.36 m puck pitch on its own).

Six petals on the bead is not six more objects: a folded ring stands for
nothing, and the real cost is the row's width when open. That width was
a literal 0.22 m carrying a comment that it had been "widened from 0.17
when the fourth petal arrived" — the clock-bank defect exactly, one
count later. A fifth petal would have pitched at 0.055 m against a
0.068 m target. It is derived now, with a criterion test.

**Still open:** the in-room teach and the promise line are new standing
objects in rooms this project is trying to quieten, and the owner's
2026-08-07 direction is that Gravity Lab in particular is "way too
cluttered". Both are focus- or once-gated for that reason, and neither
is in Gravity Lab's own instrument set — but the count is the count, and
Phase 2's container work is where it gets paid back.

## 2026-08-04 → 2026-08-06 — The entries that were never written

**Decision:** Recorded late, on 2026-08-07, because the log had none at
all for these three days and its own 2026-08-03 entry diagnoses exactly
this drift. What happened, from the commits and the code:

- **2026-08-04 — the focus panel was deleted.** `HubFocusPanel` carried
  the domain chip, the promise line, the progress dial, the New badge
  and the Enter button. Names also stopped fading on unfocus at the
  owner's direction, on the grounds that a gallery whose captions vanish
  until you stare at them cannot be read at a glance.
- **2026-08-05 — the visual polish pass**, ten commits: the material
  canon test, backed labels, `Fade`/shadows/pulse, `PlateStyle`, the
  store-copy criterion.
- **2026-08-06 — three projectile bounce fixes**, backed labels on by
  default, and `docs/CIRCUITS_DESIGN_REVIEW.md`.

**Context:** The panel's deletion is the one that mattered and the one
that went unrecorded. It took with it the only reachable way into a lab
and the only reader `HubDomain.promise` had, and because nothing was
written down, both losses were invisible until the 2026-08-07 audit
went looking. The entry that should have been written on the day would
have had to answer 2026-07-29's "neither may be deleted without the
other changing", and answering it is what would have caught this.

**Consequences:** Both losses are repaired above. The rule this
re-states: deleting a surface is not a small change if anything was
displayed ON it — the content survives compilation and dies silently,
which is the shape of every item in the audit's dead-content table.

## 2026-08-07 — The collider rule, the fan span and the press-vs-tap all stop being matters of attention

**Decision:** The Phase 0 pass of the 2026-08-07 audit arc. Nine
load-bearing defects, none of them a design change, and three of them
converted from things a careful author had to remember into things a
test enforces:

- **`RenderKit.rotation(from:to:)`** is now the only way this app builds
  a rotation between two vectors, at all thirteen sites. The
  antiparallel guard existed at `VectorFieldArrows:107` and had never
  been shared. The seven viewer-facing instruments do not use it at
  all — they use `yaw(facing:from:)`, because turning to face a reader
  is one degree of freedom and `atan2` is exact.
- **`ColliderCriterionTests`** walks every `CollisionComponent` in a
  scene built from each of the six modules, the gallery, the design
  system's primitives and the placement puck, and fails any shape more
  than `max(×1.15, +30 mm)` larger than its entity's own visual bounds,
  measured in WORLD METRES — shielding is a property of the room, and
  the two frames diverge wherever an entity is scaled per instance. It
  found violations in every module and the gallery; the worst was a
  0.52 m sphere on a 12 mm capacitor plate, which made every charge
  inside the capacitor unpinchable. `Grabbable` gained `box:`,
  `matchingVisualBoundsOf:` and `sphereTargetRadius(baseRadius:scale:)`,
  because sphere-only was what forced the rule to be broken.
  A SECOND criterion sits beside it —
  `testGalleryExhibitTargetsDoNotOverlapEachOther` — because the first
  cannot police a collider derived from the very bounds it is measured
  against. See the two review rounds below.
- **`FanLayout.spread(count:itemSpan:reach:…)`** derives a fan's span
  from how many things are in it and how wide their touch targets are.
  Gravity Lab's clock bank was hand-tuned for four discs and its array
  grew to six.
- **`PressLatch`** holds a press until it has travelled 12 mm, and
  Pendulums and Projectiles route their destructive branches through
  it.

Also: `SoundPalette` synthesis moved off the main actor and all four
cache filenames versioned; `RelativeDrag.travel(forHand:)` replacing two
copies of a drag-distance measurement that measured one frame;
`SpatialScaleRig.cancelGesture()` distinguished from the commit;
`PinchLedger` and Magnetism's grab table expiring entries after 0.5 s;
`GeometryPipeline.cancel()` and a `teardown()` on all six renderers;
`Bloom.configure` clearing `gripDrag`; `isImmersiveSpaceOpen` moved off
a `Group`; and `RoomModel.release()` no longer guarded on `isRunning`.

**Context:** Every one of these had shipped, and most had shipped
_twice_. The pattern is the same one `ResetCoverageTests` was written
for and it is worth naming again: **a test that lists the cases somebody
thought of is the same act of attention that missed them.**
`FanLayoutTests` is the clearest example — it checked disc clearance
against 0.052 m (the painted face, not the 0.068 m collider) and only
ever tested `FanLayout()`, which is the one layout in the app that no
module uses. It was thorough-looking and covered nothing that shipped.
Its ceiling of nine items turned out to be *right* — that is exactly
where the default arc runs out of room, and why Gravity Lab's ten-world
fan carries a bespoke layout — but the number was written in bare, with
no reasoning beside it and nothing to hit if a tenth choice were added
to a picker using the default. It is derived now.

**One correction to the audit.** `AUDIT_2026-08-07.md` P0-1 says the
undefined quaternions produce "either a NaN transform or an arbitrary
orientation". Measured on this platform, neither: `simd_quatf(from:to:)`
resolves both degenerate ends deterministically and maps `a` to `b`
correctly. There is no NaN anywhere in the app, and for the
rotationally symmetric geometry at most of the sites the roll it picks
is invisible. Two things remain true, and are what the change is for:
the behaviour is UNSPECIFIED and being relied on at thirteen sites, and
at one site the roll is visible and wrong — a circuit part dragged
end-for-end came out upside down rather than turned around.
`RotationTests` pins that case, and its header records the correction so
the next reader does not go looking for the NaN.

**Consequences:** Three rules are now mechanical rather than
remembered. A collider larger than its object fails the build; a fan
that outgrows its span widens instead of jamming; a `nonisolated`
synthesis path cannot be dragged back onto the main actor without
someone noticing. Two new shared primitives — `PressLatch` and
`rotation(from:to:)` — are the answer whenever the same problem appears
again, and the third module to need the press discriminator will not
hand-roll a third copy. `Grabbable.configureTouchTarget(_:collisionRadius:)`
survives for things that really are balls, but its doc comment now says
so and names the plate that proved it.

**FIVE DEFECTS IN THIS PASS WERE FOUND BY REVIEWING IT, not by the
tests, and one of them was worse than anything it fixed.** Recorded
because the list is the argument for reviewing a mechanical pass at all:

- `PressLatch` **re-armed on every frame**, because both call sites sit
  inside `if drag == nil` and a targeted gesture reports the same entity
  every frame. The anchor moved with the hand, the threshold was never
  crossed, and a pendulum bob and a ball in flight became *impossible to
  grab at any speed* — the central interaction of two modules, dead. The
  test passed because it pressed once and then only promoted: it modelled
  the sequence the author believed the handler ran. `press` now ignores a
  press while one is pending, and `testPressingEveryFrameStillPromotes`
  drives the real order.
- The gallery exhibit's target was measured from `pulser`, which contains
  the **0.40 m focus glow**, so the "fix" produced a 0.43 m target against
  a 0.36 m pitch — WIDER than the 0.19 m sphere it replaced. The collider
  criterion passed it *by construction*: a box derived from an entity's
  bounds trivially satisfies a test that measures it against those bounds.
  The answer is a criterion that question cannot dodge —
  `testGalleryExhibitTargetsDoNotOverlapEachOther` asks whether neighbours
  shield each other, which is what the rule was always about.
- The criterion measured **local extents on entities that are scaled per
  instance**. Gravity Lab's bodies and Projectiles' balls carry one
  authored collider on a sphere scaled from 0.26× to over 2×, so a single
  factor meant 2 mm of reach on a comet and 10 cm of shielding on a star,
  and the local measurement could see neither. It measures world metres
  now, and `Grabbable.sphereTargetRadius` sizes those two pools per
  instance so reach is constant in the room.
- The hoop's rim colliders shrank without the count growing, leaving
  **11 cm of every 17.6 cm of rim with no collider**. Sixteen now, not
  eight.
- `isImmersiveSpaceOpen` moved from `.onAppear` on a `Group` to
  `.background` on the same `Group` — which is **the same bug**, because a
  background distributes over children exactly like any other modifier.
  It is a sibling inside a `ZStack` now.

**AND FOUR MORE IN THE FIX ITSELF**, found by reviewing the review's
fixes. The pattern is now the entry's real subject:

- The per-instance collider was installed on `slot.entity` — the pool's
  bare CONTAINER — when the input target lives on `slot.payload`, the
  sphere under it. So the fix set an inert collider on an entity nothing
  hit-tests and left the real target at its authored 1.15× at every
  scale. It achieved *nothing*, and the criterion could not see it,
  because a fixed 1.15× rides the 1.15 proportional margin exactly at
  every scale.
- Sixteen rim colliders on the hoop still left a 22 mm hole between
  every pair. The count is derived from the radius now (a 0.034 m sphere
  spans 17° of a 0.23 m ring, so ≥ 22 are needed): twenty-four.
- `sensing = .fine` after the new `stopNow()` was a no-op writing the
  value that was already there, under a comment claiming it fixed
  something. Removed, and what `.fine` actually means when a session is
  deliberately stopped is now written down instead.
- The exhibit target lost the name plate. The obvious repair — union it
  back in — was tried and `testGalleryExhibitTargetsDoNotOverlapEachOther`
  rejected it in one run: the plate carries the module TITLE, which is
  wider than the 0.36 m puck pitch on its own. The plate stays out, and
  the reasoning is at the site so nobody helpfully restores it.

Two soft spots were closed in passing: both press latches are cancelled
in `onDisappear` (a pending press now sticks, since `press` refuses to
overwrite one, so a dropped `onEnded` would let the next gesture promote
a stale anchor), and the collider criterion now REPORTS colliders it
could not measure because their instrument was folded away, instead of
passing them silently — the flat 30 mm allowance is in metres, so at a
world scale of 0.001 it becomes 30 m and checks nothing.

**THE LESSON, stated plainly, because it cost two rounds.** Every defect
above was in code written specifically to fix the defect before it, and
every one of them shipped behind a green suite. Two failure shapes did
the damage, and both are worth recognising on sight: **a test that
models the intended call sequence tests the intention** (the latch
pressed once and promoted many times; the handler presses and promotes
in alternation, which never crosses the threshold), and **a derived
value cannot be checked against what it was derived from** (a box built
from an entity's bounds satisfies a test measuring it against those
bounds, whatever the bounds contain). The answer to the second is a
criterion that asks the question the RULE is about rather than the one
the code already answers — which is why the overlap test earns its
place and caught the name-plate attempt on the first run.

**Not yet done, and deliberately.** The stale-drag watchdog reaches the
two event-id-keyed tables (`PinchLedger`, Magnetism's `grabs`) where a
vanished hand leaves no trace. The `DragGesture`-driven carries in the
hub and Projectiles are cleared on `onDisappear` instead, because those
recognisers do deliver `onEnded`; if a stranded carry is ever seen on
device, they need the same treatment.

**One visible change hides in this pass** and needs a screenshot before
it is trusted: Gravity Lab's clock bank widens from about 0.25 m to
about 0.40 m, because six touch targets 68 mm across do not fit in
0.25 m at any angle. Placement is the thing this project has got wrong
three times with the arithmetic looking fine each time.

## 2026-08-07 — The Time Capsule ships OFF, and the reel turns because tape is coming off it

**Decision:** Owner's call, two parts. (1) `AppSettings.timeCapsule` is
a Settings toggle that defaults to **off**, and it gates the RECORDING
rather than the reel. (2) The reel is animated by the three things that
are actually happening to it: the tape drawn off it, the scrub, and the
spin it still has when it arrives.

**Why off by default.** A default is a claim about what the app IS, and
by default this one is six physics labs where pause means the room
holds still. The capsule is a second and larger idea layered on that —
a machine for interrogating a moment — and someone meeting the app for
the first time should meet the labs. Being a setting also makes the
cost honest: several megabytes per lab and a struct copy every physics
frame is a real price, and a price is a thing a user should be able to
decline.

**It gates recording, not furniture, and that is the whole point.** A
toggle that only hid the reel would have left every model snapshotting
itself sixty to ninety times a second on behalf of a feature switched
off — the expensive half still running, invisibly. So
`TimeCapsuleSettings.isEnabled` is read inside `recordCapsuleFrame`,
which becomes a no-op that also DROPS whatever was already recorded:
a capsule surviving the switch would be a recording kept after the user
said stop. `TimeCapsuleRoundTripTests` asserts both halves, and the
suites now have to switch the feature on the way a user would — which
is the friction that stops the default drifting back silently.

**Why the reel's motion is derived rather than authored.** It would
have been easy to give the reel an idle spin, and it would have been a
lie: nothing is being recorded while the room is paused. Instead it
turns by arc ÷ radius as the tape comes off it — 0.34 m over a 38 mm
spool, so nearly a turn and a half during the draw, and winding it back
in returns it exactly. It turns further as you scrub. And it arrives
still coasting, because the recording stopped at the instant of the
pause and a reel already at rest would be one that had never been
running. Every frame of that is a statement about the recording; none
of it is decoration, which is why only the coast is suppressed under
Reduce Motion and the draw is not.

**Consequences.** `-timeCapsule 1` joins the launch arguments, and
every other Time Capsule argument is inert without it — with the
feature off there is by design nothing to scrub. The tape radius is now
named in two places (`Tools/timereel.py` and `TimeRail`), which is a
duplication accepted knowingly and commented in both: the reel must
turn by the tape it gives up, and one shared number is cheaper than a
mechanism. One test defect worth recording: `simd_quatf.angle` wraps
into [0, π], so an assertion on a rotation larger than a turn failed a
reel that was turning exactly right — rotations are compared as
quaternions now.

## 2026-08-07 — The rail goes back on its reel

**Decision:** Owner's call, the same day the Time Capsule shipped. The
Time Rail no longer unfolds by itself on pause. What a pause puts in
the room is a modelled **reel** — 96 mm, three ports, the recording
wound between its flanges — under a "Time capsule" nameplate. A pinch
draws the rail out of it like tape; a second pinch winds it in. The
tape winds itself back in whenever the instrument leaves, so every
pause opens on the reel.

**Context:** The owner's words were that they did not want the feature
"always visible". The first build made pause mean *a 34 cm rail, a
value plate, a subtitle and three verb plates arrive, in every lab,
every time* — an instrument permanently occupying the room on behalf of
a capability most pauses do not use. That is the panel mistake in a new
costume: not a flat surface this time, but the same failure to make a
capability ask before it takes the room.

**Why a reel and not a lid, a drawer or a button.** A container would
have solved the visibility problem and taught nothing. A reel is not a
box the feature hides in — it IS the feature, stated as an object: the
last thirty seconds are wound on it, and the rail is that tape drawn
out. Nothing has to label what the control does, the draw animation is
the metaphor explaining itself, and — the part that made it the right
answer rather than a nice one — **the reel turns as you scrub.** The
closed object is a readout. That is the same law every other control
here obeys: where the bead sits IS the value.

**Consequences.** `Tools/timereel.py` joins the checked-in Blender
scripts, so the asset is a reviewable diff rather than a binary
somebody once made. The reel is a MOUNT with a spinning child, because
the first build hung the nameplate on the spinning part and scrubbing
a second rolled the words onto their side. A drag is refused until the
tape is fully out, since mid-draw the rail's root is still sliding and
the mapping under a hand would be moving. `-scrubBack` now draws the
tape out as well as scrubbing — the simulator has no finger to pinch
the reel with, and the standing rule is that an argument reaches a
control a hand could also reach; photographing the reel CLOSED needs no
argument at all, because that is what a pause looks like.

**What this costs.** One more pinch before the rail is usable. Accepted
knowingly: the alternative was a permanent instrument, and the reel is
discoverable in the way this app has decided things should be — it is
an object, it wears its name, and it is the only new thing in the room
when you pause.

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
