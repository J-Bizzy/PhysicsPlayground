# On-device test script

**Everything here needs a headset.** Nothing on this list can be
automated, and the reason is worth stating once so nobody wastes an
afternoon rediscovering it:

- `simctl` has **no tap, touch, or drag verb** — it can boot, install,
  launch, screenshot and terminate. That is the whole surface.
- **XCUITest has no API for RealityKit entities.** It drives SwiftUI —
  windows, buttons, pickers, lists — and everything in an immersive
  space is invisible to it. No exhibit, no podium, no magnet, no pinch.

So the automated suites cover three of four layers, and this file is the
fourth:

| Layer | Covered by | Runs where |
|---|---|---|
| Physics & geometry | `PhysicsCoreTests` (319) | `swift test`, no simulator |
| Models, clamps, layout | `PhysicsPlaygroundTests` | simulator |
| Tap *handlers* | `StationTapTests` — calls `handleTap` directly | simulator |
| Window chrome | `PhysicsPlaygroundUITests` — real taps | simulator |
| **Spatial gesture, in the room** | **this file** | **headset only** |

Work top to bottom; each item says what CORRECT looks like, because
"seems fine" is how a broken affordance survives a test pass.

**Items marked ⟳ changed on 2026-07-31** in response to the previous
pass, and are the ones worth doing first.

---

## The home

- [ ] **The gallery arrives, doesn't cut.** Launch. The whole room
      should fade up over about a fifth of a second — terraces, signs
      and exhibits together, none arriving first.
- [ ] **Both door signs read from the doorway**, at a glance, without
      leaning: `ELECTRICITY & MAGNETISM` in green, `MECHANICS & ENERGY`
      in bronze.
- [ ] ⟳ **The signs move, and the letters are SOLID.** Both bodies now
      fly in lanes measured off the finished type rather than at a
      hardcoded depth — the previous pass caught the Mechanics ball
      flying *inside* a glyph, which is what a 20 mm offset does against
      55 mm of plaque extrusion.
  - [ ] An electron laps the E&M sign. It must pass IN FRONT across the
        bottom and BEHIND across the top, and the "behind" half must
        actually be **hidden by letters** — the ellipse now crosses the
        lockup instead of clearing it, so the occlusion has something to
        occlude with.
  - [ ] The ball lobs across the Mechanics sign and **never intersects a
        letter**. It launches and lands on the ends of the rule, which
        now overhangs the type — so both ends of every throw are clear
        of the word rather than under it.
- [ ] **Look at an exhibit.** It lifts off its puck, grows, names
      itself, and its focus panel appears. Look away: it settles back.
- [ ] ⟳ **The focus panel is IN FRONT of the door sign.** It used to be
      pushed a step further out and landed behind the sign — which is
      why the item below failed. The panel should occlude the sign while
      focus holds, and nothing should occlude the panel.
- [ ] **Drag an exhibit to the podium.** It should follow your hand 1:1
      — no lurching toward the hand — the podium glows as you approach,
      the exhibit seats itself, and a `Load …` button appears above it.
- [ ] **The podium hint is legible** from where you naturally stand.
- [ ] **Press Load.** The lab opens.
- [ ] ⟳ **The other way in:** look at an exhibit, press the focus
      panel's Load button without touching the podium. **This is the
      guaranteed path and it was broken** — the button was behind a
      sign. It is now full panel width as well as unobstructed.
- [ ] ⟳ **The utility bar:** ⚙ Settings, 📖 Lab Notebook, ℹ About. All
      three now open as **utility panels in front of you**, not wherever
      the invisible main window was last parked. Each should arrive
      centred in view and clear of the podium.
- [ ] ⟳ **About fits its window.** No clipped line, no cut-off
      description.
- [ ] ⟳ **Settings has no "Home title" and no "Reduce motion".** The
      plaque is the app's voice, full stop; motion still stills for the
      SYSTEM accessibility setting.

## Circuit Workshop — and the app's one wired pair

- [ ] **The loop is live on arrival.** Pinch the switch lever: the bulb
      goes out, the electron beads stop.
- [ ] **Drag a part off the tray.** It follows your hand, and dropping
      it with copper ends near another part connects them automatically.
- [ ] **Pinch two terminals** across a distance: a wire joins them.
- [ ] ⟳ **Tap a part** → its control ring unfolds. Tap it again → it
      must **fold with the same animation, in place**. The fold has
      always existed; it ran at the scene origin at 1× scale, a metre
      away and out of view, which is why it read as the buttons simply
      vanishing.
