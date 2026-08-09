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
      system." The bug-class fixes landed, and **the design pass now
      has its review**: `docs/CIRCUITS_DESIGN_REVIEW.md` (2026-08-06)
      — eleven numbered proposals, C1–C11, sized S/M/L, written to be
      reacted to per-number in the headset. No code changed with it;
      the owner picks, then the work is planned.
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
- [ ] Below it, only two things ever appear, and both only while the
      immersive space is CLOSED: **Show in room**, and the **first-run
      hint**. Open the room and the hint leaves the window — it is a
      card in front of the apparatus from then on (2026-08-08). Dismiss
      it in either place; it stays gone on re-entry, and dismissing it
      in the window means the card never appears.
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

## Phase 1 of the 2026-08-07 audit arc — the front door

All of this is new surface, and none of it can be judged from the
simulator. Work it in this order; the first two are the ones that
decide whether the phase was worth doing.

- [ ] **⟳ The ENTER plaque, and the stack it lives in.** No argument
      needed — the gallery is what you see at launch. Each puck's
      terrace now carries a small machined ENTER slab in the module's
      accent, standing forward of the plinth. **What CORRECT looks
      like:** a caption stack under each miniature that reads as one
      thing — name, then (on the exhibit you are facing) a one-line
      promise, then the plaque in front on the terrace. **What to watch
      for:** the three are billboarded and separated in depth as well as
      height, so they can be geometrically clear and still LOOK piled
      up. Then aim at a plaque and pinch: it must open that lab, and
      pinching the miniature above it must still only flash the pad.

- [ ] **The promise line.** Turn your head slowly along the crescent.
      One sentence should fade in under the exhibit you are facing and
      out again as you move on — never two at once, never flickering as
      you sweep past.

- [ ] **The window is not blank.** Look at the hub window with the
      Gallery up. It should show the progress line, the next step and
      the compact catalog. Tapping a row there must still open its lab —
      that is the accessibility path, and it has been unreachable in
      normal use since the gallery started auto-opening.

- [ ] **The way out.** In the same window, "Put the Gallery away" should
      close the immersive space and leave you with your room and the
      window. Then "Enter the Gallery" brings it back.

- [ ] **The bead has six petals now** — home, pause, capture, dim,
      settings, reset — and the row is wider to fit them. `-paletteOpen 1`
      photographs it; on device, open it and **aim at each petal in
      turn**, which is the check the width exists for. `home` returns to
      the gallery from inside a lab; `dim` steps the room off → half →
      full and leaves the ring open so you can tune it against what you
      see.

- [ ] **The room-sensing note.** Hardest to see, because it wants a
      fresh install. On first launch the window should carry one quiet
      line about visionOS asking for your room BEFORE the sheet appears.
      `-roomSensing denied` fakes the refusal: the window should then say
      what is lost and how to turn it back on, not just show a triangle.

- [ ] **The first-run teach is in the room.** Erase the app or use
      `-resetHints 1`, then enter any lab. The module's paragraph should
      hang beside the apparatus — not only in the window, which may be
      behind you. Pinch it to dismiss; it must not come back, and the
      window's copy of it must go at the same time. Check it does not
      overlap the apparatus in the labs with the widest benches
      (Circuits, Gravity Lab).

- [ ] **The podium hint retires itself.** With hints reset, the "Or
      carry a lab to the pad" line should be up. Carry one lab to the
      pad; it should go, and stay gone on the next launch. It must never
      be visible while a lab is already docked.

## Phase 2 — Gravity Lab folds, and the room stands back

**This is the owner's own complaint, so it is a judgement call before it
is a check.** Everything here is `-openModule gravitylab` unless said
otherwise.

- [ ] **⟳⟳ IS IT CALMER?** The plain question, first, before any of the
      detail. Standing objects went from about eighteen to nine: the
      seven-plate bank is two, the six-disc clock is one tab, and two new
      tabs hold what came off. If it does not read as a quieter room,
      say so and the rest of this section does not matter.

- [ ] **The three tabs down the left flank.** Under the two remaining
      layer plates: Analysis, then Vectors. Each should read as a small
      machined tab with its own live summary beneath — "off", or
      "sweep, Lagrange", or "v a F". **The summary is the whole
      argument for folding**: if you cannot tell what is switched on
      without opening the tab, this design has failed and the plates
      should come back out.

