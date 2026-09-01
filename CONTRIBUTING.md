# Contributing

## Building

Open `Speaky.xcodeproj` and run, or `./install.sh` to build Release and install
to `/Applications`.

The app is not sandboxed and cannot be. Reading the selection anywhere on the
system needs the Accessibility API, which App Sandbox does not permit, so Speaky
is distributed outside the App Store by necessity rather than preference.

Accessibility permission is tied to the code signature and path. Set a
Development Team in Signing & Capabilities so the grant survives rebuilds;
without one, macOS re-signs ad-hoc on every build and the permission is dropped.

## Adding support for an app that reads as silent

Selection capture has four tiers in `SelectionReader.swift`, tried in order.
Before adding a fifth, find out what the existing ones actually see: turn on
**Trace selection capture** in Settings → Diagnostics and reproduce, then read
`~/Library/Logs/Speaky/capture.log`.

Every tier fails silently by design — each simply returns nothing — so the log
is the only way to tell a missing selection from a wrong target app from a
refused copy. Guessing between those three is how most of the time on iTerm2
support was spent.

Things worth knowing before you debug this:

- **Focus decides everything.** Opening a menu bar menu makes Speaky frontmost,
  so a capture triggered from the menu reads Speaky unless focus is handed back
  first. `FrontmostAppTracker` exists for that.
- **Menu items are validated lazily.** `kAXEnabledAttribute` on an item whose
  menu has never been opened can report a stale `false`. Do not filter on it.
- **HID-tap events merge with real modifier state.** A synthetic ⌘C fired while
  the hotkey's ⌃⌘ is still physically held arrives as ⌃⌘C. In a terminal that is
  Control-C: it sends SIGINT and clears the selection you were reading.
- **Not every app exposes a selection at all.** iTerm2 exposes no focused
  element over system-wide Accessibility. It is reachable only because it copies
  on selection by default, which tier 4 watches for.

## Style

Match the surrounding code. Comments explain *why* a non-obvious choice was
made, not what a line does — most of the odd-looking code here is load-bearing
and the comment is the only record of what breaks without it.

## Pull requests

State what you tested and in which apps. Capture behaviour varies enormously
between apps, and a change that fixes one can silently break another.
