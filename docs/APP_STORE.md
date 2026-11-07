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
- `Seven labs. Real constants.` (27)

*`Experiments you can hold` (24) was a fourth alternate until 2026-08-09.
It was coined while the app shipped an experiments system, and when that
system was deleted the line was left in place with a note explaining that
it no longer named anything. An alternate you have ruled out is not an
alternate — it is a line someone can still pick by accident, with the
reason not to sitting in italics beside it. Deleted rather than annotated.*

## Promotional text (170 max, editable without review)

```
Seven physics labs that stand in your actual room. Throw a pendulum bob, wire a live circuit, reshape a planet's orbit by hand — with the real equations underneath.
```
*164 characters.* ("Six" until 2026-10-21, a week after the seventh lab
joined.) The first draft came in at exactly 170 — the limit — which is
not a margin. App Store Connect counts an em dash and a curly
apostrophe as one character each, but a paste that converts either can
push a string over, so leave slack rather than discovering it in the web
form. This field can be changed at any time without
resubmitting, so it is the right place for anything seasonal or for
pointing at whatever is newest.

## Keywords (100 max, comma-separated)

```
stem,science,education,circuit,magnet,orbit,pendulum,gravity,simulator,lab,optics,projectile,spatial
```
*100 characters* — the limit, which an all-ASCII line can meet with
no paste risk. It was 105 under a note that said 99 from 2026-09-02 to
2026-10-21, which App Store Connect would have refused; `electricity`
went for `optics` (the seventh lab had no word here, and `circuit`
already reaches the electricity searches). `SellingCopyCriterionTests`
measures it now.

*`teacher,classroom` were in this line until 2026-09-01 and are out on
purpose: the app has no SharePlay, no lesson plans, no multi-device
support and no progress tracking, so ranking for a buyer who wants a
classroom tool is a refund waiting to happen. The four words that replaced
them name things the app actually does.*

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

Seven labs stand at full size in the space around you. You don't
watch them — you reach in. Throw a pendulum bob and it swings from the
hand speed you gave it. Carry a bar magnet toward another and feel the
field reorganise. Grab a planet and hurl it out of orbit, then watch the
readout tell you it is never coming back.

THE PHYSICS IS REAL

No physics engine, no approximations for convenience. Every solver is
written from scratch in SI units with real constants, and uses the exact
closed-form solution wherever one exists: Kepler orbits from true orbital
elements, nodal analysis for circuits, the exact dipole field between
two bar magnets, r = mv/qB for a charge in a magnetic field. More than
500 tests run against the physics alone.

Where something must be unphysical for you to see it, the app says so.
The field that visibly bends a half-gram ball is a thousand times the
strongest magnet ever built, and the lab calls it fictional.

THE SEVEN LABS

Electric Fields — Pull charges out of a well and watch the field redraw
around them. Add parallel plates you carry by hand, switch on a uniform
magnetic field, and send a charged ball circling through it — the
cyclotron radius, drawn at full size in your room.

Circuit Workshop — Wire real parts from a shelf: batteries, resistors,
capacitors, inductors, motors, LEDs, solved every frame. Probe it with a
multimeter, push a resistor past its rating until it scorches, and zoom
into the copper at the true drift velocity — millimetres per second.

Magnetism — Bar magnets that attract, repel and snap into alignment,
their looping field closing on itself in real time. Carry a compass
through it.

Light & Optics — A laser, a torch of white light, and mirrors, a prism,
a lens and a glass bar you set anywhere in the room and turn by hand.
White light through the prism fans into a spectrum on your own wall; the
laser, aimed into the glass bar, cannot get out through its sides. Every
ray is traced exactly, each colour through the glass's real index.

Projectile Motion — Throw anything. Real drag and restitution, gravity
from zero-g to Jupiter, and bounces off your actual walls, floor,
ceiling and table. Stand a hoop anywhere and the launcher solves for it
— both arcs, exactly — or arm it to drop the instant you fire and watch
the ball meet it in mid-air on every world.

Pendulums — Full nonlinear swings, a Newton's cradle you can break apart
and rebuild, a double pendulum that never repeats itself, and a true
3-D orbit you throw a bob into above your own floor.

Orbital Mechanics — A solar system you can walk into. Tap a planet and its orbit
becomes a ring with a bead at each end; pull one and the orbit reshapes
under your hand. Split the star into a binary and watch every orbit answer
at once.

YOUR ROOM, OR DEEP SPACE

Every lab stands in your room or, at a switch, among the real stars: all
9,096 visible to the eye, at their true places and colours, a glass
platform at your feet.

CONTROLS THAT ARE OBJECTS

You change a value by handling the thing that has it. Pull a charge's
handle and the charge grows; draw a pendulum's cable down; pull the
launcher's aim bead further out to throw harder. New objects are pulled
out of wells with your hands. Everything else waits behind one More button
beside the lab's name.

THE TIME CAPSULE

