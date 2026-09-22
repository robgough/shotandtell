# Shot and Tell

A macOS screenshot tool for talking to AI about pictures.

Capture a region, a window or a screen; mark things with numbered markers and describe
them; censor what shouldn't be seen. You get back one image: the screenshot on a
background, with a numbered legend beside it — so "the heading in ① is too big" is
understood the first time, by an AI agent or by a colleague.

Menubar app with a Dock icon. Click the Dock icon or pick *New Capture* to start.

macOS 26+. Mac App Store. Free.

## How it works

1. Start a capture — click the Dock icon, pick one from the menu bar, or press
   the global shortcut (⌃⇧S by default).
2. Drag out a region, click a window, or take a whole screen. A magnifier helps
   you land on an exact edge.
3. Mark it up: numbered pins, numbered arrows, numbered boxes, and redaction
   blocks for anything that shouldn't be seen. Type a description against each
   number as you go.
4. Done. The composed image goes on the clipboard with the legend as text beside
   it, and a PNG is saved to Pictures › Shot and Tell.

Nothing leaves your Mac. The app has no network entitlement, so it can't send
anything anywhere.

## Building

```bash
brew install xcodegen
./gen && open ShotAndTell.xcodeproj
```

See [CLAUDE.md](CLAUDE.md) for the details, [PLAN.md](PLAN.md) for why it's built
this way, and [RELEASING.md](RELEASING.md) for shipping it.

[shotandtell site](https://shotandtell.robgough.net/) · [privacy](https://shotandtell.robgough.net/privacy.html)

**Status: in development.** Headed for the Mac App Store.