- [ ] ⟳ **Pull the value bead** on a bulb. **The rail now hangs UNDER
      the part**, not out along its axis where the copper terminal sat on
      top of it. Check: the bead is visible across its whole travel, the
      number sits below the rail, and the petals are still overhead.
- [ ] ⟳ **Pull a bead with your hand drifting up and down.** The value
      must not wander — the drag is a projection onto the rail now, not
      a radial distance.
- [ ] **Two-handed pinch the bench**: it zooms. Past 4× you should be
      standing among the drifting electrons (Electron View's floor).
- [ ] **THE WIRED PAIR.** Add an inductor, wire it into a live loop,
      then switch **Electromagnet coil** on in the panel. The magnetic
      field should stand up to the RIGHT of the bench with a visible
      cable running from your inductor to its coil.
  - [ ] Beads travel along the cable, faster with more current.
  - [ ] **Open the switch → the coil dies**, the beads stop, and the
        bar magnets near it fall still. This is the app's best single
        demonstration; if it does not read, nothing else here matters.
  - [ ] **Carry a bar magnet through the coil** → the Coil EMF number
        jumps. Hold it still inside → it falls to zero.
  - [ ] **Two-handed pinch a MAGNET** → the field zooms and the bench
        does NOT.
  - [ ] Switch the coil off → the whole annex folds away cleanly.
- [ ] **Pause freezes the pair together** — never a frozen circuit
      driving a live magnet.

## Magnetism (alone)

- [ ] **No coil, no cable.** The electromagnet belongs to Circuit
      Workshop; arriving here it must be off.
- [ ] Carry a magnet toward another: they pull head-to-tail, push
      N-to-N, and swing to align.
- [ ] ⟳ **Two attracting magnets COME TO REST.** They should glide
      together, slow as they close, and stop dead, touching. They used
      to buzz against each other forever — a saturated force driving 8 mm
      inward every frame against a hard separation that projected them
      straight back out.
- [ ] ⟳ **The field lines.** Rewritten, and there are four things to
      look for:
  - [ ] Loops leave the **poles** — the ends of the bar — not its
        flanks. They used to be born 6 cm from the centre of a 16 cm
        magnet, i.e. inside it.
  - [ ] The near-field shape follows the BAR, not a point. The tracer
        now integrates a pole-pair field; the point dipole it used
        before is only valid a few bar-lengths out.
  - [ ] Lines bunch at the poles and thin at the equator — seeds are
        spaced by equal slices of flux now, not by equal area.
  - [ ] **Pull the strength bead and the picture changes.** More loops
        for a stronger magnet. This did nothing at all before: the
        tracer integrates the normalised field, so the geometry was
        identical at every strength.
- [ ] The hand-held compass needle points along the local field as you
      walk it around a magnet.

## Electric Fields — the app's only fully spatial module

Every control here is an object in the room, so **this section is the
only place most of them can be tested at all**. A screenshot proves a
rail rendered; only a hand proves it sets anything.

- [ ] ⟳ **Flick each of the five bank plates** on your left. The third
      is now labelled **"Capacitor"**, not "Parallel plates" — the old
      name collided with the apparatus it summons *and* with the panel
      copy calling the bank itself "the plates on your left". Each
      apparatus should ARRIVE, and the ones that carry an instrument
      should bring it: Capacitor puts a ΔV rail on top of the plates,
      Uniform B puts a strength rail under the bank.
- [ ] ⟳ **The bank, the B rail, the wells and the particle bank all
      moved 14 cm outward.** Check every one is still comfortably in
      reach without stepping, and still in view without turning.
- [ ] ⟳ **Pull each of the three wells.** All three must now behave
      alike: the new charge or probe is IN YOUR HAND and STAYS there all
      the way in. The two charge wells used to hand you the object and
      then yank it 30 cm inward on the next frame, because the wells
      stand outside the station and the charge was clamped to it
      immediately. A charge is escorted now — exempt from the walls
      until it first gets inside them.
- [ ] ⟳ **Drag a charge at the wall.** It still stops at the boundary,
      but the boundary is **26 % further out** (half-width 0.62 → 0.76).
- [ ] ⟳ **Pull the test charge out with Uniform B on and throw it
      sideways.** It must curve into a circle — and now **draw one**: a
      fading trail of beads marks the path behind it. Check the circle
      visibly CLOSES on its own tail, and that electron and positron
      wind opposite ways.
  - [ ] Grab the probe again mid-flight: the trail clears.
- [ ] **The particle bank:** tap each of the four discs. The tapped one
      lights, and only one is ever lit.
- [ ] **Drag each rail's bead.** The number follows your hand while it
      moves, the fill grows behind the bead, half way along the rail is
      half way through the range, and dragging off the end pins rather
      than wraps.
- [ ] **Drag along a rail with your hand drifting up and down.** The
      value must not wander with the drift.
- [ ] ⟳ **Switch the Capacitor plate OFF while dragging its ΔV bead**
      (two hands: left on the bank, right on the rail). The rail
      vanishes, the voltage stops changing, **and your hand is released**
      — it used to stay captured by the dead rail for the rest of the
      gesture, so nothing else could be grabbed until you let go.
- [ ] **Carry the capacitor low, then high.** Its rail stays on top of
      the plates the whole way.
- [ ] **Grab the flux meter's rim and pull.** It resizes under your
      fingertips, and the skin stays where your hand is.
- [ ] **THE DISC.** Cycle the meter to the disc, grab its rim and turn it
      edge-on to the field: **Φ must fall to zero.** Then cycle to the
      bubble and turn it however you like: Φ holds at Q/ε₀.
- [ ] **Grow the bubble while it is against a wall.** It must pull itself
      back inside the region rather than pushing its skin through.
- [ ] **Pinch a charge that is INSIDE the bubble.** The charge moves, not
      the surface.
- [ ] **Pinch a charge that is between the capacitor plates.** It must be
      grabbable through the plates' 26 cm collision spheres.
- [ ] Drag a charge: the field lines re-trace and follow, sticking to
      your hand rather than lagging visibly.
- [ ] ⟳ Tap a charge → ring; pull the strength bead → the sphere grows
      and the field answers live. **The bead's rail is under the charge
      now**, like every other rail in the app.
- [ ] **Tap the probe → its own ring.** With a ball selected it has a
      charge bead; switch to the electron **while the ring is open** and
      the bead must disappear (e is a constant of nature).
- [ ] **Two-hand pinch to 4×.** The field grows; the bank, the wells and
      the particle bank do NOT, and stay reachable.
- [ ] Capacitor on, plates pulled to full separation: the assembly
      stays inside the region.

## Projectiles — the one that is 1:1 with your room

- [ ] **Throw a ball at a real wall.** It must bounce where the wall
      actually is. Any offset means the display has been translated,
      which is forbidden for this bench.
- [ ] **Catch a ball out of the air.** Device-only; inert in the
      simulator.
- [ ] Drag the launcher anywhere; pinch its bead to aim; the predicted
      arc updates as you pull.
- [ ] The ball fan opens off the launcher's Balls petal, and choosing a
      ball changes the flight (a table-tennis ball and a cannonball are
      17× apart in mass).
- [ ] **Two-handed pinch does NOTHING here.** Projectiles is
      permanently excluded from scaling.

## Pendulums

- [ ] Grab a bob and throw it sideways → a true 3-D orbit, not a plane.
- [ ] ⟳ **Pull a bob's length bead.** Previously broken, three ways at
      once: the bead rode a bob sweeping past at a metre a second, the
      drag read radial distance from that moving anchor, and this module
      was the only one in the app that never called `endGrip` — so after
      the first touch, *every* later drag in the scene silently became a
      length edit. Check: the pendulum **holds still** while the bead is
      held, the cable pays out, the period tag climbs as √L, and letting
      go returns the swing without throwing it.
  - [ ] Then grab a bob normally. It must be a bob grab, not a length
        edit — that is the regression the missing `endGrip` caused.
- [ ] ⟳ **Pull a pendulum out of the spawn well; it hangs where you let
      go.** Previously broken: the pivot's floor was `0.85 m + cable`,
      i.e. 1.65 m, which is 35 cm above the well's own mouth — so the
      rig teleported out of your hand the instant it moved. The
      clearance rule is now 0.30 m of air under the bob, applied at
      birth as well as on every move.
  - [ ] Pull one out when the lab is already full: the well should go
        **dark and NOT pop**. It used to chirp and recoil while handing
        back nothing.
### ⟳ The four new instruments

The panel is empty of controls now; all seven moved into the room, and
**not one of them has ever been looked at** — the simulator was wedged on
its boot logo for the whole pass that built them. Placement is the risk,
not wiring: every one is at the pivot plane's depth (z ≈ −1.08) aiming for
the ~14° band, but this project has put controls 38° below the eye line
three times already while the arithmetic looked fine.

- [ ] **Can you SEE all four without hunting?** Stand where you naturally
      stand. The switch bank should be off your left shoulder, the worlds
      bank and two rails off your right. Anything you have to look down or
      lean for has failed, however correct its numbers are.
- [ ] **Nothing is inside the swing.** Let a bob swing wide, and pull one
      out to a 1.6 m cable. No instrument should be swept through.
- [ ] **The five-plate bank.** Each plate lights when its layer is on:
      Velocity, Acceleration, Force, Energy bars, Air resistance.
  - [ ] Every label sits BESIDE its plate, never across it — the bug that
        made this module's neighbours unreadable on 2026-07-31.
  - [ ] Switch Air resistance off and the swing stops decaying. It is the
        only plate on the bank that changes the physics rather than the
        picture, and it should feel different.
- [ ] **The worlds bank is also a readout.** Tap Moon: g follows, the
      swing stretches to about 2.5× its Earth period (T ∝ 1/√g), and the
      **Moon disc lights**.
  - [ ] Now drag the g rail slightly off 1.62. The Moon disc must go
        **dark** — you are between worlds, and nothing should claim
        otherwise. Drag back and it relights.
- [ ] **The g rail is absolute.** Where you put the bead is the value —
      start a drag from the middle of the rail and the bead must not
      jump. Its callout should read the same number the panel does.
- [ ] **The time rail.** 0.1× should make a fast swing legible; 5× should
      make a 1.6 m pendulum's 2.5 s period quick. Pause still freezes it
      independently.
- [ ] **A drag that starts on a rail stays on that rail** — slide off the
      end and over a bob, and the bob must not start swinging.
- [ ] **Reset returns all of it**: five plates to their defaults, g to
      Earth with the Earth disc lit, time to 1×.

- [ ] Gravity → Moon: the swing visibly slows.

## Gravity Lab

**Rewritten on 2026-07-31 — the orbit became the object.** Nothing
automated can pinch a bead, so this section is the only gate on the
module's new centrepiece. Everything marked ⟳ is new or changed.

### The orbit ring

- [ ] ⟳ **Tap a planet.** Two things must happen at once: its **control
      ring** unfolds (mass bead, delete petal) AND its **orbit ring**
      appears — a conic drawn around the Sun, passing through the planet,
      with a bead at each end. Tapping used to open the control ring
      without SELECTING, and selection is what the orbit ring, the
      vectors, the Kepler sweep and the Predict button all key off.
- [ ] ⟳ **Pull the far bead straight out.** The orbit stretches into an
      ellipse; the near end stays put. The planet slides along its own
      sightline rather than jumping.
- [ ] ⟳ **Pull a bead sideways.** The whole ellipse swings about the Sun
      and the other bead sweeps round to stay opposite. This is the
      module's best single moment — on Jupiter the far bead traces a
      2.6 m arc past your head.
- [ ] ⟳ **Pull a bead up, out of the ecliptic.** The orbital plane tilts
      with it. There is no inclination control anywhere; this is it.
- [ ] ⟳ **Circle a bead** — take it round a closed loop and back. The
      orbital plane should come back ROLLED, not where it started. That
      is the transport rule's holonomy, and it is why two beads are
      enough for five degrees of freedom instead of needing a third.
- [ ] ⟳ **Drag the near bead outward past the far one.** The labels swap
      — the bead in your hand becomes apoapsis — and **nothing may jump.**
      The crossing happens exactly where the orbit is circular, which is
      where the two ends are physically the same thing.
- [ ] ⟳ **Let go, and watch.** The planet stays on the orbit you drew.
      Over simulated centuries the beads should creep slowly round the
      Sun: that is real Newtonian precession, not drift.
- [ ] ⟳ **Watch the ring against the trail.** The ring is the orbit the
      body would take if nothing else pulled; the trail is what actually
      happens. They should visibly disagree — that gap is Jupiter.
- [ ] ⟳ **A bead behind its own planet is not grabbable.** Check on a
      near-circular orbit, where the near bead sits on the planet.
- [ ] ⟳ **Saturn outward: the ring draws, and has no beads.** They are
      genuinely out of arm's reach and the module does not pretend
      otherwise. Zoom out with both hands and Jupiter's should come into
      range.
- [ ] ⟳ **Press Twin suns: the ring goes out.** Correct — a planet's
      two-body ellipse about one of two equal stars describes nothing.
- [ ] ⟳ **Grab a bead at 1× and again at 9×.** It must be the same size
      in the room both times, and pinchable at both. Uncompensated it
      would be 5 mm at 0.4× and a 12.6 cm sphere at 9×.

### The room-scale walk-through

- [ ] ⟳ **Two-hand pinch to 9×.** All six of these were broken:
  - [ ] The Sun lights the OUTER planets — Uranus and Neptune should
        have a lit side facing the Sun, not be flat grey.
  - [ ] Name labels and every callout hold their size. They used to
        inflate ninefold.
  - [ ] **The spawn well stays where it was and stays the size it was.**
  - [ ] The field-flow particles fill the space around you rather than
        clustering where the Sun used to be.
  - [ ] The spacetime grid switches itself off past ~2.5× (it is a floor
        3.8 m under you by then).
  - [ ] The dimming shell is outside the orrery, not cutting through it —
        no seam where planets change from dark-backed to wall-backed.
- [ ] ⟳ **A scale readout appears beside the clock** once you are off 1×.
- [ ] ⟳ **Press Reset: the view returns to 1× and untwisted**, not just
      the bodies.

### The panel emptied

- [ ] ⟳ **The switch bank on your left**, six plates: spacetime grid,
      Kepler sweep, field flow, velocity, **acceleration**, force. The
      acceleration vector has never had a control anywhere in the app.
- [ ] ⟳ **The G rail under the bank.** Drag its bead: orbits speed up and
      slow down live.
- [ ] ⟳ **Tap the SUN.** It gets a mass bead of its own — in solar
      masses — and no delete petal. Pull it: the star inflates as the
      cube root and every orbit responds.
- [ ] ⟳ **The panel holds no slider, picker or toggle.** It reads: the
      selected body's orbital elements, and its energy — with total
      energy negative for bound and positive for escaping.

### The three doors

- [ ] ⟳ **Reverse time.** The clock bank now has −1× and −20×. Perturb an
      orbit, run it backwards, and it should un-perturb — this is the
      integrator being time-symmetric, not a replay. Rewinding past a
      MERGE must not un-merge (that information is gone).
- [ ] ⟳ **Lagrange points.** Select Jupiter, switch the layer on: five
      markers appear. L4 and L5 form equilateral triangles with the Sun
      and Jupiter.
  - [ ] Pull a world from the well and release it on L4. It should snap
        to the rotating frame and **stay there** — that is where the
        Trojans are. Drop one on L1 and it should slide off within days.
  - [ ] While doing that, the markers must NOT jump to the new body: the
        layer follows the last planet you TAPPED.
- [ ] ⟳ **The body budget is 16.** `reset()` uses ten, so you can add six
      worlds before anything refuses. Check the well goes dark rather
      than popping when it does refuse.
- [ ] ⟳ **Trails no longer hitch** when several bodies' trails rebuild at
      once (the uploads are staggered across frames now).

### Still true from before

- [ ] Crown opens toward blackness (`.progressive` immersion).
- [ ] Grab a planet: it freezes and shows the orbit it would take if
      released now; release applies your hand's velocity.
- [ ] Pull a world from the well and let go WITHOUT moving your hand: it
      holds a circular orbit.
- [ ] The clock bank changes time scale and reads back which is on.

## Cross-cutting

- [ ] ⟳ **Every rail in the app hangs under the thing it adjusts.**
      `Bloom` is shared by eight modules, so this moved everywhere at
      once: Circuits, the coil annex, Electric Fields (charge and
      probe), Kinematics, Pendulums, Magnetism and Gravity Lab. The
      stack is always petals / object / rail / number.
- [ ] ⟳ **Every ring folds in place.** Same class of fix, same eight
      modules.
- [ ] **System Reduce Motion** (Settings ▸ Accessibility): the hub's
      idle life stills, and the door signs PARK at a composed rest pose
      rather than freezing mid-flight. There is no in-app duplicate of
      this switch any more.
- [ ] **Every lab's first-run hint** appears once and stays dismissed.
- [ ] **The notebook** captures a moment from each lab with sane
      numbers and units.
- [ ] **Leave and re-enter a lab**: its state survives.
- [ ] **Leave and re-enter the hub repeatedly**: no slowdown.
