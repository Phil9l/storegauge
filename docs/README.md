# StoreGauge website and update feed

This directory contains the Astro + Starlight website served at <https://phil9l.github.io/storegauge/>.

## Website development

Install dependencies and start the local preview:

```sh
pnpm install
pnpm dev
```

Run the production build before committing:

```sh
pnpm build
```

GitHub Actions builds `docs` and deploys the generated static site. In the repository’s Pages settings, select **GitHub Actions** as the source.

The custom landing and privacy pages live in `src/pages`. Starlight documentation lives in `src/content/docs/docs`, and files copied unchanged to the published site—including the Sparkle feed—live in `public`.

## Publish a Sparkle update

1. Create a `Developer ID Application` certificate in Xcode.
2. Save notarization credentials once with `xcrun notarytool store-credentials storegauge-notary`.
3. From a clean working tree, build the signed, notarized, and stapled DMG:

   ```sh
   ./scripts/build-release.sh
   ```

   This increments the patch version and build number automatically. Pass `--version X.Y.Z` to select an explicit version. The DMG is written to `build/releases/`, and failed releases restore the previous version numbers.

4. Test the DMG and commit the successful version bump.
5. Create a matching Markdown or HTML release-notes file beside it if desired.
6. Generate the update feed using the same version and tag:

   ```sh
   ./scripts/generate-appcast.sh build/releases v1.0.1
   ```

7. Create the matching GitHub release and upload the exact signed archive.
8. Commit and push `docs/public/appcast.xml` after the release asset is public.
9. Verify **StoreGauge → Check for Updates…** from the previous public version.

The generator reads the private EdDSA key from the login Keychain account `storegauge`. Never export that key into this repository. The public key is embedded in `StoreGauge/StoreGauge/Info.plist`.

The tag passed to the helper must exactly match the GitHub release tag. The helper carries previous appcast items forward, signs the new archive using the `storegauge` Keychain account, and gives the new item a tag-specific GitHub download URL.
