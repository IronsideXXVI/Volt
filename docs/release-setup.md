# Production release setup

Volt's production workflow builds, signs, notarizes, and publishes a Sparkle-compatible DMG whenever an approved commit reaches `main`. It may also be started manually from the `main` branch. The workflow deliberately refuses to release any other ref.

## 1. Runner: GitHub-hosted macOS

The release job runs on a GitHub-hosted macOS runner:

```yaml
runs-on: macos-26
```

Because Volt is a **public** repository, standard GitHub-hosted runners — including macOS — are **free with no minute limits**. No Depot connection and no GitHub organization are required.

Do not attempt to move this job onto Depot's Linux CI (`.depot/workflows/`) or a container build. A SwiftUI macOS app cannot be built or code-signed on Linux (no Xcode, no macOS SDK, `codesign`/`notarytool` are macOS-only). Depot's macOS *runners* would work but require the repository to be owned by a GitHub organization; the free GitHub-hosted runner avoids that entirely.

## 2. Configure release secrets

Six secrets are required under **Repository settings → Secrets and variables → Actions**:

| Secret | Value |
| --- | --- |
| `DEVELOPER_ID_CERTIFICATE_P12` | Base64-encoded Developer ID Application `.p12` |
| `DEVELOPER_ID_CERTIFICATE_PASSWORD` | Password for that `.p12` |
| `APPLE_API_KEY_ID` | App Store Connect API key ID |
| `APPLE_API_ISSUER_ID` | App Store Connect issuer ID |
| `APPLE_API_KEY_CONTENT` | Complete contents of the matching `.p8` key |
| `SPARKLE_PRIVATE_KEY` | Sparkle EdDSA private key used by `sign_update` (Volt-specific, already set) |

The workflow verifies every secret before resolving packages or archiving. It writes signing material only to runner-temporary files, restricts private-key permissions, and removes those files and the temporary keychain in an `always()` cleanup step.

Never commit signing credentials, provider credentials, exported payloads, or local secret files. Rotate any credential that has been pasted into a chat, terminal transcript, or other non-secret channel.

## 3. Sparkle key pair

Volt uses its **own** dedicated Sparkle EdDSA key pair (not shared with any other app). The public key is stored in `Volt/Info.plist`:

```
SUPublicEDKey = 2S+N7Nit4yL/uqP+U2R+YNpRpUBA3XmdudOyoISgkZQ=
```

The matching private key is stored in the `SPARKLE_PRIVATE_KEY` secret and in the login Keychain under account `ed25519-volt`. If the private key is ever rotated, regenerate it with Sparkle's `generate_keys --account ed25519-volt` and update both `SUPublicEDKey` and the secret together — replacing only one side makes every update fail signature verification.

## 4. Public distribution

Volt is public, so:

- The DMG is served from public GitHub release assets.
- The appcast and release-note pages are served from GitHub Pages.

Auto-update is production-ready once all three of these URLs work in a private/incognito browser window without GitHub authentication:

- `https://github.com/IronsideXXVI/Volt/releases/download/vX.Y.Z/Volt-X.Y.Z.dmg`
- `https://ironsidexxvi.github.io/Volt/appcast.xml`
- `https://ironsidexxvi.github.io/Volt/releases/X.Y.Z.html`

## 5. Enable GitHub Pages

In **Repository settings → Pages**:

1. Select **Deploy from a branch**.
2. Select the `gh-pages` branch and `/ (root)`.
3. Save and wait for Pages to publish.

The `gh-pages` branch is created by the first release run. The workflow preserves the existing feed, keeps the 15 newest appcast items, and publishes:

```text
appcast.xml
releases/X.Y.Z.html
.nojekyll
```

## 6. Promote an approved release

Development remains on `dev`. Only promote `dev` to `main` after the exact commit is approved. A push to `main` starts the production release automatically. Manual dispatch must also be run from `main`.

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

1. Monitor the GitHub Actions job and confirm the app and DMG notarization submissions are accepted.
2. Download the DMG anonymously and verify it contains `Volt.app` plus an `/Applications` symlink.
3. On macOS, validate both artifacts:

   ```bash
   codesign --verify --deep --strict --verbose=2 /Applications/Volt.app
   spctl --assess --type execute --verbose=4 /Applications/Volt.app
   xcrun stapler validate /Applications/Volt.app

   xcrun stapler validate Volt-X.Y.Z.dmg
   spctl --assess --type open \
     --context context:primary-signature \
     --verbose=4 Volt-X.Y.Z.dmg
   ```

4. Open the appcast and versioned release-note page anonymously and validate the appcast with `xmllint --noout appcast.xml`.
5. Install the previous Volt build, use **Check for Updates**, and complete an update through Sparkle.
6. Verify automatic checking can be disabled and re-enabled in Volt's Updates settings.
7. Confirm the GitHub release title, generated notes, tag, and DMG filename all use the same version.
