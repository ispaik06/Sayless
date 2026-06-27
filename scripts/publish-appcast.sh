#!/usr/bin/env bash
set -euo pipefail

# Updates and publishes the Sparkle appcast in the sayless-updates repo.
#
# Expected flow:
#   1. scripts/build-release.sh
#   2. scripts/release-local.sh  # for Sparkle updates
#   3. gh release create/upload the generated archive
#   4. scripts/publish-appcast.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
UPDATES_REPO_DIR="${UPDATES_REPO_DIR:-$HOME/Desktop/sayless-updates}"
DIST_DIR="$UPDATES_REPO_DIR/dist"
APPCAST_PATH="$UPDATES_REPO_DIR/appcast.xml"
BUILD_DIR="${BUILD_DIR:-/tmp/SaylessReleaseBuild}"

ARCHIVE_PATH=""
RELEASE_TAG=""
DOWNLOAD_URL_PREFIX=""
SKIP_RELEASE_CHECK=0
NO_PUSH=0
MAXIMUM_VERSIONS="${MAXIMUM_VERSIONS:-3}"

usage() {
  cat <<'EOF'
Usage:
  scripts/publish-appcast.sh [options]

Options:
  --archive PATH            Archive to publish. Defaults to newest Sayless ZIP,
                            then newest Sayless DMG under sayless-updates/dist.
  --tag TAG                 GitHub Release tag. Defaults to v{shortVersion}
                            parsed from the archive filename.
  --download-url-prefix URL Override the GitHub Release download URL prefix.
  --skip-release-check      Do not verify the GitHub Release asset with gh.
  --no-push                 Commit appcast.xml but do not git push.
  -h, --help                Show this help.

Environment:
  UPDATES_REPO_DIR          Defaults to ~/Desktop/sayless-updates.
  BUILD_DIR                 Defaults to /tmp/SaylessReleaseBuild.
  SPARKLE_KEYCHAIN_ACCOUNT  Defaults to ed25519.
  SPARKLE_ED_KEY_FILE       Private EdDSA key file for generate_appcast.
  SPARKLE_PRIVATE_KEY       Private EdDSA key value passed via stdin.
  MAXIMUM_VERSIONS          Defaults to 3.

Examples:
  scripts/publish-appcast.sh
  scripts/publish-appcast.sh --archive ~/Desktop/sayless-updates/dist/Sayless-0.1.1-2.zip --tag v0.1.1
  SPARKLE_ED_KEY_FILE=~/.sparkle/sayless_ed25519 scripts/publish-appcast.sh
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --archive)
      ARCHIVE_PATH="${2:-}"
      shift 2
      ;;
    --tag)
      RELEASE_TAG="${2:-}"
      shift 2
      ;;
    --download-url-prefix)
      DOWNLOAD_URL_PREFIX="${2:-}"
      shift 2
      ;;
    --skip-release-check)
      SKIP_RELEASE_CHECK=1
      shift
      ;;
    --no-push)
      NO_PUSH=1
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

find_generate_appcast() {
  local candidates=(
    "$BUILD_DIR/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_appcast"
    "$REPO_ROOT/build/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_appcast"
  )

  local candidate
  for candidate in "${candidates[@]}"; do
    if [[ -x "$candidate" ]]; then
      printf '%s\n' "$candidate"
      return
    fi
  done

  local discovered
  discovered="$(
    find "$HOME/Library/Developer/Xcode/DerivedData" \
      -path '*/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_appcast' \
      -type f \
      -perm -111 \
      -print 2>/dev/null | sort | tail -n 1
  )"

  if [[ -n "$discovered" ]]; then
    printf '%s\n' "$discovered"
  fi
}

find_latest_archive() {
  local latest_zip latest_dmg

  latest_zip="$(
    find "$DIST_DIR" -maxdepth 1 -type f -name 'Sayless-*.zip' -exec stat -f '%m %N' {} \; 2>/dev/null \
      | sort -nr \
      | head -n 1 \
      | cut -d ' ' -f 2-
  )"
  if [[ -n "$latest_zip" ]]; then
    printf '%s\n' "$latest_zip"
    return
  fi

  latest_dmg="$(
    find "$DIST_DIR" -maxdepth 1 -type f -name 'Sayless-*.dmg' -exec stat -f '%m %N' {} \; 2>/dev/null \
      | sort -nr \
      | head -n 1 \
      | cut -d ' ' -f 2-
  )"
  if [[ -n "$latest_dmg" ]]; then
    printf '%s\n' "$latest_dmg"
  fi
}

infer_short_version() {
  local filename="$1"
  if [[ "$filename" =~ ^Sayless-(.+)-([0-9]+)\.(zip|dmg)$ ]]; then
    printf '%s\n' "${BASH_REMATCH[1]}"
    return
  fi

  return 1
}

