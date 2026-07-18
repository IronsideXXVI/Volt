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
- July 17, 2026: Rebuilt OpenAI normalization. Main and additional limits retain separate identities and titles; Spark no longer appears as a second generic “Weekly limit.” OpenAI labels show remaining capacity while bars show quota consumed. Decoding now covers `allowed`, `limit_reached`, relative and absolute reset times, code-review limits, spend control, overage/reached states, direct account email, credit/message metadata, and malformed optional entries without dropping valid siblings.
- July 17, 2026: Added product-facing OpenAI plan mapping (`prolite` → `Pro 5x`, `pro` → `Pro 20x`) instead of displaying the raw “Prolite” value.
- July 17, 2026: Rebuilt Claude normalization for legacy buckets and dynamic `limits[]` model scopes. Dynamic model display names are preserved, legacy Sonnet/Opus rows are deduplicated, generic all-model scopes stay in the main weekly row, known feature aliases are normalized, and unknown non-null usage buckets remain visible.
- July 17, 2026: Added Claude auxiliary data for prepaid balance, auto-reload, pending invoice, purchase reset/cap, and daily included routine runs. Existing extra-usage spent/monthly-limit data is retained.
- July 17, 2026: Added Claude Code credential import from `~/.claude/.credentials.json`, OAuth token refresh, plan inference including Max multipliers, and actionable OAuth-scope/Cloudflare errors. Credentials remain in Keychain.
- July 17, 2026: Rebuilt the menu panel as a compact native dashboard. Removed the misleading elapsed-time bar and heavy per-row cards. Every metric now has one bar, an explicit `% used` or `% remaining` label, reset text, semantic sections, compact account/plan metadata, and provider status/notices.
- July 17, 2026: Replaced the oversized single-form Settings window with General, Claude, OpenAI, and Updates panes. Claude and OpenAI now have separate import, masked manual fields, connection status, Save & Test, and disconnect actions. Saving one provider no longer rewrites or refreshes the other provider.

## Quota semantics and hardening follow-up

- July 17, 2026: Corrected the dashboard bar contract: labels retain provider language, while bar fill always represents quota consumed. An OpenAI quota with 10% remaining is now 90% full and enters the critical state.
- July 17, 2026: Added shared normal, warning, critical, exhausted, unavailable, and inactive quota states; sub-1% formatting; richer accessibility values; clearer reset dates; reduced-motion-aware bar animation; and an explicit “Bar fill shows quota used” legend.
- July 17, 2026: Hardened OpenAI normalization for reversed windows, split feature limits, stable duration-based identities, current root/nested/camel-case spend-control shapes, amount-derived percentages, false credit balances, duplicate reached notices, and HTTP 429 retry guidance.
- July 17, 2026: Hardened Claude normalization so a `limits[]`-only all-model quota is never dropped, inactive scoped limits do not hide active legacy limits, malformed siblings cannot erase valid limits, daily/monthly groups retain their durations, disabled extra usage no longer claims an unlimited cap, organization IDs are UUID-validated before URL construction, and HTTP 429 responses are actionable.
- July 17, 2026: Reworked dashboard metadata and Settings state. Long account/plan values truncate safely, critical and inactive limits are visually distinct, saved snapshots are invalidated when credentials change, Save & Test reports a real refresh result, provider load failures are isolated, unsaved drafts are visible, and token rotations are reflected back into the form.
- July 17, 2026: Added adaptive post-reset refresh timing and made both validation and production workflows run the warning-clean core test suite before building or releasing.

## Usage-to-window comparison

- July 18, 2026: Restored the Claude-Usage-style lower comparison bar with explicit semantics. The top bar remains quota consumed; the neutral lower bar is calculated from each limit's duration and next reset and shows the percentage of the quota window elapsed. Rows without reliable duration/reset data continue to show only usage, and accessibility output identifies both measurements.

## Production release automation

- July 17, 2026: Rebuilt the production workflow around the active GitHub Actions path and Depot's `depot-macos-26` runner. Depot CI files under `.depot/workflows/` were intentionally not used because Depot CI does not provide macOS sandboxes.
- July 17, 2026: Added manual dispatch with a strict `main`-branch guard, production concurrency, unique run-number versions, duplicate tag/release preflight, all-six-secret preflight, warning-clean core tests, and plist validation before release work.
- July 17, 2026: Replaced broad Sparkle framework signing with Sparkle's documented inner-to-outer signing order for Installer, Downloader with preserved entitlements, Autoupdate, Updater, the framework, and finally Volt with distribution entitlements.
- July 17, 2026: Added strict app and DMG signature checks, App Store Connect notarization diagnostics, retrying ticket stapling, Gatekeeper assessments without ignored failures, and a signed DMG containing `Volt.app` plus an `/Applications` symlink.
- July 17, 2026: Changed Sparkle distribution from ZIP to the final notarized/stapled DMG. Sparkle's private key is written to a mode-600 temporary file, and both the EdDSA signature and reported artifact length are validated before publishing.
- July 17, 2026: Added generated Markdown release notes, GitHub-rendered HTML notes for Sparkle's update UI, a history-preserving appcast helper that deduplicates builds and retains 15 releases, XML validation, and preservation of existing `gh-pages` files.
- July 17, 2026: Synchronized active and template release workflows, restored warning-clean core tests in the active build workflow, documented Depot/secrets/Pages/public-hosting setup, and added a first-production-release smoke-test checklist.

