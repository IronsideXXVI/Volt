# General notes

- Development happens on `dev`; `main` is production and only receives Dylan-approved builds.
- The Icon Composer source at `/images/appicon.icon` is Dylan's canonical app icon and must not be modified or replaced. `/images/applogo.png` is used as the in-app logo and as the source artwork for the branded 18-point menu-bar image.
- Provider credentials are stored in the macOS login Keychain. Volt does not proxy credentials through another service.
- Claude and OpenAI consumer usage endpoints are authenticated internal endpoints rather than stable public APIs, so their decoders and request paths may require maintenance when providers change them.

# Progress notes

- July 17, 2026: Synced the project/icon setup from `main` into `dev` before beginning implementation.
- July 17, 2026: Replaced the starter SwiftData window app with a menu-bar-only SwiftUI app. There is no Dock icon or main window.
- July 17, 2026: Added the initial provider dashboard with a Claude/OpenAI switcher, branded usage and elapsed-time bars, reset countdowns, account/plan details, credits/extra usage, loading/error/stale-data states, manual refresh, and a ten-minute refresh loop while the menu is active.
- July 17, 2026: Added Claude support using organization ID plus session key credentials. The app reads current-session, weekly, model-specific, and extra-usage data.
- July 17, 2026: Added OpenAI/Codex support using OAuth credentials. Settings can import `~/.codex/auth.json`, tokens refresh when needed, and the app reads primary, secondary, model-specific, and credit limits.
- July 17, 2026: Added Keychain-backed credential storage, provider connection/disconnection controls, and a dedicated Settings window.
- July 17, 2026: Added Sparkle 2.8.1, automatic/manual update controls, and a shared Xcode scheme. Prepared an unsigned `dev` CI workflow and an automatic signed/notarized release plus appcast workflow for every push to `main`.
- July 17, 2026: Local static validation passes for Swift syntax, plist/XML/JSON/YAML parsing, the Xcode project graph, and GitHub Actions syntax.
- July 17, 2026: Installed the validated workflow templates at `.github/workflows/build.yml` and `.github/workflows/release.yml`. Pushes to `dev` trigger the macOS build when Actions minutes are available, while the production release workflow remains limited to pushes to `main`.
- July 17, 2026: Fixed an invisible menu bar item found during the first local run by temporarily switching to SwiftUI's dedicated `MenuBarExtra` system-image initializer and removing the redundant runtime activation-policy call.
- July 17, 2026: Replaced the temporary SF Symbol with a dedicated 18-point, full-color copy of Dylan's bundled `/images/applogo.png`. Volt registers that resized copy as a named AppKit image at launch and follows the proven named-image `MenuBarExtra` pattern used by Claude Usage. The SF Symbol logo fallback was removed, and the canonical Icon Composer app icon remains untouched.
- July 17, 2026: Fixed the resulting Xcode compile error by passing `NSImage.Name` directly to `MenuBarExtra`; on macOS it is a `String` type alias and has no `rawValue` member.
- July 17, 2026: Replaced the ineffective runtime image-name registration with the same implementation pattern proven in Claude Usage: a real, original-color asset-catalog image with an 18-point canvas, referenced directly by `MenuBarExtra(_:image:)` before the scene is created.
- Next: pull and visually verify the branded menu-bar image, then test both providers with real accounts and review the UI in light/dark mode. Fixes continue on `dev`; production promotion to `main` remains Dylan's decision.

# Blockers / open questions

- GitHub Actions validation is paused because the account currently has no Actions minutes. Local Xcode builds are the active validation path.
- The Volt repository needs these Actions secrets before a production release can succeed: `DEVELOPER_ID_CERTIFICATE_P12`, `DEVELOPER_ID_CERTIFICATE_PASSWORD`, `APPLE_API_KEY_ID`, `APPLE_API_ISSUER_ID`, `APPLE_API_KEY_CONTENT`, and `SPARKLE_PRIVATE_KEY`.
- Volt currently uses the Sparkle public key already used by Hacker News. `SPARKLE_PRIVATE_KEY` must contain the matching private key, or both keys must be rotated together before release.
- The repository is private. Sparkle clients cannot read private GitHub release assets or a private appcast without authentication. Before distributing Volt, make the release/feed publicly reachable (for example by making the repository public or using a separate public update host) and enable GitHub Pages for the `gh-pages` branch.
- Real-provider verification requires Dylan's Claude and OpenAI accounts; no credentials are committed to the repository or available in CI.
