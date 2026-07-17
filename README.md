# Volt

Volt is a native macOS menu bar app for checking AI plan usage without leaving your current workspace.

## Current providers

- **Claude / Anthropic**: current session, weekly/model-specific limits, reset times, and extra usage.
- **OpenAI / Codex**: active rate-limit windows, reset times, model-specific limits, and credits.

Volt has no Dock icon or main application window. Click the Volt logo in the macOS menu bar to switch providers, refresh usage, or open Settings.

## Credentials

Credentials are stored in the macOS login Keychain.

- Claude requires an organization ID and the `sessionKey` cookie from a signed-in claude.ai session.
- OpenAI can import `~/.codex/auth.json` after `codex login`. Manual OAuth token entry is also available.

Volt talks directly to each provider. It does not proxy, log, or upload credentials anywhere else. The consumer usage endpoints used by Claude and OpenAI are not public APIs and may change.

## Build

Requirements:

- macOS 14 or newer
- Xcode 26 or newer

```bash
xcodebuild -resolvePackageDependencies \
  -project Volt.xcodeproj \
  -scheme Volt

xcodebuild build \
  -project Volt.xcodeproj \
  -scheme Volt \
  -configuration Debug \
  -destination 'generic/platform=macOS'
```

The app uses [Sparkle](https://sparkle-project.org/) for automatic and manual updates.

## Branches and releases

- `dev` is the integration and testing branch.
- `main` is production only and should receive Dylan-approved builds from `dev`.

Workflow templates live in `automation/workflows/`. Install them as `.github/workflows/build.yml` and `.github/workflows/release.yml` to enable:

- unsigned macOS validation for pull requests into `dev`;
- a signed and notarized release, GitHub release notes, and a refreshed Sparkle appcast after every push to `main`.

The production workflow expects the same Apple signing/notarization secret names used by the Hacker News project, plus `SPARKLE_PRIVATE_KEY`. GitHub Pages (or another public host) must serve `appcast.xml` and release downloads must be publicly reachable before external Sparkle updates can work.
