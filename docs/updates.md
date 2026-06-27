# Sayless Updates

Sayless uses Sparkle 2 for in-app updates on macOS.

## Repository Layout

- App source code repo: `Sayless`
- GitHub Releases repo: `ispaik06/Sayless`
- GitHub Pages branch: `gh-pages`
- Appcast URL: `https://ispaik06.github.io/Sayless/appcast.xml`
- Release asset URL example:
  `https://github.com/ispaik06/Sayless/releases/download/v0.1.1/Sayless-0.1.1-2.zip`

The `main` branch should contain source code, scripts, and docs. Release archives are generated locally under `dist/`, which is ignored by git.

The `gh-pages` branch should contain the generated `appcast.xml` for Sparkle. GitHub Pages should be configured to serve from the `gh-pages` branch.

## How Sparkle Updates Work

Sparkle reads `SUFeedURL` from the app's `Info.plist`. That URL points to `appcast.xml`. The appcast tells Sparkle what the latest version is and where to download its update archive.

For Sayless:

- GitHub Pages serves `appcast.xml` from the `gh-pages` branch.
- GitHub Releases hosts the ZIP and DMG files.
- Sparkle downloads the ZIP from the release asset URL.
- Sparkle verifies the ZIP signature with `SUPublicEDKey`.
- If verification passes, Sparkle shows its normal Update / Install and Relaunch flow.

## DMG vs ZIP

Create both files for each public version:

- `DMG`: for new users installing Sayless for the first time.
- `ZIP`: for existing users updating through Sparkle.

The appcast should normally point at the ZIP.

## Info.plist Keys

This project uses `Config/Sayless-Info.plist`.

Current update keys:

- `SUFeedURL`: `https://ispaik06.github.io/Sayless/appcast.xml`
- `SUPublicEDKey`: configured in `Config/Sayless-Info.plist`
- `SUEnableAutomaticChecks`: `true`

`SUPublicEDKey` is public and belongs in the app. Keep the matching private key out of the repo.

## Version Numbers

Sayless uses:

- `CFBundleShortVersionString`: user-facing version, for example `0.1.1`
- `CFBundleVersion`: build number, for example `2`

Always increase `CFBundleVersion` for every published update. If the build number does not increase, Sparkle may decide there is no newer update even if the ZIP changed.

Local release archives are named like:

```text
Sayless-{CFBundleShortVersionString}-{CFBundleVersion}.dmg
Sayless-{CFBundleShortVersionString}-{CFBundleVersion}.zip
```

## Release Flow

Build Release:

```sh
cd ~/Desktop/Sayless
scripts/build-release.sh
```

Create both archives:

```sh
scripts/create-dmg.sh
scripts/release-local.sh
```

Upload both files to the Sayless GitHub Release:

```sh
gh release create v0.1.1 \
  dist/Sayless-0.1.1-2.dmg \
  dist/Sayless-0.1.1-2.zip \
  --title "Sayless 0.1.1" \
  --notes "Update release"
```

If the release already exists:

```sh
gh release upload v0.1.1 \
  dist/Sayless-0.1.1-2.dmg \
  dist/Sayless-0.1.1-2.zip \
  --clobber
```

Generate and publish appcast.xml to `gh-pages`:

```sh
scripts/publish-appcast.sh
```

`publish-appcast.sh` runs Sparkle's `generate_appcast`, updates `appcast.xml` in a local `gh-pages` worktree, commits it, and pushes the `gh-pages` branch.

## Unsigned Builds And Gatekeeper

Sparkle verifies update archives with its own EdDSA key, but Sparkle does not replace Apple's Developer ID signing or notarization.

If Sayless is distributed unsigned, macOS Gatekeeper may show warnings when users first install or launch the app. Developer ID signing and notarization should be added later for better installation trust.
