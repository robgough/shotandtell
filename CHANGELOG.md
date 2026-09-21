# Changelog

User-visible changes to Shot and Tell, newest first.

Entries are written in user language, not commit language: "Captures now keep the
window's rounded corners" rather than "Add corner-radius mask to WindowCapture".
Anything a user could notice belongs here — features, fixes, performance they'd
feel, UI changes, new settings. Refactors, build tweaks and dependency bumps
don't.

## Unreleased

- Take a screenshot by dragging out a region, clicking a window, or picking a
  whole screen, with an optional 3, 5 or 10 second timer.
- The screen freezes while you choose what to capture, and a magnifier follows
  the pointer showing the exact pixel under the crosshair with its coordinates.
- Press Space while choosing to switch between dragging a region and clicking a
  window, the same way the system screenshot tool works. The overlay says so,
  and names the window you're about to take.
- A global keyboard shortcut starts a capture from any app — ⌃⇧S to begin with,
  changeable in Settings.
- Settings for the shortcut, what the Dock icon does, the default background and
  light or dark, the exported image size, and where PNGs are saved.
- Mark up a capture with numbered pins, numbered arrows, numbered boxes and
  redaction blocks, and describe each one in the legend beside it.
- The finished shot is composed onto a background with the legend down the right
  hand side, so a number on the image always has words to go with it.
- Press V, P, A, B or R to pick a tool, and start typing a description the
  moment a mark is placed — Escape sends focus back to the screenshot.
- Marks can be moved and resized by their handles after they're drawn.
- If Apple Intelligence is available, the title is suggested by the on-device
  model from the screenshot itself. Nothing is sent anywhere.
- ⇧⌘C copies just the legend as text. The image alone goes on the clipboard
  otherwise, so pasting into a chat gets the picture.
- A Copy button copies the finished image without closing the editor; the main
  button now says what it does — Copy & Close.
- Reopen the last capture from the menu bar, marks and all, if you close it by
  mistake or think of something else to point at.
- The menu bar can reveal the last saved screenshot in the Finder.
- Choose a background per shot — neutral, one of four gradients, a flat tone, or
  none — in light or dark.
- Pressing Done copies the composed image to the clipboard, puts the legend on
  it as text at the same time, and saves a PNG to Pictures › Shot and Tell.
