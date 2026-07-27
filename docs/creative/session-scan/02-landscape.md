# Loop 2 — Session scan readability — Landscape

## Status

- Creative Builder step: 2 / Search and Trending
- Status: Confirmed worth doing; problem framing authorized
- Date: 2026-07-27
- Locked from step 1: Direction A — last ~8 turns tail window → concise Chinese summary

## One-sentence positioning

> A menu-bar session picker that names each Claude session by **what just happened**,
> not by the opening prompt of a multi-hour transcript.

Relative to Claude’s own resume picker and chat-sidebar auto-titles: we keep
Morning Brief’s “pick → analyze → Todo” job, but fix the list copy so huge
sessions stay recognizable.

## Landscape

| Name | Solves | Pain for us | Borrow | We don’t build |
|------|--------|-------------|---------|----------------|
| **Claude Code `/resume` picker** | Newest-first session list; name / AI title / summary / first prompt + relative time | Official row still often falls back to early title/first prompt; not wired into our Todo flow | Newest-by-activity sort; short row + meta (project, time); optional rename later | Full TUI picker, branch filters, resume-into-Claude |
| **cc-session-resumer** | Cross-project list; preview shows **last N user prompts** | Separate tool; resume-focused, not Todo bridge | **Last-N prompts as recognition signal** (exactly our tail bias) | Token stats pane, crash badges, multi-launch TUI |
| **cch / claude-code-history** | List with summaries + open full transcript | History browser, not a daily-work bridge | Subagent awareness; newest-first list | Full transcript viewer / search / export product |
| **ChatGPT / Studio-style auto-title** | Sidebar titles from **first exchange** | First-exchange titles go stale as the session pivots — our exact failure mode | Short, scannable title; silent fallback to truncated user text | One-shot title that never updates when work continues |
| **Manual rename / notes** (non-software) | User writes a sticky name | Friction; won’t happen for 15 sessions | Allow future manual override | Mandatory naming ritual |

## Trends that matter

1. **Session pickers sort by last activity** — we must not regress this.
2. Industry auto-title mostly uses **first** exchange → great for new chats, **bad for long coding sessions that change topic**.
3. Power-user Claude tools already surface **last N prompts** in previews — validates tail-window over whole-transcript essays.

## Steal / avoid

**Steal**

- Newest-first by mtime / last activity
- Tail signal (last prompts), not opener
- Hard length: 1–2 short lines / ~40–80 Chinese chars
- Fallback: truncated last user line when agent fails

**Avoid**

- Whole-transcript “meeting minutes” for the list row
- Multi-field dashboard cards in MenuBarExtra
- Re-calling agent on every Agent-lens open (keep fingerprint cache; bump version when window/prompt changes)
- Building a second Claude history browser

## Worth-doing check

Current Morning Brief already has agent summarize + cache, but the prompt still
asks for a whole-session digest and feeds the full transcript — so large sessions
stay unreadable. Tail-first is a **tight fix** on an existing path, not a new product.
