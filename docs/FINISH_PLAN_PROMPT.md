# Plan-mode prompt — finish Physics Playground for submission

Paste everything between the fences into Claude Code **in plan mode**
(`shift+tab` twice, or start with `/plan`). It is written to be read once and
then executed, so it front-loads the spec rather than making Claude Code
rediscover it — that is the token-efficient shape.

```
Enter plan mode. Do not write any code until I approve the plan.

GOAL: finish this app to submission quality and produce a 180-second demo that
shows every feature working. Nothing that the app does not need. Minimal
deletion — fold, nest and summon rather than remove.

READ FIRST, THEN STOP RE-EXPLORING. docs/AUDIT_2026-08-07.md is a complete
audit of this app with file:line and quoted code for every claim, and
docs/GOAL_2026-08-07.md (sections §Phase 0-3) is the fix detail. Treat them as
the spec. Do NOT re-audit the codebase; spot-check a claim only when you are
about to act on it and the line has drifted. Budget your reading: the audit
replaces the exploration pass.

STATE OF THE WORLD, verified today, some of which the docs get wrong:
- The project MOVED to ~/Developer/VisionPro/PhysicsPlayground. CLAUDE.md's
  "Git safety" section still describes Desktop/VisionPro and a stray `cool/`
  repo. Fix it.
- THERE IS NO GIT REPOSITORY at this path, and CLAUDE.md cites "the git
  history" and "212 commits" that do not exist here. This is item zero: git
  init, a first commit of the current tree, and a branch before any refactor. I
  am not doing a multi-phase change with no way back.
- Signing is ready: DEVELOPMENT_TEAM TL459W44PC, bundle com.jbizzell.
  physicsplayground, automatic signing, xrOS target 26.0, MARKETING_VERSION 1.0
  build 1. PrivacyInfo.xcprivacy and a layered AppIcon.solidimagestack exist.
  Zero TODO/FIXME in the source.
- I have a physical Vision Pro. On-device verification is real, and
  docs/ON_DEVICE_TESTS.md is the acceptance instrument, not a wish list.
- Target is a full App Store submission, so the plan ends at "archive uploaded
  and review notes written", not at "tests pass".

THE ORGANIZING PRINCIPLE — write the demo script first, and let it set scope.

Before you plan any code, write a 180-second shot list: timestamp, what is on
screen, what my hands are doing, and which file produces it. That script is
both the completeness test and the scope gate. A feature that cannot hold five
seconds of those 180 is not finished — it is either broken, undiscoverable, or
buried, and the script tells you which. Work backwards from it.

Rough shape to argue with, not to copy: ~15 s arrival and gallery; ~10 s
entering a lab; three labs shown properly at ~30 s each; the other three in
fast cuts of ~8 s; ~15 s of the Time Capsule (pause, walk around the frozen
instant, scrub, resume); ~10 s completing an experiment; ~10 s close. Every
beat must be reachable by a real hand. Where a beat also needs to be reachable
from the simulator so you can self-verify between my screenshot passes, say so
and add the launch argument.

CONSTRAINTS — read these as hard limits on scope.
- Do not delete a capability unless keeping it is genuinely blocking. The
  audit's long list of authored-but-unread content (HubDomain.promise, the 20
  experiment steps, the 5 Circuits presets, lagrangeExplanations,
  PendulumsModel.insightText, compassIsReadingEarth) should be WOKEN, not
  removed — it is the app's teaching, and most of it is demo material. Deleting
  it would be solving the wrong problem.
- Do not build the full Instrument / InstrumentRail / SummonHandle refactor
  from §Phase 2 unless you can show me it is the cheapest way to the result.
  My instinct is that most of the clutter win comes from two much smaller
  changes: (a) proximity recession — instruments sit at ~45% opacity and come
  to full within ~0.8 m of a hand, applied once in the four primitives, and
  (b) a fold-with-summary handle for the two banks that are actually over-full
  (Gravity Lab's seven plates, Circuits' twelve rack mouths), where the folded
  tab still shows the state so it stays a readout. Cost those two against the
  full refactor in the plan and recommend one. Magnetism and Pendulums already
  sit at six standing objects and are proof the vocabulary works — do not touch
  them.
- No refactoring outside what a step names. No new dependencies. No layer
  boundary moves.
- Token discipline: batch related edits into one pass per file; run the fast
  loop (cd Packages/PhysicsCore && swift test) during work and the full
  xcodebuild test only at step boundaries; do not re-read a file you just
  edited to confirm the edit landed.

WHAT THE PLAN MUST CONTAIN.
1. The 180-second shot list, with the file behind each beat.
2. A gap table: for each beat, does it work today? If not, which audit finding
   is in the way. This is what turns the audit into a shipping list — anything
   the demo does not touch drops to a named "after 1.0" backlog rather than
   into this release.
3. Ordered steps, each with: the files, the acceptance criterion, the test that
   proves it, and whether it needs a screenshot from me before you continue.
   Group them so I approve in a few batches, not thirty.
4. A "clutter target per lab" line: standing-object count now vs. after, for
   all six. Give me the number, and be honest if a lab does not need changing.
5. The submission runbook: archive, App Store Connect record, the four to ten
   screenshots and which launch arguments produce them, the app preview video
   cut from the demo, privacy answers, review notes telling the reviewer what
   to do with their hands, and the keyword fix (docs/APP_STORE.md currently
   sells `teacher,classroom` on an app with no SharePlay — that is a refund
   vector, and the doc also omits the Time Capsule entirely).
6. A risk list: what could fail on device that the simulator cannot show, and
   what you would do about each.

DECISIONS I WANT YOU TO BRING BACK WITH A RECOMMENDATION, not to make alone.
- The Time Capsule ships OFF (AppSettings.timeCapsule, my call 2026-08-07). It
  is the app's most distinctive feature and the demo needs it. On by default,
  or off with a one-time offer the first time a user pauses? Cost both.
- The gallery's enter affordance. Today a tap only flashes the pad and the only
  real door is a ~1.1 m pinch-drag. DECISIONS 2026-07-29 explains why the bare
  tap was removed; whatever you propose has to answer that argument, not
  ignore it.
- Whether the six visibly-wrong physics items in §Phase 3 all belong in 1.0, or
  whether some are invisible in a 3-minute demo and can wait. Be honest — but
  weigh that this is a portfolio project whose whole claim is that the physics
  is real, so "nobody will notice in the video" is not on its own a reason to
  ship it wrong.

ASK ME BEFORE YOU FINALISE.
- Anything in the audit you think I have wrong.
- Whether any beat in your shot list needs an app capability that does not
  exist yet, so I can cut it rather than have you build it.
- The one thing you would add if I gave you an extra day, and the one thing you
  would cut if I took one away.

SHIP GATES, in order: git initialised and the tree committed; fast loop green;
full xcodebuild test green; a full pass of docs/ON_DEVICE_TESTS.md on the
device with me driving; the 180-second demo recorded end to end in one take
with no beat failing; archive validated. Nothing ships past a red gate.

Standing rules from CLAUDE.md still apply: plan before any change touching more
than one file; new capability, new test, in the suite that can reach it; prefer
a criterion test over a listing test; record graves and fix stale comments in
the same commit. You cannot see this app running — after any visual change,
stop and ask me for a screenshot and tell me the launch arguments to take it.
```

