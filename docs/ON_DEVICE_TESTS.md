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
| Physics & geometry | `PhysicsCoreTests` (291) | `swift test`, no simulator |
| Models, clamps, layout | `PhysicsPlaygroundTests` | simulator |
| Tap *handlers* | `StationTapTests` — calls `handleTap` directly | simulator |
| Window chrome | `PhysicsPlaygroundUITests` — real taps | simulator |
| **Spatial gesture, in the room** | **this file** | **headset only** |

Work top to bottom; each item says what CORRECT looks like, because
"seems fine" is how a broken affordance survives a test pass.

---

## The home

- [ ] **The gallery arrives, doesn't cut.** Launch. The whole room
      should fade up over about a fifth of a second — terraces, signs
      and exhibits together, none arriving first.
- [ ] **Both door signs read from the doorway**, at a glance, without
      leaning: `ELECTRICITY & MAGNETISM` in green, `MECHANICS & ENERGY`
      in bronze. If either is unreadable at the default gallery
      distance, the plaque's contrast is wrong on a real display and
      not just in a screenshot.
- [ ] **The signs move.** An electron laps the E&M sign — it must pass
      IN FRONT of the letters across the bottom of the lap and BEHIND
      them across the top. If it never goes behind, the depth illusion
      is dead and the type will read as a decal.
- [ ] **The ball clears the Mechanics sign**, lands on the end of the
      underline rule, and returns the other way. It should never pass
      through a letter.
- [ ] **Look at an exhibit.** It lifts off its puck, grows, names
      itself, and its focus panel appears behind it. Look away: it
      settles back and the name fades.
- [ ] **Drag an exhibit to the podium.** It should follow your hand 1:1
      — no lurching toward the hand — the podium glows as you approach,
      the exhibit seats itself, and a `Load …` button appears above it.
- [ ] **The podium hint is legible** from where you naturally stand.
- [ ] **Press Load.** The lab opens.
- [ ] **The other way in:** look at an exhibit, press the focus panel's
      Load button without touching the podium. This path must ALWAYS
      work — it is the guaranteed one.
- [ ] **The utility bar:** ⚙ opens Settings, 📖 opens the Lab Notebook,
      ℹ opens About. All three are real windows.
- [ ] **Settings → Home title → each of the five options.** The gallery
      should rebuild in that voice, fading rather than popping. "Show me
      all three" hangs the specimen wall and suppresses the live signs.

## Circuit Workshop — and the app's one wired pair

- [ ] **The loop is live on arrival.** Pinch the switch lever: the bulb
      goes out, the electron beads stop.
- [ ] **Drag a part off the tray.** It follows your hand, and dropping
      it with copper ends near another part connects them automatically.
- [ ] **Pinch two terminals** across a distance: a wire joins them.
- [ ] **Tap a part** → its control ring unfolds. Tap it again → folds.
      Tap empty space → folds.
- [ ] **Pull the value bead** on a bulb: it visibly dims as resistance
      rises, while your hand is still moving.
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
        jumps. Hold it still inside → it falls to zero. Only *change*
        induces.
  - [ ] **Two-handed pinch a MAGNET** → the field zooms and the bench
        does NOT. This is the routed scale rig; if the bench moves, the
        routing regressed.
  - [ ] Switch the coil off → the whole annex folds away cleanly.
- [ ] **Pause freezes the pair together** — never a frozen circuit
      driving a live magnet.

## Magnetism (alone)

- [ ] **No coil, no cable.** The electromagnet belongs to Circuit
      Workshop; arriving here it must be off, even if you left it on
      over there.
- [ ] Carry a magnet toward another: they pull head-to-tail, push
      N-to-N, and swing to align.
- [ ] The hand-held compass needle points along the local field as you
      walk it around a magnet.

## Electric Fields — now the app's only fully spatial module

Every control here left the window panel on 2026-07-31, so **this section
is the only place most of them can be tested at all**. A screenshot proves
a rail rendered; only a hand proves it sets anything.

- [ ] **Flick each of the five bank plates** on your left. Each apparatus
      should ARRIVE — and the ones that carry an instrument should bring it
      with them: Parallel plates puts a ΔV rail on top of the capacitor,
      Uniform B puts a strength rail under the bank. If a plate lights but
      nothing appears, the plate is lying.
- [ ] **Pull each of the three wells** on your right. The new charge (or
      probe) must be IN YOUR HAND already — if it appears somewhere else
      and then jumps to you, the born-at-the-fingertips path regressed.
