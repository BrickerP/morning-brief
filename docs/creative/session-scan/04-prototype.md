# Loop 2 — Session scan readability — Prototype

## Status

- Creative Builder step: 4 / Wireframe & Prototype
- Status: Approved; MVP implemented (tail-v1)
- Date: 2026-07-27
- Problem approved: list answers “latest stretch,” not whole-session essay

## One core journey (only)

```text
Open Agent lens
  → see newest-first sessions (≤15)
  → each row: short tail-weighted summary (or “生成中 / 最后一句用户话” fallback)
  → tap one row
  → existing full analyze → Todo review (unchanged)
```

No new screens. No rename UI. No timeline ledger in this loop.

## States (3–5)

1. **Cold / summarizing** — some rows `正在生成摘要…` + small progress cue
2. **Ready** — all visible rows show 1–2 line Chinese blurb from last ~8 turns
3. **Agent failed for a row** — show truncated **last user turn** (not first-prompt preview)
4. **Tap** — same as today: analyzing notice → analysis view

## ASCII — Agent lens list (primary)

```text
┌─ Morning Brief · Agent ─────────────────────────┐
│ Claude Session → Todo                           │
│ 从下方选一条…点选后才会通读并匹配 Todo。          │
│                                                 │
│ 最近会话  15              ◐ 生成摘要 (optional) │
│ ┌─────────────────────────────────────────────┐ │
│ │ ❝ 支付回调：对齐幂等键，待生产回归一次。      │ │
│ │   morning-brief · 2 subagent · 12 分钟前     │ │
│ └─────────────────────────────────────────────┘ │
│ ┌─────────────────────────────────────────────┐ │
│ │ ❝ ultragoal G004 质量门已过，等推远端。       │ │
│ │   morning-brief · 1 小时前                   │ │
│ └─────────────────────────────────────────────┘ │
│ ┌─────────────────────────────────────────────┐ │
│ │ 正在生成摘要…                                │ │
│ │   other-repo · 昨天                          │ │
│ └─────────────────────────────────────────────┘ │
│ ┌─────────────────────────────────────────────┐ │
│ │ 把 doctor 超时改成可取消…   ← failed fallback│ │
│ │   scripts · 2 天前                           │ │
│ └─────────────────────────────────────────────┘ │
│ 点选即通读分析。摘要按指纹缓存…                  │
│ ─────────────────────────────────────────────── │
│ [粘贴 session 结尾…]                            │
└─────────────────────────────────────────────────┘
```

**Row anatomy**

| Zone | Content | Rules |
|------|---------|--------|
| Primary | Tail summary | 1–2 short CN sentences; prefer ≤80 chars; max 3 lines in UI |
| Secondary | project tail · subagents · relative time | Unchanged |
| Icon | quote when ready; clock when pending | Light signal only — no badges/stickers |

## Copy brief (list summarizer)

Agent sees **only** last ~8 dialogue turns (+ note that earlier context was omitted).

Return JSON:

```json
{
  "summary": "一句或两句中文：最近在做什么 + 现状/下一步（不要开场回顾）"
}
```

Hard instructions: no multi-paragraph; no tool-call dumps; weight the ending; if the tail is noise, say the latest concrete user ask.

## Design brief (visual — stay in existing system)

| Slot | Choice |
|------|--------|
| Subject | Local operator scanning Claude sessions in a macOS menu-bar panel |
| Audience | Solo; dense, quiet |
| Page’s one job | **Recognize and pick a session** |
| Color | Keep Morning Brief tokens (`DS.Palette`, secondary/tertiary text) — no new theme |
| Type | Existing callout + caption2 hierarchy; primary line is the summary |
| Signature element | **Quote-forward row** (`text.quote` + tight 1–2 line blurb) — recognition by words, not chrome |

**Anti-slop:** no purple gradient, no cream editorial, no newspaper columns, no pill clusters, no floating badges on rows.

## Data / cache contract (for later MVP — not implementing yet)

- Extract last ~8 user/assistant turns from parent JSONL (and trailing subagent only if needed for tail coherence — default: parent tail first)
- Persist summary with `fingerprint` **and** `recipe_version` (e.g. `tail-v1`) so old whole-session caches invalidate once
- List sort: mtime descending (keep)

## Explicitly out of wireframe

- Work ledger timeline
- Manual rename
- Diff-since-last-visit
- Structured topic / last-act / open-thread fields
