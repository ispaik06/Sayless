#!/usr/bin/env bash
set -euo pipefail

# Builds Sayless.app for local distribution.
#
# The default DerivedData path is outside the source repo because building under
# Desktop/iCloud/File Provider folders can attach Finder/resource-fork metadata
# that makes codesign fail.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD_DIR="${BUILD_DIR:-/tmp/SaylessReleaseBuild}"
CLEAN=1

usage() {
  cat <<'EOF'
Usage:
  scripts/build-release.sh [--no-clean]

Environment:
  BUILD_DIR=/tmp/SaylessReleaseBuild  Override the DerivedData path.

Examples:
  scripts/build-release.sh
  scripts/build-release.sh --no-clean
  BUILD_DIR=/tmp/SaylessReleaseBuild scripts/build-release.sh
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --no-clean)
      CLEAN=0
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      printf 'error: unknown argument: %s\n\n' "$1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if [[ "$CLEAN" == "1" ]]; then
  rm -rf "$BUILD_DIR"
fi

cd "$REPO_ROOT"

xcodebuild \
  -project Sayless.xcodeproj \
  -scheme Sayless \
  -configuration Release \
  -derivedDataPath "$BUILD_DIR" \
  build

APP_PATH="$BUILD_DIR/Build/Products/Release/Sayless.app"

if [[ ! -d "$APP_PATH" ]]; then
  printf 'error: expected Release app was not created: %s\n' "$APP_PATH" >&2
  exit 1
fi

cat <<EOF
Built Release app:
  $APP_PATH

First-install DMG:
  APP_PATH="$APP_PATH" scripts/create-dmg.sh

Sparkle update ZIP:
  APP_PATH="$APP_PATH" scripts/release-local.sh
EOF
