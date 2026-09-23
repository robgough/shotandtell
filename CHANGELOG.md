# Changelog

User-visible changes to Shot and Tell, newest first.

Entries are written in user language, not commit language: "Captures now keep the
window's rounded corners" rather than "Add corner-radius mask to WindowCapture".
Anything a user could notice belongs here — features, fixes, performance they'd
feel, UI changes, new settings. Refactors, build tweaks and dependency bumps
don't.

## Unreleased

- Fixed region and whole-screen captures sometimes coming out blurred and
  doubled, with the magnifier caught in them. Captures are now cut from the
  frozen picture you were selecting on, so they're exactly what you framed.
- A box, arrow or redaction is drawn in its real colour and weight while you
  drag it out, with the number it's about to get, instead of a thin blue outline.
- Marks carry a soft shadow, so they sit visibly on top of busy screenshots.
- Arrows taper from a fine tail to a swept, notched head, with an outline so
  they stay visible when they cross something the same colour.
- Boxes are outlined on both edges, matching the arrows and number badges.
- Arrows, boxes and redactions can be started anywhere on the canvas, not just
  within a thin strip around the screenshot, so an arrow's number can sit well
  out in the background. Marks out there get more room around them in the export.
- Dark compositions use the same vivid marker colours as light ones, rather than
  washed-out pastels, and a badge's ring always matches its number.
- The marker colour and Background buttons stay readable whatever the canvas
  colour, instead of following the system's light or dark mode.
- Take a screenshot by dragging out a region, clicking a window, or picking a
  whole screen, with an optional 3, 5 or 10 second timer. Picking a whole screen
  now says what to click, and the click works.
- The screen freezes while you choose what to capture, and a magnifier follows
  the pointer showing the exact pixel under the crosshair with its coordinates.
- Press Space while choosing to switch between dragging a region and clicking a
  window, the same way the system screenshot tool works. The overlay says so,
  and names the window you're about to take.
- A global keyboard shortcut starts a capture from any app — ⌃⇧S to begin with,
  changeable in Settings.
- An About window with what the app is, who made it, and exactly what does and
  doesn't leave your Mac.
- Settings for the shortcut, what the Dock icon does, the default background and
  light or dark, the exported image size, and where PNGs are saved.
- Mark up a capture with numbered pins, numbered arrows, numbered boxes and
  redaction blocks, and describe each one in the legend beside it.
- The finished shot is composed onto a background with the legend down the right
  hand side, so a number on the image always has words to go with it. A long
  legend flows into columns rather than running off the bottom.
- Press V, P, A, B or R to pick a tool, and start typing a description the
  moment a mark is placed — Escape sends focus back to the screenshot.
- Marks can be moved and resized by their handles after they're drawn, and can
  sit out in the background beside the screenshot — the canvas grows to fit
  them, so you can box or point at something right on an edge.
- Placing a mark returns you to Select, so the next click picks something up
  rather than making another one.
- Renumber marks with ⌥⌘↑ and ⌥⌘↓, or from the menu on a number.
- Clicking into a description highlights its mark on the screenshot, and
  selecting a mark scrolls its description into view.
- If Apple Intelligence is available, the title is suggested by the on-device
  model from the screenshot itself. Nothing is sent anywhere.
- ⇧⌘C copies just the legend as text. The image alone goes on the clipboard
  otherwise, so pasting into a chat gets the picture.
- A Copy button copies the finished image without closing the editor; the main
  button now says what it does — Copy & Close.
- Reopen the last capture from the menu bar, marks and all, if you close it by
  mistake or think of something else to point at.
- Drag the editor window by its empty background, or by the screenshot itself
  when Select is the active tool.
- The editor puts the tools in the window's own toolbar, fills the window with
  the background you'll get, and puts the legend in a resizable inspector.
- Copy & Close has a menu beside it for Save & Close, and for turning saving on
  or off without opening Settings.
- The background picker sits on the composition it changes rather than in the
  header.
- Closing an editor with marks on it asks first, from ⌘W or the red button.
- The menu bar can reveal the last saved screenshot in the Finder.
- The framing never touches the screenshot's own pixels: the hairline sits
  outside the image and the corners blend into the background, so every captured
  pixel survives to the export exactly as taken.
- Choose the marker colour per shot — eight presets or any colour from the
  system picker — because red marks on a red screenshot can't be seen. The
  number inside each marker switches to dark automatically on pale colours.
- Choose a background per shot — neutral, one of four gradients, a flat tone, or
  none — in light or dark.
- Saved filenames contain exactly one full stop, the one before "png".
- Pressing Done copies the composed image to the clipboard, puts the legend on
  it as text at the same time, and saves a PNG to Pictures › Shot and Tell.
