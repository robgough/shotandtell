# App Store listing — Shot and Tell 1.0

The long fields live in their own files so they can be pasted into App Store
Connect without the line breaks a Markdown table would put in them:

| Field | File | Length |
| --- | --- | --- |
| Promotional Text | [`promotional-text.txt`](promotional-text.txt) | 159 / 170 |
| Description | [`description.txt`](description.txt) | 2496 / 4000 |
| Keywords | [`keywords.txt`](keywords.txt) | 98 / 100 |
| App Review notes | [`review-notes.txt`](review-notes.txt) | 1549 |

## The short fields

| Field | Value |
| --- | --- |
| Name (30) | `Shot and Tell` |
| Subtitle (30) | `Annotate screenshots for AI` |
| Bundle ID | `net.robgough.shotandtell` |
| SKU | `shotandtell-mac` |
| Primary category | Productivity |
| Secondary category | Developer Tools |
| Price | Free, no in-app purchases |
| Age rating | 4+ |
| Copyright | `2026 Rob Gough` |
| Support URL | `https://shotandtell.robgough.net` |
| Marketing URL | `https://shotandtell.robgough.net` |
| Privacy Policy URL | `https://shotandtell.robgough.net/privacy.html` |
| App Privacy | Data Not Collected — every question answered "No" |
| What's New | `First release.` |

## Screenshots

`screenshots/` — four PNGs at 2880 × 1800, which is one of the two sizes a Mac
listing accepts (the other is 2560 × 1600). Upload them in this order:

| File | Caption in the image |
| --- | --- |
| `01-editor.png` | Point at it, then say what you mean |
| `02-result.png` | One image, with the words attached |
| `03-redact.png` | Black out what they don't need to see |
| `04-settings.png` | Set it up once |

Rebuild them from the sources with:

```
swift scripts/make-appstore-shots.swift appstore/sources appstore/screenshots
```

Everything in `sources/` is real: `win.png` and `settings.png` are
screencaptures of the app's own windows, and `export.png` and `export2.png`
came out of the app's own compositor rather than being drawn to look like it.
`subject.html` and `subject2.html` are the throwaway pages being screenshotted
— invented, so no real product or person is on show — and `demo.json` /
`demo2.json` are the mark positions and descriptions used in each.

Reproducing the two window shots needs the editor opened with marks already in
place, which the app has no way to do on its own. That was a temporary
`DemoLoader` reading those JSON files, removed once the shots were taken; it's
in the history if the screenshots ever need retaking.
