---
name: Bug report
about: Something does not work
labels: bug
---

**What happens**

**What you expected**

**Which app were you selecting text in?**
Capture behaviour varies a lot between apps, so this is usually the single most
useful detail.

**macOS version**

**Capture log**
If the selection was not picked up, turn on *Trace selection capture* in
Settings → Diagnostics, reproduce, and paste the relevant part of
`~/Library/Logs/Speaky/capture.log`.

The log records tier outcomes and text lengths, not the text itself — but the
lengths do reveal roughly how much you had selected, so review it before pasting.
