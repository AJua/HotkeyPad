#!/usr/bin/env bash
# Builds hotkeypad_host's macOS release and packages it into a styled,
# distributable .dmg (custom background, app + drag-to-Applications
# layout). Idempotent and safe to re-run: cleans up after itself and
# after any previous failed attempt before doing anything else.
#
# Usage:
#   scripts/package_macos_dmg.sh [--skip-build]
#
#   --skip-build   Reuse the existing build/macos/.../Release/*.app
#                  instead of rebuilding it first.
#
# Everything this needs to know (app name, bundle version, background
# image, icon layout) is read from the project itself or set once as a
# constant below — nothing is hardcoded from a specific run.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)"
HOST_DIR="$REPO_ROOT/hotkeypad_host"
DIST_DIR="$HOST_DIR/dist"
BACKGROUND="$HOST_DIR/macos/dmg_assets/dmg_background.png"

SKIP_BUILD=0
for arg in "$@"; do
  case "$arg" in
    --skip-build) SKIP_BUILD=1 ;;
    *)
      echo "Unknown argument: $arg" >&2
      echo "Usage: $0 [--skip-build]" >&2
      exit 1
      ;;
  esac
done

command -v create-dmg >/dev/null 2>&1 || {
  echo "create-dmg not found — installing via Homebrew..." >&2
  brew install create-dmg
}

# --- Read the app's own identity rather than hardcoding it -----------------
APP_NAME="$(grep '^PRODUCT_NAME' "$HOST_DIR/macos/Runner/Configs/AppInfo.xcconfig" | sed -E 's/^PRODUCT_NAME *= *//')"
VERSION="$(grep '^version:' "$HOST_DIR/pubspec.yaml" | sed -E 's/^version: *//' | cut -d+ -f1)"
APP_BUNDLE="$APP_NAME.app"
DMG_NAME="$APP_NAME-$VERSION.dmg"
FINAL_DMG="$DIST_DIR/$DMG_NAME"

# DMG window/icon layout. --window-size is a *request* to create-dmg, not
# a guarantee of what Finder actually renders — a real screenshot this
# session showed icon "position" coordinates land somewhere other than
# where these numbers alone would suggest, and this environment cannot
# screenshot the real Finder window to re-check that mapping (see
# CLAUDE.md). Keep dmg_background.png text-only for exactly that reason:
# text position only depends on the image's own pixels, not on where
# Finder ends up placing an icon.
WINDOW_W=660
WINDOW_H=400
ICON_SIZE=128
APP_ICON_X=180
APP_ICON_Y=185
APPLICATIONS_ICON_X=480
APPLICATIONS_ICON_Y=185

log() { echo "[package_macos_dmg] $*"; }

