#!/usr/bin/env bash
set -euo pipefail

# Generates appcast.xml with Sparkle and publishes it to the Sayless gh-pages branch.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DIST_DIR="$REPO_ROOT/dist"
BUILD_DIR="${BUILD_DIR:-/tmp/SaylessReleaseBuild}"
GH_PAGES_DIR="${GH_PAGES_DIR:-/tmp/Sayless-gh-pages}"
GH_PAGES_BRANCH="${GH_PAGES_BRANCH:-gh-pages}"
APPCAST_PATH="$GH_PAGES_DIR/appcast.xml"

ARCHIVE_PATH=""
RELEASE_TAG=""
DOWNLOAD_URL_PREFIX=""
SKIP_RELEASE_CHECK=0
NO_PUSH=0
MAXIMUM_VERSIONS="${MAXIMUM_VERSIONS:-3}"
SPARKLE_KEYCHAIN_ACCOUNT="${SPARKLE_KEYCHAIN_ACCOUNT:-ispaik06.sayless}"

usage() {
  cat <<'EOF'
Usage:
  scripts/publish-appcast.sh [options]

Options:
  --archive PATH            Archive to publish. Defaults to newest Sayless ZIP,
                            then newest Sayless DMG under Sayless/dist.
  --tag TAG                 GitHub Release tag. Defaults to v{shortVersion}
                            parsed from the archive filename.
  --download-url-prefix URL Override the GitHub Release download URL prefix.
  --skip-release-check      Do not verify the GitHub Release asset with gh.
  --no-push                 Commit appcast.xml but do not git push.
  -h, --help                Show this help.

Environment:
  BUILD_DIR                 Defaults to /tmp/SaylessReleaseBuild.
  GH_PAGES_DIR              Defaults to /tmp/Sayless-gh-pages.
  GH_PAGES_BRANCH           Defaults to gh-pages.
  SPARKLE_KEYCHAIN_ACCOUNT  Defaults to ispaik06.sayless.
  SPARKLE_ED_KEY_FILE       Private EdDSA key file for generate_appcast.
  SPARKLE_PRIVATE_KEY       Private EdDSA key value passed via stdin.
  MAXIMUM_VERSIONS          Defaults to 3.
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

find_generate_keys() {
  local generate_appcast_path="$1"
  local generate_keys_path

  generate_keys_path="$(dirname "$generate_appcast_path")/generate_keys"
  if [[ -x "$generate_keys_path" ]]; then
    printf '%s\n' "$generate_keys_path"
    return
  fi

  local discovered
  discovered="$(
    find "$HOME/Library/Developer/Xcode/DerivedData" "$BUILD_DIR" \
      -path '*/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_keys' \
      -type f \
      -perm -111 \
      -print 2>/dev/null | sort | tail -n 1
  )"

  if [[ -n "$discovered" ]]; then
    printf '%s\n' "$discovered"
  fi
}

check_signing_key() {
  local generate_keys_path="$1"
  local account="$SPARKLE_KEYCHAIN_ACCOUNT"
  local configured_public_key keychain_public_key

  if [[ -n "${SPARKLE_PRIVATE_KEY:-}" || -n "${SPARKLE_ED_KEY_FILE:-}" ]]; then
    return
  fi

  if [[ -z "$generate_keys_path" ]]; then
    return
  fi

  configured_public_key="$(
    /usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' "$REPO_ROOT/Config/Sayless-Info.plist" 2>/dev/null || true
  )"

  if ! keychain_public_key="$("$generate_keys_path" --account "$account" -p 2>/dev/null)"; then
    cat >&2 <<EOF
error: Sparkle private EdDSA key was not found in Keychain.

The app has SUPublicEDKey configured, but generate_appcast needs the matching
private key to sign update archives.

If you still have the original private key file, import it:
  "$generate_keys_path" --account "$account" -f /path/to/private_ed25519_key

If this app has not been distributed yet, generate a new keypair:
  "$generate_keys_path" --account "$account"

Then copy the printed SUPublicEDKey into:
  Config/Sayless-Info.plist

