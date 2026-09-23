# fastlane for HotkeyPad (Android / Google Play)

Automates pushing HotkeyPad's Play Console listing (description,
screenshots) and app bundle — no manual clicking through the Play
Console web UI.

## One-time setup

1. **Install fastlane** (already vendored — see `../Gemfile`):

   ```
   cd hotkeypad_client/android
   bundle install
   ```

2. **Create a release keystore** — not set up yet in this repo. Follow
   https://flutter.dev/to/reference-keystore, then wire it into
   `android/key.properties` (gitignored) the way that guide describes.
   `flutter build appbundle --release` produces an unsigned/debug-signed
   build without this, which Play Console will reject.

3. **Create the app in Play Console** first, if it doesn't exist yet
   (All apps → Create app), using package name
   `com.chienhunglin.hotkeypad`. Like `deliver` on the iOS side, `supply`
   pushes an existing app's listing/binary — it doesn't create the app
   record itself. Play Console also requires the first release of a new
   app to go through its web UI once (or via `supply` after the app's
   store listing and content rating questionnaire are complete) — a
   brand new app can't take its very first upload from an automated
   pipeline.

4. **Create a Play Console API service account**:

   - Play Console → Setup → API access → link/create a Google Cloud
     project, then create a service account there with the "Release
     manager" (or a custom role with release + app-info permissions)
     role.
   - Download its JSON key and save it as
     `fastlane/play-store-credentials.json` (already gitignored — never
     commit this file), or point `SUPPLY_JSON_KEY` at wherever you keep
     it instead:

     ```
     export SUPPLY_JSON_KEY="/path/to/play-store-credentials.json"
     ```

## What's still a TODO in this checked-in scaffold

- The release keystore itself (step 2 above) — nothing to sign a release
  build with yet.
- `fastlane/play-store-credentials.json` — not checked in at all; create
  it yourself (step 4).
- The Play Console **content rating questionnaire** and **data safety
  form** — first-time-only forms filled in on the Play Console web UI,
  same as the age rating step on the iOS side; `supply` doesn't have an
  action for either.
- `fastlane/metadata/android/*/images/` (at the repo root, shared with
  F-Droid) — no feature graphic, icon, or
  screenshots yet. Play requires at minimum a feature graphic
  (1024×500) and 2 phone screenshots before a listing can go live. See
  https://docs.fastlane.tools/actions/supply/#images-and-screenshots for
  the exact folder names `supply` expects.
- The description drafts in the repo-root `fastlane/metadata/android/*/` are a
  starting point — read them over before the first real submission.

## Lanes

Run from `hotkeypad_client/android/`:

- `bundle exec fastlane android build` — `flutter build appbundle
  --release` only.
- `bundle exec fastlane android metadata` — push text + screenshots, no
  binary.
- `bundle exec fastlane android beta` — build, then upload to a testing
  track (defaults to `internal`; pass `track:beta` for the open/closed
  beta track instead):

  ```
  bundle exec fastlane android beta track:beta
  ```

- `bundle exec fastlane android release` — build, then upload to
  production as a 10% staged rollout by default. Pass `rollout:1.0` to
  release to everyone at once:

  ```
  bundle exec fastlane android release rollout:1.0
  ```
