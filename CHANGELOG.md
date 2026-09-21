# Changelog

User-visible changes to Shot and tell, newest first.

Entries are written in user language, not commit language: "Captures now keep the
window's rounded corners" rather than "Add corner-radius mask to WindowCapture".
Anything a user could notice belongs here — features, fixes, performance they'd
feel, UI changes, new settings. Refactors, build tweaks and dependency bumps
don't.

## Unreleased

- Take a screenshot by dragging out a region, clicking a window, or picking a
  whole screen, with an optional 3, 5 or 10 second timer.
- Mark up a capture with numbered pins, numbered arrows, numbered boxes and
  redaction blocks, and describe each one in the legend beside it.
- The finished shot is composed onto a background with the legend down the right
  hand side, so a number on the image always has words to go with it.
- Choose a background per shot — neutral, one of four gradients, a flat tone, or
  none — in light or dark.
- Pressing Done copies the composed image to the clipboard, puts the legend on
  it as text at the same time, and saves a PNG to Pictures › Shot and tell.
