# Desktop Shell + TCA — Brainstorm

## Status

- Creative Builder step: 1 / Brainstorm
- Status: Approved — Direction C; landscape authorized
- Date: 2026-07-28
- Path: `docs/creative/desktop-shell-tca/` (subproject; does not replace ledger/session-scan docs)

## Idea in one sentence

Rebuild Morning Brief as a Loop-like translucent macOS desktop shell with TCA-driven state, covering 工作台账 → Agent → 晨报 in that order—without abandoning the working `briefctl` backend.

Confidence: **72%**

## How Might We

How might we give a solo operator a modern desktop shell and a predictable state machine across ledger, agent apply, and brief reading—while shipping a one-week vertical slice that stays usable day-to-day?

## What we heard

- Want **both** visual shell (Luminare / Loop-like) **and** TCA state machine—not pick one.
- End state: **全都要** — sidebar shell + 台账 + Agent 确认流 + 晨报阅读.
- Week-1 order locked: **台账 → Agent → 晨报**.
- Not for: teams, multi-user SaaS, App Store polish, replacing `briefctl`.
- Existing surface: Dock `WindowGroup` + `NavigationSplitView` + fat `BriefStore`.

## Explicit non-users and non-goals

Not primarily for:

- iOS / multi-platform productization
- Replacing Python `briefctl` / SQLite ledger with an in-app database
- Rewriting all three lenses in one week to “done”
- Chasing every new low-star design system (ThemeKit / PrettyUI / IronUI)

## Direction variants (diverged)

1. **Invert**: Keep `BriefStore`, only restyle with Luminare — pretty shell, same chaos.
2. **Drop constraint**: Full TCA rewrite of all lenses before any polish — long dark week.
3. **Swap user**: Build a settings-first “framework demo” — fails “自己用”.
4. **Merge**: Shell tokens + TCA only on Work; Agent/Brief stay store until patterns proven.
5. **10x simplify**: One window, one lens (Work), hide Agent/Brief behind menu until later.
6. **Expert**: TCA + Luminare + NavigationStack domains per lens + shared `AppFeature`.
7. **Anti-framework**: Hand-rolled `@Observable` + custom glass chrome, no SPM deps.
8. **Backend-first**: Freeze UI; harden briefctl APIs for cleaner client — delays the felt win.

## Converged directions (2–3)

### A. Shell-first, store later

- **Value**: Instant “feels like a real Mac app”.
- **Feasibility**: High in a week.
- **Diff**: Looks new; `BriefStore` still accidental.
- **Hidden assumption**: Visual debt was the main pain (user said architecture too).

### B. TCA-first on Work, shell thin

- **Value**: Date select / status / capture become predictable.
- **Feasibility**: Medium; TCA learning + migration cost.
- **Diff**: Internals clean; may still look like today’s UI.
- **Hidden assumption**: User will tolerate “same face, better bones” for a week.

### C. Work vertical slice = Luminare shell + TCA Work feature (recommended)

- **Value**: One screen proves both bets; daily path (台账) gets both wins.
- **Feasibility**: Fits one week if Agent/Brief stay on adapters behind the same shell chrome.
- **Diff**: Relative to today: Work is the new product; other lenses keep working but not yet TCA-pure.
- **Hidden assumption**: Shared shell chrome can wrap old Agent/Brief views without a full rewrite in week 1.

## Recommendation

**Direction C.**

Ship week-1 MVP as:

1. App chrome in Luminare (or Luminare-aligned) style: sidebar, window materials, Work as home.
2. TCA `WorkFeature` owns: selected day, heatmap counts cache, capture, status, projection refresh.
3. Agent + 晨报 remain reachable in the shell but **not** fully TCA-migrated until loops 2–3.

Roadmap after dogfood: Agent apply/confirm → Brief reading/refresh.

## Assumptions to validate

| # | Assumption | How to check |
|---|------------|--------------|
| 1 | Luminare SPM fits `swiftc`/scripts build (or we vendor a thin chrome) | Landscape + spike note in step 2/4 |
| 2 | TCA can wrap existing `BriefctlRunner` without rewriting Python | Prototype boundary in step 4 |
| 3 | User can live with Agent/Brief “旧内脏、新外壳” for one week | Explicit approval |
| 4 | Work lens alone is enough daily value to justify the refactor week | Dogfood scripts later |

## Open question for step-1 close

User priority order confirmed: 台账 → Agent → 晨报.  
Awaiting approval of **Direction C** and permission to enter step 2 (landscape).
