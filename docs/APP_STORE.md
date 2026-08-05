# App Store listing — Physics Playground

Draft copy and the screenshot plan. Everything here is checked against
what the app actually does; if a claim below stops being true, it is a
bug in the app or in this file and not a marketing decision.

**Character limits are App Store Connect's, and the counts are real** —
they were counted, not estimated.

---

## Name (30 max)

```
Physics Playground
```
*18 characters.* Matches `CFBundleDisplayName`.

## Subtitle (30 max)

```
Real physics, in your room
```
*26 characters.*

Alternates, all within limit:
- `Room-scale physics labs` (23)
- `Six labs. Real constants.` (25)
- `Experiments you can hold` (24)

## Promotional text (170 max, editable without review)

```
Six physics labs that stand in your actual room. Throw a pendulum bob, wire a live circuit, reshape a planet's orbit by hand — with the real equations underneath.
```
*162 characters.* The first draft came in at exactly 170 — the limit —
which is not a margin. App Store Connect counts an em dash and a curly
apostrophe as one character each, but a paste that converts either can
push a string over, so leave slack rather than discovering it in the web
form. This field can be changed at any time without
resubmitting, so it is the right place for anything seasonal or for
pointing at whatever is newest.

## Keywords (100 max, comma-separated)

```
stem,science,education,teacher,classroom,circuit,magnet,orbit,pendulum,gravity,simulator,lab,ar
```
*95 characters.*

Rules this follows, because they cost ranking if broken:
- **No word from the name or subtitle.** "physics", "real" and "room"
  are already indexed from those fields; repeating them wastes the
  budget.
- **Singular only.** The store matches plurals automatically.
- **No spaces after commas** — a space is a character.
- **No competitor names, no "app", no "vision pro".**

## Description (4000 max)

```
Physics Playground turns your room into a laboratory.

Six experiments stand at full size in the space around you. You don't
watch them — you reach in. Throw a pendulum bob and it swings from the
hand speed you gave it. Carry a bar magnet toward another and feel the
field reorganise. Grab a planet and hurl it out of orbit, then watch the
readout tell you it is never coming back.

THE PHYSICS IS REAL

No physics engine, no approximations for convenience. Every solver is
written from scratch in SI units with real constants, and uses the exact
closed-form solution wherever one exists: Kepler orbits from true orbital
elements, nodal analysis for circuits, the exact dipole field between
two bar magnets, r = mv/qB for a charge in a magnetic field. Nearly 350
tests run against the physics alone.

Where something has to be deliberately unphysical for you to see it, the
app says so on screen, next to the number. The magnetic field that visibly
bends a half-gram ball is about a thousand times the strongest magnet ever
built — and it tells you that, because a lab that hides its fictions is
teaching the wrong thing.

THE SIX LABS

Electric Fields — Pull charges out of a well and watch the field redraw
around them. Add parallel plates you carry by hand, switch on a uniform
magnetic field, and send a charged ball circling through it — the
cyclotron radius, drawn at full size in your room.

Circuit Workshop — Build from racks of real parts: batteries, resistors,
capacitors, inductors, motors, LEDs. Solved every frame. Probe it with a
multimeter, then switch on Electron View and shrink into the copper to
watch the drift velocity — which is millimetres per second, and is the
single most common misconception in introductory electricity.

Magnetism — Bar magnets that attract, repel and snap into alignment,
their looping field closing on itself in real time. Carry a compass
through it.

Projectile Motion — Throw anything. Real drag and restitution, gravity
from zero-g to Jupiter, and bounces off your actual walls, floor and
ceiling.

Pendulums — Full nonlinear swings, a Newton's cradle you can break apart
and rebuild, a double pendulum that never repeats itself, and a true
3-D orbit you throw a bob into above your own floor.

Gravity Lab — A solar system you can walk into. Tap a planet and its orbit
becomes a ring with a bead at each end; pull one and the orbit reshapes
under your hand. Split the star into a binary and watch every orbit answer
at once.

CONTROLS THAT ARE OBJECTS

There are no floating control panels. Switches are plates you press,
quantities are rails with a bead you slide, and new objects are pulled out
of wells with your hands. If you want to know what something does, look at
it.

A LAB NOTEBOOK

Capture a moment and it records exactly what the physics said at that
instant. Export the whole book as CSV or Markdown.

PRIVACY

No accounts, no analytics, no advertising, and no network code of any
kind. Nothing you do leaves your device.

Requires visionOS 26.0 or later.
```
*2,937 characters* of 4,000. Counted, not estimated.

