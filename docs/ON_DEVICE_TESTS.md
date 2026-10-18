# On-device test script

**Everything here needs a headset.** Nothing on this list can be
automated, and the reason is worth stating once so nobody wastes an
afternoon rediscovering it:

- `simctl` has **no tap, touch, or drag verb** — it can boot, install,
  launch, screenshot and terminate. That is the whole surface.
- **XCUITest has no API for RealityKit entities.** It drives SwiftUI —
  windows, buttons, pickers, lists — and everything in an immersive
  space is invisible to it. No exhibit, no pad, no magnet, no pinch.

So the automated suites cover four of five layers, and this file is the
fifth:

| Layer | Covered by | Runs where |
|---|---|---|
| Physics & geometry | `PhysicsCoreTests` (450) | `swift test`, no simulator |
| Models, clamps, layout | `PhysicsPlaygroundTests` | simulator |
| Tap *handlers* | `SpatialTapTests`, `SpatialActionBankTests`, `BloomPetalTests`, `MultimeterTests` — call `handleTap` directly | simulator |
| Window chrome | `PhysicsPlaygroundUITests` — real taps | simulator |
| **Spatial gesture, in the room** | **this file** | **headset only** |

Work top to bottom; each item says what CORRECT looks like, because
"seems fine" is how a broken affordance survives a test pass.

**Items marked ⟳ changed on 2026-08-04** in response to the previous
pass, and are the ones worth doing first.

## Release 1.0 gate (2026-09-01) — the demo, in order, as the acceptance pass

`docs/DEMO_SCRIPT.md` is the 180-second script; this is the same order
as a checklist, and it is the fourth ship gate: nothing is recorded
until every line here passes on the headset with the owner driving.
Beats marked **[F]**, **[G]** and **[H]** exist only once those batches
have landed; skip them on a pass before that and say so in the report.
The older sections below stay as history and detail — where one of them
contradicts this section, this section is current.

- [ ] **0 · Arrival.** Cold launch goes STRAIGHT into the space: a beat
      of plain passthrough, then the room dims slightly and glowing
      particles fall, swirl, ripple like a wave and settle into six
      portals around you, each looping its own physics — about three
      seconds. A pinch anywhere during it skips to the end. With Reduce
      Motion on, the portals simply fade in. The end state IS the home:
      the wordmark, six short names, More.
- [ ] **1 · Enter.** Pinch the Projectiles portal: dissolve through
      passthrough, the lab fades up with the room ramping (not snapping)
      to 0.35, a welcome shot already in the air.
