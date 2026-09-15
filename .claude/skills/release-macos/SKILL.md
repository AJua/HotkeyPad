---
name: release-macos
description: Builds hotkeypad_host's macOS release and packages it into a styled, distributable .dmg (custom background, app + drag-to-Applications layout). Use this whenever the user asks to release, package, or build a distributable .dmg for the macOS host app.
---
# Release: macOS .dmg for HotkeyPad Host

Packages `hotkeypad_host` into a signed, styled `.dmg` ready to hand to a
user for install. This is the entire release process for the macOS app —
there is nothing else to do by hand.

## Usage

Run the script from the repo root:

```
scripts/package_macos_dmg.sh
```

or, from anywhere:

```
.claude/skills/release-macos/scripts/package_macos_dmg.sh
```

Flags:
- `--skip-build` — reuse the existing `build/macos/.../Release/*.app`
  instead of rebuilding it first. Use this when iterating on the DMG
  background/layout without needing to rebuild Flutter each time.

The script prints its own progress and ends with a `done: <path> (<size>
MB)` line. Output lands at `hotkeypad_host/dist/<AppName>-<version>.dmg`
(app name and version are read from the project itself — not hardcoded).

## What it does

1. Cleans up any disk images left mounted under this app's volume name
   from a previous failed attempt (a real cause of cascading failures on
   this machine — see below).
2. Builds `hotkeypad_host` in release mode (unless `--skip-build`).
3. Runs `create-dmg` to produce a styled window (custom background,
   app icon + Applications drop-link, hidden extension).
4. If `create-dmg`'s own final compression step fails (see "Known
   machine-specific issue" below), recovers the styled intermediate image
   it already produced and finishes the compression itself.
5. Sanity-checks the result (size relative to the source `.app`) and
   verifies the final `.dmg` mounts and contains a correctly-signed app,
   printing `codesign -dv` output.

Every step is idempotent — safe to just re-run the script if anything
above fails partway.

## Known machine-specific issue: `hdiutil convert failed`

On this machine, `create-dmg`'s internal step that converts its styled
read/write image into the final compressed read-only `.dmg` reliably
fails with `hdiutil: convert failed - Resource temporarily unavailable`.
The Finder/AppleScript styling before that point always succeeds. The
script already works around this automatically (step 4 above) — this is
just documented here so a `hdiutil convert failed` line in the script's
own output is expected and not a sign anything actually went wrong, as
long as the script goes on to print `done: ...` at the end.

If the script fails for a *different* reason, check:
- **Leftover mounted images**: `hdiutil info | grep -c image-path` should
  match whatever it was before you started. If it's crept up, something
  (a previous manual `hdiutil attach`/`open` you ran outside this script,
  not the script itself — it always cleans up its own mounts) is still
  attached; find it with `hdiutil info` and `hdiutil detach <device>
  -force`.
- **`create-dmg` not installed**: the script installs it via
  `brew install create-dmg` automatically if missing.

## Editing the install-screen background

Source image: `hotkeypad_host/macos/dmg_assets/dmg_background.png`
(660×400, matching `WINDOW_W`/`WINDOW_H` in the script). It is
intentionally **text-only** (title + short instruction) — an earlier
version tried to draw an arrow from the app icon to the Applications
drop-link, but `create-dmg`'s actual icon placement in the rendered
Finder window didn't match what its `--icon`/`--app-drop-link` coordinate
arguments alone would suggest, and this environment cannot screenshot a
real Finder window to iterate on that mapping (see the note below). Keep
any future background edits confined to elements that don't depend on
where Finder ends up placing an icon.

## Verification limits in this environment

This environment cannot reliably screenshot real macOS GUI windows
(`osascript`/`screencapture` return stale or unrelated content — this is
also documented in the repo's `CLAUDE.md` for `hotkeypad_host`'s own app
window, and was separately confirmed to apply to Finder DMG windows too).
After running this script, verification stops at what's checked
programmatically: the DMG mounts, contains the app, and the app is
correctly signed. If the actual install-screen appearance needs
confirming, ask the user to open the `.dmg` themselves and describe or
screenshot what they see.
