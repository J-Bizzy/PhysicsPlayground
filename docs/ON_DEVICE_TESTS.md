# On-device test script

**Everything here needs a headset.** Nothing on this list can be
automated, and the reason is worth stating once so nobody wastes an
afternoon rediscovering it:

- `simctl` has **no tap, touch, or drag verb** — it can boot, install,
  launch, screenshot and terminate. That is the whole surface.
- **XCUITest has no API for RealityKit entities.** It drives SwiftUI —
  windows, buttons, pickers, lists — and everything in an immersive
  space is invisible to it. No exhibit, no pad, no magnet, no pinch.

So the automated suites cover three of four layers, and this file is the
fourth:

| Layer | Covered by | Runs where |
|---|---|---|
| Physics & geometry | `PhysicsCoreTests` (379) | `swift test`, no simulator |
| Models, clamps, layout | `PhysicsPlaygroundTests` | simulator |
| Tap *handlers* | `SpatialTapTests`, `SpatialActionBankTests`, `BloomPetalTests`, `MultimeterTests` — call `handleTap` directly | simulator |
| Window chrome | `PhysicsPlaygroundUITests` — real taps | simulator |
| **Spatial gesture, in the room** | **this file** | **headset only** |

Work top to bottom; each item says what CORRECT looks like, because
"seems fine" is how a broken affordance survives a test pass.

**Items marked ⟳ changed on 2026-08-04** in response to the previous
pass, and are the ones worth doing first.

## Deferred — the owner asked to be reminded

Three revisits from the 2026-08-03 pass, deliberately NOT addressed in
the fix pass that followed it. Bring these up when planning the next
working session:

- [ ] **Circuit Workshop, whole-module improvement.** "Okay I want to
      revisit this with you … and we will plan out how to improve this
      system." The bug-class fixes landed; the design pass has not.
- [ ] **Projectiles, whole-module improvement.** "It has the same UI
      flip issue, the wall bouncing is unreliable, and it just seems
      uninspired. we will revisit." The flip is fixed app-wide and a
      ball well was added; **the bounce reliability landed 2026-08-06**
      (three distinct defects: walls fed in world space so bounces went
      wrong by exactly the anchor offset after relocating the lab; a
      graze whose v·n flipped mid-frame skipped its own strike; the
      post-bounce remainder of the frame was discarded, deadening fast
      bounces). The check is below in the module section. The
      INSPIRATION half is still owed.
- [ ] **The capacitor ΔV rail.** "We will revisit this later. please
      remind me about it because I want to improve it." The
      cannot-switch-off bug got a fix (see the module section), and
      **the improvement pass landed 2026-08-06**: a live E = V/d line
      hangs under the rail (it follows a PLATE drag as well as the
      bead — pull a plate and watch E fall while ΔV holds), writes
      snap to 500 V so the bead lands on honest values, and VoiceOver
      speaks both quantities. Judge in the room: `-emCap 1
      -emVolts 30000`, then drag a plate and watch the E line follow.

---

## The home

- [ Y] **The gallery arrives, doesn't cut.** Launch. The whole room
      should fade up over about a fifth of a second — terraces, signs
      and exhibits together, none arriving first.
- [ Y] **Both door signs read from the doorway**, at a glance, without
      leaning: `ELECTRICITY & MAGNETISM` in green, `MECHANICS & ENERGY`
      in bronze.
