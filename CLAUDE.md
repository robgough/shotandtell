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

A post-build phase installs a copy to `~/Applications/Shot and tell.app`, purely
as a stable thing to launch. The bundle is `Shot and tell.app` (`PRODUCT_NAME`)
while the Swift module is `ShotAndTell` (`PRODUCT_MODULE_NAME`).

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

macOS keys the Screen Recording grant to the bundle ID and the app's
*code-signing requirement* — not its path. Ad-hoc signatures change on every
build, so the grant is revoked every time. Set both `SHOTANDTELL_TEAM_ID` and
`SHOTANDTELL_CODE_SIGN_IDENTITY` in `.env` to pin it to a real certificate;
setting only the team ID still leaves the identity empty, which is still ad-hoc,
which is why `./gen` warns on the *identity*.

Unset, the build falls back to **ad-hoc** signing (`./gen` defaults the identity
to `-` rather than empty — an unsigned binary can't carry entitlements at all,
which would silently disable the sandbox).

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

**Every declaration in `Sources/ShotAndTellKit/` must be marked `nonisolated`.**
The isolation default is module-wide, and Kit is compiled into the same module,
so without it the document model, the compositor and even their synthesised
`Codable` / `CaseIterable` conformances become main-actor-isolated — which is
precisely backwards, because composing and encoding the image is the work that
belongs off the main thread. It fails at the point of *use*, not the point of
declaration, so it's cheap now and a retrofit across every Kit type later.

If an iOS target ever arrives, promote Kit to a local Swift package with its own
`SWIFT_DEFAULT_ACTOR_ISOLATION = nonisolated`. That also turns "nothing here may
import AppKit" from a comment into a compile error. Not done yet because it means
`public` on everything while the model is still changing shape daily.

### Entry point

There is no `MainMenu.xib`. `ShotAndTellMain.swift` creates `NSApplication`, sets
the delegate and calls `run()` by hand, because:

`@main` on an `NSApplicationDelegate` uses AppKit's default `main()`, which just
calls `NSApplicationMain` and never instantiates the delegate — it expects to find
one connected in a MainMenu nib. Without a nib the app launches perfectly happily
and then never calls a single delegate method: no status item, no Dock-click
capture, and no error explaining why.

A top-level `main.swift` works equally well and is a fine alternative; the `@main`
enum is used only because it gives the weakly-referenced delegate somewhere
obvious to be owned.

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
