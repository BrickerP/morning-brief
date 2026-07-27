# Loop 2 — Session scan — MVP Prompt (Scope Cop revised)

## Status

- Creative Builder step: 5 / MVP
- Date: 2026-07-27
- Prototype approved; implementation authorized

## One-line problem

List rows must identify the **latest stretch** of a Claude session, not the opening.

## MVP goal

Tail-first summarize (last ~8 dialogue turns) → 1–2 sentence Chinese blurb, cached
with recipe version; newest-first list; fallback = last user turn.

## Non-goals

- Work-ledger timeline
- Manual rename UI
- Full transcript browser
- Changing Todo analyze prompt
- Structured multi-field cards

## Keep / Cut / Defer

| Item | Verdict |
|------|---------|
| Extract last ~8 turns before agent | **Keep** |
| Prompt: recent stretch + concise | **Keep** |
| `recipe_version` in cache (invalidate old) | **Keep** |
| Fallback last user message | **Keep** |
| Newest-first sort | **Keep** (already) |
| Subagent full feed into list summarize | **Cut** (parent tail only for v1) |
| Force-refresh button | **Defer** |
| Manual rename | **Defer** |
| Timeline ledger | **Defer** (next loop) |

## Acceptance

- [x] Summarize agent receives truncated tail context, not full transcript
- [x] Prompt forbids opener-style whole-session essays
- [x] Cache miss when `recipe_version` differs (old caches invalidated)
- [x] `list_recent_sessions` fallback preview prefers last user turn when summary missing/failed
- [x] Tests cover tail extract + cache recipe bump + no second agent call on hit
- [x] App typecheck / tests green (93 passed)

## Risk

- Tail-only may miss topic if last 8 turns are pure tool noise → prompt says use latest concrete user ask; fallback helps.