Every lab remembers its last thirty seconds. Pause, pinch the reel that
appears, and draw out the tape: the whole room runs backwards — the ball
retraces its arc, the bounce un-happens. Walk around the frozen instant,
step it one tick at a time, and resume from any moment.

PRIVACY

No accounts, no analytics, no advertising, and no network code of any
kind. Nothing you do leaves your device.

Requires visionOS 26.0 or later.
```
*3,805 characters* of 4,000. Counted, not estimated (2026-10-24, when the
Milky Way left the deep-space sentence; 3,832 on 2026-10-21, when the
sentence about the opening left with the opening; 3,927 before that, once
the room-or-deep-space paragraph had joined and the Circuits, Time Capsule
and fictional-field paragraphs were cut back to make room). **Recount after
every edit:** Light & Optics' paragraph took it to 4,049 on 2026-10-14 —
over the limit, under a note that still said 3,689 — and nothing caught
it for a week; `SellingCopyCriterionTests` counts every field with a
limit now. (3,689 after the controls paragraph was rewritten for the
subtraction pass, 3,626 before that, and 3,758 before the
capture-and-export paragraph left with its feature;
2,937 before the Time Capsule paragraph and the new Projectiles and
Circuits sentences).

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
that sits low, like Orbital Mechanics' orrery, lands in the bottom third of a
mostly black frame, and there is no legal crop that fixes it.

**Take the store screenshots on device.** Stand where the composition is
best, then capture. Use the simulator commands below to *stage* each shot
— they put the app in exactly the right state — and treat the simulator
output as a reference for what should be on screen, not as the deliverable.

## Ordering

**These were shot before being ranked.** The first ordering in this file
was written from memory and was wrong twice — Orbital Mechanics is not the
strongest frame and Projectiles is much stronger than expected. What
follows is the order after actually looking.

The first two do almost all the work; most people never swipe past three.

| # | Shot | Verdict from the actual frame |
|---|---|---|
| 1 | **Projectile Motion** — staged volley, walls on | The best single frame the app produces. Arcs sweep the whole room and visibly bounce off the shelf and wall; the apex height, the angle and the speed beside the aim bead are all legible; the ball fan shows it is an instrument and not a toy. It is the only shot that carries "in your room" AND "real physics" at once. |
| 2 | **Circuit Workshop — zoomed into the copper** | The most surprising image in the app: you are standing among copper conductors two metres thick with the electron bands crawling along them at true drift speed, under a glowing bulb reading `24 Ω`. Nothing else looks like this, which is exactly what a second screenshot is for. |
| 3 | **Electric Fields — lines + capacitor + B** | The densest "this is real physics" frame — field lines filling the room, the carried capacitor plates with their sign glyphs, the uniform B switched on. (Reframed 2026-08-05: the flux instrument this slot was built around left the app on 2026-08-03 — DECISIONS.md has the story.) Slightly busy, which is why it is third rather than first. |
| 4 | **Orbital Mechanics — binary star** | Conceptually the best story (two suns, every orbit reshaped) and the weakest *simulator* frame: the orrery sits low, so two-thirds of the image is black. **Shoot this one on device**, standing closer and looking down. |
| 5 | **Orbital Mechanics — the orbit ring** | Depth, for the person who has already decided to look: Earth's orbit as a ring in the room, apoapsis pulled out to 2.2× under a hand. The module's documented centrepiece. (Reframed 2026-08-05: the previous subject left the app on 2026-08-03 — DECISIONS.md has the story. If two Gravity frames read as repetitive against shot 4, the alternate is Magnetism's room-filling field lines — `-openModule magnetism`, defaults.) |
| 6 | **Home Screen** | Shows the scope — seven labs in miniature floating around you, each looping its own physics, under the wordmark. A closer, not an opener: it is the least *spatial* frame, because nothing in it is an experiment. |
| 7 | **Time Capsule** — the reel with its tape out, a ball rewound mid-arc | The feature nothing else in the category has, photographed as the object it is: the reel, the rail drawn out of it, the recorded path hanging as a tube and the ball frozen part-way back along it. Added 2026-09-01 when the capsule started shipping on. |

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
  xcrun simctl terminate $D com.jbizzell.physicsplayground 2>/dev/null
  xcrun simctl launch $D com.jbizzell.physicsplayground "$@"
  sleep 32   # ~15 s of prop-cache warm-up before the lab mounts (a cold
             # simulator), then scenes settle and fields trace. `-pauseAfter`
             # counts from the mount, not from launch (2026-09-02).
  xcrun simctl io $D screenshot "$name.png"
}

shot 1-throws    -openModule kinematics     -kinBalls 1 -kinWalls 1
shot 2-circuits  -openModule circuits       -trueSpeed 1
shot 3-fields    -openModule electrostatics -emCap 1 -emMagnetic 1 -emVolts 90 -emTesla 0.6
shot 4-gravity   -openModule gravitylab     -gravBinary 1
shot 5-orbitring -openModule gravitylab     -selectBody Earth -gravRing 1 -apsisDrag far,2.2
shot 6-home                                 # no arguments at all
shot 7-capsule   -openModule kinematics     -kinBalls 1 -pauseAfter 4 -scrubBack 1.5
shot 8-hoops     -openModule kinematics     -kinHoops 1 -kinSolve 1
shot 9-coil      -openModule circuits       -circCoil 1
```