**Do not keyword-stuff this field.** Apple indexes the name, subtitle and
keywords — not the description — so repetition here buys nothing and
reads badly.

## What's New (first release)

```
First release.
```

## Age rating

**4+.** No user-generated content, no web views, no purchases, no
contact between users, nothing to disclose.

## Privacy nutrition label

**Data Not Collected.** This is the whole answer, and it is checkable:
the app target and both packages contain no `URLSession`, no `URLRequest`
and no `Network` import, and there are no remote package dependencies.
Declare the one required-reason API already in `PrivacyInfo.xcprivacy`:
`NSPrivacyAccessedAPICategoryUserDefaults`, reason `CA92.1`.

## URLs

- **Privacy Policy** — `https://j-bizzy.github.io/PhysicsPlayground/PRIVACY.html`. **Required**; the app
  cannot be submitted without a reachable URL.
- **Support** — `https://j-bizzy.github.io/PhysicsPlayground/SUPPORT.html`. **Required.**
- **Marketing** — optional, skip it.

Both are served by GitHub Pages from the `docs/` folder of the public
repo `J-Bizzy/PhysicsPlayground` (its `_config.yml` and the two pages'
front matter exist for exactly this). That repo is a **subtree split**,
not the working repo: the local git root is the parent `VisionPro/`
directory, which holds sibling projects that must never be published,
so only this project's subtree goes out. To publish updates, from the
repo root:

```bash
git subtree split --prefix=PhysicsPlayground -b public-main
git push public public-main:main
git branch -D public-main
```

(`public` is the remote named for `J-Bizzy/PhysicsPlayground`.)

## App category

`INFOPLIST_KEY_LSApplicationCategoryType = public.app-category.education`
is set in the app target. In App Store Connect: primary **Education**,
secondary none.

---

# Screenshot plan

## The format constraint

visionOS store screenshots are **3840 × 2160**, which is exactly what
`xcrun simctl io <device> screenshot` produces. No resizing, no cropping —
a crop changes the pixel dimensions and will be rejected.

**That last point is the whole problem with shooting these in the
simulator**, and it is worth understanding before spending an evening on
it. The simulator renders from one fixed viewpoint in a fixed synthetic
room. You cannot step closer, crouch, or turn your head — so an apparatus
that sits low, like Gravity Lab's orrery, lands in the bottom third of a
mostly black frame, and there is no legal crop that fixes it.

**Take the store screenshots on device.** Stand where the composition is
best, then capture. Use the simulator commands below to *stage* each shot
— they put the app in exactly the right state — and treat the simulator
output as a reference for what should be on screen, not as the deliverable.

## Ordering

**These were shot before being ranked.** The first ordering in this file
was written from memory and was wrong twice — Gravity Lab is not the
strongest frame and Projectiles is much stronger than expected. What
follows is the order after actually looking.

The first two do almost all the work; most people never swipe past three.