After changing SUPublicEDKey, rebuild and recreate DMG/ZIP before publishing.
EOF
    exit 1
  fi

  if [[ -n "$configured_public_key" && "$keychain_public_key" != *"$configured_public_key"* ]]; then
    cat >&2 <<EOF
error: Keychain Sparkle key does not match Config/Sayless-Info.plist.

Configured SUPublicEDKey:
  $configured_public_key

Keychain public key output:
  $keychain_public_key

Use the private key that matches the app's SUPublicEDKey, or update
SUPublicEDKey to the public key printed by generate_keys and rebuild the app.
EOF
    exit 1
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
  remote="$(git -C "$REPO_ROOT" config --get remote.origin.url || true)"

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

  printf 'ispaik06/Sayless\n'
}

ensure_gh_pages_worktree() {
  if [[ -d "$GH_PAGES_DIR/.git" || -f "$GH_PAGES_DIR/.git" ]]; then
    git -C "$GH_PAGES_DIR" fetch origin "$GH_PAGES_BRANCH" >/dev/null 2>&1 || true
    git -C "$GH_PAGES_DIR" checkout "$GH_PAGES_BRANCH" >/dev/null
    git -C "$GH_PAGES_DIR" pull --ff-only origin "$GH_PAGES_BRANCH" >/dev/null 2>&1 || true
    return
  fi

  rm -rf "$GH_PAGES_DIR"

  if git -C "$REPO_ROOT" ls-remote --exit-code --heads origin "$GH_PAGES_BRANCH" >/dev/null 2>&1; then
    git -C "$REPO_ROOT" worktree add "$GH_PAGES_DIR" "origin/$GH_PAGES_BRANCH" >/dev/null
    git -C "$GH_PAGES_DIR" checkout -B "$GH_PAGES_BRANCH" "origin/$GH_PAGES_BRANCH" >/dev/null
  else
    git -C "$REPO_ROOT" worktree add --detach "$GH_PAGES_DIR" >/dev/null
    git -C "$GH_PAGES_DIR" checkout --orphan "$GH_PAGES_BRANCH" >/dev/null
    git -C "$GH_PAGES_DIR" rm -rf . >/dev/null 2>&1 || true
  fi
}

GENERATE_APPCAST="$(find_generate_appcast || true)"
if [[ -z "$GENERATE_APPCAST" ]]; then
  cat >&2 <<'EOF'
error: Sparkle generate_appcast was not found.

Run a release build first so SwiftPM downloads Sparkle:

  scripts/build-release.sh
EOF
  exit 1
fi

GENERATE_KEYS="$(find_generate_keys "$GENERATE_APPCAST" || true)"
check_signing_key "$GENERATE_KEYS"

if [[ -z "$ARCHIVE_PATH" ]]; then
  ARCHIVE_PATH="$(find_latest_archive || true)"
fi

if [[ -z "$ARCHIVE_PATH" || ! -f "$ARCHIVE_PATH" ]]; then
  cat >&2 <<EOF
error: release archive was not found.

Expected a Sayless ZIP or DMG under:
  $DIST_DIR

Create both release files first:
  scripts/create-dmg.sh
  scripts/release-local.sh
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

ensure_gh_pages_worktree

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

APPCAST_ARGS+=("--account" "$SPARKLE_KEYCHAIN_ACCOUNT")

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

if git -C "$GH_PAGES_DIR" diff --quiet -- appcast.xml; then
  printf 'appcast.xml is already up to date.\n'
  exit 0
fi

git -C "$GH_PAGES_DIR" add appcast.xml
git -C "$GH_PAGES_DIR" commit -m "Update appcast for $ARCHIVE_NAME"

if [[ "$NO_PUSH" == "0" ]]; then
  git -C "$GH_PAGES_DIR" push -u origin "$GH_PAGES_BRANCH"
fi

cat <<EOF
Published appcast:
  $APPCAST_PATH

Archive:
  $ARCHIVE_NAME

Download URL:
  $DOWNLOAD_URL_PREFIX$ARCHIVE_NAME
EOF
