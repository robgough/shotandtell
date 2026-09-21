# Shot and tell — build plan

A macOS screenshot tool for talking to AI about pictures. You capture, you point at
things with numbered markers and describe them, and you get back a single image with
the shot on a background and a numbered legend beside it — so "the heading in ① is too
big" is unambiguous to a model that can only see pixels.

Status: planning. Nothing built yet.

## Decisions taken

| Question | Decision |
| --- | --- |
| Distribution | **Mac App Store only.** Hard sandbox, no Sparkle, no Accessibility APIs. |
| Minimum macOS | **26.0** (matches Dictator). |
| Composition | Screenshot inset on a background, **legend column on the right**. |
| Editor | **Dedicated editor window**, live WYSIWYG — what you see *is* the export. |
| Tools (v1) | Numbered pin, numbered arrow, numbered box, redaction rectangle. |
| Export | **Composed PNG to clipboard** + **saved PNG to disk**. No history/library in v1. |
| Capture modes | Region drag, window click, whole screen, timed (3/5/10s). |
| Background | Neutral default + per-shot picker (neutral / gradients / solid / none). |
| Legend header | **Editable title** you type. No app branding on the output. |
| Hotkey | Global, **user-configurable** (Carbon `RegisterEventHotKey` — sandbox-safe). |
| Output size | **2x, long edge capped ~2400pt** so files stay paste-able. |
| Pricing | **Free, no IAP.** No StoreKit code. |

Still open: app icon, App Store name availability, bundle ID, marketing site.

## Shape of the app

Menubar `NSStatusItem` **and** a Dock icon (so `LSUIElement` stays false). Three ways in:

1. Click the Dock icon → `applicationShouldHandleReopen` starts a capture.
2. Menubar → *New Capture* (plus mode submenu, Settings, Quit).
3. The global hotkey.

All three funnel into one `CaptureCoordinator.beginCapture(mode:)`.

## Architecture

XcodeGen (`project.yml` → `./gen` → `ShotAndTell.xcodeproj`, gitignored), same as Dictator.
Two source folders, one target now, room for an iOS target later:

- **`Sources/ShotAndTellKit/`** — platform-light core that an iOS app could reuse:
  the document model, the numbering rules, the compositor, background styles, PNG
  encoding. No `SCStream`, no `NSStatusItem`. Compiled straight into the target's
  sources list (not a framework — no `public` churn), Dictator-style.
- **`Sources/ShotAndTell/`** — the Mac app: app delegate, menubar, capture overlays,
  ScreenCaptureKit plumbing, editor window, settings, hotkey.

### The pieces

**`CaptureService`** — ScreenCaptureKit. `SCShareableContent` to enumerate displays and
windows; one borderless overlay window per display at `.screenSaver` level for the
crosshair/dimming; `SCScreenshotManager` for the actual grab. Window mode hit-tests the
window list under the cursor and highlights it; optionally grabs with shadow + rounded
corners. Timed mode just delays the overlay. Returns a `CapturedImage` (CGImage + scale
+ source rect + app/window name, used to prefill the title).

**`Document`** (`ShotAndTellKit`) — `@Observable`, the whole state of one capture:

```
Document
  image: CGImage, scale: CGFloat
  title: String
  background: BackgroundStyle        // neutral | gradient(id) | solid(color) | none
  annotations: [Annotation]
```

`Annotation` is an enum over `Pin(point, text)`, `Arrow(from, to, text)`,
`Box(rect, text)`, `Redaction(rect, style)`. Geometry is stored in **normalised image
coordinates** (0…1) so the model is independent of display scale and of how the editor
happens to be zoomed — that's the thing that keeps preview and export identical.

Numbering is derived, never stored: pins, arrows and boxes share one counter in
creation order, so deleting ② renumbers everything after it in both the canvas and the
legend, automatically. Redactions aren't numbered (they appear once in the legend as a
key, if at all).

**`Compositor`** (`ShotAndTellKit`) — the single source of truth for what the output
looks like. One function: `Document -> CGImage`, drawing via Core Graphics into a
context sized from the layout rules (padding, inset shadow, corner radius, legend
column width, type scale). The editor renders **the same compositor output** as its
preview rather than a parallel SwiftUI re-implementation. This is the one design
decision I'd most defend: two renderers always drift.

Layout maths lives in a `CompositionLayout` value — computes legend column width from
the longest line, wraps text, grows the canvas to fit whichever of image/legend is
taller, then scales to the 2400pt cap.