- [ ] **Pull the test charge out with Uniform B on and throw it sideways.**
      It must curve into a circle in the direction you threw. Release it
      almost still: it should still circle, on the fallback push. A probe
      that just sits there means `releaseProbe(flick:)` lost its launch.
- [ ] **The particle bank:** tap each of the four discs. The tapped one
      lights, and only one is ever lit. Electron and positron must curve
      OPPOSITE ways in the same field.
- [ ] **Drag each rail's bead.** The number follows your hand while it
      moves, the fill grows behind the bead, and half way along the rail is
      half way through the range. Drag off the end: it pins, never wraps.
- [ ] **Drag along a rail with your hand drifting up and down.** The value
      must not wander with the drift.
- [ ] **Switch the capacitor OFF while dragging its ΔV bead.** The rail
      vanishes and the voltage stops changing. (Before `isEnabled`, it kept
      writing.)
- [ ] **Carry the capacitor low, then high.** Its rail stays on top of the
      plates the whole way — never inside them, never left behind.
- [ ] **Grab the flux meter's rim and pull.** It resizes under your
      fingertips, and the skin stays where your hand is.
- [ ] **THE DISC.** Cycle the meter to the disc, grab its rim and turn it
      edge-on to the field: **Φ must fall to zero.** Then cycle to the
      bubble and turn it however you like: Φ holds at Q/ε₀. That contrast
      is Gauss's law, and until this change the app instructed the user to
      perform it while providing no way to do so.
- [ ] **Grow the bubble while it is against a wall.** It must pull itself
      back inside the region rather than pushing its skin through.
- [ ] **Pinch a charge that is INSIDE the bubble.** The charge moves, not
      the surface. (The surface is a container; the thing inside is the
      subject.)
- [ ] **Pinch a charge that is between the capacitor plates.** It must be
      grabbable — the plates carry 26 cm collision spheres that overlap in
      the gap, and only the 12 cm proximity fallback gets you through them.
- [ ] Drag a charge: the field lines re-trace and follow, sticking to
      your hand rather than lagging visibly.
- [ ] **Drag a charge at the wall.** It should stop at the region
      boundary — the clamp added on 2026-07-30.
- [ ] Tap a charge → ring; pull the strength bead → the sphere grows
      and the field answers live.
- [ ] **Tap the probe → its own ring.** With a ball selected it has a
      charge bead; switch to the electron **while the ring is open** and
      the bead must disappear (e is a constant of nature, not a setting).
- [ ] **Two-hand pinch to 4×.** The field grows; the bank, the wells and
      the particle bank do NOT, and stay reachable.
- [ ] Capacitor on, plates pulled to full separation: the assembly
      stays inside the region.

## Projectiles — the one that is 1:1 with your room

- [ ] **Throw a ball at a real wall.** It must bounce where the wall
      actually is. Any offset here means the display has been
      translated, which is forbidden for this bench.
- [ ] **Catch a ball out of the air.** Device-only; inert in the
      simulator.
- [ ] Drag the launcher anywhere; pinch its bead to aim; the predicted
      arc updates as you pull.
- [ ] The ball fan opens off the launcher's Balls petal, and choosing a
      ball changes the flight (a table-tennis ball and a cannonball are
      17× apart in mass).
- [ ] **Two-handed pinch does NOTHING here.** Projectiles is
      permanently excluded from scaling; if it zooms, that is a
      regression.

## Pendulums

- [ ] Grab a bob and throw it sideways → a true 3-D orbit, not a plane.
- [ ] Pull a bob's length bead: the cable pays out and the period tag
      climbs as √L while your hand moves.
- [ ] Pull a pendulum out of the spawn well; it hangs where you let go.
- [ ] Gravity → Moon: the swing visibly slows.

## Gravity Lab

- [ ] Crown opens toward the starfield (`.progressive` immersion).
- [ ] Grab a planet: it freezes and shows the orbit it would take if
      released now; release applies your hand's velocity.
- [ ] Pull a body's mass bead: it inflates as the cube root of mass.
- [ ] The clock bank changes time scale and reads back which is on.
- [ ] Two-handed pinch to 9×: the inner solar system becomes a room you
      walk through.

## Cross-cutting

- [ ] **Reduce Motion** (Settings, and the system setting): the hub's
      idle life stills, and the door signs PARK at a composed rest pose
      rather than freezing mid-flight.
- [ ] **Every lab's first-run hint** appears once and stays dismissed.
- [ ] **The notebook** captures a moment from each lab with sane
      numbers and units.
- [ ] **Leave and re-enter a lab**: its state survives.
- [ ] **Leave and re-enter the hub repeatedly**: no slowdown. (A
      subscription leak here once kept an orphaned gallery animating
      forever behind every module.)
