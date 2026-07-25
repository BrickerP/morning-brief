# Design

## Source of truth
- Status: Active
- Last refreshed: 2026-07-23
- Primary product surfaces: macOS menu bar extra panel with `工作台账 | Agent | 晨报` lenses
- Evidence reviewed: `apps/MorningBrief/Sources/*`, `docs/creative/01-brainstorm.md` through `04-prototype.md`, Apple MenuBarExtra + LSUIElement guidance

## Brand
- Personality: Calm editorial briefing plus a quiet operator's work ledger, not a chatbot dashboard
- Trust signals: Clear date header, readable typography, honest source status chips, visible agent actors/reasons/evidence, reversible mutations, subtle system-native chrome
- Avoid: Purple gradients, neon accents, “AI slop” aesthetics, mascot icons, dense widget grids, shimmer loaders, chat bubbles, Kanban squeezed into a menu

## Product goals
- Goals: Surface today’s brief at a glance; capture and maintain today's work throughout the day; expose pending/in-progress/completed/cancelled state; allow explicit **删除** (append-only tombstone hide) distinct from **取消**; retain progress and recent completion history; recover a Claude session from pasted ending text; let the local agent summarize and propose inspectable Todo updates before confirmed, reversible writes
- Non-goals: Full markdown editor, project-management hierarchy, calendar/timeboxing, generic connector marketplace, general-purpose multi-session chat, Dock presence, multi-window browsing, notification spam, hard SQL purge of ledger events
- Success signals: User captures meeting work before context is lost; one opening answers what is pending/active/completed; agent changes remain explainable and undoable; the brief stays readable without competing with the ledger

## Personas and jobs
- Primary personas: Single user (Yupeng) starting the day on macOS
- User jobs: “What happened overnight?” “What am I doing now?” “What changed or is blocked?” “What did I finish recently?” “Let my agent update this safely from external evidence”
- Key contexts of use: Early morning briefing; meetings that create rough commitments; repeated daytime context switches; end-of-day or follow-up progress recall

## Information architecture
- Primary navigation: One segmented lens selector inside a single panel: `工作台账 | Agent | 晨报`
- Core routes/screens: Menu bar icon → selected lens; work lens → overview → item event trail or recent history; Agent lens → pasted ending → summary/matches/proposals → confirmation; brief lens → existing hero/full-text flow
- Content hierarchy: Shared date/lens → work quick capture and state groups or brief content → contextual footer actions

## Design principles
- Principle 1: **Quiet by default** — icon stays hierarchical SF Symbol; color only for status/degraded/stale
- Principle 2: **Readable first** — generous line length (~420pt panel), section titles as anchors, body in secondary tone
- Principle 3: **System-native** — `windowBackgroundColor`, bordered buttons, no custom chrome fighting macOS
- Principle 4: **Autonomous but observable** — the agent may decide and mutate without approval dialogs, but every change exposes actor, reason, evidence, and undo
- Principle 5: **Append progress** — decisions, blockers, and next steps become chronological events instead of overwritten notes
- Tradeoffs: Rich markdown remains secondary; the MVP favors four states and recent history over projects, deadlines, priorities, drag ordering, or deep analytics

## Visual language
- Color: Neutrals from system palette; active blue for in-progress/unread agent changes; completion green; cancelled gray; error red remains reserved for failures
- Typography: `title3.semibold` app/item title, `headline` section titles, `callout` task/progress text, `caption` state/actor labels, monospaced captions for timestamps/evidence IDs
- Spacing/layout rhythm: 20pt panel padding, 16pt vertical sections, 8pt chip spacing, 20pt between brief sections
- Shape/radius/elevation: 8pt rounded notice boxes; capsule chips; no drop shadows on panel (MenuBarExtra window provides depth)
- Motion: None intentional — status icon may use system hierarchical rendering only
- Imagery/iconography: SF Symbols only; status-specific icons listed in app README

## Components
- Existing components to reuse: SwiftUI `MenuBarExtra`, `ScrollView`, `Divider`, system `bordered` buttons
- New/changed components: three-way lens selector, work overview, quick capture, work row, item detail, event rail, recent-history view, Claude session composer, Agent summary/match/proposal review, confirmation action, plus existing brief components
- Variants and states: Empty brief/workday, pending, in-progress, completed, cancelled, read-only historical day, mutation in flight, mutation error followed by projection reconciliation, existing brief loading/degraded/error states
- Token/component ownership: Defined in Swift sources under `apps/MorningBrief/Sources/`

