# Volt

Volt is a native macOS menu-bar app for checking AI plan usage without leaving your current workspace.

## Providers

- **Claude / Anthropic**
  - Current-session and weekly usage
  - Dynamic model-scoped limits from the modern `limits[]` schema
  - Legacy Sonnet, Opus, Claude Design, Cowork, OAuth apps, and routine limits when returned
  - Extra usage, prepaid balance, auto-reload, purchase reset date, and daily routine-run budget
- **OpenAI / Codex**
  - 5-hour, daily, weekly, and other active plan windows
  - Model/feature-specific limits such as GPT-5.3-Codex-Spark
  - Code-review, spend-control, credit, and account-limit status when returned

Claude presents **percent used**, matching Anthropic. OpenAI presents **percent remaining**, matching the Codex usage dashboard. The top bar consistently shows **quota consumed**, so a limit with 10% remaining is 90% full and 10% empty. When reset timing is known, the neutral lower bar shows how much of that quota window has elapsed, making usage pace easy to compare with time. Warning and critical colors are based on consumption, not the provider’s label direction.

Volt has no Dock icon or main application window. Click the Volt logo in the macOS menu bar to switch providers, refresh usage, or open Settings.

## Credentials

Credentials are stored in the macOS login Keychain. Volt talks directly to each provider and does not proxy, log, or upload credentials.

### Claude

The recommended setup is:

1. Run `claude login`.
2. In Volt Settings → Claude, import `~/.claude/.credentials.json`.
3. Select **Save & Test**.

Volt uses Anthropic's OAuth usage endpoint when Claude Code credentials are available. An organization ID plus claude.ai `sessionKey` can also be saved as a fallback and enables browser-session-only auxiliary data. Browser sessions are less reliable because Cloudflare may challenge static API requests.

### OpenAI

The recommended setup is:

1. Run `codex login`.
2. In Volt Settings → OpenAI, import `~/.codex/auth.json`.
3. Select **Save & Test**.

Volt stores a private Keychain copy and refreshes the OAuth access token when needed.

The consumer usage endpoints used by Claude and OpenAI are authenticated internal endpoints and may change.

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

## Core tests

Provider payload parsing and normalization are isolated in a small Swift package so they can be tested without launching the menu-bar app:

```bash
swift test
```

The redacted fixtures cover OpenAI weekly-only, reversed primary/secondary, split feature windows, Spark, code-review, current and legacy spend-control shapes, credits, and status responses. Claude coverage includes legacy and limits-only payloads, dynamic scoped limits, inactive scopes, extra usage, prepaid credits, bundles, and routine budgets.

## Branches and releases

- `dev` is the integration and testing branch.
- `main` is production only and should receive Dylan-approved builds from `dev`.

The active workflows live in `.github/workflows/`, with synchronized reviewable copies in `automation/workflows/`:

- `build.yml` runs plist validation, warning-clean core tests, and an unsigned macOS build for `dev` and relevant pull requests;
- `release.yml` uses `depot-macos-26` to build, explicitly sign Sparkle and Volt, notarize and staple both the app and DMG, create generated GitHub release notes, and publish a historical Sparkle appcast plus versioned HTML notes after every approved push to `main`.

The production workflow expects the same five Apple signing/notarization secret names used by the Hacker News project, plus `SPARKLE_PRIVATE_KEY`. Volt's release asset, appcast, and release-note pages must all be anonymously reachable before external Sparkle updates can work. Because the repository is currently private, that distribution requirement is still blocked.

See [Production release setup](docs/release-setup.md) for Depot connection requirements, all six secrets, Sparkle key verification, GitHub Pages setup, the private-repository blocker, promotion rules, and the first-release smoke test.