# --- Defensive cleanup: a disk image this same script left mounted from -----
# an earlier failed run is exactly what starves hdiutil of resources and
# makes the *next* run fail too (confirmed this session: five leftover
# mounts from earlier manual attempts were the actual cause of a string
# of "Resource temporarily unavailable" errors, not a real one-off
# glitch). Detach anything already mounted under this app's volume name
# before doing anything else.
cleanup_stale_mounts() {
  local device
  while IFS= read -r device; do
    [ -n "$device" ] || continue
    log "detaching stale mount: $device"
    hdiutil detach "$device" -force >/dev/null 2>&1 || true
  done < <(hdiutil info | awk -v name="$APP_NAME" '
    /^\/dev\/disk[0-9]+$/ { dev = $1 }
    $0 ~ "/Volumes/" name { print dev }
  ')
}

# hdiutil attach/create/convert on this machine fail intermittently with
# "Resource temporarily unavailable" even with nothing else going on —
# confirmed transient by retrying the exact same command immediately
# after (this session: it succeeded on the very next attempt every
# time). Retry a handful of times with a short backoff rather than
# treating the first failure as final.
retry() {
  local attempts=$1
  shift
  local n=1
  until "$@"; do
    if [ "$n" -ge "$attempts" ]; then
      echo "Failed after $attempts attempts: $*" >&2
      return 1
    fi
    log "attempt $n/$attempts failed, retrying in 8s: $*"
    sleep 8
    n=$((n + 1))
  done
}

# Notarizes and staples $FINAL_DMG using an App Store Connect API key, so a
# fresh install of the app doesn't trip Gatekeeper's "unidentified developer"
# warning. Needs NOTARY_API_KEY_PATH/NOTARY_API_KEY_ID/NOTARY_API_ISSUER_ID
# in the environment (set by CI from secrets, or export them yourself for a
# local run) — silently skipped without them, so a plain local iteration
# build still works without Apple credentials on hand.
notarize_dmg() {
  if [ -z "${NOTARY_API_KEY_PATH:-}" ] || [ -z "${NOTARY_API_KEY_ID:-}" ] || [ -z "${NOTARY_API_ISSUER_ID:-}" ]; then
    log "NOTARY_API_KEY_PATH/NOTARY_API_KEY_ID/NOTARY_API_ISSUER_ID not set — skipping notarization."
    return 0
  fi
  log "submitting $FINAL_DMG for notarization (this can take a few minutes)..."
  xcrun notarytool submit "$FINAL_DMG" \
    --key "$NOTARY_API_KEY_PATH" \
    --key-id "$NOTARY_API_KEY_ID" \
    --issuer "$NOTARY_API_ISSUER_ID" \
    --wait
  log "stapling notarization ticket..."
  xcrun stapler staple "$FINAL_DMG"
}

main() {
  mkdir -p "$DIST_DIR"
  cleanup_stale_mounts

  if [ "$SKIP_BUILD" -eq 0 ]; then
    log "building $APP_NAME (release)..."
    (cd "$HOST_DIR" && flutter build macos --release)
  fi

  local built_app="$HOST_DIR/build/macos/Build/Products/Release/$APP_BUNDLE"
  [ -d "$built_app" ] || {
    echo "Expected build output not found: $built_app" >&2
    echo "(run without --skip-build, or build it first)" >&2
    exit 1
  }

  # Not `local`: the EXIT trap fires after main() has already returned,
  # by which point a local variable's scope is gone — under `set -u`
  # that turned into "work: unbound variable" right after a fully
  # successful run (confirmed the hard way testing this script).
  work="$(mktemp -d)"
  trap 'rm -rf "$work"' EXIT

  local src="$work/src"
  mkdir -p "$src"
  cp -R "$built_app" "$src/"

  rm -f "$FINAL_DMG"
  # create-dmg's own final step — converting the read/write image it
  # styles via Finder into a compressed read-only one — fails on this
  # machine close to every time (see the retry() doc comment above; the
  # same transient failure, just inside create-dmg's own hdiutil call
  # instead of one of ours). Let it fail: what actually matters is the
  # *styled* rw.*.dmg it leaves behind either way, which the fallback
  # below turns into the final compressed image itself.
  create-dmg \
    --volname "$APP_NAME" \
    --background "$BACKGROUND" \
    --window-size "$WINDOW_W" "$WINDOW_H" \
    --icon-size "$ICON_SIZE" \
    --icon "$APP_BUNDLE" "$APP_ICON_X" "$APP_ICON_Y" \
    --app-drop-link "$APPLICATIONS_ICON_X" "$APPLICATIONS_ICON_Y" \
    --hide-extension "$APP_BUNDLE" \
    --no-internet-enable \
    "$FINAL_DMG" \
    "$src" || true

  if [ -f "$FINAL_DMG" ]; then
    log "create-dmg produced the final image directly."
  else
    log "create-dmg's own compression step failed (expected on this machine) — finishing manually."
    local rw_dmg
    rw_dmg="$(find "$DIST_DIR" -maxdepth 1 -name "rw.*.$DMG_NAME" -print -quit)"
    [ -n "$rw_dmg" ] || {
      echo "create-dmg left no rw.*.dmg to recover — something else went wrong." >&2
      exit 1
    }

    local mount_point="$work/mount"
    mkdir -p "$mount_point"
    retry 5 hdiutil attach "$rw_dmg" -mountpoint "$mount_point" -nobrowse -readonly
    # A mount that "succeeds" but races the copy right after has produced
    # a silently-empty DMG before (this session, more than once) — check
    # the app actually landed before trusting the mount.
    [ -d "$mount_point/$APP_BUNDLE" ] || {
      echo "Mounted $rw_dmg but $APP_BUNDLE is missing from it." >&2
      exit 1
    }

    local styled="$work/styled"
    mkdir -p "$styled"
    cp -R "$mount_point/." "$styled/"
    hdiutil detach "$mount_point" -quiet
    rm -f "$rw_dmg"

    retry 5 hdiutil create \
      -volname "$APP_NAME" \
      -srcfolder "$styled" \
      -fs HFS+ \
      -format UDZO \
      -ov \
      "$FINAL_DMG"
  fi

  # Sanity check: a truncated/empty DMG from a race earlier in this same
  # session was under 15KB against a real ~20MB image — anything much
  # smaller than the source .app means something silently went wrong
  # rather than actually packaging it.
  local dmg_bytes app_bytes
  dmg_bytes="$(stat -f%z "$FINAL_DMG")"
  app_bytes="$(du -sk "$built_app" | cut -f1)"
  app_bytes=$((app_bytes * 1024))
  if [ "$dmg_bytes" -lt $((app_bytes / 4)) ]; then
    echo "$FINAL_DMG is suspiciously small ($dmg_bytes bytes vs a $app_bytes byte .app) - probably packaged empty." >&2
    exit 1
  fi

  notarize_dmg

  log "verifying the final image..."
  local verify_mount="$work/verify"
  mkdir -p "$verify_mount"
  retry 5 hdiutil attach "$FINAL_DMG" -mountpoint "$verify_mount" -nobrowse -readonly
  [ -d "$verify_mount/$APP_BUNDLE" ] || {
    echo "Final DMG does not contain $APP_BUNDLE." >&2
    exit 1
  }
  codesign -dv "$verify_mount/$APP_BUNDLE" 2>&1 | sed 's/^/[codesign] /'

  # Ask spctl the same question Gatekeeper asks at first launch. This is
  # checked against a copy of the *app*, not the create-dmg container
  # itself — a plain disk image is never code-signed on its own, only
  # notarized/stapled, so running this same check against $FINAL_DMG
  # reports "rejected: no usable signature" even for a fully notarized
  # app (confirmed this session) — a false alarm, not a real one.
  local spctl_check="$work/spctl_check"
  cp -R "$verify_mount/$APP_BUNDLE" "$spctl_check"
  hdiutil detach "$verify_mount" -quiet
  spctl -a -t exec -vv "$spctl_check" 2>&1 | sed 's/^/[spctl] /' || true

  # Re-measure: stapling appends a ticket to the dmg, growing it slightly.
  dmg_bytes="$(stat -f%z "$FINAL_DMG")"
  log "done: $FINAL_DMG ($((dmg_bytes / 1024 / 1024)) MB)"
}

main "$@"
