---
layout: default
title: Privacy Policy — Physics Playground
---

# Privacy Policy — Physics Playground

**Last updated: 1 August 2026**

Physics Playground collects nothing about you. There are no accounts, no
analytics, no advertising, no crash reporting, and no network code of any
kind in the app.

That last claim is checkable rather than aspirational: the app target and
both of its local Swift packages contain no `URLSession`, no `URLRequest`,
no `Network` import, and the project has no remote package dependencies.
The app cannot send data anywhere because it has no way to send anything
anywhere.

## What the app asks permission for

**World Sensing.** visionOS uses the shape of your room so the physics
happens in it — projectiles bounce off your real walls, floor and
ceiling, and apparatus is hidden correctly behind your furniture.

**Hand Tracking.** So you can pick up a magnet, stretch a pendulum's
cable, and pinch with both hands to zoom an experiment.

Both are processed **on your device by visionOS**. The app receives only
what the system hands it — plane and mesh geometry, hand joint positions
— it holds that data in memory while a lab is open, and it discards it
when the lab closes. None of it is written to disk, and none of it leaves
your device.

You can decline either permission. The app keeps working: experiments run
in open space instead of using your walls, and everything else is
unchanged. If you decline and later change your mind, every lab shows a
warning in its title bar telling you where in Settings to turn it back on.

## What is stored on your device

Stored locally in the app's own container, never transmitted:

- **Settings** — volume, ambient audio, and whether the Time Capsule
  records.
- **Your circuit bench** — Circuit Workshop remembers what you built.

Deleting the app deletes all of it. Nothing is exported or shared.

## Children

The app is suitable for all ages. Because it collects no data at all, it
collects no data from children either.

## Changes

If this policy ever changes, the date at the top changes with it. Since a
change could only be caused by the app starting to do something it does
not currently do, any change will say plainly what that is.

## Contact

Jackson Bizzell — jackson.bizzell@outlook.com