(Shots 8 and 9 are the 2026-09-02 features — a hoop with both solved arcs
through it and its angle callout; the coil's own field over the bench —
and are optional: the store takes up to ten, and seven already carry the
argument.)

(Shot 7 needs no `-timeCapsule` argument: recording is the default. Pass
`-timeCapsule 0` to photograph a plain pause with no reel.)

**In zsh, quote the arguments as `"$@"`, not `$2`.** zsh does not
word-split an unquoted parameter expansion, so passing a whole argument
string through `$2` hands `simctl` one long argument, which it silently
ignores — the app launches on the Home Screen and the shot looks like the
staging simply did not work. This cost two rounds of confused screenshots.

## Before you shoot

- [ ] **Let each scene settle.** Field lines re-trace, orbits move,
      pendulums swing. 20 seconds is about right; a shot taken at 5
      catches half-built geometry.
- [ ] **Check the title bar is not truncating** — "Circuit Workshop" is
      the long one.
- [ ] **Deep space (`-surroundings space`) is the second surroundings,
      not the default.** It photographs cleanly and drops the room, which
      is the reason most of the app exists — the labs that answer your
      room (Projectiles' bounces, Light's spectrum on the wall) stay in
      the room. Shoot it for the home and for Orbital Mechanics, which
      opens there by itself.

## Captions

visionOS screenshots take no burned-in caption text, so the images have to
carry themselves. Two consequences worth checking on device:

- Every shot should contain **at least one legible number or label** —
  that is what separates this from a toy.
- Shot 1 must contain something **unmistakably domestic** (a sofa, a
  bookshelf, a floor) or the whole spatial premise is lost.

## Archive, validate, upload (2026-09-02)

The order the gates run in: fast loop green → full suite green → the
on-device pass (`ON_DEVICE_TESTS.md` › Release 1.0 gate) → the 180-second
take (`DEMO_SCRIPT.md`) → archive validated. Nothing ships past a red one.

```bash
# From the project folder. Signing is automatic (team TL459W44PC).
xcodebuild -project PhysicsPlayground.xcodeproj -scheme PhysicsPlayground \
  -configuration Release -destination 'generic/platform=visionOS' \
  -archivePath build/PhysicsPlayground.xcarchive archive -allowProvisioningUpdates
```

Then Xcode › Organizer › the archive › **Distribute App › App Store
Connect › Validate**, and only after a clean validation **Upload**. (The
command-line equivalent is `xcodebuild -exportArchive` with an
`ExportOptions.plist` of `method: app-store-connect`, `teamID:
TL459W44PC`, `uploadSymbols: true`; the Organizer is the same thing with
the errors readable.) Build 1 is the first upload; bump
`CURRENT_PROJECT_VERSION` for every upload after it — a version can be
uploaded once per build number.

In App Store Connect the record is: name from this file, bundle
`com.jbizzell.physicsplayground`, category **Education**, age rating
**4+**, App Privacy **Data Not Collected** (the manifest declares only
`UserDefaults`, reason CA92.1), export compliance already answered by
`ITSAppUsesNonExemptEncryption = false`, the two URLs above. Review
notes, verbatim:

> Physics Playground opens in an immersive space: seven labs rise into
> place around you in miniature. visionOS will ask for World Sensing and Hand Tracking — both are
> needed for the labs to stand in the room and be grabbed; nothing is
> collected or transmitted. To enter a lab, pinch it. In a lab,
> handle the objects: pull from a well to make a new one, drag to move,
> tap an object for its ring, and pull the handle on a ring to change the
> object's value. The title bar holds Home, More (the lab's switches,
> live numbers, room dimming, Deep space, Settings and Reset) and Pause.
> Pause any lab and pinch the reel that appears to rewind the last 30
> seconds. No account, no purchase, no network.

After approval, the docs site (`PRIVACY.html`, `SUPPORT.html`) is
republished with the subtree commands under **URLs** above.

## App preview video (optional)

If one is made, it must show a **hand**. Every claim in the description
is about reaching in, and no still frame can show a grab. The strongest
30 seconds: pull a charge out of the well → the field redraws around it →
pinch with both hands to zoom → tap a planet → drag the apsis bead and
watch the orbit stretch.

**The full demo is scripted in `docs/DEMO_SCRIPT.md`** (180 s, every
beat with the file behind it and the launch arguments that stage it in
the simulator). The preview is cut from a **Developer Capture** (Reality
Composer Pro › File › Developer Capture, HEVC .mov, 30 fps), not from the
headset's Control Center recording — App Store Connect wants 3840 × 2160,
16:9, 30 fps, 15–30 s, H.264 at 10–12 Mbps or ProRes 422 HQ, stereo AAC,
≤ 500 MB, up to three previews, poster frame at 5 s.
