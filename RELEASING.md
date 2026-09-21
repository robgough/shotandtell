# Releasing Shot and Tell

Shot and Tell ships through the **Mac App Store** only. There is no Sparkle feed,
no appcast and no notarized DMG — which makes this shorter than Dictator's
release process, but it's also new ground: Dictator has only ever shipped
Developer ID builds, so none of the App Store machinery is reused from there.

## What's already done in the repo

These are the things an App Store archive is rejected for, and they're all in
place — worth knowing so you don't go hunting when something else fails:

| Requirement | Where |
| --- | --- |
| Hard sandbox, no network entitlement | `Sources/ShotAndTell/ShotAndTell.entitlements` |
| `get-task-allow` false in Release | same file (Debug has its own) |
| `LSApplicationCategoryType` | `project.yml` → `info.properties` (ITMS-90242) |
| App icon, every size | `Sources/ShotAndTell/Assets.xcassets` (ITMS-90236) |
| Privacy manifest | `Sources/ShotAndTell/PrivacyInfo.xcprivacy` |
| Export compliance answered | `ITSAppUsesNonExemptEncryption: false` in `project.yml` |

## One-time setup

### 1. Apple Developer Program

The paid programme ($99/year). The free Personal Team can't sign for
distribution at all.

### 2. Certificates

App Store distribution needs **different** certificates from the Developer ID
ones Dictator uses. Two of them:

- **Apple Distribution** — signs the `.app`.
- **Mac Installer Distribution** (shown in older docs as "3rd Party Mac Developer
  Installer") — signs the `.pkg` that actually gets uploaded.

Xcode → Settings → Accounts → Manage Certificates → **+** for each.

### 3. App Store Connect record

At <https://appstoreconnect.apple.com>, create a new macOS app:

- **Bundle ID** `net.robgough.ShotAndTell` — register it first under
  Certificates, Identifiers & Profiles, with the App Sandbox capability.
- **Name** "Shot and Tell" (confirmed available).
- **Primary category** Productivity, matching `LSApplicationCategoryType`.
- **Privacy policy URL** — required even though the app collects nothing. A page
  saying exactly that is enough.
- **App privacy** — answer "No" to data collection throughout. It's true: the app
  has no network entitlement, so it couldn't transmit anything if it wanted to.

### 4. Provisioning profile

A **Mac App Store** distribution profile for the bundle ID. Let Xcode create it
on first use; there's nothing to configure in this repo.

Don't bother switching the target to automatic signing before archiving. It
wouldn't survive anyway — "Cutting a release" starts with `./gen`, which
regenerates the project from `project.yml` and pins Manual signing again — and it
isn't needed: the CLI archive is signed with whatever `.env` names (a Developer
ID certificate, most likely), and Organizer **re-signs** it with the Apple
Distribution certificate and the Mac App Store profile on the way out. The
archive's own signature is throwaway.

## Cutting a release

1. **Bump the version.** `MARKETING_VERSION` in `project.yml`. `CURRENT_PROJECT_VERSION`
   must increase on every upload, even a re-upload of the same version — App Store
   Connect rejects a build number it has seen before.
2. **Move the changelog.** Everything under `## Unreleased` in `CHANGELOG.md` goes
   under a `## v<version> — <date>` heading. The same text is the "What's New"
   field in App Store Connect, which is why the changelog is written in user
   language rather than commit language.
3. **Archive.**

   ```bash
   ./gen
   DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
     -project ShotAndTell.xcodeproj -scheme ShotAndTell \
     -configuration Release -archivePath build/ShotAndTell.xcarchive \
     archive
   ```

4. **Upload.** The reliable path is Xcode's Organizer (Window → Organizer →
   select the archive → Distribute App → App Store Connect). It handles the
   re-signing with the Apple Distribution certificate and the Mac App Store
   profile, builds the `.pkg` and uploads it.

   The CLI path is `xcodebuild -exportArchive` with an `ExportOptions.plist`
   whose `method` is `app-store-connect` and `destination` is `upload`, or
   exporting the `.pkg` and sending it with the Transporter app. Note that
   `xcrun altool --upload-app` is **not** an option: Apple discontinued it in
   November 2023. Given releases are occasional, Organizer is fine.

5. **Submit.** Attach the build in App Store Connect, fill in What's New, submit
   for review.

## Review notes

Screen-capture apps get looked at. Things that help:

- The purpose is obvious from the screenshots and description — point at things
  in a screenshot and describe them.
- **No network entitlement at all.** Say so in the review notes; it's the
  strongest possible answer to "where do the screenshots go".
- Include a short demo video with the submission. Reviewers can't grant Screen
  Recording on their own machine as smoothly as a user can, and a review that
  stalls on "we couldn't get it to capture anything" costs a week.
- Guideline 2.4.5(i) sometimes prompts a question about the
  `com.apple.security.assets.pictures.read-write` entitlement. The answer is that
  it's the default save location for the screenshots the user just took.

## Screenshots for the listing

The App Store wants macOS screenshots at 2880×1800 or 2560×1600. The app can take
them of itself, which is the obvious thing to do and also a decent smoke test.
