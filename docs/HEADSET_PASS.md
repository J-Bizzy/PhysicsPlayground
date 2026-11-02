# Headset pass: the 1.0 release gate

One sitting, about an hour, with the owner driving. Work top to bottom,
since the first section needs a fresh install. Each box says what to do,
then what right looks like.

**Only a break blocks 1.0.** A break is something that doesn't answer, a
stuck object, a crash, a wrong number or word, or frames dropped at rest.
If something works but could feel better, put it under *Judge*; it goes
into 1.1. `ON_DEVICE_TESTS.md` has the detail behind every line, and its
⟳ 2026-11-02 sections match section 4.

## Before you start

- Delete the app from the headset. Run a Debug build from Xcode with
  `-frameLog 1` (Scheme › Run › Arguments), and keep the console open.
- Turn the volume up, and look at every wall once so the room is scanned.

## 1 · First launch

- [ ] The permission sheet asks for your hands and your room, each with
      its own sentence. Allow both.
- [ ] The music rises with half a second of empty room. Then the
      wordmark lands alone. Then the seven labs rise in left to right,
      with one soft tone as the last settles. It all takes about 3.5 s,
      and no "dropped" line comes after the arrival's clock starts.
- [ ] Pinch two portals in quick succession: you enter the first one only.

## 2 · The doors

- [ ] Enter a lab: its miniature swells, holds, then dissolves into the
      real lab. The room is never empty.
- [ ] Go Home, then lab to lab through the Lab list: the lab you leave
      stays where it was until the next one is up, then they cross-fade.
      The music runs straight through every door.
- [ ] **Cut test:** enter all seven in turn. The brightness changes only at
      Orbital Mechanics, which opens in Deep space, and it ramps rather
      than steps.
- [ ] More › Deep space: the stars come up over your room with no black
      frame, and the choice survives a relaunch.

## 3 · The seven labs

- [ ] **Projectiles.** Throw the waiting ball hard at a real wall ten
      times. It bounces *at* the wall and leaves as hard as you threw it,
      no farther and no shorter.
- [ ] Pull a hoop from its well and stand it across the room. Tap it ›
      Aim › Low arc, then Fire from the launcher's ring: the ball goes
      through with a chime. A ball thrown
      onto a table rests on it and rolls off the edge. A still hand
      catches; an open hand swats.
- [ ] **Circuit Workshop.** Tap the switch blade: the bulb lights as the
      blade lands, and goes out at once when you tap again.
- [ ] Pull a part off the shelf: it glows at your fingertips. Set it
      beside a lead: it leans in and glides home, and the two dots
      become one junction.
- [ ] Pull a lead to a terminal: it's wired. Tap a lead: its whole net
      lights. Pull a lead onto its own net: it recoils red.
- [ ] Open a resistor's ring: its bead clicks calmly from 10 Ω to 4.7 kΩ.
      Put the meter on A⎓ across the open switch: it reads the current.
- [ ] Pinch the turntable's rim to turn the circuit, and its deck to carry
      it. Clear the bench (two taps), then relaunch: the starter loop is
      back.
- [ ] **Orbital Mechanics.** Tap Earth: its ring appears. Pull the far
      bead: the ellipse stretches, and Earth keeps the orbit you drew.
- [ ] Earth's mass bead clicks, and the sphere swells with the number
      holding steady. Add a world from the well. Pinch More › Twin suns:
      every orbit answers. Zoom to about 4× with two hands and walk in:
      the labels hold their size.
- [ ] **Electric Fields.** Pull Charge + and Charge −: the lines redraw
      around your hand as you carry them. Flip a charge, and pull its
      bead to swell it.
- [ ] With More › Uniform B on, throw a test charge sideways: it circles.
      With the capacitor off, ΔV is grey and says "Needs the capacitor".
- [ ] **Magnetism.** Carry one bar toward the other: it swings round and
      snaps head-to-tail, the lines re-trace, and the compass follows.
- [ ] Pull a coil from the well (Add coil) and push a magnet briskly through it: the
      LED flashes red one way and green the other.
- [ ] **Pendulums.** Release the cradle: it clicks like steel. Draw a
      bob's cable handle down: the cable pays out.
- [ ] Flick a Double from the upper well: its motion is chaotic. More ›
      Coupled pair: in about 7 s the swing has passed wholly to the inner
      bob, and the cradle is undisturbed.
- [ ] **Light & Optics.** It opens alive: a spectrum on the wall ahead, the
      laser trapped in the bar, and a green spot on the wall.
- [ ] Carry a mirror and the prism: the light re-traces with no stutter.
      A held laser points from your eyes through your hand. A bead turns
      its piece. In Deep space the beams fade out with no hard cut.

## 4 · Every lab

- [ ] Every grab glows and ticks, and every release ticks (the turntable
      only ticks; it is too big to glow). A full well thuds.
- [ ] A deleted object fades rather than popping. Clear all, Clear the
      bench and Reset lab all say "Tap again" before they act.
- [ ] Go Home while still pinching a bob, a ball or a charge. Come back:
      nothing is stuck.
- [ ] **Time Capsule.** Pause: one reel appears. Pinch it: the tape draws
      out with "n s recorded". Scrub back: the room retraces. Resume: it
      runs from there, and nothing jumps.
- [ ] Every greyed control in More has a dim line under it saying why.
- [ ] At rest in every lab, the frame log reads about 11.1 ms median with
      0 long frames.

## 5 · Accessibility

- [ ] **VoiceOver:** double-tap an object in each lab and its ring opens.
      Values are spoken in words ("470 ohms").
- [ ] **Reduce Motion:** the labs don't rise on the home, the doors cut,
      and nothing leans or coasts.
- [ ] **Largest text:** the names in More wrap, and none ends in "…".
- [ ] If there's time, turn off both permissions in Settings › Privacy &
      Security and relaunch: every lab still opens and answers a pinch.

## Judge (a word each; these don't block)

- the 0.15 s fades;
- the switch's 0.12 s;
- the turntable's coast;
- the swelled miniature at a door;
- the readout card moving aside for a ring;
- whether the waiting ball is in easy reach;
- the beams against a sunlit wall;
- the pink field lines through passthrough;
- the music's level.

## Then

1. While you're set up, shoot the seven store screenshots listed in
   `APP_STORE.md` › Screenshot plan, staged with the scheme's arguments.
2. Send back each failed box in one line: the lab, what you did, and what
   happened.
3. Fix only those, then archive and upload.
