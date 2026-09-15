# fastlane for HotkeyPad (iOS / App Store)

Automates pushing HotkeyPad's App Store Connect listing (description,
keywords, screenshots) and binary — no manual clicking through the App
Store Connect web UI.

## One-time setup

1. **Install fastlane** (already vendored — see `../Gemfile`):

   ```
   cd hotkeypad_client/ios
   bundle install
   ```

2. **Fill in `fastlane/Appfile`**: replace the two `TODO_...` placeholders
   with your Apple ID email and Team ID (Apple Developer → Membership),
   or set them as environment variables instead so nothing account-
   specific has to live in a checked-in file:

   ```
   export FASTLANE_APPLE_ID="you@example.com"
   export FASTLANE_TEAM_ID="ABCDE12345"
   ```

3. **Set up an App Store Connect API key** (recommended over Apple ID
   login — no 2FA prompt, works the same in CI):

   - App Store Connect → Users and Access → Integrations → App Store
     Connect API → generate a key with the "App Manager" role.
   - Download the `.p8` file once (Apple only lets you download it
     once) and note the Key ID and Issuer ID.
   - Convert it into the JSON shape fastlane's `app_store_connect_api_key`
     action expects and save it as `fastlane/api_key.json` (already
     gitignored — never commit this file):

     ```json
     {
       "key_id": "ABC123DEFG",
       "issuer_id": "12345678-1234-1234-1234-123456789012",
       "key": "-----BEGIN PRIVATE KEY-----\n...\n-----END PRIVATE KEY-----\n",
       "in_house": false
     }
     ```

   Without this file, lanes fall back to interactive Apple ID login
   using the Appfile's `apple_id` (will prompt for a 2FA code).

4. **Create the app in App Store Connect** first, if it doesn't exist yet
   (My Apps → + → New App), using bundle ID `com.chienhunglin.hotkeypad`.
   fastlane pushes an existing app's listing/binary — it doesn't create
   the app record itself.

## What's still a TODO in this checked-in scaffold

- `fastlane/Appfile` — Apple ID / Team ID placeholders (step 2 above).
- `fastlane/api_key.json` — not checked in at all; create it yourself
  (step 3).
- `fastlane/metadata/*/privacy_url.txt` — Apple requires a real, hosted
  privacy policy URL before a version can be submitted. HotkeyPad talks
  directly device-to-device and collects nothing, so a one-page static
  policy saying exactly that is enough — GitHub Pages is a free way to
  host one.
- `fastlane/metadata/*/support_url.txt` / `marketing_url.txt` — currently
  point at the GitHub repo as a placeholder; swap in a real support
  contact if you have one.
- App Store Connect's **Age Rating questionnaire** — has to be answered
  once in the web UI (App Information → Age Rating) before any version
  can be submitted; fastlane has no action for first-time completion of
  this.
- `fastlane/screenshots/` — empty. Add per-locale, per-device-size PNGs
  (e.g. `screenshots/en-US/iPhone 6.9/01.png`) before running a lane that
  uploads screenshots, or pass `skip_screenshots: true`.
- The description/keywords/subtitle drafts in `fastlane/metadata/` are a
  starting point — read them over and adjust the voice/wording to taste
  before the first real submission.

## Lanes

Run from `hotkeypad_client/ios/`:

- `bundle exec fastlane ios build` — `flutter build ipa --release` only.
- `bundle exec fastlane ios metadata` — push text + screenshots, no
  binary. Good for fixing a typo or updating the listing without a new
  build.
- `bundle exec fastlane ios beta` — build, then upload to TestFlight.
- `bundle exec fastlane ios release` — build, then upload binary + full
  listing to App Store Connect. Add `submit:true` to also submit the new
  version for review:

  ```
  bundle exec fastlane ios release submit:true
  ```
