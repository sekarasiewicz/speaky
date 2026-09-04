# Speaky

A macOS menu bar app that reads your selected text aloud using OpenAI
text-to-speech.

Select text anywhere, press a hotkey, and it starts speaking within a few
hundred milliseconds. Pause, resume and seek while it reads.

## Requirements

- macOS 26.5 or later
- An OpenAI API key
- Accessibility permission

## Install

Download the latest `Speaky-<version>.dmg` from
[Releases](https://github.com/sekarasiewicz/speaky/releases), open it and
drag Speaky to Applications. The app is signed with Developer ID and
notarized, so it launches without any Gatekeeper warning (Apple silicon only).

To build from source instead:

```sh
git clone git@github.com:sekarasiewicz/speaky.git
cd speaky
./install.sh
```

This builds Release, installs to `/Applications` and launches the app.

Without Xcode, `./install.sh --prebuilt` installs the app committed in
`dist/Speaky.zip`. That copy is signed with a development certificate and
not notarized; the script strips the quarantine attribute before launching,
and if you unzip it by hand run `xattr -dr com.apple.quarantine Speaky.app`
first or Gatekeeper reports the app as damaged.

Then:

1. Grant Accessibility permission when prompted, and **relaunch** — the
   permission is read at process start, so it does not take effect until then.
   Settings → General shows whether it is actually active.
2. Open Settings from the menu bar icon and paste your OpenAI API key. It is
   stored in the login keychain, never in the app bundle.
3. Optionally turn on **Launch at login** in Settings → General.

Speaky is not sandboxed and cannot be: reading the selection anywhere on the
system needs the Accessibility API, which App Sandbox does not permit.

## Shortcuts

| Default | Action                |
|---------|-----------------------|
| ⌃⌘S     | Read selection / stop |
| ⌃⌘P     | Pause / resume        |
| ⌃⌘←     | Skip back             |
| ⌃⌘→     | Skip forward          |

All four are rebindable in Settings → Shortcuts. A combination another app
already owns is flagged there: `RegisterEventHotKey` grants a combination to
whoever registers it first and silently refuses everyone after, so an unflagged
shortcut that does nothing would otherwise be indistinguishable from a bug.

Combinations using ⌥ without ⌘ are flagged too. On layouts where Option composes
diacritics — Polish, German and others — a failed registration does not fall
silent, it types a character.

## How the selection is read

No single mechanism covers every app, so four are tried in order:

1. **`AXSelectedText`** — clean and instant, where the app implements it.
2. **Edit ▸ Copy pressed over Accessibility** — no synthetic keyboard involved,
   which reaches apps that ignore injected events. Matched by the item's command
   character rather than its title, so it works whatever the app's language.
3. **A synthetic ⌘C** — sent only once the hotkey's modifiers are physically
   released. Events posted to the HID tap merge with real hardware modifier
   state, so firing early turns ⌘C into ⌃⌘C, which a terminal reads as
   Control-C: it sends SIGINT and clears the very selection being read.
4. **Watching the pasteboard** — terminals commonly copy on selection, which
   makes the clipboard a truthful record of the selection. The source app is
   recorded alongside the text and has to match, so an unrelated clipboard entry
   is never mistaken for a selection. Copies older than five minutes are ignored.

iTerm2 needs the fourth. It exposes no focused element over system-wide
Accessibility, leaves its Copy menu item unvalidated until the menu is opened,
and ignores a synthetic ⌘C. Its default *Copy to pasteboard on selection* is
what makes it reachable at all — turn that off and iTerm2 goes silent again.

## Audio

Speech is requested as raw 24 kHz mono PCM so bytes off the socket can be
scheduled straight onto an `AVAudioPlayerNode` — no container to parse, no
decoder between download and sound. Text is split on sentence boundaries into
~350 character chunks so the first one is already speaking while the rest is
still being generated.

Playback waits for half a second of audio to accumulate before the first sound.
Chunks arrive in ~0.2 s pieces, and starting on the first one leaves the queue
empty the moment network jitter delays the next, which stutters the opening
words.

Every sample received is retained, because seeking backwards needs audio that
has already played. Seeking forward stops at the buffered edge: audio beyond it
does not exist yet.

## Troubleshooting

Turn on **Trace selection capture** in Settings → Diagnostics and capture
attempts are traced to `~/Library/Logs/Speaky/capture.log`, recording what each
tier saw. Selection grabbing fails silently by nature — every tier just returns
nothing — so the log is the only way to tell a missing selection from a wrong
target app from a refused copy.

It is off by default: it writes on every hotkey press and records the length of
whatever was selected.

**Nothing happens in one specific app.** Check the log. If all four tiers come
back empty, that app exposes no selection Speaky can reach; open an issue with
the log and the app name.

**A shortcut does nothing.** Open Settings → Shortcuts and look for the warning
triangle, which means another app owns the combination.

**Secure Keyboard Entry.** While any app has it on — it is a menu item in
iTerm2 — macOS blocks both synthetic key events and other apps' global hotkeys.
Settings → Diagnostics warns when it is currently active.

## Tests

```sh
xcodebuild test -project Speaky.xcodeproj -scheme Speaky -destination 'platform=macOS'
```

## Roadmap

[ROADMAP.md](ROADMAP.md) records what works, what is knowingly rough, and what
was deliberately left out — with the reasoning, so it does not have to be
rediscovered.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). Bug reports about a specific app are
much more useful with a capture log attached.

## License

MIT — see [LICENSE](LICENSE).
