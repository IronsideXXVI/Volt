# Production release setup

Volt's production workflow builds, signs, notarizes, and publishes a Sparkle-compatible DMG whenever an approved commit reaches `main`. It may also be started manually from the `main` branch. The workflow deliberately refuses to release any other ref.

## 1. Connect Depot to GitHub Actions

The release job uses Depot's macOS runner label:

```yaml
runs-on: depot-macos-26
```

1. In Depot, connect the GitHub account or organization that owns `IronsideXXVI/Volt`.
2. Install and authorize the Depot GitHub App for the repository.
3. Confirm the Depot project can launch `depot-macos-26` from GitHub Actions.

Depot's documented setup requires a Depot organization owner and a connected GitHub organization. Because `IronsideXXVI` is currently a personal GitHub account, verify that Depot supports this repository directly. If it does not, move Volt to a GitHub organization or confirm an alternative setup with Depot before promoting to `main`.

References:

- <https://depot.dev/docs/github-actions/quickstart>
- <https://depot.dev/docs/github-actions/runner-types>

Do not move this macOS job into `.depot/workflows/`. Depot CI workflows use Linux sandboxes and do not support macOS; this workflow must remain under `.github/workflows/`.

## 2. Configure release secrets

Add all six secrets under **Repository settings → Secrets and variables → Actions**:

| Secret | Value |
| --- | --- |
| `DEVELOPER_ID_CERTIFICATE_P12` | Base64-encoded Developer ID Application `.p12` |
| `DEVELOPER_ID_CERTIFICATE_PASSWORD` | Password for that `.p12` |
| `APPLE_API_KEY_ID` | App Store Connect API key ID |
| `APPLE_API_ISSUER_ID` | App Store Connect issuer ID |
| `APPLE_API_KEY_CONTENT` | Complete contents of the matching `.p8` key |
| `SPARKLE_PRIVATE_KEY` | Sparkle EdDSA private key used by `sign_update` |

The workflow checks every secret before resolving packages or archiving. It writes signing material only to runner-temporary files, restricts private-key permissions, and removes those files and the temporary keychain in an `always()` cleanup step.

Never commit signing credentials, provider credentials, exported payloads, or local secret files. Rotate any credential that has been pasted into a chat, terminal transcript, or other non-secret channel.

## 3. Verify the Sparkle key pair

`Volt/Info.plist` contains the public update key in `SUPublicEDKey`. Before the first release, use Sparkle's key tooling to derive the public key associated with `SPARKLE_PRIVATE_KEY` and confirm it exactly matches that plist value.

If the keys do not match, rotate the private key and `SUPublicEDKey` together before shipping. Replacing only one side will make every update fail signature verification.

## 4. Make the update channel public

Volt is currently a private repository. Anonymous Sparkle clients cannot download a private GitHub release asset, even when the appcast itself is public. Before external distribution, choose one of these designs:

1. **Recommended:** make Volt public, then use its public GitHub release assets.
2. Keep source private and publish the DMG, appcast, and release-note HTML to a separate public repository, bucket, or CDN. This requires additional hosting credentials and corresponding workflow changes.

The current workflow implements option 1. Do not consider auto-update production-ready until all three of these URLs work in a private/incognito browser window without GitHub authentication:

- `https://github.com/IronsideXXVI/Volt/releases/download/vX.Y.Z/Volt-X.Y.Z.dmg`
- `https://ironsidexxvi.github.io/Volt/appcast.xml`
- `https://ironsidexxvi.github.io/Volt/releases/X.Y.Z.html`

## 5. Enable GitHub Pages

In **Repository settings → Pages**:

1. Select **Deploy from a branch**.
2. Select the `gh-pages` branch and `/ (root)`.
3. Save and wait for Pages to publish.

The release workflow preserves the existing feed, keeps the 15 newest appcast items, and publishes:

```text
appcast.xml
releases/X.Y.Z.html
.nojekyll
```

## 6. Promote an approved release

Development remains on `dev`. Only promote `dev` to `main` after Dylan approves the exact commit. A push to `main` starts the production release automatically. Manual dispatch must also be run from `main`.

The version is derived from the first two components of `MARKETING_VERSION` and the GitHub run number. For example, base version `0.1.0` and run number `42` produce:

```text
version: 0.1.42
build: 42
tag: v0.1.42
release: Volt 0.1.42
asset: Volt-0.1.42.dmg
```

The workflow refuses to begin expensive signing work if that tag or release already exists. If a run fails after creating its GitHub release, remove the incomplete release and tag only after verifying they are safe to replace, then rerun it.

## 7. First-release smoke test

After the approved merge reaches `main`:

1. Monitor the GitHub Actions job and confirm it is running on `depot-macos-26`.
2. Confirm the app and DMG notarization submissions are accepted.
3. Download the DMG anonymously and verify it contains `Volt.app` plus an `/Applications` symlink.
4. On macOS, validate both artifacts:

   ```bash
   codesign --verify --deep --strict --verbose=2 /Applications/Volt.app
   spctl --assess --type execute --verbose=4 /Applications/Volt.app
   xcrun stapler validate /Applications/Volt.app

   xcrun stapler validate Volt-X.Y.Z.dmg
   spctl --assess --type open \
     --context context:primary-signature \
     --verbose=4 Volt-X.Y.Z.dmg
   ```

5. Open the appcast and versioned release-note page anonymously and validate the appcast with `xmllint --noout appcast.xml`.
6. Install the previous Volt build, use **Check for Updates**, and complete an update through Sparkle.
7. Verify automatic checking can be disabled and re-enabled in Volt's Updates settings.
8. Confirm the GitHub release title, generated notes, tag, and DMG filename all use the same version.