- [ ] ⟳ **The signs hold still.** The kinetic bodies — the electron's
      lap, the bouncing ball — are REMOVED at the owner's direction
      after two redesigns failed to convince ("remove this for now, can
      revisit later"). What remains is signage: the flush lockup, and
      the rule's slow shimmer, parked entirely under Reduce Motion.
      Nothing should orbit, bounce, or trail anywhere near either sign.
- [ ] ⟳ **Look at an exhibit.** It lifts off its puck, grows, and its
      halo lights. Look away: it settles back. **There is no panel any
      more** — the owner cut the floating card; the gaze answer is the
      exhibit itself, and the ONLY way into a lab is carrying it to the
      pad. Check nothing card-shaped appears anywhere while focusing.
- [ ] ⟳ **Every exhibit's name is ALWAYS legible** — no fading in on
      gaze. Sweep the room: six names readable at a glance, focused or
      not.
- [ ] ⟳ **The two terraces are LEVEL.** Their slab tops share one
      height now — the staggered "architecture" read as uneven. The
      slight depth difference between them stays.
- [ ] **Drag an exhibit to the pad.** It should follow your hand 1:1
      — no lurching toward the hand — the pad glows as you approach,
      the exhibit seats itself, and a `Load …` button appears above it.
      The faint white ring that used to circle each exhibit is gone;
      only the accent progress arc remains.
- [ ] **The pad reads as floating, not as broken.** A plate at chest
      height with a ring of light hanging below it: standing in a real
      room, does it look suspended on purpose? If the ring is invisible
      against your floor, say so.
- [ ] **The Load button hangs over the LAB, not over the room**, and
      still reads as that exhibit's button. Check the tall exhibits —
      Pendulums, Circuit Workshop.
- [ ] ⟳ **Gaze at the Load button.** The default hover was invisible on
      device; the plaque now swells and highlights explicitly under the
      gaze. If looking at it still does nothing visible, the pinch has
      no aiming feedback and that is a real failure.
- [ ] **The pad hint is legible** from where you naturally stand.
- [ ] **Press Load.** The lab opens.
- [ ] ⟳ **THE GALLERY GRAB BAR** — new, replacing the Settings sliders
      that duplicated the gallery:
  - [ ] A slim glass bar hangs under the pad, like the bar under a
        native window. It brightens under the gaze.
  - [ ] Drag it: the WHOLE gallery comes — terraces, signs, wordmark,
        pad — smoothly, with no second copy left behind and no rebuild
        stutter.
  - [ ] While the gallery is moved, exhibit focus, the exhibit carry
        and the pad all still work exactly as before.
  - [ ] Tap the bar (a press that doesn't move): the gallery glides
        home and swings round to face you.
  - [ ] Quit and relaunch: the gallery opens EXACTLY where you left it.
- [ ] **The utility bar:** ⚙ Settings, 📖 Lab Notebook, ℹ About. All
      three open as utility panels in front of you, centred in view and
      clear of the pad.
- [ ] **About fits its window.** No clipped line, no cut-off
      description.
- [ ] ⟳ **Settings has no "Gallery" section at all** — no distance or
      height slider, no Recenter button. Moving the gallery is the
      bar's job now.

## Circuit Workshop

**The whole-module improvement pass is deferred** (see the top of this
file). What follows is the standing script.

- [ ] **The loop is live on arrival.** Pinch the switch lever: the bulb
      goes out, the electron beads stop.
- [ ] **Pull a part out of a rack.** Eleven parts stand free on the two
      flanks, above the furniture row. The part must be born AT YOUR
      FINGERTIPS — not at the rack, then flown to your hand — and
      dropping it with copper ends near another part connects them
      automatically.
- [ ] **Both racks are fully in frame** from where you naturally
      stand, with every name readable against a real field of view.
- [ ] **Fill the bench to sixteen parts, then pull a twelfth kind.**
      The source must FADE — the refusal that says nothing came out of
      here.
- [ ] **Pinch two terminals** across a distance: a wire joins them.
- [ ] **Tap a part** → its control ring unfolds. Tap it again → it
      must **fold with the same animation, in place**.
      ⟳ And the petals must no longer FLIP: the tap acknowledgement was
      tumbling every petal 90° app-wide; now it is a clean swell that
      keeps the petal's facing. Check here and on every other ring.
- [ ] **Pull the value bead** on a bulb. The rail hangs UNDER the part.
      Check: the bead is visible across its whole travel, the number
      sits below the rail, and the petals are still overhead.
- [ ] **Pull a bead with your hand drifting up and down.** The value
      must not wander — the drag is a projection onto the rail.
- [ ] **Two-handed pinch the bench**: it zooms — but see the
      cross-cutting same-object rule below: both hands on the bench (or
      one part) resize; one part in each hand must NOT.

### The meter

- [ ] ⟳ **The multimeter stands to the RIGHT of the bench**, mirroring
      the layers bank on the left — the two swapped flanks on
      2026-08-04 so the buttons sit on the left in every module. Dark
      casing, dark face, its name above it.
- [ ] **Tap it: the face lights** and reads "tap two terminals" — not a
      confident 0.00 V.
- [ ] Tap two terminals: **the answer appears ON THE METER**, not only in
      the window. Same number the panel prints.
- [ ] **Arming it must not also probe whatever is behind it.** Tap it
      several times and confirm no stray terminal gets selected.
- [ ] Tap it again to disarm: face goes dark, reading clears, and
      re-arming starts from nothing probed.
- [ ] **Place a probe, then WALK.** Set the red probe on a terminal,
      then step round the bench and turn your head. **The case must
      turn to face you and the probe must not move at all** — the lead
      swings, the tip stays on the terminal, the reading holds.
- [ ] **The holstered probe still hangs off the meter.** With a probe
      untouched, turn the meter and confirm it swings round with the
      case rather than being left behind in mid-air.
- [ ] **Pick the meter up with a probe placed.** The probe must STAY on
      its terminal while the case travels, with the lead stretching
      between them. Check the lead does not visibly pass through the
      bench or a part on the way.
- [ ] **Zoom the bench to 8×.** Neither the meter nor either bank should
      grow — they are instruments in the room, not parts on the bench.
- [ ] **Reset from Electron View.** The bench must come back at normal
      size with only Electron flow lit.
- [ ] **Nothing but the bench is in the room.** No coil, no cable, no
      second apparatus — Circuit Workshop stands alone.

## Magnetism

- [ ] **Nothing but the magnets is in the room.** Bar magnets and the
      hand compass — no coil, no cable, and ⟳ **no compass grid**: the
      245-needle lattice came out with its bank plate. The bank is four
      plates now.
- [ ] Carry a magnet toward another: they pull head-to-tail, push
      N-to-N, and swing to align.
- [ ] **Two attracting magnets COME TO REST.** They should glide
      together, slow as they close, and stop dead, touching.
- [ ] ⟳ **The field lines fill the ROOM.** The loops used to stop at a
      ~0.6 m box; the tracing bounds are metres wide now. Stand inside
      the field: loops should pass around and behind you, and nothing
      should read as a display case.
  - [ ] Loops leave the **poles** — the ends of the bar — not its
        flanks.
  - [ ] The near-field shape follows the BAR, not a point.
  - [ ] Lines bunch at the poles and thin at the equator.
  - [ ] ⟳ **Pull the strength bead and the loop COUNT changes** — a
        weak magnet draws visibly fewer loops, a strong one visibly
        more. This did nothing at all before (fixed budget of 26).
- [ ] The hand-held compass needle points along the local field as you
      walk it around a magnet. ⟳ **Its poles now wear N and S letters**
      — check both are legible through the glass, from either side.
- [ ] ⟳ **Delete down to an empty room.** Tap the last magnet's Delete
      petal: it must actually delete (a guard used to silently refuse),
      with no flip on the petal, and the well must hand back a fresh
      magnet afterwards.
- [ ] ⟳ **One magnet in each hand — for real this time.** The previous
      pass could only STOP the accidental resize; the second grab never
      existed, because SwiftUI runs one DragGesture instance and the
      second hand's pinch was never delivered to it. Magnetism's object
      grabs now run on raw spatial events, one session per pinch:
  - [ ] Grab a magnet in each hand: BOTH follow their hands, the
        physics fights neither, and nothing resizes.
  - [ ] Bring them together and let ONE go: it snaps toward the one
        still held, which stays pinned to your hand.
  - [ ] The compass in one hand, a magnet in the other — walk the
        needle around the bar you are carrying.
  - [ ] Both hands on the SAME magnet: the two-hand resize still works.
  - [ ] One hand pulling a NEW magnet from the well while the other
        holds an existing one: both behave.

### The switch bank

- [ ] ⟳ **Visible without hunting**, off your LEFT shoulder now — every
      module's switch bank stands on the left as of 2026-08-04 — at
      about the same glance as the magnets themselves. Four plates:
      Magnets move, Field lines, Hand compass, Earth's field. Check it
      does not crowd the Add-magnet well, which shares that flank lower
      down.
- [ ] Each label sits BESIDE its plate, never across it.
- [ ] **It does not grow when you zoom.**
- [ ] **"Magnets move" is the physics switch.** Bring two magnets
      close, switch it off: they must stop dead and hold. Switch it on:
      they resume closing.
- [ ] The other plates only change what is DRAWN — hiding the field
      lines must not nudge a magnet.
- [ ] **Reset relights the bank's defaults**, and the magnets come back
      free.

## Electric Fields

Every control here is an object in the room, so **this section is the
only place most of them can be tested at all.**

- [ ] ⟳ **The bank is FOUR plates now** — Field lines, Free charges,
      Capacitor, Uniform B. The flux meter, its "Open disc" plate and
      the four-disc particle bank are all gone at the owner's direction.
      Nothing in the room should reference them.
- [ ] **Flick each plate.** Each apparatus should ARRIVE, and the ones
      that carry an instrument should bring it: Capacitor puts a ΔV
      rail on top of the plates, Uniform B puts a strength rail under
      the bank.
- [ ] **Pull each of the four wells.** The new charge or probe is IN
      YOUR HAND and STAYS there all the way in.
- [ ] ⟳ **THERE ARE NO WALLS.** Drag a charge three metres across your
      real room: it goes exactly where your hand goes, stopped only by
      the floor. Same for the capacitor — carry it anywhere. If
      anything invisible stops a drag mid-air, that is the removed bug
      returned.
- [ ] ⟳ **And no black shadows.** The room-shaped occlusion mesh is
      gone: no dark shapes moulded to your furniture, and no UI cut off
      behind them. (Field lines still stop at your real walls — that is
      the room clip, kept on purpose.)
- [ ] **Pull the test charge out with Uniform B on and throw it
      sideways.** It must curve into a circle and draw one — a fading
      trail that visibly CLOSES on its own tail. ⟳ A + probe and a −
      probe (the two test wells) wind opposite ways.
  - [ ] Grab the probe again mid-flight: the trail clears.
- [ ] **Drag each rail's bead.** The number follows your hand, the fill
      grows behind the bead, half way along the rail is half way through
      the range, and dragging off the end pins rather than wraps.
- [ ] **Drag along a rail with your hand drifting up and down.** The
      value must not wander with the drift.
- [ ] ⟳ **Switch the Capacitor plate OFF while dragging its ΔV bead**
      (two hands: left on the bank, right on the rail). This was
      impossible on device — the second hand's pinch never reached the
      plate. A raw-pinch path now routes a second-hand tap to the bank:
      the plate must toggle, the rail vanishes, the voltage stops
      changing, and your dragging hand is released. Also check a
      NORMAL one-handed plate tap still toggles exactly once.
- [ ] **Carry the capacitor low, then high.** Its rail stays on top of
      the plates the whole way.
- [ ] **Pinch a charge that is between the capacitor plates.** It must
      be grabbable through the plates' 26 cm collision spheres.
- [ ] Drag a charge: the field lines re-trace and follow, sticking to
      your hand rather than lagging visibly.
- [ ] Tap a charge → ring; pull the strength bead → the sphere grows
      and the field answers live. The bead's rail is under the charge.
- [ ] **Tap the probe → its own ring**, with its charge bead.
- [ ] **Two-hand pinch to 4×.** The field grows; the bank and the wells
      do NOT, and stay reachable. And per the same-object rule: a
      charge in each hand moves two charges, resizes nothing.

## Projectiles — the one that is 1:1 with your room

**The whole-module improvement pass is deferred** (see the top of this
file). The new well and the standing script:

- [ ] **THE BOUNCE IS RELIABLE NOW (2026-08-06) — beat on it.** Ten
      hard overhand throws at a real wall: ten bounces AT the wall,
      zero balls through it or frozen against it (fast bounces used to
      die at contact because the frame's remainder was discarded).
- [ ] **Throw AFTER relocating the lab with the anchor.** This is the
      exact defect: the walls were fed in world space while the lab
      rendered offset, so after a move every bounce happened a step
      away from the real wall. Move the lab a metre, throw at every
      wall, and confirm contact visibly AT the surface. Catching a
      ball also had the offset — catch one after moving the lab too.

- [ ] ⟳ **THE BALL WELL** — new. On the instrument wall, under the
      switch bank: reach in and pull a ball out.
  - [ ] The ball is born at your fingertips and rides your hand.
  - [ ] Let go WITHOUT moving: it hangs in the air, inert, exactly
        where you left it.
  - [ ] Throw it: it flies with your hand's velocity, bounces off your
        real walls, and behaves exactly like a launcher ball.
  - [ ] It wears whatever kind the ball fan has picked — pull one out
        as a cannonball and feel the difference.
- [ ] **Throw a ball at a real wall.** It must bounce where the wall
      actually is. Any offset means the display has been translated,
      which is forbidden for this bench.
- [ ] **Catch a ball out of the air.** Device-only; inert in the
      simulator.
- [ ] Drag the launcher anywhere; pinch its bead to aim; the predicted
      arc updates as you pull.
- [ ] The ball fan opens off the launcher's Balls petal, and choosing a
      ball changes the flight.
- [ ] **Two-handed pinch does NOTHING here.** Projectiles is
      permanently excluded from scaling.
- [ ] **The balls read as crafted, not matte** — check a ball in flight
      and one at rest against passthrough, and that the orange aim bead
      still reads as the LIT one of the pair.

### The instrument wall

- [ ] **Fire a dozen shots, sweep the launcher around, throw by hand.**
      Nothing should ever hit an instrument or pass through one —
      including the new ball well.
- [ ] **They do not ride the launcher.** Carry it across the room: the
      instruments stay where they are.
- [ ] **Four worlds, not three.** Zero-g is on this bank. Tap it: the
      shot must fly **dead straight**, no arc at all.
- [ ] Tap Moon, then Jupiter: the arc stretches, then collapses. The
      matching disc lights each time, and drifting the g rail off a
      world darkens it.
- [ ] **The wind rail only exists in air.** With Air resistance off there
      should be no wind rail at all. Switch air on and it appears; set a
      wind and the flight visibly bends.
  - [ ] **Start dragging the wind bead, and while still dragging, have
        the air switched off.** The rail must go dead, not keep writing.
- [ ] **Reset makes the room real again.** Switch Walls bounce off, press
      Reset: walls must come back on with the plate lit.

## Pendulums

- [ ] Grab a bob and throw it sideways → a true 3-D orbit, not a plane.
- [ ] ⟳ **A pendulum pulled from the well hangs STILL** — plumb, at
      rest, until your hand swings it. It used to be born mid-swing.
      (The Newton's cradle cold-open keeps its drawn-back first ball;
      that is the cradle's job, not the well's.)
- [ ] ⟳ **The cable cannot stretch.** Grab a bob and pull outward: the
      bob stays exactly one cable-length from the pivot, steering round
      the sphere under your hand. Only the length bead changes L.
- [ ] **Pull a bob's length bead.** The pendulum holds still while the
      bead is held, the cable pays out, the period tag climbs as √L,
      and letting go returns the swing without throwing it.
  - [ ] Then grab a bob normally. It must be a bob grab, not a length
        edit.
- [ ] **Pull a pendulum out of the spawn well; it hangs where you let
      go.**
  - [ ] Pull one out when the lab is already full: the well should go
        **dark and NOT pop**.
- [ ] ⟳ **There is no Foucault rig.** The feature came out whole at the
      owner's direction: no "Earth turns" plate, no globe, no spin
      rail, no floor markers, anywhere. The bank is FOUR plates:
      Velocity, Acceleration, Force, Air resistance.

### The switch bank

- [ ] **Can you SEE the bank without hunting?** Off your left shoulder,
      at the pivot plane's depth, in the ~14° band.
- [ ] **Nothing is inside the swing.** Let a bob swing wide, and pull one
      out to a 1.6 m cable. No instrument should be swept through.
- [ ] **The four-plate bank.** Each plate lights when its layer is on.
  - [ ] Every label sits BESIDE its plate, never across it.
  - [ ] Switch Air resistance off and the swing stops decaying — the
        one plate on this bank that changes the physics rather than
        the picture.
- [ ] **Reset returns all four plates to their defaults.**

## Gravity Lab

### The orbit ring

- [ ] **Tap a planet.** Two things must happen at once: its **control
      ring** unfolds (mass bead, delete petal) AND its **orbit ring**
      appears — a conic drawn around the Sun, passing through the planet,
      with a bead at each end.
- [ ] **Pull the far bead straight out.** The orbit stretches into an
      ellipse; the near end stays put.
- [ ] **Pull a bead sideways.** The whole ellipse swings about the Sun
      and the other bead sweeps round to stay opposite.
- [ ] **Pull a bead up, out of the ecliptic.** The orbital plane tilts
      with it.
- [ ] **Circle a bead** — take it round a closed loop and back. The
      orbital plane should come back ROLLED, not where it started.
- [ ] **Drag the near bead outward past the far one.** The labels swap
      and **nothing may jump.**
- [ ] **Let go, and watch.** The planet stays on the orbit you drew.
      Over simulated centuries the beads should creep slowly round the
      Sun: real Newtonian precession, not drift.
- [ ] **Watch the ring against the trail.** They should visibly
      disagree — that gap is Jupiter.
- [ ] **A bead behind its own planet is not grabbable.**
- [ ] **Saturn outward: the ring draws, and has no beads.** Zoom out
      with both hands and Jupiter's should come into range.
- [ ] **Press Twin suns: the ring goes out.**
- [ ] **Grab a bead at 1× and again at 9×.** It must be the same size
      in the room both times, and pinchable at both.

### The room-scale walk-through

- [ ] **Two-hand pinch to 9×:**
  - [ ] The Sun lights the OUTER planets.
  - [ ] Name labels and every callout hold their size.
  - [ ] **The spawn well stays where it was and stays the size it was.**
  - [ ] The field-flow particles fill the space around you.
  - [ ] The spacetime grid switches itself off past ~2.5×.
  - [ ] The dimming shell is outside the orrery, not cutting through it.
- [ ] **A scale readout appears beside the clock** once you are off 1×.
- [ ] **Press Reset: the view returns to 1× and untwisted.**

### The panel emptied

- [ ] **The switch bank on your left**, seven plates: spacetime grid,
      Kepler sweep, field flow, velocity, acceleration, force,
      Lagrange points.
- [ ] **The G rail under the bank.** Drag its bead: orbits speed up and
      slow down live.
- [ ] **Tap the SUN.** It gets a mass bead of its own — in solar
      masses — and no delete petal.
- [ ] **The panel holds no slider, picker or toggle.**

### The three doors

- [ ] **Reverse time.** Perturb an orbit, run it backwards, and it
      should un-perturb. Rewinding past a MERGE must not un-merge.
- [ ] **Lagrange points.** Select Jupiter, switch the layer on: five
      markers appear. L4 and L5 form equilateral triangles.
  - [ ] Drop a world on L4: it stays. Drop one on L1: it slides off
        within days.
  - [ ] The markers must NOT jump to the new body.
- [ ] **The body budget is 16.** Check the well goes dark rather than
      popping when it refuses.
- [ ] **Trails no longer hitch** when several bodies' trails rebuild at
      once.

### Still true from before

- [ ] Crown opens toward blackness (`.progressive` immersion).
- [ ] Grab a planet: it freezes and shows the orbit it would take if
      released now; release applies your hand's velocity.
- [ ] Pull a world from the well and let go WITHOUT moving your hand: it
      holds a circular orbit.
- [ ] The clock bank changes time scale and reads back which is on.

## The window is a title bar

- [ ] The window shows a title bar and nothing else — no cards, no
      dropdowns, no scroll.
- [ ] Below it, only two things ever appear: **Show in room** when the
      immersive space is closed, and the **first-run hint** until you
      dismiss it. Dismiss the hint; it stays gone on re-entry.
- [ ] The bar does not truncate the longest name. **Circuit Workshop**
      at default and at the largest accessibility text size.
- [ ] **Key** opens the legend as a popover and it closes on a tap
      outside. Every module's legend is present and matches what is
      drawn — ⟳ including that Magnetism's no longer mentions a compass
      grid and Electric Fields' no longer mentions the flux meter or
      the electron.
- [ ] **Place the lab** shows the cross-hair. Drag it — the whole
      apparatus follows and the instruments follow WITH it. **Tap** the
      cross-hair and the lab snaps home.
- [ ] Reset still confirms, and after a reset nothing is left armed.

### The standing verbs (`SpatialActionBank`)

- [ ] **Projectiles — Clear**, the launcher's third bloom petal. With
      balls in the air: tap once — it must ARM (glyph swaps to a
      checkmark), not fire. Tap again to clear. Arm it and walk away
      five seconds: it disarms itself. With NO balls it is dim, and a
      tap falls THROUGH.
- [ ] **Electric Fields — Clear all**, above the well column. Dim when
      there are no charges, and a tap on it while dim must fall through.
- [ ] **Circuit Workshop — Clear bench**, on the bench's far left flank.
- [ ] **Gravity Lab — Twin suns** and **Worlds**, below the clock bank.

**The confirmation, on both Clear plates that have one:**

- [ ] First tap ARMS: the lamp lights and the nameplate becomes
      "Tap again". It does not clear.
- [ ] Wait ~5 seconds without touching it — it disarms itself.
- [ ] Arm it, then Reset from the title bar. **Nothing may still be
      armed.**
- [ ] Arm the Circuits plate, force-quit, relaunch: the bench is still
      there.

### The worlds fan — ten discs, the widest in the app

- [ ] Tap **Worlds** in Gravity Lab. The fan opens ABOVE the system.
- [ ] All ten labels are readable and none overlaps its neighbour.
- [ ] Tapping a disc adds that world and folds the fan.

### The readouts that came out of the dropdowns

- [ ] **Pendulums** — tap a bob; the card appears above it with L, T, θ,
      v. Grab that same bob: the card must not steal the grab.
- [ ] **Gravity Lab** — tap a planet; its elements and energies appear.
      Pinch to 9×: **the card must not change size.**
- [ ] **Circuit Workshop** — tap a part; volts, amps and watts appear.
      Electron View: the card must not grow. Short a battery and
      confirm the red "short circuit" warning.
- [ ] **Electric Fields** — the standing card on the left carries the
      probe's numbers, the capacitor and B lines. **Switch on Uniform B
      and read the 50 kT disclosure** — it must be legible with the
      field lines drawn over it.

### The room, when it cannot be sensed

- [ ] Deny world sensing (Settings › Privacy & Security › World Sensing,
      then relaunch). A **warning triangle** appears in every module's
      title bar; its popover names Settings and says what is lost.
- [ ] Grant it again — the triangle goes.

### The experiment steps

- [ ] On the home screen, a lab's card shows the next experiment's title
      AND its step. Follow one to the end in the room — every control it
      names must exist and be where it says. ⟳ Electric Fields' third
      experiment is the cyclotron circle now, not the Gauss bubble.

## Cross-cutting

- [ ] **The room tone, fourth recipe (2026-08-05).** Switch "Lab room
      tone" on and stand in any module for two minutes. It should read
      as a planetarium after closing — suspended and floating (no
      major-third sweetness anywhere), with a far-off bell glint maybe
      once a minute. If a glint repeats often enough to be awaited, or
      any voice draws attention to itself, the amplitudes in
      `synthesizeAmbient` are the dials (and a new recipe needs a NEW
      cached filename — currently `ambient-lab-4.wav`).
- [ ] **Studio Mode's new night (2026-08-05).** Toggle the moon-stars
      button in any module. The sky should carry a faint galactic band
      arcing overhead — one continuous river, never discrete dots — a
      few halo stars, and stars in two colour temperatures. The floor
      has a champagne-lit centre pool; the stage rings are champagne
      within, cool blue far out, each over a soft glow. Judge that the
      band and pool stay BENEATH the physics: this is a venue, and a
      venue that competes with the exhibits has failed.
- [ ] **Grounding shadows under the floating controls (2026-08-05,
      shipped as its own commit for easy revert).** Bank plates, picker
      discs, Bloom petals and grips, and the wells' preview models now
      cast the same contact shadow every grabbable already did. Judge
      in a BRIGHT room and a DIM one: the intent is "present in the
      room, not pasted on" — if a plate hanging in mid-air instead
      reads as detached or the shadows read as dirt on the floor,
      revert the commit (`git log --oneline -- 
      PhysicsPlayground/DesignSystem/SpatialLayerBank.swift` finds it).
- [ ] **The grab answers in sound now too (2026-08-06, its own commit
      for easy revert).** Grab any body: a short bright tick with the
      pulse. Set it down: a lower, softer answer. Close a control ring
      (tap the object again, or tap empty space): the same soft tick —
      the unfold pops, so the fold answering was the missing half.
      Judge three things: the ticks stay QUIET (acknowledgement, not
      percussion); a Projectiles THROW does not stack the release tick
      and the whoosh unpleasantly; and master volume at zero silences
      every one of them.
- [ ] **The pickup pulse (2026-08-05, its own commit for easy
      revert).** Grab a charge, a circuit part, a bob, a ball, a
      planet: a soft white glow blooms around it and dies in a quarter
      second — light, not a scale pop. One flash per grab, never a
      strobe while carrying. Magnetism deliberately has none yet (its
      renderer has no grab signal; the magnets glide under a mobility
      law), and the hoops and launcher wait on this verdict. Under
      Reduce Motion there must be NO flash at all. If it reads as
      lag or flicker rather than acknowledgement, revert the commit.
- [ ] **State changes FADE now (2026-08-05).** Select a magnet, a
      charge, a circuit part: the halo arrives over ~0.15 s instead of
      popping. Flip a bank plate: the lamp cross-fades. Toggle the
      vector layers in Pendulums and Gravity Lab: arrows fade in and
      out. With the system Reduce Motion on, ALL of these must snap —
      the fade honours the switch by disappearing.
- [ ] ⟳ **Two hands, two objects — where each module stands.**
      MAGNETISM has the full thing: an object in each hand, both
      moving, on the spatial-event grab (its own section above). The
      other three scaling modules (Circuits, Electric Fields, Gravity
      Lab) still have only the SUPPRESSION half: two hands on two
      objects must not resize, but the second object will not move —
      its grab needs the same spatial-event migration, which is queued
      behind the owner confirming Magnetism's feel on device. Both
      hands on ONE object (or empty space) resizes everywhere.
- [ ] ⟳ **The petal flip is DEAD everywhere.** Tap petals across all
      the modules: a quick swell, facing held, never a tumble.
- [ ] ⟳ **No invisible walls anywhere.** Carry objects to the far side
      of your real room in every module that has them.
- [ ] ⟳ **Every module's switch bank is on your LEFT** (2026-08-04).
      Walk all six rooms: the layer plates are always off the left
      shoulder, so the hand that learns one module has learned them
      all. Magnetism and Circuit Workshop are the two that moved.
- [ ] **Every rail in the app hangs under the thing it adjusts.**
- [ ] **Every ring folds in place.**
- [ ] **System Reduce Motion** (Settings ▸ Accessibility): the hub's
      idle life stills, and the door signs PARK at a composed rest pose
      — the electron at its track's side, the ball resting on the rule.
- [ ] **Every lab's first-run hint** appears once and stays dismissed.
- [ ] **The notebook** captures a moment from each lab with sane
      numbers and units.
- [ ] **Leave and re-enter a lab**: its state survives.
- [ ] **Leave and re-enter the hub repeatedly**: no slowdown.

---

## Still unseen from the 2026-08-03 review pass

Carried forward: these were changed then and have not yet been judged
in a room.

### The one that is not finished

- [ ] **`-magInertia 1` — magnets with real mass and rotational inertia.**
      Run the two benches back to back: launch Magnetism normally, then
      again with the argument.
  - [ ] **Set a magnet swinging in another's field and watch one needle.**
        With inertia it must swing PAST alignment and ring back before
        settling. Without it, it slides to alignment and stops.
  - [ ] **Then let two magnets touch, and keep watching.** This is the
        known defect: a touching pair does not come to rest. **Judge how
        bad it looks** — that decides whether it is worth fixing or
        whether the glide simply wins. DECISIONS.md 2026-08-03 has the
        analysis.
  - [ ] Reset returns to whichever bench the launch argument asked for.

### The hub

- [ ] **The gyroscope bead and the modelled miniatures** at real
      passthrough contrast, in a bright room and a dim one.
- [ ] **The wordmark.** If the machined plaque reads as faint against a
      real wall too, that is a real finding about the one piece of type
      every visitor sees first.

### Accessibility

- [ ] **VoiceOver over a `Callout`.** Every tethered live number — the
      compass µT, catch speed, sweep area, prediction countdown —
      carries a NAME and a VALUE. Check both are spoken, and that the
      value tracks as it changes.
- [ ] **Reduce Motion inside a lab**, not just in the hub. The palette
      bead must stop breathing. It must still UNFOLD when pinched.

### The catalog, and the numbers

- [ ] **Open the flat catalog.** Above the two domains there is a tally
      and ONE next step. Complete that experiment and check the line
      moves on to another.
- [ ] **Capture a notebook entry in three different labs and compare
      them.** Every row should read in one voice.
- [ ] **Gravity Lab at 100× clock, watching the data card.** ν reads to
      a tenth of a degree and the card should feel steadier, not
      coarser.

### Leaks — the only test for these is patience

- [ ] **Enter and leave eight or ten labs in a row, then use one.**
      Nothing should feel heavier at the tenth lab than at the first.
- [ ] **Complete an experiment, then leave that lab and enter another.**
      No chime should fire for the lab you left.
