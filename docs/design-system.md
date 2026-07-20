# Volt design system

This is the **binding UI contract** for Volt's menu-bar popover. Any new provider
tab, section, row, or piece of text **must** use the tokens and rules below — never
hardcode font sizes, weights, or colors in a view. The tokens live in
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
| `voltTabLabel(selected:)` | 13, semibold+primary (selected) / medium+secondary | Provider switcher tab labels |
| `voltRowText()` | 12 semibold, monospaced digits | A usage row's name, "X% used", "Resets …", "X% elapsed" |
| `voltFooterText()` | 12 medium | Footer status text + control glyphs |
| `voltCaption()` | 11, **secondary** | Account/plan lines, section & credit subtitles, notices, detail-row labels, empty/edge messages |
| `voltDetailValue()` | 11 semibold, monospaced | A key/value detail row's value ("$0.00", "Off", "Jul 31") |
| `voltControlLabel()` | 12 semibold | A settings control/row label: provider name in a picker, toggle title, key in a key/value row, disclosure heading, connection-state title |
| `voltChipText()` | 11 semibold | Emphatic small text in a status pill or inline status label (caller supplies the semantic color) |

Size tiers, high to low: **15** title · **14** state heading · **13**
header/tabs/section headers · **12** usage-row + control labels · **11**
captions + detail values + chips. There are **no half-point sizes** and no
other body sizes. `voltControlLabel`/`voltChipText` reuse the 12/11 tiers — the
Settings window introduces no new sizes, only these two field types.

Icons are exempt (they are sized to match their adjacent text, e.g. footer
glyphs at 13, notice/status icons at 11).

## Color

All colors come from `VoltTheme` (`AppTheme.swift`). Never hardcode a hex or a
per-provider color in a view.

| Token | Value | Meaning |
| --- | --- | --- |
| `VoltTheme.primary` | `#D94BC9` | The **one** Volt accent (magenta) — used everywhere an accent is needed |
| `VoltTheme.windowElapsed` | `Color.primary.opacity(0.55)` | The neutral time/elapsed bar (adaptive) |
| `VoltTheme.track` | `primary.opacity(0.08)` | Progress-bar track |
| `VoltTheme.hairline` | `primary.opacity(0.09)` | Dividers and borders |
| `VoltTheme.card` | `primary.opacity(0.035)` | Card / notice fill |
| `VoltTheme.cardHover` | `primary.opacity(0.06)` | Selected switcher segment |

Rules:

- **One accent.** `AIProvider.tint` resolves to `VoltTheme.primary` for every
  provider. There are **no per-provider colors**, and no status "dots".
- **Usage bars are always `VoltTheme.primary`** — they never change color with
  quota state. **Time bars are always `VoltTheme.windowElapsed`.** Neither
  changes.
- The **only** non-accent colors allowed are semantic: `.red`/`.orange` for
  warning/critical/error *text and banners* (not bars), `.green` reserved for
  the Updates/system area, and `.secondary`/`.tertiary` for de-emphasis.

## Layout & structure

- Popover is **360pt wide**, content-sized height capped at 520 (then scrolls).
- Sections are **card-less**, separated by `Divider()`. Only the settings panes
  and notices use `voltCard()`.
- A usage row is: name + percentage (top), the two stacked bars (usage over
  time), then metadata (reset + elapsed). Both bars are equal height for
  easy comparison.
- Provider identity is shown **once** (the switcher). Do not repeat it in a
  hero/header card.
- Each switcher tab shows the provider's **monochrome logo** to the left of its
  name. Logos are imported as **template images** (`template-rendering-intent`)
  and tinted to the tab's label color (primary when selected, secondary when
  not) so they adapt to light/dark — never a per-provider brand color.

## Notices, links & Markdown

- Notice/subtitle/footnote text is rendered through `styledMarkdown(…)`:
  - **Links** are `VoltTheme.primary` and **underlined**.
  - The API's strongly-emphasized run (a banner's first sentence) is colored
    with the `lead` color; the rest uses `base`. Do **not** bold it — emphasis
    is conveyed by color, driven by the API's own Markdown so future messages
    stay accurate.
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
  connection dots** in the sidebar.
- Sections are `voltCard()`s. A provider mark is drawn with `VoltLogoGlyph`
  (the branded counterpart to `VoltGlyph`), never a per-provider brand color.
- Connection state is conveyed by the **color of its title** (`voltControlLabel`
  tinted `primary` connected/ready, `.orange` on error, `.secondary` when not
  connected) — not by a status dot or a redundant chip.
- **One accent** still holds: `primary` for connected/ready/info/success and the
  "Recommended"/"Credential ready" chips; `.orange` for errors. **Green is used
  only in the Updates pane** (the system area). The page tint (`.tint`) is
  `primary` everywhere except Updates, which is green.

## Fetch behavior

- Usage is fetched **only** when the menu opens (an unstructured `Task` in
  `onAppear`, so it isn't cancelled by re-renders) or when the refresh button
  is clicked. **No background polling. No fetch on tab switch.** Opening the
  menu refreshes every configured provider once.

## Adding a new provider tab (checklist)

1. Add the case to `AIProvider`; keep `tint` = `VoltTheme.primary`. Add a
   monochrome logo imageset (template rendering, @1x/@2x/@3x) and point
   `logoAsset` at it.
2. Normalize its response into the shared `ProviderUsageSnapshot`
   (`UsageSection` / `UsageDetailSection` / `UsageWindow`) — the popover renders
   any provider from these types, so no new view code should be needed.
3. Reuse the existing rendering: `usageSection`, `detailSection`, `UsageRowView`,
   `noticeView`. Every text field must use a token above.
4. If a genuinely new field type appears, add **one** new token here and in
   `AppTheme.swift`, then use it — do not inline a new size/weight/color.
5. Keep the restraint rules: one accent, card-less sections, no gradients/glows,
   fetch only on open/refresh.
