# Public Repository Release Checklist

Do not change the private repository to public until every item below is
complete.

## Licensing and history

- [ ] Confirm `LICENSE` is the exact PolyForm Noncommercial 1.0.0 text.
- [ ] Confirm `NOTICE`, `TRADEMARKS.md`, `CLA.md`, and `CONTRIBUTING.md` are
      present and linked from `README.md`.
- [ ] Confirm every contributor has agreed to the CLA or separately licensed
      their work.
- [ ] Audit third-party dependencies and assets and retain all required notices.
- [ ] Publish from a new repository or a clean, squashed initial commit.
      Do not expose superseded private licensing history.
- [ ] Search the exported source for superseded license notices and claims that
      StoreGauge is OSI-approved open source.

## Brand and distribution

- [x] Create the StoreGauge App Store Connect record for macOS and iOS.
- [ ] Verify that official bundle identifiers and signing assets are controlled
      by the project owner.
- [ ] Perform a trademark availability search and decide whether to file with
      DPMA, EUIPO, or both.
- [ ] Confirm the repository, documentation, release artifacts, and App Store
      listing use the same owner identity.

## Security and privacy

- [ ] Scan the complete export for API keys, private keys, tokens, signing
      material, provisioning profiles, and personal data.
- [ ] Confirm demo data contains no real account or reviewer information.
- [ ] Confirm release archives contain the correct privacy policy and notices.
- [ ] Confirm the iPhone, direct Mac, and Mac App Store bundles declare
      `ITSAppUsesNonExemptEncryption` as false.
- [ ] Confirm imported store credentials use the device-only Keychain
      accessibility class and remain available for background refresh.

## App Review

- [ ] Confirm **Explore with demo data** is visible on first launch and exercises
      the complete interface without store credentials or network access.
- [ ] Confirm the current privacy policy is linked in App Store Connect metadata
      and is directly accessible from iPhone Settings.
- [ ] Verify the `com.bazun.storegauge.refresh` app-refresh task on a physical
      iPhone with Background App Refresh enabled, including new-review delivery,
      rescheduling, task expiration, and the disabled/Low Power Mode states.
- [ ] Recommend a dedicated, least-privileged App Store Connect key. Describe
      Admin access as optional and required only for the complete feature set.
- [ ] Include these notes with the iPhone submission:

      > StoreGauge is a local developer dashboard for data belonging to the
      > user’s own App Store Connect account. It never requests an Apple ID or
      > password. Real accounts use an API key created by the user in App Store
      > Connect. The private key is stored only in the device Keychain, JWTs are
      > signed locally, and requests go directly to Apple. StoreGauge has no
      > backend or account system.
      >
      > To review without credentials, launch the app and select “Explore with
      > demo data.” This provides representative apps, metrics, releases,
      > subscriptions, and reviews, including local review-management actions.
      >
      > The iPhone target declares Background fetch only for a short,
      > best-effort review and release-status check against the user’s connected
      > Apple or Google account. It requests execution no earlier than hourly,
      > stores results locally, and posts a local notification when it discovers
      > a new review or release-state change. It does not contact a StoreGauge
      > server.

## Release process

- [ ] Install the locked Ruby dependencies and run
      `bundle exec fastlane ios verify` and `bundle exec fastlane mac verify`.
- [ ] Inspect the `StoreGaugeAppStore` Release bundle and confirm it has no
      `Sparkle.framework`, `SUFeedURL`, `SUPublicEDKey`, Sparkle Mach-service
      exceptions, or **Check for Updates…** command.
- [ ] Confirm `fastlane/.env`, App Store Connect `.p8` keys, IPA files, and
      generated release artifacts are absent from the public-source export.
- [ ] Create a dedicated App Store Connect API key for release automation and
      store its `.p8` file outside the repository.
- [ ] Build and test macOS and iOS from the clean public-source export.
- [ ] Verify notarization, App Store signing, Sparkle signing, and update feeds
      use production credentials that are not present in the repository.
- [ ] Tag the first public-source release only after the clean history is
      published.
