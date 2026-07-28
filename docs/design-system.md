# Volt design system

This is the **binding UI contract** for Volt's menu-bar drawer and Settings
window. Any new provider tab, section, row, or piece of text **must** use the
tokens and rules below — never hardcode font sizes, weights, or colors in a
view. The tokens live in
`Volt/Views/AppTheme.swift` and are the single source of truth.

The guiding principle is **restraint**: native materials, hairline dividers, one
accent color, and a small fixed set of text styles. No gradients, glows,
backdrop blobs, drop shadows, or per-provider accent colors.

## Text styles (one token per field type)

Every text element uses exactly one of these `View` modifiers. Do not use
`.font(.system(size:…))` directly in a view — add or reuse a token instead.

| Token | Style | Use for |
| --- | --- | --- |
| `voltTitle()` | 15 semibold | The "&lt;Provider&gt; plan usage limits" heading |
| `voltStateTitle()` | 14 semibold | Full-view state headings: connect / error / empty / syncing |
| `voltHeaderTitle()` | 13 semibold | The app wordmark in the top bar |
| `voltSectionHeader()` | 13 semibold | Section headings: Weekly limits, Usage, Usage credits, Spend limit, Usage limit resets |
| `voltTabLabel(selected:)` | 13, semibold+primary (selected) / medium+secondary | Account switcher tab labels |
| `voltRowText()` | 12 semibold, monospaced digits | A usage row's name, "X% used", "Resets …", "X% elapsed" |
| `voltFooterText()` | 12 medium | Footer status text + control glyphs |
| `voltCaption()` | 11, **secondary** | Account/plan lines, section & credit subtitles, notices, detail-row labels, empty/edge messages |
| `voltDetailValue()` | 11 semibold, monospaced | A key/value detail row's value ("$0.00", "Off", "Jul 31") |
| `voltControlLabel()` | 12 semibold | A settings control/row label: provider name in a picker, toggle title, key in a key/value row, disclosure heading, connection-state title |

Size tiers, high to low: **15** title · **14** state heading · **13**
header/tabs/section headers · **12** usage-row + control labels · **11**
captions + detail values. There are **no half-point sizes** and no other body
sizes. `voltControlLabel` reuses the 12 tier, so the Settings window introduces
no new size.

Icons are exempt (they are sized to match their adjacent text, e.g. footer
glyphs at 13, notice/status icons at 11).

## Color

All colors come from `VoltTheme` (`AppTheme.swift`). Never hardcode a hex or a
per-provider color in a view.

| Token | Value | Meaning |
| --- | --- | --- |
| `VoltTheme.primary` | `#D94BC9` | The **one** Volt accent (magenta) — used everywhere an accent is needed |
| `VoltTheme.windowElapsed` | `Color.primary.opacity(0.55)` | The neutral time/elapsed bar (adaptive) |
| `VoltTheme.track` | `primary.opacity(0.08)` | Progress-bar track and inline-notice fill |
| `VoltTheme.hairline` | `primary.opacity(0.09)` | Dividers and borders |
| `VoltTheme.card` | `primary.opacity(0.035)` | Subtle switcher-well fill |
| `VoltTheme.cardHover` | `primary.opacity(0.06)` | Selected switcher segment |

Rules:

- **One accent.** `AIProvider.tint` resolves to `VoltTheme.primary` for every
  provider. There are **no per-provider colors**, and no status "dots".
- **Usage bars are always `VoltTheme.primary`** — they never change color with
  quota state. **Time bars are always `VoltTheme.windowElapsed`.** Neither
  changes.
- The **only** non-accent colors allowed are native semantic colors on
  full-page failure states and destructive controls, plus
  `.secondary`/`.tertiary` for de-emphasis. Inline notices never change color
  with severity. There is **no green**.

## Layout & structure

- Popover is **360pt wide**, content-sized height capped at 520 (then scrolls).
- The native `MenuBarExtra` window supplies the drawer surface. Do not add a
  root fill or change that surface's color; component fills remain limited to
  the existing switcher and notice tokens below.
- Sections are **card-less**, separated by `Divider()`. Settings follows the
  same flat structure; notices use the shared track-filled notice primitive.
- A usage row is: name + percentage (top), the two stacked bars (usage over
  time), then metadata (reset + elapsed). Both bars are equal height for
  easy comparison.
- Provider identity is shown **once** (the switcher logo). Do not repeat it in a
  hero/header card.
- Each switcher tab shows the provider's **monochrome logo and provider name**,
  followed by the account's global drawer ordinal when numbers are enabled.
  Logos are imported as **template images** (`template-rendering-intent`) and
  tinted to the tab's label color (primary when selected, secondary when not)
  so they adapt to light/dark — never a per-provider brand color. Number
  visibility changes only the ordinal; help, Settings, and accessibility labels
  always use an explicit label such as "OpenAI account 3."

### Account switcher geometry and behavior

- Account ordinals are derived from the account's current position in the
  global drawer order. They are never persisted and never used as identity.