| # | Shot | Verdict from the actual frame |
|---|---|---|
| 1 | **Projectile Motion** — staged volley, walls on | The best single frame the app produces. Arcs sweep the whole room and visibly bounce off the shelf and wall; `9.81 m/s²`, `1.9 m` and `5.0 m/s` are all legible; the world discs and the ball fan show it is an instrument and not a toy. It is the only shot that carries "in your room" AND "real physics" at once. |
| 2 | **Circuit Workshop — Electron View** | The most surprising image in the app: you are standing among copper conductors two metres thick with the electron bands crawling along them, under a glowing bulb reading `24 Ω`. Nothing else looks like this, which is exactly what a second screenshot is for. |
| 3 | **Electric Fields — lines + capacitor + B** | The densest "this is real physics" frame — field lines filling the room, the carried capacitor plates with their sign glyphs, the uniform B switched on. (Reframed 2026-08-05: the flux instrument this slot was built around left the app on 2026-08-03 — DECISIONS.md has the story.) Slightly busy, which is why it is third rather than first. |
| 4 | **Gravity Lab — binary star** | Conceptually the best story (two suns, every orbit reshaped) and the weakest *simulator* frame: the orrery sits low, so two-thirds of the image is black. **Shoot this one on device**, standing closer and looking down. |
| 5 | **Gravity Lab — the orbit ring** | Depth, for the person who has already decided to look: Earth's orbit as a ring in the room, apoapsis pulled out to 2.2× under a hand. The module's documented centrepiece. (Reframed 2026-08-05: the previous subject left the app on 2026-08-03 — DECISIONS.md has the story. If two Gravity frames read as repetitive against shot 4, the alternate is Magnetism's room-filling field lines — `-openModule magnetism`, defaults.) |
| 6 | **Home Screen** | Shows the scope — six labs behind two coloured doors, under the wordmark. A closer, not an opener: it is the least *spatial* frame, because nothing in it is an experiment. |

## Staging commands

Install once:

```bash
D=<device-udid>          # xcrun simctl list devices available | grep "Vision Pro"
APP=<DerivedData>/Build/Products/Debug-xrsimulator/PhysicsPlayground.app
xcrun simctl install $D "$APP"
```

Then, per shot — **terminate first**, or the arguments are ignored:

```bash
shot () {   # shot <name> <args...>
  local name=$1; shift
  xcrun simctl terminate $D j-bizzell.PhysicsPlayground 2>/dev/null
  xcrun simctl launch $D j-bizzell.PhysicsPlayground "$@"
  sleep 22                                   # scenes settle; fields trace
  xcrun simctl io $D screenshot "$name.png"
}

shot 1-throws    -openModule kinematics     -kinBalls 1 -kinWalls 1
shot 2-circuits  -openModule circuits       -electronView 1
shot 3-fields    -openModule electrostatics -emCap 1 -emMagnetic 1 -emVolts 90 -emTesla 0.6
shot 4-gravity   -openModule gravitylab     -gravBinary 1
shot 5-orbitring -openModule gravitylab     -selectBody Earth -gravRing 1 -apsisDrag far,2.2
shot 6-home                                 # no arguments at all
```

**In zsh, quote the arguments as `"$@"`, not `$2`.** zsh does not
word-split an unquoted parameter expansion, so passing a whole argument
string through `$2` hands `simctl` one long argument, which it silently
ignores — the app launches on the Home Screen and the shot looks like the
staging simply did not work. This cost two rounds of confused screenshots.

## Before you shoot

- [ ] **Dismiss the first-run hint** in each lab, or it sits across the
      top of the frame. It is dismissed per module and persists — so shoot
      each lab twice: once to dismiss, once for real. (`-resetHints 1`
      brings them all back if you want the hint *in* a shot.)
- [ ] **Let each scene settle.** Field lines re-trace, orbits move,
      pendulums swing. 20 seconds is about right; a shot taken at 5
      catches half-built geometry.
- [ ] **Check the title bar is not truncating** — "Circuit Workshop" is
      the long one.
- [ ] **Studio Mode (`-studioMode 1`) is a fallback, not a default.** It
      replaces the room with a dark void, which photographs cleanly and
      throws away the entire reason the app exists. Use it only if a
      real-room shot is unreadable.

## Captions

visionOS screenshots take no burned-in caption text, so the images have to
carry themselves. Two consequences worth checking on device:

- Every shot should contain **at least one legible number or label** —
  that is what separates this from a toy.
- Shot 1 must contain something **unmistakably domestic** (a sofa, a
  bookshelf, a floor) or the whole spatial premise is lost.

## App preview video (optional)

If one is made, it must show a **hand**. Every claim in the description
is about reaching in, and no still frame can show a grab. The strongest
30 seconds: pull a charge out of the well → the field redraws around it →
pinch with both hands to zoom → tap a planet → drag the apsis bead and
watch the orbit stretch.
