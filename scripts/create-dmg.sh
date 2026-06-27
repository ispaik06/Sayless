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
DIST_APP="$DIST_DIR/$APP_NAME"

find_release_app() {
  if [[ -n "${APP_PATH:-}" ]]; then
    printf '%s\n' "$APP_PATH"
    return
  fi

  if [[ -d "$DIST_APP" ]]; then
    printf '%s\n' "$DIST_APP"
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
ln -s /Applications "$STAGING_DIR/Applications"
rm -f "$DMG_PATH"

hdiutil create \
  -volname "Sayless" \
  -srcfolder "$STAGING_DIR" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

cat <<EOF
Created first-install DMG:
  $DMG_PATH

This DMG contains:
  - Sayless.app
  - Applications folder shortcut

Sparkle in-app updates should still use the ZIP from scripts/release-local.sh.
Do not commit dist/, ZIP, or DMG files to the Sayless source repository.
EOF
