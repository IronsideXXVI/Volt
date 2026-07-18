# General notes

- Development happens on `dev`; `main` is production and only receives Dylan-approved builds.
- The Icon Composer source at `/images/appicon.icon` is Dylan's canonical app icon and must not be modified or replaced. `/images/applogo.png` is used as the in-app logo and as the source artwork for the branded menu-bar image.
- Provider credentials are stored in the macOS login Keychain. Volt does not proxy credentials through another service.
- Claude and OpenAI consumer usage endpoints are authenticated internal endpoints rather than stable public APIs, so their decoders and request paths may require maintenance when providers change them.

# Progress notes

## Initial app foundation

- July 17, 2026: Synced the project/icon setup from `main` into `dev` before beginning implementation.
- July 17, 2026: Replaced the starter SwiftData window app with a menu-bar-only SwiftUI app. There is no Dock icon or main window.
- July 17, 2026: Added the initial Claude/OpenAI dashboard, Keychain-backed credentials, ten-minute refresh loop, stale-data handling, Sparkle 2.8.1, and macOS build/release workflow templates.
- July 17, 2026: Installed the workflow templates at `.github/workflows/build.yml` and `.github/workflows/release.yml`. Pushes to `dev` trigger validation when Actions minutes are available; production release automation remains limited to `main`.
- July 17, 2026: Replaced temporary menu-bar imagery with the verified asset-catalog status icon and fixed the successful-response dashboard collapsing to zero height.

## Provider correctness and UI rebuild

- July 17, 2026: Audited Volt against the official Claude and Codex usage pages, Dylan's supplied screenshots, the working `Claude-Usage` app, current OpenAI Codex source, and CodexBar's Claude/OpenAI implementations.
- July 17, 2026: Live-tested `GET https://chatgpt.com/backend-api/wham/usage`. Confirmed that the apparent duplicate weekly rows are distinct limits: the main Codex weekly quota and `GPT-5.3-Codex-Spark`. Confirmed OpenAI's payload reports `used_percent` while the official dashboard displays the complement as percent remaining.
- July 17, 2026: Confirmed static claude.ai browser-session requests can receive a Cloudflare managed challenge. Added the modern Anthropic OAuth usage route (`/api/oauth/usage`) as the preferred path while preserving browser-session credentials as a fallback.
- July 17, 2026: Replaced the provider-assuming `UsageWindow` model with explicit canonical percent-used data, `.used`/`.remaining` display semantics, semantic source identity, sections, provider status, detail rows, and notices.
- July 17, 2026: Rebuilt OpenAI normalization. Main and additional limits retain separate identities and titles; Spark no longer appears as a second generic “Weekly limit.” OpenAI bars and labels now show remaining capacity. Decoding now covers `allowed`, `limit_reached`, relative and absolute reset times, code-review limits, spend control, overage/reached states, direct account email, credit/message metadata, and malformed optional entries without dropping valid siblings.
- July 17, 2026: Added product-facing OpenAI plan mapping (`prolite` → `Pro 5x`, `pro` → `Pro 20x`) instead of displaying the raw “Prolite” value.
- July 17, 2026: Rebuilt Claude normalization for legacy buckets and dynamic `limits[]` model scopes. Dynamic model display names are preserved, legacy Sonnet/Opus rows are deduplicated, generic all-model scopes stay in the main weekly row, known feature aliases are normalized, and unknown non-null usage buckets remain visible.
- July 17, 2026: Added Claude auxiliary data for prepaid balance, auto-reload, pending invoice, purchase reset/cap, and daily included routine runs. Existing extra-usage spent/monthly-limit data is retained.
- July 17, 2026: Added Claude Code credential import from `~/.claude/.credentials.json`, OAuth token refresh, plan inference including Max multipliers, and actionable OAuth-scope/Cloudflare errors. Credentials remain in Keychain.
- July 17, 2026: Rebuilt the menu panel as a compact native dashboard. Removed the misleading elapsed-time bar and heavy per-row cards. Every metric now has one bar, an explicit `% used` or `% remaining` label, reset text, semantic sections, compact account/plan metadata, and provider status/notices.
- July 17, 2026: Replaced the oversized single-form Settings window with General, Claude, OpenAI, and Updates panes. Claude and OpenAI now have separate import, masked manual fields, connection status, Save & Test, and disconnect actions. Saving one provider no longer rewrites or refreshes the other provider.

## Tests and validation

- July 17, 2026: Added a standalone SwiftPM core target plus nine redacted fixtures covering OpenAI weekly-only, main + Spark, primary + secondary, code review, credits and spend control; Claude legacy fields, dynamic scoped limits, extra usage, prepaid credits/bundles, and routine budget.
- July 17, 2026: Added nine normalization tests for used/remaining math, bar fractions, title preservation, dynamic deduplication, epoch/ISO/relative resets, plan mapping, optional/malformed fields, auxiliary endpoints, and unknown future Claude buckets.
- July 17, 2026: `swift test -Xswiftc -warnings-as-errors` passes all nine tests with Swift 6.3.3 on Linux. Every Swift file also passes compiler parser validation, and every JSON fixture parses successfully.
- July 17, 2026: No live credentials or identity-bearing endpoint payloads were added to source, tests, fixtures, logs, or documentation. The canonical app icon and in-app logo were not modified.

# Next verification

- Pull `dev` on a Mac and run the Xcode 26 Debug build. The current sandbox has no macOS SDK, AppKit, SwiftUI, or `xcodebuild`, so the full app target cannot be compiled here.
- Exercise both saved accounts through Settings → Save & Test, then compare the resulting rows with the official provider pages.
- Inspect the menu panel and Settings panes in light mode, dark mode, reduced transparency, and with long account/plan strings.
- Keep fixes on `dev`. Promotion to `main` remains Dylan's decision.

# Blockers / release notes

- GitHub Actions validation is paused because the account currently has no Actions minutes. Local Xcode builds are the active app-target validation path.
- The Volt repository needs these Actions secrets before a production release can succeed: `DEVELOPER_ID_CERTIFICATE_P12`, `DEVELOPER_ID_CERTIFICATE_PASSWORD`, `APPLE_API_KEY_ID`, `APPLE_API_ISSUER_ID`, `APPLE_API_KEY_CONTENT`, and `SPARKLE_PRIVATE_KEY`.
- Volt currently uses the Sparkle public key already used by Hacker News. `SPARKLE_PRIVATE_KEY` must contain the matching private key, or both keys must be rotated together before release.
- The repository is private. Sparkle clients cannot read private GitHub release assets or a private appcast without authentication. Before distribution, make the release/feed publicly reachable and enable GitHub Pages for the `gh-pages` branch (or use another public update host).