- [ ] **The clock tab.** On the right flank where the fan used to be,
      reading "Clock · 5×". Pinch it: the six-disc fan should unfold
      ABOVE the tab, and the number on the tab should track whichever
      disc you pick. Pinch again to fold. **Then check the tab still
      tells you the speed with the fan closed** — that is the readout the
      six discs used to be.

- [ ] **Recession.** Stand back with your hands at your sides: every
      instrument should sit at about 45% — clearly still readable, just
      quiet. Reach toward one and it should come to full within about
      arm's length, and only it, not the whole room. **Watch for
      flicker**: if the hand tracking drops, everything should go to FULL
      brightness rather than fading, and if you see it pulse as you move
      your hands about, that is the bug.

- [ ] **Reduce Motion.** Turn it on in system settings. The recession
      should switch off entirely — full brightness, no fade — and every
      fold should snap rather than ease. Nothing anywhere should freeze
      part-way.

- [ ] **Nothing lost.** Kepler sweep, Lagrange points, velocity,
      acceleration and force must all still work from behind their
      tabs, and the grid and field flow from the two plates that stayed.
      The point of the fold is that nothing was removed.

### VoiceOver can operate the room (2026-08-07)

**This needs a headset with VoiceOver on, and it is the first time any
of it has ever worked.** Before this pass a grep for `systemActions`
returned zero matches across the whole project: every plate, petal,
disc, rail, well and grip was announced, readable, and impossible to
press. With the window panels gone there was no fallback either, so the
app was six rooms of readouts with no controls in them.

- [ ] **A layer plate.** Any lab. Swipe to a plate — it should read its
      name and whether it is showing or hidden — then double-tap.
      The layer must toggle, and **the spoken value must change with
      it.** (It used to read the LAUNCH state of thirty-five toggles for
      the whole session, whatever you did to them.)
- [ ] **A destructive plate still confirms.** `-openModule circuits`,
      find Clear. The FIRST activation must only arm it — the value
      should change to "armed — tap again to confirm" — and the second
      must fire. Routing straight at the verb would hand the one user
      who cannot see the plate light up a single-tap way to wipe a bench.
- [ ] **An unavailable plate refuses.** A plate that is dim because its
      action cannot happen should offer VoiceOver no action at all,
      rather than accepting one and doing nothing.
- [ ] **A summon handle.** `-openModule gravitylab`, swipe to Clock: it
      should read "Clock", value "hidden", and double-tap should unfold
      the fan and change the value to "showing".
- [ ] **The labels are part of their plates.** With VoiceOver OFF, aim a
      pinch at the WORD beside a plate rather than at the plate itself —
      "Spacetime grid", "Field flow". It should flip the layer. The pill
      sits outside the plate and carried no collider, so the word was a
      hole you pinched straight through.

### Phase 3 — physics that was visibly wrong

- [ ] **The double pendulum draws its trail.** `-openModule pendulums`.
      The chaotic rig's lower bob should leave a trace, its readout card
      should show a changing speed rather than `v 0.00 m/s`, and pausing
      should produce a freeze sculpt. None of that existed: `step` wrote
      the double's own state and never wrote the field every readout
      reads. Grab it too — it used to freeze and refuse to follow.

- [ ] **The predicted arc lands where the ball lands.**
      `-openModule kinematics -kinBalls 1`, pick the BASKETBALL (the
      error scales with radius: 12 cm). Fire it at a wall and at the
      floor. The white arc should corner where the ball corners and
      touch down where it touches down — it used to be drawn for a
      point, so it cut 12 cm inside every wall and 12 cm below every
      bounce, compounding with each segment.

- [ ] **⟳ The orbit ring's beads with the primary OFF the origin.**
      `-openModule gravitylab -gravBinary 1` — this is the case the
      whole fix is about and NO automated test reaches it. With twin
      suns the primaries sit at ±0.2 AU. Select a planet, open its orbit
      ring, and watch the two apsis beads as the pair orbits: a bead
      buried inside a body should vanish, and a bead in open space
      should stay visible AND stay pinchable. Before this the two were
      swapped, intermittently, because the occluders were measured in
      one frame and the beads in another.

