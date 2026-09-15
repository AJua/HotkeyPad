# Working in this repo

## Verifying `hotkeypad_host` UI changes

This environment cannot reliably see or drive `hotkeypad_host`'s own macOS
window — `osascript`/`screencapture` against it show the terminal, stale
content, or plain desktop wallpaper rather than what's actually on
screen, and mouse clicks into it aren't controllable either. Don't spend
time trying to visually verify the host's UI.

For a `hotkeypad_host` UI change, verification stops at:

- `flutter analyze` and `flutter test` passing.
- Real logic exercised through pure, extracted functions (e.g.
  `isPressAllowed`, `nextLockedClientId`) rather than the widgets
  themselves, matching this project's established pattern of pulling
  testable decisions out of the UI code.

`hotkeypad_client` (the Android phone) is not affected by this — its UI remains
verifiable via `adb` screenshots as usual.