## Visual system overhaul

- July 18, 2026: Rebuilt the menu panel and Settings presentation around an adaptive electric-glass visual system while preserving provider, credential, refresh, and quota behavior. Added a layered backdrop, branded gradient treatment, shared icon tiles/status pills/section labels, more deliberate spacing, softer elevation, and provider-aware accenting in light and dark appearances.
- July 18, 2026: Reworked the menu dashboard hierarchy with a richer product header, two-line provider switcher, live account summary, explicit usage/time legend, compact quota-window badges, labeled usage-vs-time tracks, stronger empty/loading/setup states, and a glass utility footer.
- July 18, 2026: Rebuilt Settings as a wider control center with a translucent grouped sidebar, animated selection treatment, contextual page headers, provider connection summaries, numbered recommended import flows, visual default-provider choices, improved privacy/update cards, and persistent save/test controls.
- July 18, 2026: Kept the canonical Icon Composer source and in-app logo unchanged. No credential, provider-service, normalization, or release behavior was modified by the redesign.

## Tests and validation

- July 17, 2026: Added a standalone SwiftPM core target plus eleven redacted fixtures covering OpenAI weekly-only, main + Spark, primary + secondary, split feature windows, code review, credits and current/legacy spend control; Claude legacy fields, limits-only and dynamic scoped limits, extra usage, prepaid credits/bundles, and routine budget.
- July 17, 2026: Added thirteen normalization tests for consumed-vs-displayed math, quota states, title and identity preservation, split-window sorting, current spend schemas, dynamic deduplication, limits-only fallbacks, inactive scopes, epoch/ISO/relative resets, plan mapping, optional/malformed fields, auxiliary endpoints, and unknown future buckets.
- July 17, 2026: `swift test -Xswiftc -warnings-as-errors` passes all thirteen tests with Swift 6.3.3 on Linux. Every Swift file also passes compiler parser validation, and every JSON fixture parses successfully.
- July 17, 2026: No live credentials or identity-bearing endpoint payloads were added to source, tests, fixtures, logs, or documentation. The canonical app icon and in-app logo were not modified.
- July 18, 2026: Added fixed-time coverage for elapsed-window progress, percentage formatting, boundary clamping, and missing timing data. All fourteen warning-clean core tests pass with Swift 6.3.3 on Linux; all Swift sources remain parser-valid.
- July 18, 2026: The electric-glass redesign passes repository whitespace checks and tree-sitter parsing for every Swift source. Core tests and the macOS Xcode build are delegated to PR validation because this sandbox does not include the Swift toolchain or macOS SDK.

# Next verification

- Pull `dev` on a Mac and run the Xcode 26 Debug build. The current sandbox has no macOS SDK, AppKit, SwiftUI, `xcodebuild`, `codesign`, `notarytool`, or `hdiutil`, so the app target and production signing pipeline cannot be executed locally here.
- Exercise both saved accounts through Settings → Save & Test, then compare the resulting rows with the official provider pages.
- Inspect the menu panel and Settings panes in light mode, dark mode, reduced transparency, and with long account/plan strings. Confirm each timed quota's lower neutral bar and right-side percentage track elapsed window time, while untimed rows retain a single usage bar.
- Connect Depot, confirm `depot-macos-26` access, configure all six Actions secrets, and complete the anonymous-download and Sparkle smoke tests in `docs/release-setup.md` before first production distribution.
- Keep fixes on `dev`. Promotion to `main` remains Dylan's decision.

# Blockers / release notes

- Standard GitHub-hosted Actions validation is paused because the account currently has no Actions minutes. The production job now targets Depot, but Depot still must be connected and authorized for this repository; Depot's documented organization requirement may require moving Volt from Dylan's personal account to a GitHub organization.
- The Volt repository needs these Actions secrets before a production release can succeed: `DEVELOPER_ID_CERTIFICATE_P12`, `DEVELOPER_ID_CERTIFICATE_PASSWORD`, `APPLE_API_KEY_ID`, `APPLE_API_ISSUER_ID`, `APPLE_API_KEY_CONTENT`, and `SPARKLE_PRIVATE_KEY`.
- Volt currently uses the Sparkle public key already used by Hacker News. `SPARKLE_PRIVATE_KEY` must contain the matching private key, or both keys must be rotated together before release.
- The repository is private. Sparkle clients cannot anonymously read private GitHub release assets. Before distribution, either make Volt public or change the workflow to publish the DMG, appcast, and release notes through a separate public repository/bucket/CDN, then enable and verify GitHub Pages or the replacement host.
- The GitHub App used by this environment does not currently have permission to create or update `.github/workflows/*`. The release branch may need to be pushed with Dylan's GitHub credentials or after granting the App workflow permission.