- [ ] **Electric Fields' card under a magnetic orbit.**
      `-openModule electrostatics -emMagnetic 1 -emTesla 50000`. With no
      charges in the room the card should show `Force qE 0.00 N`, a
      NON-zero `Force qv×B`, and a total that matches. It used to report
      only qE — so a probe visibly circling in front of you reported
      zero force. Then `-emCap 1`: between the plates a strong E must
      not sit beside `0.00 V`.

- [ ] **Deleting an armed circuit part.** `-openModule circuits`. Pinch
      a terminal to arm it, open that part's ring, Delete it, then tap
      any other terminal. No wire should appear. Before, an invisible
      un-pinchable wire was created, ate one of the 36 budget slots, and
      came back after a relaunch.

### The magnet force is measurably the wrong model — and fixing it needs you

**Not a check: a decision, with the measurement already done.**

`MagneticField` treats a magnet as a point dipole for the FORCE, while
the field lines drawn over the top are traced from the pole-pair model
its own header says is exact for a bar. Head-to-tail on the axis, dipole
against pole-pair:

| r / L | dipole error |
|---|---|
| **0.92** — Magnetism's `contactDistance` | **50.3 % low** |
| 1.5 | 21 % |
| 3.0 | 5.5 % |
| 5.0 | 2.0 % |

So the module's most repeated interaction — two magnets snapping
together — is driven by a field reporting half its real value, under
loops computed correctly.

**But the obvious remedy is worse, and this is the useful part.**
`MagneticField.netBarForce` is written and tested — it obeys Newton's
third law exactly and converges on the dipole past r/L ≈ 8. Switching
the dynamics onto it was tried and reverted, because the pole-pair model
puts one bar's north pole and the other's south pole at the SAME POINT
when they are one length apart. At and inside contact it is not merely
inaccurate but pathological: at r/L = 1.0 it reports REPULSION for a
pair that must attract, and at 1.2 it is seven times the dipole value.

So both models are unusable where these magnets meet, in opposite
directions, and the dipole at least keeps the sign right and stays
smooth. A force that is genuinely correct near contact needs the
magnetised VOLUME integrated — physics neither model contains.

- [ ] **Nothing to check here; this is a note.** The magnets behave
      exactly as they did. It is recorded because P1-22 reads like a
      one-line fix and is not, and because the next person to try it
      should find the measurement rather than repeat it.

## Cross-cutting

### Phase 0 of the 2026-08-07 audit arc — mostly invisible, four things that are not

Everything in this pass is mechanical and covered by tests EXCEPT the
five items here, which are gestures or placement and therefore cannot
be. The first is a visible change and wants judging, not just checking.

- [ ] **⟳ Gravity Lab's clock bank is now about 40 cm wide, not 25.**
      `-openModule gravitylab`. Six speeds — −20×, −1×, 1×, 5×, 20×,
      100× — and their touch targets are 68 mm across, so they do not
      fit in the old row at any angle: the end pair used to sit 49 mm
      apart, which is why aiming at 1× could select −1× and run the
      solar system backwards. The span is now derived from the count
      (`FanLayout.spread`), so this widens again if a seventh speed is
      ever added. **What CORRECT looks like:** still one shallow, tidy
      row reading as a single instrument, symmetric about the system,
      not spraying across the orrery, and not colliding with the layers
      bank or the worlds fan when that opens. **Then actually aim at
      each disc in turn and confirm you get the one you looked at** —
      that is the defect, and it is invisible in a screenshot.

- [ ] **⟳⟳ FIRST: can you grab a bob and a ball AT ALL?** This is the
      one to do before anything else. The press-versus-tap fix shipped
      broken for one commit — the latch re-armed on every frame, so the
      threshold was never crossed and neither object could be picked up
      at any speed. Fixed, and `PressLatchTests` now drives the real
      frame sequence rather than the intended one, but the wiring itself
      is headset-only. `-openModule pendulums`: pinch a bob and carry it
      somewhere. `-openModule kinematics -kinBalls 1`: pinch a resting
      ball and carry it. Both must follow the hand, and must not jump to
      your fingertips at the moment they are picked up.

