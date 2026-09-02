# Roadmap

Where the project stands, and what was deliberately left undone. Everything here
is a choice, not an oversight — the reasoning is recorded so it does not have to
be rediscovered.

## Working

Selection capture (four tiers), streaming playback with preroll, seeking,
rebindable global hotkeys, text cleanup, on-disk audio cache, spend guard and
counter, retry on transient API failures, launch at login, a menu bar panel with
a scrubber, 23 unit tests.

## Known rough edges

**The progress bar drifts a little.** Total length is projected from the
character count using a speaking rate measured from the audio produced so far,
and that rate is recalculated per chunk. Speech density varies — numbers, dates
and abbreviations take noticeably longer per character than ordinary words — so
the scale shifts slightly as each chunk lands. Smoothing the transition, or
keeping a per-chunk estimate, would fix it. Cosmetic.

**Two copies can run at once.** Terminating anything sharing the bundle
identifier meant a debug build silently quit the copy in `/Applications` and
vice versa, which looked like the app closing itself. Now only an exact-path
duplicate is terminated, so a debug build and the installed copy coexist — and
only one wins the global hotkeys. Diagnostics lists the other copy.

**iTerm2 depends on a preference.** It is reachable only through tier 4, which
watches the pasteboard. That works because *Copy to pasteboard on selection* is
on by default. Turn it off and iTerm2 becomes unreadable, with no workaround:
it exposes no focused element over system-wide Accessibility, leaves its Copy
menu item unvalidated until the menu is opened, and ignores a synthetic ⌘C.

## Ideas, not commitments

- Notifications instead of a beep for errors.
- Queue several selections instead of replacing the current read.
- Highlight the sentence being spoken in the source app.
- An LLM pass for "summarise and read" on top of the regex cleanup.
- Localisation, if anyone other than the author uses it.
- CI building on `macos-latest` for pull requests (~20 lines).
- Screenshots in the README — the most visible gap for a GUI tool.

## Working on it

```sh
./install.sh    # build Release, install to /Applications, launch
xcodebuild test -project Speaky.xcodeproj -scheme Speaky -destination 'platform=macOS'
```

Quit the copy running from Xcode before installing, or you end up with two
copies competing for the hotkeys.

Accessibility permission is tied to the code signature and path, and is read
only at process start. Reinstalling over the same path keeps it; running a debug
build is a separate grant.