- [ ] **2 · Projectiles.** Pull a basketball from the well and throw it
      overhand at a real wall: it bounces AT the wall. In More, slide
      Gravity onto Jupiter (arc collapses, the readout names it) and
      Zero-g (dead straight). Catch a ball on your fingertips. Air on in
      More: the Wind slider wakes, a wind bends the flight. Pull the aim
      bead outward: the shaft lengthens, the protractor's speed climbs
      and the arc stretches; inward, all three shrink.
      **[F]** Pull a hoop from its well (the mint mouth beside the ball's)
      and stand it across the room. Tap it: its ring — Aim, Drop when
      fired, Delete — and under it a callout reading "low 32° · high 74°"
      (or "out of range at 6.0 m/s"); two faint ghost arcs pass through
      the rim. Pinch Aim: a two-disc fan, Low arc / High arc; pick one and
      the launcher's bead swings to it. Fire → chime, the hoop flashes.
      Pinch "Drop when fired": the callout adds "drops when fired"; fire
      straight at the hoop and it falls as the shot leaves — the ball
      meets it in mid-air, on the Moon and on Jupiter too, and the next
      shot re-hangs it. Pick Custom in the ball fan: More's Custom ball
      mass wakes; change it and the arc changes only with Air on.
      Air on: the vacuum ghost stands beside the real arc and the landing
      ring reads both ranges. Throw at your coffee table: it bounces off
      the top and comes to rest on it, rolls off the edge and falls; swat
      a ball out of the air with an open hand, and confirm a still hand
      still CATCHES. **[C]** Tap the launcher: its ring unfolds
      (Fire / Balls / Clear); tap empty space: it folds;
      the aim bead works with the ring folded.
- [ ] **3 · Time Capsule** (ships ON now — no Settings visit). Pinch
      Pause in the title bar: the room holds; ONE reel arrives, still
      coasting, under "Time capsule". Pinch it: the tape draws out and the
      reel turns ~1.5 turns. Drag the bead back: the ball retraces its arc
      and the bounce un-happens, landing on recorded frames. Walk around
      the frozen ball: velocity and force arrows sculpted on it, the path a
      tube. "Back a frame" ×3 through the wall contact. "Resume here": the
      room runs forward FROM that instant. Settings › Time Capsule OFF,
      pause again: nothing new appears.
- [ ] **4 · Circuits** (Home, then the Circuits portal). The loop is live;
      pinch the switch: bulb out, beads stop. Pull a resistor from the
      shelf, born at your fingertips; click it nose-to-tail onto the loop.
      Pull a lead across: wired; tap a lead: the whole net lights green.
      More → True drift speed, then two-hand zoom into the copper: beads at
      mm/s, the field front laps the loop. **[G]** Tap the resistor and
      pull its value handle out from under it to 10 Ω: it glows, then
      scorches and the loop goes dark; Replace. More → Load RC charger;
      wire in the coil; More → Magnetic field: a looping field over the
      coil, flipping when you reverse the battery, collapsing when you open
      the switch. Tap the AC source: a frequency slider hangs under it; at
      3 Hz the bulb flickers and the capacitor lags. **[H]** Every part on
      the shelf and on the bench reads as one milled family.
- [ ] **5 · Orbital Mechanics** (Home, then the Orbits portal). The room
      goes to 0.85 and reads as entering space — nothing stands in it but
      the system and the world well. The sky is QUIET until you tap Earth;
      then ring, card and arrows arrive together. Pull the far bead: the
      ellipse stretches; let go: Earth stays on the orbit you drew. Pull
      Earth's mass handle out: the sphere swells. More → Clock 20×: the
      beads creep (precession). Two-hand pinch to ~4× and walk in: labels
      hold their size, the well stays put, the chord plays. More → Twin
      suns: every orbit answers. More → Lagrange points; drop a world on
      L4: it holds, and the capture paragraph appears at the point.
- [ ] **6 · Electric Fields.** Pull a charge from the Charge well: the
      field redraws around your hand. Tap it → Flip: the lines reverse;
      pull its handle out: it swells and the field strengthens. More →
      Uniform B; pull a test charge and throw it sideways: it circles and
      closes on its tail; More's Values read a non-zero qv×B.
- [ ] **7 · Magnetism.** Carry one bar toward the other: it swings and
      snaps head-to-tail; the loops re-trace around you (judge the pink);
      the hand compass follows. Tap one and draw its strength handle out
      from under it: the loops multiply.
- [ ] **8 · Pendulums.** Release the cradle: click-click. Tap a bob and
      draw its length handle down: the cable pays out, the period tag
      climbs. Pull "Double" from the upper well and flick it: the lower bob
      leaves a chaotic trail and wears NO period tag. Throw a bob sideways:
      a true 3-D orbit.
- [ ] **9 · More and Studio Mode.** Pinch More: the lab's switches, its
      live numbers, the room. Studio Mode: a night sky over a dark floor
      with a soft pool of light, and nothing on it glowing.
- [ ] **10 · Close.** Home: dissolve, and the seven portals stand around
      you again under the wordmark.
- [ ] **Judgement calls, answered in writing:** the pink field lines
      through passthrough; whether 45 % recession is legible in your
      room; the reel's size and where it lands; whether More's panel
      reads against the field lines that can cross in front of it (Fields,
      Magnetism); whether a handle on a stalk reads as "pull me" without a
      word; the house music (2026-10-14 score) — it should fade up, sit
      UNDER the room rather than in front of you, never click at its
      64 s seam, and be quiet enough to forget (−22 dB head-locked; say
      if it wants more or less); the re-voiced effects — do the ticks,
      pops and chime read as one family with the music, does the cradle
      CLACK like steel and the launcher THUMP, does the mains hum still
      read as a hum and the orbital chord as glass; whether the title bar
      clears the apparatus in all seven labs — Pendulums' cradle hangs from
      1.62 m since 2026-09-04 because at 2.0 m the bar crossed its cables.
- [ ] **The cut test:** enter all seven labs in sequence; the room's
      brightness moves only at Orbital Mechanics, and ramps rather than steps.

## The 2026-10-14 polish pass

- [ ] **The bench labels.** Stand where you stand for the demo: every
      lab's name reads on its bench's front edge at a glance, in a bright
      room AND with the lights down. If the dark edge itself is lost in a
      dim room, the label still glows; say whether it reads as a label or
      as a stray light.
- [ ] **Nothing moves the names.** Face each exhibit in turn: it lifts and
      grows, its name brightens, nothing collides with a door sign.
- [ ] **The pool stays on the mount** as the exhibit lifts — a disc of
      light on the mount's top, never a smudge in the air beside it.
- [ ] **Reset arms first.** Open the palette, pinch Reset once: the petal
      turns red and reads "Tap again"; nothing has reset. Wait four
      seconds: it goes back to Reset. Pinch it twice: the lab resets and
      the ring folds. Arm it and fold the ring: reopened, it reads Reset.
      `-paletteReset 1` photographs the armed state.
- [ ] **Look at an icon in the title bar or the home's utility bar**:
      its name appears (Home, Show the physics, Place the lab, Studio
      Mode, Reset; Lab list, Settings, About).
- [ ] **Settings › Effects volume** wears a quiet speaker at the left end
      and a loud one at the right.

### The charm pass (2026-10-16) — sound, so judge with the volume up

- [ ] **Electric Fields, More › Free charges.** The dipole drifts together
      and meets with one soft clack, not a buzz while they touch. Pull a
      test charge, let it go beside the negative charge: one glassy pop as
      it lands. With Uniform B on, let a probe go: a whoosh as it leaves;
      with B off, letting go is silent (it starts at rest).
- [ ] **Circuit Workshop, the meter on continuity.** Touch the probes to
      both ends of a wire: a steady soft A6 from the meter's case for as
      long as they touch, no click as it starts or stops. Lift a probe: it
      stops. Pause: it stops. Judge: a real meter's beep, or a shriek?
- [ ] **The three gleams — each once a session.**
      - Light & Optics: set a mirror square to the laser so the beam comes
        straight back into it. Judge: is it findable by hand with the aim
        bead (about half a degree)? If not, the collar tolerance is the lever.
      - Pendulums: More › Coupled pair, then wait about seven seconds for
        the swing to pass wholly into the inner bob.
      - Magnetism: a coil from the well, a magnet pushed briskly through.
      Judge: is the gleam a quiet "look", under the hoop's chime — or does
      it compete with the moment it marks?

### The laws in More › Values (2026-10-15)

- [ ] **Open More in each lab with something selected** (a bob, a charge
      with a test charge out, a magnet and a coil, a prism, a circuit
      part, a planet; Projectiles with air off, then on). Under the
      numbers, smaller and dimmer: the law each one obeys, with the live
      values in it where it is one product or quotient. Judge at arm's
      length, in a bright room: legible without leaning in, and still
      plainly secondary to the column of numbers?
- [ ] **A long formula breaks before its numbers**, never in the middle
      of a term: Optics' least deviation, Pendulums' "Against".
- [ ] **VoiceOver on a reading** speaks the value and then the law.
- [ ] **Nothing in the room changed.** The laws are in More only; no lab
      writes an equation into the space.

### The labs, same day

- [ ] **Every lab answers a grab.** Pick up a ball, a planet, a charge, a
      magnet, the hand compass, a bob, a circuit part: each flashes and
      ticks as the pinch closes and ticks again where it is let go. Set a
      bob down without throwing it: no whoosh. Throw it: whoosh.
- [ ] **The ring and the halo agree.** In Magnetism and Circuit Workshop,
      with one object selected, tap another: its ring opens AND its halo
      lights; the readout card follows it.
- [ ] **Every ring folds with a tick**, including Electric Fields' and the
      pendulum collar's. Tap a collar: its ring pops open; tap empty
      space: it folds.
- [ ] **Petals sound.** Every petal pops when it fires; the hoop's Delete
      and the launcher's Clear are red like every other Delete.
- [ ] **Pause says Resume.** Pause from the palette, reopen it: the petal
      shows a play glyph and reads "Resume"; pinch it and the lab runs.
- [ ] **The ball fan.** Projectiles › launcher ring › Balls: the five
      discs open above and right of the launcher, and none of them sits
      in front of or behind the Moon / Earth / Jupiter discs from where
      you stand. Pinch Table-tennis ball: the ball changes, the world
      does not.
- [ ] **Circuit Workshop remembers a clear.** Clear bench (twice), quit,
      relaunch: the starter loop, not the bench you cleared. Load a
      preset, quit, relaunch: the preset.
- [ ] **Numbers settle.** Drag the launcher's aim bead and stop dead: the
      protractor and the range land on the final value within a moment,
      never one degree behind. Same for the compass µT when you stop.
- [ ] **Reduce Motion on, in Orbital Mechanics:** the planets stop
      turning on their axes; orbits still run. A merge flashes without
      growing.

## Deferred — the owner asked to be reminded

Three revisits from the 2026-08-03 pass, deliberately NOT addressed in
the fix pass that followed it. Bring these up when planning the next
working session:

- [x] **Circuit Workshop, whole-module improvement.** "Okay I want to
      revisit this with you … and we will plan out how to improve this
      system." The bug-class fixes landed, the design pass got its
      review (`docs/CIRCUITS_DESIGN_REVIEW.md`, eleven proposals
      C1–C11), and **it was triaged on 2026-08-26**: C3 and C4 are moot
      (the wiring gesture changed under them on 08-11), C7 was a
      correctness bug and is fixed, C10 is half done and half declined,
      and the remaining seven are declined for v1 as new features. The
      verdicts and their reasons are at the top of that file. Nothing
      is owed here any more — but the module has changed a great deal
      since the review was written, so **walk it once on device** and
      say whether the answer still feels right.
- [ ] **Projectiles, whole-module improvement.** "It has the same UI
      flip issue, the wall bouncing is unreliable, and it just seems
      uninspired. we will revisit." The flip is fixed app-wide and a
      ball well was added; **the bounce reliability landed 2026-08-06**
      (three distinct defects: walls fed in world space so bounces went
      wrong by exactly the anchor offset after relocating the lab; a
      graze whose v·n flipped mid-frame skipped its own strike; the
      post-bounce remainder of the frame was discarded, deadening fast
      bounces). The check is below in the module section. The
      INSPIRATION half: **on 2026-10-17 throwing became the main act**
      (owner's pick of three) — the room opens quiet with a ball waiting
      at your hand, throws leave at the hand's peak, and a throw reads out
      its own angle and speed. Judge it on device (module section) before
      ticking this.
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

### The labs in miniature, and the icon (2026-10-16)

- [ ] **Each portal holds its lab, small, on the same graphite stage.**
      The cradle clacks, the magnet slides through the coil and the LED
      flashes red then green, the prism's spectrum sweeps its screen, the
      charges sit in their glass shells with heads riding the lines, the
      launcher's ball drops through the hoop, the switch closes and the
      bulb lights, the planets go round the orrery. Judge from where you
      stand, 1.75 m off: does each read as its lab at a glance, and do the
      seven stages read as one set?
- [ ] **Walk up to a portal.** Up close the models should hold: the
      cradle's bent champagne frame and bifilar threads, the coil's copper
      turns, the prism's glass. Nothing pokes through the glass pane
      behind it, and a pinch on the front of a diorama still enters the lab.
- [ ] **Frame time on the home with all seven running.** The Light
      diorama re-traces seven rays every frame; it should not be felt.
- [ ] **The app icon**, on the Home View: the prism and its white beam on
      one layer, the spectrum floating in front of it on another. Look
      around it: the parallax should separate them by depth.

- [ ] **The opening plays once and ends as the home.** The room dims a
      little; particles fall under gravity, swirl in a crossed field,
      ripple like a wave and settle into seven portals in an arc around
      you. It takes about three seconds and the bell lands as they
      settle.
- [ ] **A pinch skips it.** Pinch anywhere during the opening: the
      portals are simply there.
- [ ] **Reduce Motion:** no particles at all — the portals fade in.
- [ ] **Each portal previews its physics in a loop** and its short name
      is legible from where you stand, all seven at a glance — system type
      on a glass capsule with the lab's colour as a dot.
- [ ] **The particles are points of light**, not beads or tiles: soft
      halos, no square around any of them, and the room's dimming intact
      behind them. They draw each portal's ring as its glass grows the
      last few per cent into place, and the wordmark rises into its spot.
- [ ] **The bezels are one clean ring each** — champagne alloy, the
      colour of the i's dot, no notch or tick anywhere round it, the glass
      meeting it with no gap at any angle you look from.
- [ ] **At rest the portals float** a few millimetres, never in step —
      felt rather than seen. Under Reduce Motion they hang still.
- [ ] **The wordmark is the app's own type** (2026-10-14): rounded white
      letters standing a few centimetres off a glass plaque the shape of
      every panel, the i's dot a point of champagne light. Walk round it:
      the letters are solids with soft rounded edges, with no spike, nick
      or hole anywhere, and they hold white against a bright wall. Judge:
      does it read as the same app as the labs' title bars?
- [ ] **The wordmark arrives by physics.** "Physics" drops in letter by
      letter and bounces to rest across the bell; "Playground" swings in
      from its top edges like hung signs and settles; the i's dot drops
      onto its stem last. The plaque fades up with the portals' labels.
      Then a slow wave rolls through both lines and a glint brightens the
      letters every few seconds. Judge: playful, or too much for a title?
- [ ] **Pinch a letter**: it hops and bounces back to exactly its place,
      with a pop. Gaze at one first: it highlights like any button.
- [ ] **Hover a portal:** the system highlight. Pinch it: you are in
      that lab.
- [ ] **More** under the wordmark opens Lab list, Settings and About in
      one row; nothing hides behind the portals.
- [ ] **Coming home** from a lab stands the seven portals around you again
      without replaying the whole opening.

## Circuit Workshop

**The whole-module improvement pass is deferred** (see the top of this
file). What follows is the standing script.

- [ ] **The loop is live on arrival.** Pinch the switch lever: the bulb
      goes out, the electron beads stop.
- [ ] **Flip the switch with a drifting hand (2026-08-29).** A pinch on
      the lever that wanders a few millimetres — under ~12 mm — must
      still flip it, the same grace every other target gets. And a
      clean tap must flip it exactly ONCE: a switch that visibly does
      nothing on a tap is the double-fire, not a dead switch.
- [ ] **Pull a part out of the shelf.** The parts and the meter stand in
      a column with nothing behind them — no pane, no plate — six in the
      window at a time, "Parts" floating above. Pinch a part and move
      your hand: the moment it travels, the part is born AT YOUR
      FINGERTIPS and rides the hand; dropping it with copper ends near
      another part connects them. A tap on a part spawns nothing.
- [ ] **Every part comes out, whichever way you pull.** Straight out,
      sideways, downward: a drag that starts on a part is a pull, never
      a scroll. Nothing on the shelf reads your direction.
- [ ] **The column arrives (2026-09-06).** On entering the lab the
      parts column glides up into its place over about a second, the
      crown beside it rolling; then it is still. Under Reduce Motion it
      is simply there.
- [ ] **The crown scrolls (2026-09-06).** A knurled steel wheel stands
      edge-on in a gap of the hairline spine beside the column, at the
      window's middle. Pinch it and move your hand up: the parts move UP
      with your hand, exactly as far, and the later ones rise into the
      window with a tick per slot; the wheel turns as they move. Let go
      and it settles on a whole slot with a click. Flick it and it
      coasts. Roll past either end: it stretches and springs back. It
      must move on the FIRST pinch — the thumb it replaced never moved
      by hand at all (the gesture re-pressed it every frame). Zoom the
      bench in and check the crown still rides the hand one to one: it
      stands outside the zoom. VoiceOver reads the crown as "Parts, 1 to
      6 of 12" and pages it.
- [ ] **Parts fade at the window's ends** as you scroll, rather than
      popping into existence at the edge.
- [ ] **ONE TARGET AT EACH END (2026-08-11).** Pinch each end of a
      part ten times. **The same thing must happen all ten times.**
      Until this pass there were two grab targets at every end — a
      copper terminal and an orange grip, 3 cm apart with 2.6 cm hit
      radii that OVERLAPPED — so which one you got was decided by hit
      order. The orange grips are gone. Pinch the copper to wire;
      pinch the body to carry; there is nothing else there to hit.
- [ ] **Parts click nose to tail.** Release a part with a lead within
      ~6 cm of another part's lead: it must MOVE AND TURN so the two
      leads become one point, and read afterwards as a chain rather
      than two things near each other. Do it again against the edge of
      the build volume — there it must stay exactly where your hand
      left it, wired across the gap but NOT snapped, because a snap
      the wall would undo is a snap that lies.
- [ ] **A part hanging by one lead hangs from its JOINT (2026-08-29).**
      Carry it with your hand near the joint: the wired lead sits ON
      the joint and the body swings about it as you circle your hand.
      Pull further away: the body follows your hand while its wired
      lead keeps aiming back at the joint, the wire stretching between
      them — across the whole room if that is where you take it. **A
      wire never lets go because of distance (2026-09-05):** to undo a
      connection, pull the wire's end off its terminal, or cut it from
      the part's ring. A part wired at both ends, or at neither, must
      not swing — it moves rigidly.
- [ ] **A part pulled from the rack FOLLOWS your hand from the first
      frame (2026-08-29).** It is born at your fingertips and rides
      the hand all the way to the bench — it must never sit frozen at
      the rack until you let go.
- [ ] **PULL A LEAD (2026-08-11).** Pinch a copper lead and draw it
      across the bench: copper follows your hand. Bring it near
      another lead — it snaps to it and goes green. Let go: wired.
- [ ] **Let a lead go in open air.** It springs back. Nothing is made
      and nothing is destroyed.
- [ ] **Pull a lead onto one it is ALREADY joined to.** It must go RED
      and visibly recoil toward where it came from. No wire, no text.
      A silent no-op is the thing this replaced.
- [ ] **Carry a part up to its own net (2026-08-29).** Take a part
      that is already wired into a chain and park one of its leads
      near a DIFFERENT terminal of the same net — not one it shares a
      wire with. The ghost between them must be RED, not green, and
      letting go must thud with no wire made. Set a chained part back
      down in its own place: silence — that connection exists, and
      there is nothing to refuse.
- [ ] **Tap a terminal. NO WIRE MAY APPEAR.** A tap selects. Until
      this pass a tap could arm the wiring and — through the
      overlapping drag — complete a different wire in the same event.
- [ ] **Tap a wire. IT MUST NOT VANISH.** It used to delete on the
      first tap, with no confirmation, on a bench that persists.
- [ ] **VoiceOver: two terminal activations make one wire.** This is
      the only surviving tap-tap path, and it is deliberate — pulling
      a lead needs a sustained pinch that travels.
- [ ] **VoiceOver: activating a wire removes it (2026-08-29).** The
      pinch path deletes by pulling an end into open air, a gesture
      VoiceOver cannot make — so the wire's activation is the delete.
      A physical tap on a wire must still only select it.
- [ ] **UNPLUG A WIRE (2026-08-11).** Grab a wire near one end and
      pull: that end comes off into your hand and **the bulb goes
      out**, immediately, while you are still holding it. Land it on a
      third terminal — rewired. Land it back where it came from — the
      bulb lights again, and there must be exactly ONE wire, not two.
      Drop it in open air — gone.
- [ ] **Tap a lead: its whole net lights** — every terminal at that
      potential and every wire between them, in the module's green.
      Tap a lead three hops away from anything and confirm the far end
      lights too. Tap empty space: it goes out with the ring.
- [ ] **A wire is STRAIGHT at any span (2026-08-29).** Drag two parts
      far apart: the wire between them is a taut straight line — no
      droop — and the electron beads ride exactly that line. Push the
      parts together until they snap: the cable between the joined
      leads disappears entirely. A joint that snapped has no cable.
- [ ] **Grab the wire in the MIDDLE.** It must still take the nearer
      end, not do nothing. And a pinch at the joint must take the
      LEAD, not the wire — the bead is fatter than the cable and sits
      at its endpoint, which is the whole rule.
- [ ] **The shelf is fully in frame** from where you naturally stand,
      turned to face you, with every name and the "Parts" header
      readable against a real field of view.
- [ ] **Fill the bench to sixteen parts, then pull one more.** The
      source must FADE — the refusal that says nothing came out of
      here.
- [ ] **Pull a lead from one terminal to another** across a distance:
      a wire joins them.
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

## Light & Optics (2026-10-14)

Nothing here can be judged from the simulator, which has no walls (the
CLI stages one with `-roomWall 2.6`). Look at the room's walls first, so
ARKit has found them: the light lands only on walls it knows.

- [ ] **It opens alive.** A torch's white beam enters the prism and leaves
      as a spectrum straight ahead, landing on the wall in front of you as
      a row of colours, violet bent furthest. The green laser turns off the
      mirror into the end of the glass bar, zig-zags inside it without
      leaking out of the sides, and leaves a green spot on the wall.
- [ ] **The beams read.** A millimetre core with a soft glow, at the house
      dimming (0.35), in a bright room and a dim one. Judge: do they hold
      against a sunlit wall, or does the lab need its own dimming (the one
      exception the atmosphere test allows is already Orbital's)?
- [ ] **Carry anything.** A mirror, the prism, the bar, either light: it
      comes with your hand and the light re-traces as you move it, with no
      stutter. Two at once, one in each hand.
- [ ] **The laser points where you point.** Pick it up: the beam goes
      from your eyes through your hand. Sweep it across the walls.
- [ ] **Turn a piece by its bead.** Tap the mirror: its ring opens and a
      bead stands out along the way it faces. Move the bead and the mirror
      turns to face it. The prism's bead stays level — it turns about the
      vertical only. Judge the biggest risk in the lab: does a bead feel
      like turning a thing, or like a fiddly handle?
- [ ] **Least deviation, by hand.** Turn the prism slowly by its bead:
      the spectrum on the wall swings one way, stops, and comes back. More
      › Values shows Deviation meeting Least deviation at the turn.
- [ ] **The lens.** Pull a lens from the well, set the torch to Open (its
      ring), and put the lens in the broad beam: the rays cross near
      15 cm behind it, the rim ones a little short of the middle ones
      (spherical aberration), and the colours a little apart.
- [ ] **More.** Weak reflections shows the partial reflections every glass
      face makes (15 % at the prism's first face); Angles draws each
      surface's normal; Glass › Crown narrows the spectrum about three
      times; Clear all asks first and leaves the two lights.
- [ ] **The home.** Light stands in the middle of the arc between
      Magnetism and Projectiles; its emblem is a prism fanning a beam into
      a spectrum, rocking through least deviation.

## Magnetism

### The pickup coil (2026-10-15)

- [ ] **The room opens without a coil.** Pull one from the well above the
      magnet's: a copper coil on a graphite bobbin, its LED dark.
- [ ] **Push a magnet through it briskly**: the LED flashes red as the
      north pole goes in and green as it comes out (or the reverse,
      pushed south first), with a soft glow and a tint on the copper.
      Slowly, nothing: the LED needs its 1.8 V. Judge: does the flash read
      from where you stand, and does the coil look like a real one up
      close?
- [ ] **Hold the magnet still inside it**: dark. Move the coil over a
      still magnet instead: it lights just the same (relative motion).
- [ ] **Ring › Turns** to 1000 and the same push no longer lights it;
      4000 again and it does. **Turn** stands the bore toward you.
      (⟳ 2026-10-17: now 2500 / 5000 / 10 000 — see below.)
- [ ] **More › Values** with the coil selected: the linkage, ε = −dΛ/dt
      swinging through a pass, the LED current and the winding's ~490 Ω.
      (⟳ 2026-10-17: ~1230 Ω at 10 000 turns of 0.25 mm.)

### ⟳ 2026-10-17 — "it didn't seem to work": the full winding and the sleeve

- [ ] **A gentle push lights it now.** Carry the magnet through at the pace
      you would guide it into a real coil — about a third of a metre a
      second. The LED should glow plainly, red one way and green the other.
      At 4000 turns it needed more than twice that, and a careful push left
      it dark. Creeping through, it should still stay dark.
- [ ] **Bring the magnet in crosswise.** Hold it across the bore and carry
      it at the mouth. As its end reaches the mouth it should swing round to
      lie along the bore, keeping whichever pole already led, and slide
      through the middle rather than through the winding. Judge: does the
      swing read as the bore taking it, or as the magnet being yanked? Is a
      sixth of a second too quick, or too slow at a brisk push?
- [ ] **Hold the magnet beside the coil, not at its mouth.** It must keep
      its aim; only the mouth turns it.
- [ ] **Pull it out sideways from inside.** It should leave the bore
      steadily, never in a jump.
- [ ] **Ring › Turns** to 2500: the same gentle push leaves it dark,
      because thicker wire of the same copper makes a quarter of the EMF.
      10 000 again and it lights.

- [ ] **THE FIELD LINES ARE PINK NOW, AND THIS IS THE JUDGEMENT CALL.**
      ⟳ 2026-08-26: they were a hardcoded lavender, ΔE 46 from the accent
      on every plate in the lab; they now derive from `magnetismAccent`
      the way Electric Fields' lines derive from its own. The measurements
      all improved (ΔE 58 from the N pole, 73 from S, against lavender's
      31 from S). **What a simulator frame cannot tell you is how a room
      filled with hot pink feels through passthrough** — that is what this
      step is for. Judge: do the loops still read as *field* rather than
      as decoration, and can you still tell a line from the red N pole it
      leaves? If it is too much, the fix is NOT to hand-mix a paler pink
      (`DesignTokens` forbids deriving-by-eye) — it is to move the accent
      itself, and the whole lab with it.
- [ ] **Nothing but the magnets is in the room.** Bar magnets and the
      hand compass — no coil, no cable, and ⟳ **no compass grid**: the
      245-needle lattice came out with its bank plate, and the bank's
      other four switches are in More now.
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
  - [ ] ⟳ **Draw the strength handle out and the loop COUNT changes** — a
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

### More, and the strength handle

- [ ] **More holds the four switches**: Magnets move, Field lines, Hand
      compass, Earth's field. Earth's field greys out while the compass
      is off.
- [ ] **"Magnets move" is the physics switch.** Bring two magnets
      close, switch it off: they must stop dead and hold. Switch it on:
      they resume closing.
- [ ] The others only change what is DRAWN — hiding the field lines
      must not nudge a magnet.
- [ ] **Tap a magnet: Flip poles, Delete, and a handle under it.**
      Draw the handle out toward your right: the loops multiply and
      reach further; push it back: they thin. With two magnets snapped
      nose to tail, the handle is still in the open, not buried in the
      partner.
- [ ] **Reset restores the defaults**, and the magnets come back free.

## Electric Fields

The room holds the charges, the capacitor and two wells; the layers, ΔV,
B, Deflect shot and Clear all are in More (2026-10-14). A charge's sign
and size are the charge's own, so **this section is the only place they
can be tested at all.**

- [ ] **Three mouths: Charge +, Charge − and Test charge.** Pull each:
      the new charge or probe is IN YOUR HAND and STAYS there all the
      way in. The charges come out the sign their previews show; the test
      charge comes out positive. (⟳ 2026-10-16: the negative mouth is new,
      and the test charge's mouth moved one pitch down to make room.)
- [ ] **Tap a charge → its ring: Flip, Delete, and a handle on its
      surface.** Flip: the sphere turns blue with a −, and the field
      lines reverse at once. Pull the handle outward: the sphere SWELLS
      under it and the field strengthens live; push it in and it
      shrinks. The handle stays on the surface the whole way.
- [ ] **Tap the probe → the same ring at its scale.** Flip turns it
      round mid-flight; its handle grows it from 1 to 50 nC.
- [ ] **In More, flick each switch.** Capacitor makes the plates ARRIVE
      and wakes Plate voltage ΔV and Deflect shot; Uniform B wakes its
      own slider. Off, each dependent control greys out.
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
      trail that visibly CLOSES on its own tail. Flip it and throw
      again: it winds the other way.
  - [ ] Grab the probe again mid-flight: the trail clears.
- [ ] **Pinch a charge that is between the capacitor plates.** It must
      be grabbable through the plates' 26 cm collision spheres.
- [ ] Drag a charge: the field lines re-trace and follow, sticking to
      your hand rather than lagging visibly.
- [ ] **Clear all, in More, arms first** ("Tap again"), then empties
      the room; the switches stay as they were.
- [ ] **Two-hand pinch to 4×.** The field grows; the wells do NOT, and
      stay reachable. And per the same-object rule: a charge in each
      hand moves two charges, resizes nothing.

### Equipotential shells (2026-10-15)

- [ ] **The room opens without them.** More › Equipotentials: four glass
      shells round each charge, red round +, blue round −, closer
      together near the charges where the field is strong. No flat pane
      between the two: the 0 V surface of an equal pair is an infinite
      plane, and a surface the sampling box would cut is not drawn.
- [ ] **Pull one charge's handle out** (unequal charges): a faint white
      0 V sphere closes round the WEAKER charge. Judge: is it visible
      without being a fog?
- [ ] **Drag a charge with the shells on.** ⟳ 2026-10-16, after "it's
      kind of laggy": they should follow smoothly, slightly faceted while
      the hand moves (the coarse grid) and smoothing a quarter-second
      after it stops (the fine one). Judge both: is the drag smooth now,
      and is the coarse look acceptable while it moves? (A lone charge's
      shells move rigidly with it, exactly.)
- [ ] **Frame rate with the shells on and the room still.** Three shells
      per sign now, not four: the outermost, largest pair is gone, and with
      it most of the overdraw. If it still drops frames standing close,
      the next lever is opacity, or culling each shell's far half.
- [ ] **With field lines on too**, each line glints white where it
      crosses a shell's silhouette — the glass's rim catching the line.
      Judge: polish or noise? If noise, the lever is the shells'
      opacity, not the lines.
- [ ] **Look from beside and from above.** Nested shells all show, none
      hides another (no depth writes), and the frame rate holds: the
      shells are at most 60k triangles, meshed off the main thread.

## Projectiles — the one that is 1:1 with your room

### ⟳ 2026-10-17 — minimal: the Trajectory and the Numbers wait in More

- [ ] **The quiet room.** Launcher, a smaller bead on its thin shaft, the
      waiting ball, the hoop well. No arc, no labels. Does it still say
      "launcher" without the arc? Is the bead's shaft enough to read the
      speed by?
- [ ] **Hold the bead.** Its reading, "45° · 6.0 m/s", appears beside it
      while you hold it and goes when you let go, with Numbers off.
- [ ] **More › Trajectory** draws the arc with its apex and landing marks;
      **More › Numbers** adds every label and callout. Each alone is a clean
      picture.
- [ ] **The strobe.** Throw twice: the first throw's dots stay until the
      second ball leaves your hand, then shrink away. Pause: nothing shrinks.
- [ ] **A hoop.** Tap a hoop with Trajectory off: its two arcs still show.

### ⟳ 2026-10-17 — throwing is the main act

- [ ] **The room opens quiet.** No welcome shot: the launcher stands still,
      and a golf ball waits at chest height on your left (the ball well's
      mouth, "Add ball"). Is it in easy reach? It is about 1.1 m from your
      eyes — a lean from the left shoulder — because the house rules keep it
      left of the launcher's line and within 48° of straight ahead. If it is
      too far, say so: moving the launcher right is the next lever.
- [ ] **Take it and throw it.** Pinch the waiting ball, swing, let go. The
      mouth is full again at once. Throw ten times at your real wall, hard and
      soft: **do the balls leave as hard as you threw them?** The release now
      reads the hand's fastest 50 ms just before the pinch was reported open,
      not the average over the slowing follow-through. A throw that goes
      FARTHER than you meant is as much a failure as one that drops short.
- [ ] **The waiting ball is the ball you will throw.** Open the launcher's
      ring › Balls and pick the basketball: the token in the mouth wears its
      skin. It never looks like the orange aim bead.
- [ ] **Your throw, read out.** Where the ball left your hand, "32° · 7.4
      m/s" hangs under a dot while the ball flies and rolls, then fades. Is it
      in a place you look? The readout riding the ball is a different number
      (the ball now, not the throw then). More › Values shows Release speed
      and Release angle.
- [ ] **A throw's arc.** The strobe dots trace the parabola you threw, a
      fifteenth of a second apart.

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
- [ ] Drag the launcher anywhere; pinch its bead to aim and pull it
      out or in to set the speed; the predicted arc updates as you pull.
      The bead never leaves its 0.36–0.80 m band, however far the hand
      goes.
- [ ] The ball fan opens off the launcher's Balls petal, and choosing a
      ball changes the flight.
- [ ] **Two-handed pinch does NOTHING here.** Projectiles is
      permanently excluded from scaling.
- [ ] **The balls read as crafted, not matte** — check a ball in flight
      and one at rest against passthrough, and that the orange aim bead
      still reads as the LIT one of the pair.

### The wells

- [ ] **Fire a dozen shots, sweep the launcher around, throw by hand.**
      Nothing should ever hit a well or pass through one.
- [ ] **They do not ride the launcher.** Carry it across the room: the
      wells stay where they are.
- [ ] **Reset makes the room real again.** Switch Walls bounce off in
      More, press Reset: Walls bounce must come back on.

## Pendulums

### Coupled pendulums (2026-10-14)

- [ ] **More › Coupled pair** hangs two pendulums and a steel spring to
      the right of the cradle, the outer one already pulled back. Watch for a
      minute: the swing passes wholly to the inner bob, stops the outer, and
      comes back, about every 13 seconds. The cradle beside it is
      undisturbed.
- [ ] **The spring reads as a spring**: a fine steel helix from bob to
      bob, its coils spreading as it stretches. No flicker at the bobs'
      surfaces.
- [ ] **Swing a coupled bob across the spring** (toward or away from you)
      instead of along it: almost nothing passes across. That is the 3-D
      result a one-dimensional model cannot show.
- [ ] **Couple two of your own.** Pull two pendulums from the well about
      half a metre apart; tap one, Couple; the spring appears between them.
      Uncouple (scissors) takes it away. A cradle bob never offers Couple.
- [ ] **The Spring slider**: stiffer and the beat quickens. More ›
      Values gives ω₁, ω₂ and the beat period for an identical pair.
- [ ] **Hold one coupled bob still**: the other is pulled about by the
      spring alone, and the release preview (ghost) swings both.

- [ ] Grab a bob and throw it sideways → a true 3-D orbit, not a plane.
- [ ] ⟳ **A pendulum pulled from the well hangs STILL** — plumb, at
      rest, until your hand swings it. It used to be born mid-swing.
      (The Newton's cradle cold-open keeps its drawn-back first ball;
      that is the cradle's job, not the well's.)
- [ ] ⟳ **The cable cannot stretch.** Grab a bob and pull outward: the
      bob stays exactly one cable-length from the pivot, steering round
      the sphere under your hand. Only the length handle changes L.
- [ ] **Tap a bob: Mass, Delete, and a handle just past the bob, on the
      line of the cable.** Draw it down: the pendulum holds still, the
      cable pays out, the period tag climbs as √L, and letting go
      returns the swing without throwing it. Push it up: the cable
      shortens. On a double pendulum the handle hangs off the lower bob
      and still lengthens the cable.
  - [ ] Then grab a bob normally. It must be a bob grab, not a length
        edit.
- [ ] **Press a collar without moving it**: the same ring opens on its
      bob. Drag the collar: the rig re-hangs, and no ring opens.
- [ ] **No card floats over the selected bob** — the period tag is the
      one number in the room.
- [ ] **Pull a pendulum out of the spawn well; it hangs where you let
      go.**
  - [ ] Pull one out when the lab is already full: the well should go
        **dark and NOT pop**.
- [ ] ⟳ **There is no Foucault rig**, and no switch bank: Velocity,
      Force and Air resistance are in More. Switch Air resistance off
      and the swing stops decaying — the one switch here that changes
      the physics rather than the picture.
- [ ] **Nothing is inside the swing.** Let a bob swing wide, and pull one
      out to a 1.6 m cable. Neither well should be swept through.
- [ ] **Reset returns the three switches to their defaults.**

## Orbital Mechanics

### ⟳ 2026-10-17 — the trails are one mesh, written at most 30 times a second

- [ ] **Run the clock at 100× and watch Mercury.** Its trail must end on the
      planet with no gap and no visible kink where the thin leader carries
      it from the last written point. Then pause: the leader settles away.
- [ ] **Smoothness.** Is the lab smooth at 1× and at 100×, with every world
      trailing? Before this it held the main thread on the renderer for
      nearly half of every frame in the simulator.
- [ ] **The fade.** Does the tail still slide away smoothly at 1×? It now
      steps ten times a second.

### The quiet arrival (2026-08-29)

- [ ] **Open the module and touch nothing.** The sky is QUIET: planets,
      trails, labels — and no orbit ring, no data card, no vector
      arrows. All three of those ride the selection, and nothing is
      selected until you say "this one". No grid under the system and no
      drifting dots around it either (2026-09-04): the module's two
      analogies came out, and the black disc the grid stood in for went
      with them.
- [ ] **The system stays put (2026-09-06).** Run at 100× for a few
      minutes: the Sun wobbles a few millimetres about one spot and the
      whole orrery stays centred where it opened. It used to walk across
      the room at 16 m/s of simulated drift — 2.5 m of room per half hour
      at 100× — because the opening scene carried net momentum.

### The paths (2026-09-06)

- [ ] **Every body trails about three quarters of ITS OWN loop**, bright
      at the planet and fading to nothing at the tail — Mercury and
      Neptune alike. Neptune's fills over hours at 1× and minutes at
      100×; watch it fill and then hold its length.
- [ ] **A trail never freezes while its planet flies on.** Leave the lab
      running at 1× for two minutes: Mercury's and Venus's paths must
      still end ON the planet. (The old mesh stopped updating once it was
      full, and left a stationary arc behind.)
- [ ] **The path is the planet's colour**, the same as its sphere —
      Saturn gold, Uranus cyan, Neptune deep blue, the comet ice-white.
      No two bodies share one.
- [ ] **Same density at every clock speed and every zoom.** Compare
      Earth's path at 1× and at 100×, and at 1× and 9× zoom: the same
      smooth line, the same 1.2 mm thickness in the room, no polygon.
- [ ] **Reverse time eats the trail from the planet's end.** At −1× each
      path shortens toward its tail; rewind past the recording and the
      sky is clean.
- [ ] **Scrub the capsule (pause, pinch the reel):** each trail keeps
      its own length at the restored instant — except where the 30 s
      tape does not reach back a whole window, where it is as long as
      the recording.
- [ ] **Twin suns: both stars trail their mutual orbit.**

### The orbit ring

- [ ] **Tap a planet.** Two things must happen at once: its **control
      ring** unfolds (mass bead, delete petal) AND its **orbit ring**
      appears — a conic drawn around the Sun, passing through the planet,
      with a bead at each end. (And the data card and the arrows arrive
      with it — the room answering the tap. The Kepler sweep waits
      behind the Show tab, off until asked for.)
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
- [ ] **Let go, and watch.** The planet stays on the orbit you drew and
      the beads hold still. Any creep on an undisturbed orbit is
      integrator error, and the suite pins it below 0.05″ per orbit
      (2026-09-06: the old integrator walked Mercury's beads 19″ per
      orbit at 1× and 119″ at 5×, backwards, while this line called it
      "real Newtonian precession").
- [ ] **Make the perturbation you can see.** Pull a world from the well
      near Earth's orbit, open its ring and take its mass bead to 400
      Earths, then run at 20×: Earth's ring walks FORWARD and its trail
      departs the ring — precession and perturbation, both Newtonian,
      both real. For the real planets alone, ring and trail lie on each
      other: the other planets move Earth by kilometres, far under a
      millimetre of room.
- [ ] **The ring is the same thickness on Mercury and on Neptune, at
      1× and at 9×** (2026-09-06). It used to be a hairline on Mercury
      and a 13 cm hose on Neptune.
- [ ] **No shape pop while dragging a bead.** The ring used to snap
      between eccentricity buckets of 0.03 mid-drag.
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
  - [ ] The dimming shell is outside the orrery, not cutting through it.
- [ ] **A scale readout appears beside the clock** once you are off 1×.
- [ ] **Press Reset: the view returns to 1× and untwisted.**

### The panel emptied

- [ ] **The Show tab on your left** (2026-09-04): one machined tab
      reading "v F" (or "off"). Pinch it and five plates unfold ABOVE
      it — velocity, acceleration, force, Kepler sweep, Lagrange points
      — none of them touching the tab or each other.
- [ ] **The G rail at the foot of the fore column**, under Worlds and
      Twin suns. Drag its bead: orbits speed up and slow down live.
      Nothing stands on the rail and its readout is not inside anything.
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
      popping when it refuses. The fan offers nine worlds: the Moon left
      it on 2026-09-06 (at 0.5 m/AU a bound Moon sits inside Earth's own
      drawn sphere, and the preset merged into Earth on its first frame).
- [ ] **Trails no longer hitch** when several bodies' trails rebuild at
      once — they are ring buffers rewritten in place now, not meshes.

### Still true from before

- [ ] Crown opens toward blackness (`.progressive` immersion).
- [ ] Grab a planet: it freezes and shows the orbit it would take if
      released now. **Let go with a still hand and it takes the circular
      orbit at that radius** (2026-09-06: before this a still hand
      released it at rest and it fell into the Sun, and orbit needed a
      throw of exactly 0.35 m/s exactly along the orbit). Toss it gently
      sideways: an ellipse. Toss it hard: it escapes. The ghost path
      while you hold it shows exactly what you will get.
- [ ] Pull a world from the well and let go WITHOUT moving your hand: it
      holds a circular orbit.
- [ ] The clock bank changes time scale and reads back which is on.

## The window is a title bar

- [ ] The window shows a title bar and nothing else — no cards, no
      dropdowns, no scroll.
- [ ] Below it, one thing ever appears, and only while the immersive
      space is CLOSED: **Show in room**. No hint, no card, nothing
      written under any module's title (2026-09-04).
- [ ] The bar does not truncate the longest names. **Orbital Mechanics**
      and **Projectile Motion** (17 characters each, one more than Circuit
      Workshop) at default and at the largest accessibility text size.
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
- [ ] **Electric Fields — Clear all**, at the base of the well column on
      the left, at the same height and x as Circuit Workshop's Clear
      (2026-08-29). Dim when there are no charges, and a tap on it
      while dim must fall through.
- [ ] **Circuit Workshop — Clear bench**, on the bench's far left flank.
- [ ] **Orbital Mechanics — Twin suns** and **Worlds**, below the clock bank.

**The confirmation, on both Clear plates that have one:**

- [ ] First tap ARMS: the lamp lights and the nameplate becomes
      "Tap again". It does not clear.
- [ ] Wait ~5 seconds without touching it — it disarms itself.
- [ ] Arm it, then Reset from the title bar. **Nothing may still be
      armed.**
- [ ] Arm the Circuits plate, force-quit, relaunch: the bench is still
      there.

### The worlds fan — ten discs, the widest in the app

- [ ] Tap **Worlds** in Orbital Mechanics. The fan opens ABOVE the system.
- [ ] All ten labels are readable and none overlaps its neighbour.
- [ ] Tapping a disc adds that world and folds the fan.

### The readouts that came out of the dropdowns

- [ ] **Pendulums** — tap a bob; the card appears above it with L, T, θ,
      v. Grab that same bob: the card must not steal the grab.
- [ ] **Orbital Mechanics** — tap a planet; its elements and energies appear.
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

*(Deleted 2026-08-09 with the experiments system. There are no authored
steps, no per-lab progress and no tally anywhere in the app.)*

## Phase 1 of the 2026-08-07 audit arc — the front door

All of this is new surface, and none of it can be judged from the
simulator. Work it in this order; the first two are the ones that
decide whether the phase was worth doing.

- [ ] **⟳⟳ A TAP SENDS A LAB TO THE PAD.** No argument needed — the
      gallery is what you see at launch. Aim at any miniature and pinch
      it once. **What CORRECT looks like:** it lifts off its mount and
      flies to the cradle front and centre over about half a second, the
      three latch fingers fold down over it, and Load Module appears
      above it naming that lab. Pinch that to enter. **What to watch
      for:** (a) the flight has to be FOLLOWABLE — if you lose track of
      where your lab went, it is too fast; (b) tapping a second lab must
      send the first one home, not stack them; (c) tapping the lab
      already on the pad must do nothing at all; (d) the latches must
      close as it ARRIVES, not as it sets off.

      *(This replaced the ENTER plaque on 2026-08-09. Nothing stands on
      the terraces now except the mounts and the miniatures — if you see
      a small machined slab reading ENTER, you are on an old build.)*

- [ ] **⟳ The caption stack.** Under each miniature: its name, and on
      the exhibit you are facing, a one-line promise. **What to watch
      for:** both billboard, so they can be geometrically clear and
      still LOOK piled up. This was a stack of three until the plaque
      came off, and the plaque was the piece that made it hard.

- [ ] **The promise line.** Turn your head slowly along the crescent.
      One sentence should fade in under the exhibit you are facing and
      out again as you move on — never two at once, never flickering as
      you sweep past.

- [ ] **THE LAUNCH (2026-08-22).** Cold-start the app. It must go
      STRAIGHT into the Gallery with the arrival choreography — no flat
      window at any point, not even a flash. Expect a beat of plain
      passthrough first while the prop cache warms; that is
      `PlaygroundSpaceView.ready` doing its job, and it is the wait that
      used to happen behind the front door. What must NOT happen is the
      gallery building cold: if the terraces pop in piecemeal or the
      first seconds judder, the gate is not holding.

- [ ] **The window is not blank.** Get the hub window back (Digital
      Crown, or "Put the Gallery away" then reopen). It should show the
      catalog — each lab's name and its promise line. Tapping a row
      there must still open its lab — that is the accessibility path,
      and nothing reaches it in normal use now that the app launches
      into the room.
  - [ ] **AND THE LAB IT OPENS MUST FADE IN, not cut.** ⟳ 2026-08-26:
        the catalog row assigned `activeModuleID` directly instead of
        going through `AppModel.go(to:)`, so entering a lab this way
        skipped the departure dissolve every other route runs. It is
        `private(set)` now and the compiler enforces the door, but
        **no automated test can watch a fade from inside an immersive
        space** — XCUITest cannot see it and `simctl` cannot pinch. Go
        lab → window → different lab, and watch the handover: the old
        apparatus should fade, your real room should be briefly just
        your room, then the new lab fades up. A hard cut is the bug.
  - [ ] **The door button itself.** Same reason — `DECISIONS.md`
        2026-08-23 records that this control cannot be covered by any
        automated test. Press it, twice, from both the gallery and a
        lab. Exactly one window, exactly one lab, no catalog left
        standing behind the module.

- [ ] **The way out, and back.** In that window, "Put the Gallery away"
      should close the immersive space and leave you with your room and
      the window. Then "Enter the Gallery" brings it back — that button
      is no longer a front door, it is the ONLY way to undo the button
      above, so it has to work.

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

- [ ] **⟳⟳ NO CARD OF WORDS STANDS IN A LAB.** Enter each of the six.
      **What CORRECT looks like:** the apparatus, and nothing written
      floating in front of it — no teach paragraph, no running
      commentary, and nothing under the title bar either (the last
      sentence a lab spoke went on 2026-09-04).
      **What to watch for:** the small backed readouts on the apparatus
      itself (values, switch labels, rack names) are NOT this and must
      still be there — if those have gone, too much was deleted.

      *(An in-room teach card shipped 2026-08-08 and Circuits' insight
      card with it; both were cut 2026-08-09 for covering the bench they
      described. If you see a dark paragraph over the apparatus you are
      on an old build.)*

- [ ] **⟳ Nothing hangs at the pad's rim.** The "Or carry a lab to the
      pad" card was deleted 2026-08-09 — the tap demonstrates the
      gesture instead. Carry a lab to the pad by hand and confirm the
      drag sweeps through clean air: that card used to sit inside the
      volume the carry passes through, so the sentence describing the
      gesture stood in the way of performing it.

- [ ] **⟳⟳ The three platforms, which are modelled now.** Stand close
      enough to read them. **The terraces** are milled benches with
      T-slots running their length and a lit channel along the front
      rail — check the slots CROSS the joins between tiles, because
      hiding those joins is half of why they are there. **The mounts**
      should read as three-ball kinematic mounts: a base, a smaller top
      plate, and three bright steel balls standing OUTSIDE the plate's
      rim. **The pad** is a hexagonal cradle with a machined pocket and
      three latch fingers. **What to watch for:** the terraces must not
      have got louder than the physics standing on them — they measured
      identical in median brightness to the plain slabs they replaced,
      but the new specular highlights are real and only a headset can
      say whether they pull the eye.

## Phase 2 — Orbital Mechanics folds, and the room stands back

**This is the owner's own complaint, so it is a judgement call before it
is a check.** Everything here is `-openModule gravitylab` unless said
otherwise.

- [ ] **⟳⟳ IS IT CALMER?** The plain question, first, before any of the
      detail. Standing objects went from about eighteen to nine: the
      seven-plate bank is two, the six-disc clock is one tab, and two new
      tabs hold what came off. If it does not read as a quieter room,
      say so and the rest of this section does not matter.

- [ ] **The one tab at the deep flank** (it was three objects — two
      plates and two tabs — until 2026-09-04). A small machined tab
      reading "Show" with its live summary beneath — "off", or
      "v F · sweep, Lagrange" — the world well 7 cm under it, and its
      five plates unfolding ABOVE it when pinched. It stands 20 cm nearer
      than the old bank did, because the old bank was a step away.
      **The summary is the whole argument for folding**: if you cannot
      tell what is switched on without opening the tab, this design has
      failed and the plates should come back out.

- [ ] **The clock tab.** At the head of the fore column off your LEFT
      shoulder (moved from the right flank 2026-08-29), reading
      "Clock · 5×". Pinch it: the six-disc fan should unfold ABOVE the
      tab, and the number on the tab should track whichever disc you
      pick. Pinch again to fold. **Then check the tab still tells you
      the speed with the fan closed** — that is the readout the six
      discs used to be. And check the fore column does not stand in
      front of the deep column: from where you naturally stand, the
      tabs, sub-banks and G rail at the system's flank must all be
      visible past it.

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

- [ ] **Nothing lost that was physics.** Kepler sweep, Lagrange points,
      velocity, acceleration and force must all still work from behind
      the Show tab. The grid and the field flow ARE gone (2026-09-04) —
      deliberately, as the module's two disclosed analogies — so their
      absence is correct, not a regression.

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

- [ ] **⟳ Orbital Mechanics' clock bank is now about 40 cm wide, not 25.**
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
- [ ] **Orbital Mechanics' two clocks.** Set the time picker to −1× or 20×,
      let it run, then pause and scrub. The picker sets how time runs;
      the rail asks what already happened. Changing the picker while
      scrubbed should take effect only on resume. Judge whether the two
      ever read as fighting each other.
- [ ] **Read a scrubbed instant.** With the room frozen in its past,
      open the Physics box. It should show the physics of the instant on
      screen, not of the live present.
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
      vector layers in Pendulums and Orbital Mechanics: arrows fade in and
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
- [ ] ⟳ **Every CONTROL is on your LEFT** (banks 2026-08-04; everything
      else 2026-08-29). Walk all six rooms: every plate, tab, rail,
      picker and verb stands off the left shoulder, so the hand that
      learns one module has learned them all. The one deliberate
      exception is Circuit Workshop's parts rack — a shelf you reach
      into, not a button, and its right-side reach analysis stands.
- [ ] **Every rail in the app hangs under the thing it adjusts.**
- [ ] **Every ring folds in place.**
- [ ] **System Reduce Motion** (Settings ▸ Accessibility): the hub's
      idle life stills, and the door signs' rule stops shimmering. (The
      electron and the ball this line used to name were deleted on
      2026-08-04; the signs are static lockups now.)
- [ ] **Every lab's first-run hint** appears once and stays dismissed —
      under the module's title bar, closed by its ✕ (the in-room card of
      2026-08-08 was cut on 2026-08-09, and from 2026-09-01 the window
      shows the hint whether or not the room is open, because the app
      now launches into the room and a hint shown only while it is shut
      had no readers). Check it stands ABOVE the apparatus band, never
      through it.
- [ ] **The Physics box** reads sane numbers and units in each lab.
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

- [ ] **THE PHYSICS BOX (2026-09-05).** In any lab, press ƒ in the title
      bar: a card unfolds at the upper left of the apparatus with the
      lab's live numbers, monospaced, updating as things move, and
      beside it, toward the room's centre, one rail per quantity you can
      set — Fields: plate voltage and uniform B; Magnetism: the magnet's moment;
      Projectiles: g and wind; Orbital Mechanics: G and the star's mass;
      Circuits and Pendulums: numbers only. Drag a bead: the number on
      the card and the apparatus change together (the capacitor's own ΔV
      rail moves too — same value, two handles). Press ƒ again: it folds.
      It must never catch a pinch aimed at the apparatus behind it.
- [ ] **Electric Fields opens with NO test charge.** The dipole stands
      alone; pull a probe from the Test charge well and it rides
      the field from your hand. Reset leaves it probe-free too.
- [ ] **Both ampersands wear their keyline on the FRONT.** "& Magnetism"
      and "& Energy": the bright chamfer band runs round every edge of
      the & facing you, exactly as on the letters beside it — not only
      round its silhouette from behind.
- [ ] **THE EMBLEMS (2026-09-05).** Pinch the bead: the ring of six accent
      discs fans out as before, and each disc holds the lab's emblem —
      one bold object, few parts, fat lines: two big charges with seven
      field lines and riding arrowheads; a copper loop with a big
      battery and a lit bulb, charge going round; one bar magnet turning
      slowly with eight field loops turning with it; a launcher on a
      puck, one fat arc, a ball and a hoop; one big brass bob on a beam,
      swinging in a slow ellipse; a star with one world on one orbit.
      Each must be recognisable at arm's length without its name.
- [ ] **The same emblems stand on the gallery's terraces,** where they
      read as objects rather than diagrams: nothing thinner than a cable
      anywhere in them.
- [ ] **The gyroscope bead and the modelled miniatures** at real
      passthrough contrast, in a bright room and a dim one.
- [ ] **The wordmark.** If the white letters read as faint against
      their glass on a real wall too, that is a real finding about the one
      piece of type every visitor sees first.

### Accessibility

- [ ] **VoiceOver over a `Callout`.** Every tethered live number — the
      compass µT, catch speed, sweep area, prediction countdown —
      carries a NAME and a VALUE. Check both are spoken, and that the
      value tracks as it changes.
- [ ] **Reduce Motion inside a lab**, not just in the hub. The palette
      bead must stop breathing. It must still UNFOLD when pinched.

### The catalog, and the numbers

- [ ] **Open the flat catalog.** Two domains, seven labs, and nothing that
      counts your progress. (This said "a tally and ONE next step —
      complete that experiment" until 2026-08-09; the experiments system
      was deleted and the check outlived it.)
- [ ] **Open the Physics box in three different labs and compare
      them.** Every row should read in one voice.
- [ ] **Orbital Mechanics at 100× clock, watching the data card.** ν reads to
      a tenth of a degree and the card should feel steadier, not
      coarser.

### Leaks — the only test for these is patience

- [ ] **Enter and leave eight or ten labs in a row, then use one.**
      Nothing should feel heavier at the tenth lab than at the first.

## The 2026-08-09 cleanup — what the suites cannot see

Every item here exists because a green test proved the arithmetic and
proves nothing about the room.

### The cut test (the whole point of the atmosphere change)

- [ ] **Enter all seven labs in sequence, as a demo would cut between
      them.** The room's brightness should not change from lab to lab.
      Five now open at 0.35; Orbital Mechanics alone goes to 0.85 and that
      one step should read as *entering space*, not as a bug.

### Magnetism's field lines — the riskiest change in the pass

- [ ] **Look along a loop where it wraps a pole.** The polylines are
      decimated before they become tubes, keeping points by curvature.
      Faceting, if it exists, shows up here first and at close range —
      the simulator's resolution cannot settle it.
- [ ] **Slide the strength bead from one end to the other.** Loop count
      should still change with it, and the redraw should not stutter:
      the retrace is now gated on 2 mm / ~1°, so a settling bench stops
      re-tracing instead of retracing every frame.

### The labels that moved onto the house plate

- [ ] **Pendulums: select ONE pendulum** (the tag is suppressed when
      pivots crowd, so the default cradle shows none). "T = … s" should
      wear a dark plate and sit centred on its anchor, not hang from its
      baseline.
- [ ] **Orbital Mechanics with the Lagrange layer on.** Planet names and
      Lagrange markers should now wear the same plate. They were two
      different treatments a few centimetres apart.

### Reach — measured now, but a metre is a body, not a number

- [ ] **Orbital Mechanics: reach for Binary and Worlds without stepping.**
      They came in from 1.36 m on 2026-08-09 and moved to the left
      fore column on 2026-08-29 — closer still.
- [ ] **And the clock tab, which was a third case at 1.33 m.** It
      sits ABOVE the verbs on the same x, which is also what the verbs'
      own comment always claimed ("under the clock bank, on the same
      flank") and what the first version of this fix accidentally
      broke by putting them side by side. Open the fan and check it
      does not reach into the orrery.

### Corner radii and nameplate sizes

- [ ] **Settings, a module window and the flat catalog, in one
      sitting.** Four radii are now named steps — window 28,
      section 20, card 14, chip 9 — and two near-duplicate pairs were
      collapsed (a hint card 12 → 14, a chip 8 → 9). Sub-2pt each;
      the question is whether the four steps read as a scale.
- [ ] **Any bank plate, well mouth, picker disc, rail bead and the
      multimeter, in one room.** Nine nameplate sizes became two. The
      biggest single move is the palette's petal labels, 0.014 → 0.0104
      — about a quarter smaller.
- [ ] **Projectiles: reach every instrument on the wall.** It was
      rebuilt from two columns into one — ball well, worlds, g, wind,
      layers, top to bottom — because a second column beside the rails
      could not be both inside 1.25 m and inside 48° off axis at any
      depth. All five now measure 1.09–1.24 m.
- [ ] **And look at where the LAYERS bank ended up.** It is last in the
      column at y = 0.90, which is the one placement here chosen by
      arithmetic rather than by eye: the ball well's reach fails at the
      bottom of a column and the bank's does not, so they traded ends.
      A bank at knee height may read as an afterthought, or may be
      hidden behind real furniture — neither is visible in a synthetic
      simulator room.
- [ ] **Throw at each of the four walls with the wall layer on.** The
      whole instrument column moved 15 cm inboard, to 15 cm clear of the
      launcher's line. Confirm nothing gets shot.

### The home screen is the room now (2026-08-10)

- [ ] **Open the app and let the gallery come up.** The flat catalog
      shows first (it is the front door, and the way back if the gallery
      fails to open) and should put itself away once the terraces are
      in the room. Nothing should be parked behind the crescent.
- [ ] **Enter a lab, then leave it with the palette's Home petal.** The
      window should come back as the lab's title bar and go away again
      when you return to the gallery.
- [ ] **Close the gallery with the Digital Crown.** The window must
      come back. This is the one that matters: once it is dismissed,
      nothing but `PlaygroundSpaceView`'s onDisappear can bring it back,
      and if that ever breaks the app is left with no scene at all.
- [ ] **While the gallery is up, reopen the app from the Home View.**
      That is where "Put the Gallery away" lives now — the only
      `dismissImmersiveSpace` in the app, one deliberate step away
      rather than standing in front of the terraces.
- [ ] **Look at the utility bar under the wordmark.** Settings and About
      were behind the catalog window before and are now the home's only
      chrome. Confirm both still open.

### Prediction arc — unreachable from the CLI

- [ ] **Hold a planet and watch the ghost path.** It is cased now, the
      way Projectiles' predicted arc already was. It only draws while a
      body is held, so no screenshot could check it.