---

## Why it is shaped this way

**The demo script is the spec, not a deliverable at the end.** You asked for
full polish and a 3-minute demo. Those are the same requirement stated twice: a
feature that cannot hold five seconds of screen time is not polished, it is
hidden or broken. Making Claude Code write the shot list before it plans any
code converts a vague "finish it" into a finite list, and it is what stops the
audit's 100+ findings from becoming the scope. The gap table in item 2 is the
mechanism — everything the demo does not touch is named and deferred rather
than silently included.

**It scales the clutter fix down.** The previous arc proposed a container
protocol across every primitive. Against "don't do anything the app doesn't
need," that is probably too much, so the prompt makes Claude Code cost the
cheap version (recession + fold-with-summary on the two over-full banks)
against the full refactor and argue for one. It also names Magnetism and
Pendulums as already-correct so they don't get touched.

**It protects the authored content.** Your "don't delete unless necessary" and
the demo requirement point the same way: the dead teaching should be woken,
because it is the material a 3-minute demo needs.

## Two things worth deciding before you paste

**Git.** There is genuinely no repo at the new path. I would not run a
multi-step refactor without one — the prompt makes that item zero, but if you
have a repo elsewhere that got detached in the move, say so and that step
changes from `git init` to reconnecting it.

**`docs/APP_STORE.md` keywords.** It sells `teacher,classroom` on an app with
no SharePlay, no lesson plans and no multi-device support. That mis-targets
ranking toward a buyer the app cannot satisfy, which is how you get one-star
reviews from people who bought the wrong thing. The prompt includes the fix.