## Accessibility
- Target standard: macOS HIG + WCAG-minded contrast using system semantic colors
- Keyboard/focus behavior: Quit supports ⌘Q; Enter submits capture/progress; the work lens autofocuses quick-capture and binds ⌘N to refocus it; Esc returns from a work item / history to the list; the brief lens binds ⌘R to Refresh; the Agent composer offers a paste button and autofocuses. Standard controls remain focusable.
- Contrast/readability: Primary/secondary text pairing; error text on light red background
- Screen-reader semantics: Status always includes text/icon; work rows announce title, status, last actor/time, and history availability; historical mode announces read-only
- Reduced motion and sensory considerations: No autoplay animation; static layout

## Responsive behavior
- Supported breakpoints/devices: Fixed 420pt panel width on macOS 14+
- Layout adaptations: Header/lens/footer remain stable; the selected lens owns the middle scroll; work detail and history replace the overview rather than stacking into one feed
- Touch/hover differences: N/A (pointer/hover menu bar context)

## Interaction states
- Loading: `running` icon; Refresh disabled while `briefctl run` in flight
- Empty: Sun icon + “No brief yet” + hint to Refresh
- Error: Red banner with stderr/message; icon `xmark.circle`
- Success: Ready newspaper icon; optional blue notice (e.g. “已在生成” for exit 75); a fresh brief flags an unread blue dot on the 晨报 lens until opened
- Disabled: Refresh/Doctor disabled during respective subprocess
- Cancellable: Long agent calls (session analysis, brief synthesis) show a 取消 control; cancelling terminates briefctl and its `agent` grandchild, then shows a neutral “已取消” notice rather than an error
- Offline/slow network: Reflected via source chip status and `degraded`/`error` run states from artifacts
- Work mutation: Controls pause during the local command; drafts clear only after success. Failures retain typed text, show the diagnostic, and regenerate the projection to reconcile any committed event.
- Agent update: A quiet unread dot on the work lens and a chronological event with actor/reason/evidence; no pulsing or approval modal
- Session pick: The Agent lens lists recent Claude sessions (newest first, with preview); picking one analyzes it directly without pasting
- Session locate: Pasting an ending first runs a fast locate phase and shows the matched session for confirmation before the slow agent read; a wrong match can be restarted without waiting
- Session analysis: Show locating/reading progress without mutating work; show the matched session ID, summary, Todo matches, and every proposed mutation before one explicit confirmation
- Session apply success: Clear the completed Agent conversation and navigate directly to the refreshed work ledger; do not leave a success dead-end in the Agent lens
- Session conflict: If any matched Todo changed after analysis, reject the stale proposal set and ask for a fresh analysis rather than partially overwriting current work

## Content voice
- Tone: Brief, neutral, and operational; Chinese work-ledger language coexists with the Morning Brief brand
- Terminology: `待处理`, `进行中`, `已完成`, `取消` (retained terminal stop), `删除` (tombstone hide from views, undoable), `进展`, `证据`, and `撤销`; brief terminology remains unchanged
- Microcopy rules: Non-errors use secondary/blue styling; errors use red; avoid exclamation-heavy copy; cancel confirms are not error-styled; delete confirm may use destructive role inside the sheet only

## Implementation constraints
- Framework/styling system: SwiftUI on macOS 14+, AppKit only for process/terminate/open; Python `briefctl` owns session recovery, structured Agent analysis, and confirmed work mutations
- Design-token constraints: No external design system; system colors and fonts only
- Performance constraints: 2s poll + directory watch; atomic `work.json` projections; small local event ledger; no network dependency for ordinary work operations
- Compatibility constraints: LSUIElement agent (no Dock); MenuBarExtra `.window` style only
- Test/screenshot expectations: Python event/CLI/concurrency tests; Swift typecheck/build; isolated CLI journey; manual panel verification with synthetic `work.json` and existing brief artifacts

## Open questions
- [ ] Full markdown (lists, links, headings) vs inline-only — currently inline-only preserving whitespace / owner: user / impact: rendering fidelity
- [ ] Localized UI strings (English panel vs bilingual) — currently English chrome with Chinese generation notice / owner: user / impact: i18n
