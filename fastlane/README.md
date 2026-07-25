# StoreGauge Fastlane

Fastlane covers the iPhone App Store/TestFlight workflow and wraps the existing
direct-distribution workflow for the desktop app. It never commits credentials,
uploads screenshots, or changes App Store metadata.

## Setup

Use a managed Ruby 3 installation, then install the locked dependencies:

```sh
bundle install
cp fastlane/.env.example fastlane/.env
```

Create a dedicated App Store Connect API key, keep its `.p8` file outside the
repository, and fill in `fastlane/.env`:

```dotenv
FASTLANE_ASC_KEY_ID=XXXXXXXXXX
FASTLANE_ASC_ISSUER_ID=00000000-0000-0000-0000-000000000000
FASTLANE_ASC_KEY_PATH=/absolute/path/to/AuthKey_XXXXXXXXXX.p8
```

If `fastlane/.env` is absent, the lanes also read the credential names used by
the App Store Connect helper from `~/.appstoreconnect/.env`. Fastlane values
take precedence when both files are configured. Neither file is committed.

The issuer ID and key ID belong to Fastlane’s release automation. They are
separate from the App Store Connect credentials that StoreGauge users enter
inside the app.

The App Store Connect app record and bundle ID `com.bazun.storegauge` must
already exist. Automatic signing uses Apple Developer team `75RZ97C25R` unless
overridden in `fastlane/.env`.

## iPhone

Run tests and an unsigned Release simulator build:

```sh
bundle exec fastlane ios verify
```

Create a signed IPA without uploading:

```sh
bundle exec fastlane ios build
```

Build with the next TestFlight build number and upload:

```sh
bundle exec fastlane ios beta
```

Build and attach the binary to its App Store version:

```sh
bundle exec fastlane ios release
```

Both upload lanes require a clean Git worktree. Pass `version:1.2.0` or
`build_number:42` to override release numbers. `CHANGELOG="..."` is used by the
TestFlight lane.

The release lane uploads only the binary by default. It does not upload
screenshots or metadata and does not submit for review. To opt in explicitly:

```sh
SUBMIT_FOR_REVIEW=1 bundle exec fastlane ios release
```

Add `AUTOMATIC_RELEASE=1` only if the approved version should release
automatically.

## Desktop

Run shared tests and an unsigned universal Release build:

```sh
bundle exec fastlane mac verify
```

This compiles both desktop targets and verifies that the direct-download bundle
contains Sparkle while the Mac App Store bundle contains no Sparkle framework,
feed keys, or update command.

Validate Developer ID, notarization, Sparkle, entitlements, and release inputs:

```sh
bundle exec fastlane mac preflight
```

Build, sign, notarize, staple, and export the direct-download DMG:

```sh
bundle exec fastlane mac direct
bundle exec fastlane mac direct version:1.2.0
```

This wraps the existing release scripts and uses the Keychain-backed
`storegauge-notary` profile by default. Set `STOREGAUGE_NOTARY_PROFILE` to use
another profile.

Create a signed Sparkle-free Mac App Store package without uploading it:

```sh
bundle exec fastlane mac app_store_build
```

Build and upload that package to the Mac App Store version:

```sh
bundle exec fastlane mac app_store
```

The upload lane requires a clean Git worktree and uses the same binary-only,
no-screenshots, no-metadata, and no-review-submission defaults as the iPhone
release lane. Add `SUBMIT_FOR_REVIEW=1` only when the Mac version is ready.

The `StoreGauge` target remains the Sparkle-enabled direct-download edition.
The `StoreGaugeAppStore` target reuses the same product identity and source but
has a separate Info.plist, entitlements, scheme, and compilation condition that
exclude Sparkle and **Check for Updates…**.

## Safety

`fastlane/.env`, `.p8` keys, IPA files, archives, and Fastlane reports are
ignored by Git. Release artifacts go to `build/`, which is ignored as well.
Upload lanes use App Store Connect API-key authentication; they do not require
an Apple ID password.
