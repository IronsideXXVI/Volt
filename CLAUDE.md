# Volt — project rules

Volt is a native macOS (SwiftUI, macOS 14+) menu-bar app that shows AI plan
usage across providers. Keep it restrained, native, and consistent.

## UI design — binding

**Follow [`docs/design-system.md`](docs/design-system.md) for every UI change.**
It is the single source of truth for text styles, colors, layout, and behavior,
and it includes the checklist for adding a new provider tab.

Non-negotiables (details in the doc):

- **Never hardcode a font size/weight or a color in a view.** Use the text-style
  tokens (`voltTitle`, `voltSectionHeader`, `voltStateTitle`, `voltHeaderTitle`,
  `voltTabLabel`, `voltRowText`, `voltFooterText`, `voltCaption`,
  `voltDetailValue`) and `VoltTheme` colors, all in `Volt/Views/AppTheme.swift`.
  If a genuinely new field type appears, add **one** token there and reuse it.
- **One accent** (`VoltTheme.primary`, magenta). No per-provider colors, no
  status dots. Usage bars are always the accent; time bars are always
  `VoltTheme.windowElapsed`; neither changes with state.
- **Restraint:** card-less sections separated by dividers; native materials; no
  gradients, glows, backdrop blobs, or drop shadows.
- **Fetch only** on menu-open or the refresh button — no background polling, no
  fetch on tab switch.
- New providers should render entirely through the shared
  `ProviderUsageSnapshot` types and the existing views — no new field styling.

## Build, test, release

- Build: `xcodebuild build -project Volt.xcodeproj -scheme Volt -configuration Debug -destination 'generic/platform=macOS'`
- Core tests: `swift test`
- Branches: develop on `dev`; production is `main`. Promoting `dev` → `main`
  ships a signed, notarized, auto-updating release (see
  [`docs/release-setup.md`](docs/release-setup.md)). Version is `0.1.<run#>`.
