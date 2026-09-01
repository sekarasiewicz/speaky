# Speaky

A macOS menu bar app that reads your selected text aloud using OpenAI text-to-speech.

Select text anywhere, press a hotkey, and it starts speaking within a few hundred
milliseconds. Works in Mail, Safari, Notes, Office, Electron apps and terminals.

## Requirements

- macOS 26.5 or later
- An OpenAI API key
- Accessibility permission (System Settings → Privacy & Security → Accessibility)

## Setup

1. Open `Speaky.xcodeproj` and run the app.
2. Grant Accessibility permission when prompted, then relaunch — the permission
   is only picked up at process start.
3. Open Settings from the menu bar icon and paste your OpenAI API key. It is
   stored in the login keychain, never in the app bundle.

## Launch at login

Settings has a **Uruchamiaj przy logowaniu** toggle, backed by `SMAppService`.
It registers whichever bundle is running, so a build launched from Xcode
registers its DerivedData path and stops working as soon as that build is
replaced. Enable it on a copy in `/Applications`.

macOS may list the item as requiring approval; the toggle links straight to the
Login Items pane when it does.

## Shortcuts

| Default | Action                     |
|---------|----------------------------|
| ⌃⌘S     | Read selection / stop      |
| ⌃⌘P     | Pause / resume             |
| ⌃⌘←     | Skip back                  |
| ⌃⌘→     | Skip forward               |

All four are rebindable in Settings. A shortcut another app already owns is
flagged there, because `RegisterEventHotKey` grants a combination to whoever
registers it first and silently refuses everyone after.

## How the selection is read

No single mechanism covers every app, so four are tried in order:

1. **`AXSelectedText`** — clean and instant, where the app implements it.
2. **Edit ▸ Copy pressed over Accessibility** — no synthetic keyboard involved,
   which reaches apps that ignore injected events.
3. **A synthetic ⌘C** — sent only once the hotkey's modifiers are physically
   released. Events posted to the HID tap merge with real hardware modifier
   state, so firing early turns ⌘C into ⌃⌘C, which a terminal reads as
   Control-C: it sends SIGINT and clears the very selection being read.
4. **Watching the pasteboard** — terminals commonly copy on selection, so the
   clipboard becomes a truthful record of the selection. The source app is
   recorded alongside the text and has to match, so an unrelated clipboard entry
   is never mistaken for a selection.

iTerm2 needs the fourth: it exposes no focused element over system-wide
Accessibility, leaves its Copy menu item unvalidated until the menu is opened,
and ignores a synthetic ⌘C. Its default *Copy to pasteboard on selection* is
what makes it reachable at all — turn that off and iTerm2 goes silent again.

## Audio

Speech is requested as raw 24 kHz mono PCM so bytes off the socket can be
scheduled straight onto an `AVAudioPlayerNode` — no container to parse, no
decoder between download and sound. Text is split on sentence boundaries into
~350 character chunks so the first one is already speaking while the rest is
still being generated.

Every sample received is retained, because seeking backwards needs audio that
has already played. Seeking forward is capped at the buffered edge: audio beyond
it does not exist yet.

## Troubleshooting

Turn on **Zapisuj log odczytu zaznaczenia** in Settings and capture attempts are
traced to `~/Library/Logs/Speaky/capture.log`, recording what each tier saw.
Selection grabbing fails silently by nature — every tier just returns nothing —
so the log is the only way to tell a missing selection from a wrong target app
from a refused copy.

It is off by default: it writes on every hotkey press and records the length of
whatever the user had selected.