- [ ] **A tap on a pendulum bob no longer stops the room.**
      `-openModule pendulums`. Set the cradle swinging, wait for trails,
      then gaze at one bob and pinch WITHOUT moving your hand. Correct:
      its control ring opens and **the swing carries on** with every
      trail in the room intact. The old behaviour stopped that pendulum
      dead and wiped every trail. Then pinch and actually carry a bob —
      it must still grab, and must not jump to your fingertips at the
      moment it is picked up.

- [ ] **A tap on a ball in flight no longer catches it.**
      `-openModule kinematics -kinBalls 1`. Fire a ball and pinch it
      mid-flight without moving. Correct: nothing happens to the ball —
      it keeps flying, keeps its strobe trail. The old behaviour froze
      it in mid-air permanently. Then pinch and carry one: it must still
      be catchable, and again must not jump to the hand.

- [ ] **Carrying a lab at a normal speed makes it stay put.**
      Open any lab, summon the placement puck, and move the apparatus
      60–80 cm at an unhurried pace — the speed you would actually use
      to put something beside your sofa. Correct: it stays where you
      left it. Before this pass only a drag faster than about 1.1 m/s
      registered as a drag at all; anything slower was read as a tap and
      snapped the lab home the instant you released. The same test on
      the gallery's grab bar in the hub.

- [ ] **Two hands on two different magnets no longer resizes the bench.**
      `-openModule magnetism`. Grab one magnet in each hand and move
      them apart. Correct: two independent carries, and the bench's
      scale is exactly where it started when you let go. The
      suppression existed; it committed the partial swell it was
      suppressing.

- [ ] **A hand that vanishes mid-pinch does not disable two-hand zoom.**
      Any lab. Start a two-hand pinch and then drop one hand out of the
      tracking volume — behind your back, or below the field of view —
      rather than releasing it. Correct: within about half a second the
      rig forgets that pinch, and two-hand zoom works on the next try.
      It used to be dead for the rest of the module session with nothing
      on screen to say why. In Magnetism, the same test with a magnet in
      the vanishing hand: the magnet must be released, not held forever.

- [ ] **Small planets and small balls are still easy to grab.** Their
      targets are now sized per instance so the REACH is constant in the
      room rather than scaling with the object — a comet had dropped to
      about 2 mm of margin. `-openModule gravitylab -gravWorlds 1` and
      pick a preset with a comet or a moon; `-openModule kinematics` and
      fire a table-tennis ball. Both should feel no harder to grab than
      a planet or a basketball. The other half of the same change: a
      big body's target should no longer swallow the apsis bead sitting
      just outside it.

- [ ] **The hoop can be grabbed anywhere on its rim.**
      `-openModule kinematics -kinBalls 1`. The rim carries twenty-eight
      small colliders now rather than eight — the count is derived from
      the tube's SURFACE, not its centreline (a 0.034 m sphere has to
      reach 0.02 m off-axis, which 24 does not quite manage). Try to
      drag the hoop from several different points around the ring,
      including between the compass points, and from a shallow angle
      rather than straight on.

