# CLAUDE.md

Guidance for Claude Code (claude.ai/code) working in this repository.

## What this is

Shot and tell is a macOS screenshot tool for talking to AI about pictures. You
capture a region, window or screen; you point at things with numbered markers and
describe them; you censor what shouldn't be seen. The export is a single image —
the capture on a background with a numbered legend beside it — plus the same
legend as markdown text, so "the heading in ① is too large" means something to a
model that can only see pixels.

Menubar app **and** a Dock icon. macOS 26+, Apple Silicon, Mac App Store, free.

[PLAN.md](PLAN.md) is the spec: decisions taken, architecture, and the six phases.
Read it before starting work. Keep it current when a decision changes — it's the
thing that explains *why* the code looks like this.

## Build & run

```bash
brew install xcodegen
cp .env.example .env && $EDITOR .env   # optional; see "Signing" below
./gen                                  # regenerate ShotAndTell.xcodeproj
open ShotAndTell.xcodeproj             # then ⌘R
```

`ShotAndTell.xcodeproj` is gitignored — it's generated from `project.yml`, which is
the source of truth. **Adding a source file means re-running `./gen`**; xcodegen
lists sources at generation time, so a new file that hasn't been through `./gen`
simply isn't in the project. It fails at the *link* stage, not the compile stage,
which makes it look like something much stranger than it is.

CLI builds (for headless verification — `xcode-select` points at CommandLineTools
here, which has no `xcodebuild`):

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project ShotAndTell.xcodeproj -scheme ShotAndTell -configuration Debug \
  -derivedDataPath .derivedData build
```

A post-build phase installs a signed copy to `~/Applications/ShotAndTell.app`.

There is no test target yet and no lint config.

### Checking behaviour at runtime

The app logs through `os.Logger` under subsystem `net.robgough.ShotAndTell`:

```bash
/usr/bin/log show --predicate 'subsystem == "net.robgough.ShotAndTell"' --last 5m --style compact
```

Use the **absolute path**: zsh has a `log` builtin that shadows the real tool and
fails with "too many arguments" — which reads exactly like an empty result if
you're not looking carefully. User-initiated events log at `notice` so they're
persisted by default; `info` and `debug` need `--info` / `--debug`.

### Signing & macOS TCC

macOS keys the Screen Recording grant to the app's *signed identity* and launch
path. Ad-hoc signatures change on every build, so grants are revoked constantly.
Three optional env vars in `.env` pin the signature to a real certificate:
`SHOTANDTELL_TEAM_ID`, `SHOTANDTELL_CODE_SIGN_IDENTITY`,
`SHOTANDTELL_CODE_SIGN_STYLE`. Unset, the build falls back to **ad-hoc** signing
(`./gen` defaults the identity to `-` rather than empty — an unsigned binary can't
carry entitlements at all, which would silently disable the sandbox).

Prefer the certificate releases are signed with, so local and released builds
share a grant. If one goes stale:
`tccutil reset ScreenCapture net.robgough.ShotAndTell`.

## Architecture

Two source folders, one target:

- **`Sources/ShotAndTellKit/`** — the platform-light core: document model,
  numbering, compositor, background styles, markdown legend. **Nothing here may
  import AppKit or ScreenCaptureKit.** It's compiled straight into the app rather
  than built as a framework (no module boundary, no `public` churn), but kept
  separate so an iOS/iPadOS target can pick it up later by adding one line to
  `project.yml`.
- **`Sources/ShotAndTell/`** — the Mac app: entry point, menu bar, capture
  overlays, ScreenCaptureKit, editor window, settings, hotkey.

### Concurrency

`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` with Swift 6 language mode. This app is
almost entirely UI, so main-actor is the default and the *exceptions* — the
ScreenCaptureKit grab, PNG encoding — are what have to be marked. Don't sprinkle
`@MainActor`; it's already implied.

### Entry point

There is no `MainMenu.xib`. `ShotAndTellMain.swift` creates `NSApplication`, sets
the delegate and calls `run()` by hand, because:

- `@main` on an `NSApplicationDelegate` routes through `NSApplicationMain`, which
  expects to find the delegate wired up in a nib. Without one the app launches
  perfectly happily and then never calls a single delegate method — no status
  item, no Dock-click capture, and no error explaining why.
- A top-level `main.swift` isn't an option either: top-level code in an AppKit
  target makes the linker try to link `SwiftUICore` directly, which it refuses.

The menu bar (`MainMenu.swift`) is built in code for the same reason.

### Three ways into a capture

The Dock icon (`applicationShouldHandleReopen`), the menu bar
(`MenuBarController`), and the global hotkey (phase 5). All three funnel through
`CaptureCoordinator.beginCapture(_:)` — keep it that way, so behaviour like
"don't start a second capture while the picker is up" is written once.

## Sandbox

Hard sandbox, because the Mac App Store requires it. The entitlements are
deliberately minimal and **there is no network entitlement** — the app makes no
network connections at all, and not having the entitlement means it can't. Don't
add one without a very good reason and a matching change to
`PrivacyInfo.xcprivacy`.

Two entitlements files, swapped per configuration, differing *only* in
`get-task-allow` (Debug true so the debugger attaches; Release false because the
App Store rejects binaries that ship with it set). Any other change goes in both.

Screen recording needs no entitlement — ScreenCaptureKit works inside the sandbox
and consent is handled by TCC — and macOS composes that permission prompt itself,
so there's no Info.plist purpose string to write. The explaining has to happen in
our own first-run UI.

## Changelog

When a commit changes user-visible behaviour, add a one-line bullet under
`## Unreleased` in `CHANGELOG.md` in the same commit. User language, not commit
language. Internal changes — refactors, build tweaks — don't belong there.
