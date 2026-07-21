# Design

## Source of truth
- Status: Active
- Last refreshed: 2026-07-21
- Primary product surfaces: macOS menu bar extra panel (single window-style dropdown)
- Evidence reviewed: `apps/MorningBrief/Sources/*`, approved Morning Brief plan, Apple MenuBarExtra + LSUIElement guidance

## Brand
- Personality: Calm, editorial, morning ritual — like opening a well-typeset newspaper over coffee, not a chatbot dashboard
- Trust signals: Clear date header, readable typography, honest source status chips, subtle system-native chrome
- Avoid: Purple gradients, neon accents, “AI slop” aesthetics, mascot icons, dense widget grids, shimmer loaders, chat bubbles

## Product goals
- Goals: Surface today’s brief at a glance from the menu bar; reload when artifacts change; trigger refresh/doctor without leaving the flow
- Non-goals: Full markdown editor, in-app settings chrome, Dock presence, multi-window browsing, notification spam
- Success signals: User opens panel once each morning, reads sections without scrolling fatigue, trusts source chips and staleness badge

## Personas and jobs
- Primary personas: Single user (Yupeng) starting the day on macOS
- User jobs: “What happened overnight?” “Are my sources healthy?” “Regenerate if stale” “Open the folder if I need raw files”
- Key contexts of use: Early morning, low cognitive load, often before full desktop setup; panel may stay open while reading

## Information architecture
- Primary navigation: None — single panel only
- Core routes/screens: Menu bar icon → panel (header → notices → sources → sections → actions)
- Content hierarchy: Date → status/staleness → source health → brief sections (title + body) → utility actions

## Design principles
- Principle 1: **Quiet by default** — icon stays hierarchical SF Symbol; color only for status/degraded/stale
- Principle 2: **Readable first** — generous line length (~420pt panel), section titles as anchors, body in secondary tone
- Principle 3: **System-native** — `windowBackgroundColor`, bordered buttons, no custom chrome fighting macOS
- Tradeoffs: Rich markdown deferred to inline-only parsing for speed; full MD features sacrificed for calm rendering

## Visual language
- Color: Neutrals from system palette; green/orange/red reserved for source chips; orange stale badge; blue tint for informational notices (not errors)
- Typography: `title3.semibold` app title, `headline` section titles, `body`/`secondary` for content, `caption` for chips
- Spacing/layout rhythm: 20pt panel padding, 16pt vertical sections, 8pt chip spacing, 20pt between brief sections
- Shape/radius/elevation: 8pt rounded notice boxes; capsule chips; no drop shadows on panel (MenuBarExtra window provides depth)
- Motion: None intentional — status icon may use system hierarchical rendering only
- Imagery/iconography: SF Symbols only; status-specific icons listed in app README

## Components
- Existing components to reuse: SwiftUI `MenuBarExtra`, `ScrollView`, `Divider`, system `bordered` buttons
- New/changed components: `MenuBarPanelView`, `BriefSectionView`, `SourceChipView`, `FlowLayout` (chip wrap)
- Variants and states: Empty brief, loading/running (disabled Refresh), notice vs error banners, stale badge on icon + panel
- Token/component ownership: Defined in Swift sources under `apps/MorningBrief/Sources/`

## Accessibility
- Target standard: macOS HIG + WCAG-minded contrast using system semantic colors
- Keyboard/focus behavior: Quit supports ⌘Q shortcut; buttons are standard focusable controls
- Contrast/readability: Primary/secondary text pairing; error text on light red background
- Screen-reader semantics: Icon accessibility label includes status; chips label name + status
- Reduced motion and sensory considerations: No autoplay animation; static layout

## Responsive behavior
- Supported breakpoints/devices: Fixed 420pt panel width on macOS 14+
- Layout adaptations: Section body scrolls when content exceeds ~420pt height; chips wrap via `FlowLayout`
- Touch/hover differences: N/A (pointer/hover menu bar context)

## Interaction states
- Loading: `running` icon; Refresh disabled while `briefctl run` in flight
- Empty: Sun icon + “No brief yet” + hint to Refresh
- Error: Red banner with stderr/message; icon `xmark.circle`
- Success: Ready newspaper icon; optional blue notice (e.g. “已在生成” for exit 75)
- Disabled: Refresh/Doctor disabled during respective subprocess
- Offline/slow network: Reflected via source chip status and `degraded`/`error` run states from artifacts

## Content voice
- Tone: Brief, neutral, morning-appropriate; Chinese notice for already-running generation
- Terminology: “Morning Brief”, “Sources”, “Stale”, “Refresh”, “Doctor” aligned with CLI
- Microcopy rules: Non-errors use secondary/blue styling; errors use red; avoid exclamation-heavy copy

## Implementation constraints
- Framework/styling system: SwiftUI on macOS 14+, AppKit only for process/terminate/open
- Design-token constraints: No external design system; system colors and fonts only
- Performance constraints: 2s poll + directory watch; lazy section stack in scroll view
- Compatibility constraints: LSUIElement agent (no Dock); MenuBarExtra `.window` style only
- Test/screenshot expectations: Manual verification with sample `brief.json` in Application Support path

## Open questions
- [ ] Full markdown (lists, links, headings) vs inline-only — currently inline-only preserving whitespace / owner: user / impact: rendering fidelity
- [ ] Localized UI strings (English panel vs bilingual) — currently English chrome with Chinese generation notice / owner: user / impact: i18n