- [ ] **The capacitor's interior is reachable again.** `-openModule
      electrostatics -emCap 1`. Put a charge between the plates and try
      to tap it to open its ring, and to drag it. Both used to fail —
      each plate carried a 52 cm collision sphere, so the two overlapped
      through the whole interior and swallowed every pinch. The plates
      themselves must still be draggable along the field axis.


### The Time Capsule (2026-08-07) — new, and none of it is verifiable from the CLI

**Switch it on first: Settings → Time Capsule → "Record the last 30
seconds". It ships OFF.** Then every lab records its last 30 seconds:
pause and a REEL appears in front of the apparatus with the recording
wound on it; pinch the reel and the rail draws out like tape, its bead
reading "seconds ago".

- [ ] **Off is genuinely off.** Before touching the setting, pause any
      lab. Nothing new should appear — no reel, no rail — and the pause
      should feel exactly as it did before this feature existed. Then
      switch it on, run a lab for a few seconds and pause again: the
      reel should be there. Switch it off while a recording exists and
      the reel should go with it.
- [ ] **The coast-down.** Watch the reel at the moment it arrives. The
      recording stopped when you paused, so it should come in still
      turning and wind down to rest over about a second, not appear
      already stopped. Under Reduce Motion it should arrive at rest —
      but the DRAW must still animate, because that answers a pinch.

- [ ] **The reel is all a pause shows.** In Projectiles, throw a ball,
      let it bounce, then pinch the palette's pause petal. What should
      arrive is one small machined reel under a "Time capsule"
      nameplate — NOT the rail. Judge whether it reads as an object
      worth pinching, and whether at 96 mm it is big enough to hit and
      small enough not to be furniture.
- [ ] **The draw, and the reel turning with it.** Pinch the reel. The
      rail should come out of it to the right, sliding and fading up
      together, with the plates following — AND the reel should spin as
      it gives the tape up, very nearly a turn and a half (it is arc ÷
      radius, computed from the same numbers the model was built with,
      so it should look like a consequence rather than a flourish).
      Pinch again and it should wind back in, returning to exactly
      where it started. Judge the speed: the whole draw is about a third
      of a second, and it should read as tape being pulled, not as a
      panel appearing.
- [ ] **The scrub itself.** With the tape out, drag the bead left: the
      whole room should run backwards — the ball retraces its arc and
      the bounce un-happens — landing on recorded frames, never sliding
      between them.
- [ ] **The reel is a readout.** While scrubbing, watch the reel rather
      than the bead: it should turn as the tape runs out, about 52° a
      second of recording, and its three ports make the rotation
      legible. Check the nameplate stays upright while it does (it
      rolled over onto its side in the first build).
- [ ] **Walk into the frozen instant.** Scrub to mid-flight and walk
      around the ball. The velocity and force arrows should be sculpted
      on it at THAT instant, and the recorded path should hang in the
      air as a tube you can put your head through.
- [ ] **Frame-step a bounce.** Park the bead just before a wall contact
      and tap "Back a frame" / "Ahead a frame" repeatedly. Each tap is
      one physics tick — the ball should visibly cross the wall's
      surface over two or three taps, not jump past it.
- [ ] **Resume from the past.** Scrub back, then tap "Resume here" (or
      the pause petal). The room should run forward again FROM that
      instant and the rail's recorded length should shrink to match —
      the future you rejected is gone, not replayed.
- [ ] **Sculpt, then resume.** While scrubbed, drag a ball somewhere
      else and resume: the run continues from the state you edited.
      Scrub again and the recording re-asserts itself, discarding the
      edit. Both are intended; judge whether the second surprises you.
- [ ] **Scrub with a magnet in your hand.** In Magnetism, hold a magnet,
      pause, and scrub. The held magnet must NOT be dragged out of your
      fingers by the restore — everything else in the room rewinds
      around it.
- [ ] **The LED un-blows.** In Circuits, wire an LED to burn out, then
      scrub back past the failure: it should light again, and blow again
      on resume. Also confirm that quitting while scrubbed and relaunching
      gives you the bench you BUILT, not the one you rewound to.
- [ ] **Gravity Lab's two clocks.** Set the time picker to −1× or 20×,
      let it run, then pause and scrub. The picker sets how time runs;
      the rail asks what already happened. Changing the picker while
      scrubbed should take effect only on resume. Judge whether the two
      ever read as fighting each other.
- [ ] **Capture a scrubbed instant.** With the room frozen in its past,
      tap the notebook petal. The entry should record the physics of the
      instant on screen, not of the live present.
- [ ] **The rail's placement.** The reel stands at chest height in front
      of the apparatus and the rail draws out to its right. Both were
      placed against the simulator's fixed viewport, which is not a
      wearer's head — judge whether the reel lands where you would look
      after pausing, whether the drawn-out rail is comfortably reachable
      from where the reel is, and whether either ever gets between you
      and the physics. (They exist only while paused, so neither should
      obstruct a live grab.)

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
- [ ] **Every lab's first-run hint** appears once and stays dismissed — as a CARD IN THE ROOM, in front of the apparatus, dismissed by touching it anywhere (2026-08-08). Check it is not crossed by the physics; that is the defect it was moved to fix. With the room shut it still appears in the window instead, and dismissing it either way counts.
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