**`EditorWindowController`** — SwiftUI in an `NSWindow`. Toolbar (pin / arrow / box /
redact / background / Done), canvas on the left, legend list on the right. Clicking the
canvas drops a marker *and* focuses its legend row, so the flow is click → type →
click → type without ever reaching for the mouse in between. Escape cancels, ⌘Z undoes
(`UndoManager` over document mutations), ⌘⏎ is Done.

**`Exporter`** — `Compositor` → PNG → `NSPasteboard` + write to disk. Redaction is
applied by the compositor as opaque fill, so the censored pixels are never in the
exported bytes at all. The original capture is never written to disk.

**Settings** — hotkey recorder, default background, save folder, output size, whether
window captures include shadow. `@AppStorage`-backed, one SwiftUI settings scene.

## Sandbox / App Store notes

These are the things that will bite, worth getting right at the start rather than
retrofitting:

- **Screen recording** — ScreenCaptureKit works inside the sandbox, but needs the TCC
  *Screen & System Audio Recording* grant. Needs a first-run explainer and a graceful
  "open System Settings" path when denied. macOS re-prompts periodically; the app must
  handle the permission vanishing mid-session.
- **Saving to ~/Pictures** — a sandboxed app has no free access to it. Use the
  `com.apple.security.assets.pictures.read-write` entitlement for the default
  `~/Pictures/Shot and tell/` folder; if the user picks a different folder, hold a
  security-scoped bookmark.
- **Global hotkey** — `RegisterEventHotKey` (Carbon) works in the sandbox and needs no
  Accessibility grant. `CGEventTap`/`NSEvent.addGlobalMonitor` do need it — avoid both.
- **Privacy manifest** (`PrivacyInfo.xcprivacy`) is required for submission.
- **No Sparkle**, no update checks, no analytics. Review-clean, and less code.
- Signing: Apple Distribution + Mac App Store provisioning profile via `.env`
  (`SHOTANDTELL_TEAM_ID`), following Dictator's `./gen` pattern. Local debug builds can
  stay on a Developer ID cert so the screen-recording grant survives rebuilds — TCC keys
  the grant to the signing identity, and ad-hoc signing changes it every build.

## Phases

Each phase ends with something runnable and a commit.

**0 — Skeleton.** `project.yml`, `./gen`, `.env.example`, entitlements, README, CLAUDE.md.
App launches with a Dock icon and a menubar item; both trigger a stub that logs.
*Done when:* `./gen && xcodebuild` is clean and the app runs.

**1 — Capture.** Permission flow, overlay windows, region drag with magnifier and
dimensions readout, then window click, whole screen, timed. Ends by dumping a PNG to
the clipboard — no markup yet, but already a usable screenshot tool.
*Done when:* all four modes produce a correct image on multi-display, mixed-DPI setups.

**2 — Document + editor shell + pins.** Model, compositor v1 (image on neutral
background, empty legend column), editor window rendering compositor output, pin tool,
legend rows, keyboard flow, undo, delete + renumber.
*Done when:* capture → drop three pins → type three lines → the preview looks like the
thing you'd want to paste.

**3 — The other three tools.** Arrow (drag, numbered at the tail, tidy arrowhead),
numbered box, redaction rectangle. Selection, dragging to reposition, resize handles.

**4 — Composition polish + export.** Background picker, editable title, typography and
spacing pass, portrait/landscape behaviour, 2x render with the width cap, clipboard +
disk write, filename scheme, "Reveal in Finder".
*Done when:* the output is genuinely nice to look at, not merely correct.

**5 — Settings, hotkey, first run.** Hotkey recorder, preferences, permission
onboarding, About.

**6 — Ship.** App icon, App Store Connect record, screenshots, description, privacy
manifest, TestFlight, submit. `CHANGELOG.md` from the first release on, same
user-language style as Dictator.

**Later (not v1):** iPhone/iPad app over `ShotAndTellKit`; capture history; markdown
legend on the clipboard as text as well as pixels; scrolling capture; annotation
presets.

## Risks

- **Getting the output *attractive*** is the actual hard part, and it's a taste problem
  rather than an engineering one. Expect phase 4 to take real iteration, and expect to
  look at a lot of exports side by side.
- **Window capture with shadow** gets fiddly around rounded corners and transparency.
  Fallback: capture the window rect without shadow, synthesise the shadow in the
  compositor — probably nicer anyway, and consistent across sources.
- **App Store review** occasionally takes against screen-capture apps. Mitigation: a
  clear purpose string, no network access at all (declare no entitlement for it), and a
  demo video with the submission.
- **Name availability** — "Shot and tell" may collide on the Store. Worth checking
  before the icon gets drawn.