infer_github_repo() {
  local remote
  remote="$(git -C "$UPDATES_REPO_DIR" config --get remote.origin.url || true)"

  if [[ "$remote" =~ ^git@github.com:(.+)\.git$ ]]; then
    printf '%s\n' "${BASH_REMATCH[1]}"
    return
  fi

  if [[ "$remote" =~ ^https://github.com/(.+)\.git$ ]]; then
    printf '%s\n' "${BASH_REMATCH[1]}"
    return
  fi

  if [[ "$remote" =~ ^https://github.com/(.+)$ ]]; then
    printf '%s\n' "${BASH_REMATCH[1]}"
    return
  fi

  printf 'ispaik06/sayless-updates\n'
}

if [[ ! -d "$UPDATES_REPO_DIR/.git" ]]; then
  printf 'error: updates repo not found: %s\n' "$UPDATES_REPO_DIR" >&2
  exit 1
fi

GENERATE_APPCAST="$(find_generate_appcast || true)"
if [[ -z "$GENERATE_APPCAST" ]]; then
  cat >&2 <<'EOF'
error: Sparkle generate_appcast was not found.

Run a release build first so SwiftPM downloads Sparkle:

  scripts/build-release.sh
EOF
  exit 1
fi

if [[ -z "$ARCHIVE_PATH" ]]; then
  ARCHIVE_PATH="$(find_latest_archive || true)"
fi

if [[ -z "$ARCHIVE_PATH" || ! -f "$ARCHIVE_PATH" ]]; then
  cat >&2 <<EOF
error: release archive was not found.

Expected a Sayless ZIP or DMG under:
  $DIST_DIR

For Sparkle updates, create a ZIP first:
  scripts/release-local.sh

For a first-install DMG:
  scripts/create-dmg.sh
EOF
  exit 1
fi

ARCHIVE_PATH="$(cd "$(dirname "$ARCHIVE_PATH")" && pwd)/$(basename "$ARCHIVE_PATH")"
ARCHIVE_NAME="$(basename "$ARCHIVE_PATH")"
SHORT_VERSION="$(infer_short_version "$ARCHIVE_NAME" || true)"

if [[ -z "$SHORT_VERSION" ]]; then
  printf 'error: could not infer version from archive filename: %s\n' "$ARCHIVE_NAME" >&2
  exit 1
fi

if [[ -z "$RELEASE_TAG" ]]; then
  RELEASE_TAG="v$SHORT_VERSION"
fi

GITHUB_REPO="$(infer_github_repo)"

if [[ -z "$DOWNLOAD_URL_PREFIX" ]]; then
  DOWNLOAD_URL_PREFIX="https://github.com/$GITHUB_REPO/releases/download/$RELEASE_TAG/"
fi

if [[ "$SKIP_RELEASE_CHECK" == "0" && -x "$(command -v gh)" ]]; then
  if ! gh release view "$RELEASE_TAG" --repo "$GITHUB_REPO" --json assets --jq '.assets[].name' \
    | grep -Fxq "$ARCHIVE_NAME"; then
    cat >&2 <<EOF
error: GitHub Release asset was not found.

Expected release:
  $GITHUB_REPO $RELEASE_TAG

Expected asset:
  $ARCHIVE_NAME

Upload it first, then re-run this script:
  gh release upload "$RELEASE_TAG" "$ARCHIVE_PATH" --repo "$GITHUB_REPO" --clobber

Or bypass this check:
  scripts/publish-appcast.sh --skip-release-check
EOF
    exit 1
  fi
fi

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/sayless-appcast.XXXXXX")"
cleanup() {
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

cp "$ARCHIVE_PATH" "$WORK_DIR/$ARCHIVE_NAME"
if [[ -f "$APPCAST_PATH" ]]; then
  cp "$APPCAST_PATH" "$WORK_DIR/appcast.xml"
fi

APPCAST_ARGS=(
  "--download-url-prefix" "$DOWNLOAD_URL_PREFIX"
  "--maximum-versions" "$MAXIMUM_VERSIONS"
)

if [[ -n "${SPARKLE_KEYCHAIN_ACCOUNT:-}" ]]; then
  APPCAST_ARGS+=("--account" "$SPARKLE_KEYCHAIN_ACCOUNT")
fi

if [[ -z "${SPARKLE_PRIVATE_KEY:-}" && -n "${SPARKLE_ED_KEY_FILE:-}" ]]; then
  APPCAST_ARGS+=("--ed-key-file" "$SPARKLE_ED_KEY_FILE")
fi

if [[ -n "${SPARKLE_PRIVATE_KEY:-}" ]]; then
  printf '%s\n' "$SPARKLE_PRIVATE_KEY" | "$GENERATE_APPCAST" "${APPCAST_ARGS[@]}" --ed-key-file - "$WORK_DIR"
else
  "$GENERATE_APPCAST" "${APPCAST_ARGS[@]}" "$WORK_DIR"
fi

if [[ ! -f "$WORK_DIR/appcast.xml" ]]; then
  printf 'error: generate_appcast did not create appcast.xml\n' >&2
  exit 1
fi

cp "$WORK_DIR/appcast.xml" "$APPCAST_PATH"

if command -v xmllint >/dev/null 2>&1; then
  xmllint --noout "$APPCAST_PATH"
fi

if git -C "$UPDATES_REPO_DIR" diff --quiet -- appcast.xml; then
  printf 'appcast.xml is already up to date.\n'
  exit 0
fi

git -C "$UPDATES_REPO_DIR" add appcast.xml
git -C "$UPDATES_REPO_DIR" commit -m "Update appcast for $ARCHIVE_NAME"

if [[ "$NO_PUSH" == "0" ]]; then
  git -C "$UPDATES_REPO_DIR" push
fi

cat <<EOF
Published appcast:
  $APPCAST_PATH

Archive:
  $ARCHIVE_NAME

Download URL:
  $DOWNLOAD_URL_PREFIX$ARCHIVE_NAME
EOF
