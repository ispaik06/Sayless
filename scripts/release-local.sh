#!/usr/bin/env bash
set -euo pipefail

# Creates a local Sparkle update archive.
#
# This ZIP is for Sparkle in-app updates. It is not the first-install DMG.
# Do not commit files from dist/ to the Sayless source repository.

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

  APP_PATH=/path/to/Sayless.app scripts/release-local.sh
EOF
  exit 1
fi

mkdir -p "$DIST_DIR"
rm -rf "$DIST_APP"
ditto "$APP_SOURCE" "$DIST_APP"

INFO_PLIST="$DIST_APP/Contents/Info.plist"
SHORT_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$INFO_PLIST")"
BUILD_NUMBER="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$INFO_PLIST")"
ZIP_NAME="Sayless-${SHORT_VERSION}-${BUILD_NUMBER}.zip"
ZIP_PATH="$DIST_DIR/$ZIP_NAME"

rm -f "$ZIP_PATH"
(
  cd "$DIST_DIR"
  ditto -c -k --sequesterRsrc --keepParent "$APP_NAME" "$ZIP_NAME"
)

cat <<EOF
Created Sparkle update ZIP:
  $ZIP_PATH

Copied Release app:
  $DIST_APP

Next steps:
  1. Upload $ZIP_NAME to the public sayless-updates GitHub Release.
  2. Update ~/Desktop/sayless-updates/appcast.xml to point at that release asset.
  3. Commit and publish appcast.xml from the sayless-updates repo.

Do not commit dist/, ZIP, or DMG files to the Sayless source repository.
EOF
