#!/usr/bin/env bash
set -euo pipefail

# Creates a local first-install DMG.
#
# Sparkle in-app updates should use the ZIP produced by release-local.sh.
# This DMG is for initial installation and can be built without Developer ID
# signing or notarization for local development/testing.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
APP_NAME="Sayless.app"
DIST_DIR="$REPO_ROOT/dist"
BACKGROUND_PATH="$REPO_ROOT/scripts/assets/sayless_dmg_bg.png"
BACKGROUND_SOURCE_PATH="$REPO_ROOT/scripts/assets/sayless_dmg_bg_source3.png"
WINDOW_WIDTH=800
WINDOW_HEIGHT=400
APP_ICON_X=225
APP_ICON_Y=224
APPLICATIONS_ICON_X=575
APPLICATIONS_ICON_Y=224

find_release_app() {
  if [[ -n "${APP_PATH:-}" ]]; then
    printf '%s\n' "$APP_PATH"
    return
  fi

  local candidates=(
    "/tmp/SaylessReleaseBuild/Build/Products/Release/$APP_NAME"
    "$REPO_ROOT/build/Build/Products/Release/$APP_NAME"
    "$REPO_ROOT/build/Release/$APP_NAME"
  )

  local candidate
  for candidate in "${candidates[@]}"; do
    if [[ -d "$candidate" ]]; then
      printf '%s\n' "$candidate"
      return
    fi
  done

  local derived_data_candidate
  derived_data_candidate="$(
    find "$HOME/Library/Developer/Xcode/DerivedData" \
      -path "*/Build/Products/Release/$APP_NAME" \
      -type d \
      -print 2>/dev/null | sort | tail -n 1
  )"

  if [[ -n "$derived_data_candidate" && -d "$derived_data_candidate" ]]; then
    printf '%s\n' "$derived_data_candidate"
  fi
}

APP_SOURCE="$(find_release_app || true)"

if [[ -z "$APP_SOURCE" || ! -d "$APP_SOURCE" ]]; then
  cat >&2 <<'EOF'
error: Release Sayless.app was not found.

Build a Release app first, then run this script again:

  scripts/build-release.sh

You can also pass a specific app:

  APP_PATH=/path/to/Sayless.app scripts/create-dmg.sh
EOF
  exit 1
fi

mkdir -p "$DIST_DIR"

if ! command -v create-dmg >/dev/null 2>&1; then
  cat >&2 <<'EOF'
error: create-dmg was not found.

Install it first:

  brew install create-dmg
EOF
  exit 1
fi

if [[ ! -f "$BACKGROUND_PATH" ]]; then
  cat >&2 <<EOF
error: DMG background image was not found:
  $BACKGROUND_PATH
EOF
  exit 1
fi

BACKGROUND_SIZE="$(sips -g pixelWidth -g pixelHeight "$BACKGROUND_PATH" 2>/dev/null || true)"
BACKGROUND_WIDTH="$(awk '/pixelWidth/ {print $2}' <<<"$BACKGROUND_SIZE")"
BACKGROUND_HEIGHT="$(awk '/pixelHeight/ {print $2}' <<<"$BACKGROUND_SIZE")"

if [[ "$BACKGROUND_WIDTH" != "$WINDOW_WIDTH" || "$BACKGROUND_HEIGHT" != "$WINDOW_HEIGHT" ]]; then
  cat >&2 <<EOF
error: DMG background image must match the Finder window size.

Expected: ${WINDOW_WIDTH}x${WINDOW_HEIGHT}
Actual:   ${BACKGROUND_WIDTH:-unknown}x${BACKGROUND_HEIGHT:-unknown}

Regenerate it from the high-resolution source:

  sips -z $WINDOW_HEIGHT $WINDOW_WIDTH "$BACKGROUND_SOURCE_PATH" --out "$BACKGROUND_PATH"
EOF
  exit 1
fi

INFO_PLIST="$APP_SOURCE/Contents/Info.plist"
SHORT_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$INFO_PLIST")"
BUILD_NUMBER="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$INFO_PLIST")"
DMG_NAME="Sayless-${SHORT_VERSION}-${BUILD_NUMBER}.dmg"
DMG_PATH="$DIST_DIR/$DMG_NAME"
STAGING_DIR="$(mktemp -d "${TMPDIR:-/tmp}/sayless-dmg.XXXXXX")"

cleanup() {
  rm -rf "$STAGING_DIR"
}
trap cleanup EXIT

ditto "$APP_SOURCE" "$STAGING_DIR/$APP_NAME"
rm -f "$DMG_PATH"

create-dmg \
  --volname "Sayless" \
  --background "$BACKGROUND_PATH" \
  --window-size "$WINDOW_WIDTH" "$WINDOW_HEIGHT" \
  --text-size 12 \
  --icon-size 96 \
  --icon "$APP_NAME" "$APP_ICON_X" "$APP_ICON_Y" \
  --app-drop-link "$APPLICATIONS_ICON_X" "$APPLICATIONS_ICON_Y" \
  --no-internet-enable \
  --format UDZO \
  "$DMG_PATH" \
  "$STAGING_DIR"

cat <<EOF
Created first-install DMG:
  $DMG_PATH

This DMG contains:
  - Sayless.app
  - Applications folder drop link
  - Custom Finder background: scripts/assets/sayless_dmg_bg.png

Sparkle in-app updates should still use the ZIP from scripts/release-local.sh.
Do not commit dist/, ZIP, or DMG files to the Sayless source repository.
If you want this DMG in the appcast after uploading it to a GitHub Release, run scripts/publish-appcast.sh.
EOF
