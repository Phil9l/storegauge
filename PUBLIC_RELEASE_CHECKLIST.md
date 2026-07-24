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

- [ ] Create the StoreGauge App Store Connect record for macOS and iOS.
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

## Release process

- [ ] Build and test macOS and iOS from the clean public-source export.
- [ ] Verify notarization, App Store signing, Sparkle signing, and update feeds
      use production credentials that are not present in the repository.
- [ ] Tag the first public-source release only after the clean history is
      published.
