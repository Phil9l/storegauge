---
title: Direct distribution
description: Build, notarize, publish, and update StoreGauge using a DMG and Sparkle.
---

StoreGauge’s direct build is distributed as a signed, notarized DMG and checks a signed Sparkle feed hosted on GitHub Pages.

## Fastlane

The repository includes Fastlane entry points for both Apple clients. Install
the locked Ruby dependencies first:

```sh
bundle install
cp fastlane/.env.example fastlane/.env
```

Use `bundle exec fastlane ios verify` and `bundle exec fastlane mac verify` for
tests and unsigned Release builds.

The iPhone lanes are:

- `ios build` — create a signed IPA without uploading it.
- `ios beta` — choose the next build number and upload to TestFlight.
- `ios release` — upload only the binary to its App Store version. Metadata,
  screenshots, review submission, and automatic release stay off by default.

The desktop lanes are:

- `mac verify` — test shared code, build both desktop variants, and confirm
  Sparkle exists only in the direct-download bundle.
- `mac preflight` — validate the direct-release machine and signing inputs.
- `mac direct` — build, sign, notarize, staple, and export the direct-download
  DMG.
- `mac app_store_build` — create a signed Sparkle-free Mac App Store package
  without uploading it.
- `mac app_store` — build and upload that package to its Mac App Store version.

The upload lanes read a dedicated App Store Connect API key from the ignored
`fastlane/.env` file, or fall back to the credential names in
`~/.appstoreconnect/.env`. Keep the `.p8` file outside the repository. These
release credentials are separate from the App Store Connect credentials
entered by StoreGauge users.

The `StoreGauge` target is the direct-download edition. `StoreGaugeAppStore`
reuses the application source and product identity but has a separate scheme,
Info.plist, entitlements, and compilation condition. It neither links nor
embeds Sparkle and omits the feed keys, Sparkle Mach-service exceptions, and
**Check for Updates…** command.

## One-time setup

1. Create a **Developer ID Application** certificate in Xcode.
2. Store App Store Connect notarization credentials:

   ```sh
   xcrun notarytool store-credentials storegauge-notary
   ```

3. Keep Sparkle’s private EdDSA key in the login Keychain under account `storegauge`. Its matching public key is committed in StoreGauge’s `Info.plist`.

## Validate the release machine

```sh
./scripts/release-preflight.sh
```

The preflight checks the Developer ID certificate, notarization profile, Sparkle configuration and key match, sandbox permissions, appcast XML, and Git status without changing the project or publishing anything.

## Build the DMG

Commit the working tree, then run:

```sh
./scripts/build-release.sh
```

The script increments the patch and build versions, creates a Developer ID archive, exports StoreGauge, builds and signs the DMG, submits it to Apple, staples the notarization ticket, and verifies it with Gatekeeper. A failed run restores the previous project version.

Use `--version X.Y.Z` for an explicit version or `--notary-profile NAME` for another stored notary profile.

## Publish and update Sparkle

1. Install and launch the DMG once on another Mac account if possible.
2. Commit the version bump.
3. Create a matching GitHub release such as `v1.0.1` and upload the exact DMG.
4. Generate the signed appcast entry:

   ```sh
   ./scripts/generate-appcast.sh build/releases v1.0.1
   ```

5. Commit and push `docs/public/appcast.xml` only after the GitHub release asset is public.
6. Test **StoreGauge → Check for Updates…** from the previous release.

Never commit the Sparkle private key or an exported copy of it.