- One to three accounts divide the 326pt tab content width evenly.
- Four or more accounts keep the same three-across tab width inside a
  horizontally scrolling strip. Tabs never compress below that width.
- The selected UUID is always a scroll target. Opening the drawer reveals it
  without animation; selection, addition, removal, and reorder reveal it with
  a restrained animation unless Reduce Motion is enabled.
- Scrolling uses native trackpad and shift-wheel behavior with indicators
  hidden. Switching tabs never fetches usage.
- Hiding account numbers must not resize tabs, alter selection or order, scroll
  the strip, or trigger a usage fetch. Tabs retain their provider names; repeated
  providers remain distinguishable by selection, unique help text, Settings
  labels, and VoiceOver.

## Notices, links & Markdown

- Subtitle and footnote text is rendered through `styledMarkdown(…)`; links
  outside notices are `VoltTheme.primary` and underlined.
- Every inline notice in the drawer and Settings uses `VoltNotice`:
  - The fill is exactly `VoltTheme.track`, matching unused limit-bar space.
  - The border is `VoltTheme.hairline` at 0.5pt.
  - Icon, normal text, emphasized Markdown, and links are all `.secondary`.
    Links remain underlined and do not become magenta.
  - Authored/API Markdown uses the Markdown initializer; dynamic operational
    and error strings use the verbatim initializer so punctuation is preserved.
    Notice links remain actionable for keyboard and VoiceOver users.
  - Severity changes only the SF Symbol and spoken prefix: Information uses
    `info.circle.fill`, Success uses `checkmark.circle.fill`, Warning uses
    `exclamationmark.triangle.fill`, and Error uses `xmark.circle.fill`.
  - VoiceOver announces the semantic prefix before the message.
- This notice contract covers quota/plan messages, promotions, stale-snapshot
  banners, credential-import and connection-test feedback, and provider
  caveats. Full-page failures and destructive buttons are not notices and keep
  native semantic treatment.
- The Claude boost/promotion banner is parsed generically from the org
  bootstrap `org_growthbook.features` (locale → Markdown), never by hardcoded
  feature id. It sits under **Weekly limits**, with "Learn more about usage
  limits" beneath it.

## Settings window

The Settings window is a sibling surface to the popover and uses the **same
tokens and the same one-accent restraint**. It is 700×560 with a 190pt
`.ultraThinMaterial` sidebar.

- The sidebar is a **flat** list (General · Claude · OpenAI · Updates) — no group
  eyebrows. Provider rows use the **template logo** (tinted to the label color,
  like the popover switcher); non-provider rows use an SF Symbol. There are **no
  connection dots** in the sidebar. Its background remains the transparent
  native material itself—never an opaque or accent-colored replacement.
- Sections are flat and divider-separated. Do not nest rounded card surfaces,
  add accent chips, provider glyph tiles, or magenta drop outlines.
- The selected sidebar row uses `VoltTheme.cardHover` with primary icon/text;
  unselected rows use secondary icon/text. Provider logos remain raw,
  monochrome template images.
- `VoltTheme.primary` is reserved for Save & Test, links outside notices, and
  active native controls. Connection summaries and operational results are
  neutral, with the latter rendered through `VoltNotice`.
- **General → Account tabs** begins with the persisted, default-on "Show
  account numbers in drawer" toggle. Global account order appears as flat
  divider-separated rows (grip handle + raw provider logo + generated account
  label). Drag-and-drop, context-menu actions, and VoiceOver actions all support
  moving an account earlier or later.
- **Claude / OpenAI → Accounts** uses a generated-label picker and Add Account
  button. Account names are not editable. A flat Credentials section contains
  a bordered Import button and one Advanced disclosure for manual fields.
- Provider footers remain anchored: native destructive actions on the left,
  secondary "Unsaved changes" text without a colored dot, and one stable-width,
  prominent magenta Save & Test action on the right.
- **Updates** is a flat Software Updates section with divider-separated
  automatic-check and installed-version rows plus a normal bordered Check for
  Updates button.

## Fetch behavior

- Usage is fetched **only** when the menu opens (an unstructured `Task` in
  `onAppear`, so it isn't cancelled by re-renders) or when the refresh button
  is clicked. **No background polling. No fetch on tab switch.** Opening the
  menu refreshes every configured account once.

## Adding a new provider tab (checklist)

1. Add the case to `AIProvider`; keep `tint` = `VoltTheme.primary`. Add a
   monochrome logo imageset (template rendering, @1x/@2x/@3x) and point
   `logoAsset` at it.
2. Normalize its response into the shared `ProviderUsageSnapshot`
   (`UsageSection` / `UsageDetailSection` / `UsageWindow`) — the popover renders
   any provider from these types, so no new view code should be needed.
3. Reuse the existing rendering: `usageSection`, `detailSection`,
   `UsageRowView`, and `VoltNotice`. Every text field must use a token above.
4. If a genuinely new field type appears, add **one** new token here and in
   `AppTheme.swift`, then use it — do not inline a new size/weight/color.
5. Keep the restraint rules: one accent, card-less sections, no gradients/glows,
   fetch only on open/refresh.
