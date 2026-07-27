# Loop 2 — Session scan readability — Problem

## Status

- Creative Builder step: 3 / Design Thinking
- Status: Approved; prototype authorized
- Date: 2026-07-27

## Look inward

Assumptions we were stuck on:

- “2–4 sentence whole-session summary” is enough for a list row.
- Feeding the full transcript (main + subagents) improves recognition.
- Early `preview` / first-user text is a harmless fallback.

These bind us to a **meeting-minutes** mental model. The real job of the list is
**re-identification of the latest stretch**, not archival completeness.

## Look outward

| Who | When it hurts | Who benefits from status quo |
|-----|---------------|------------------------------|
| Solo operator (you) using Morning Brief Agent lens after many long Claude sessions | Opening Agent lens to pick “which session was the payment / ultragoal / bugfix one” | Nobody usefully — maybe an archivist who wants whole-session essays; that is not this surface |

Pain moment: 15 rows of similar-looking prose that still sound like the *start*
of the day, while the work that matters is in the last hour.

## Problem statement

When I return to Morning Brief’s Agent lens after several long Claude sessions,
I cannot quickly tell which row matches the work I just did, because list copy
summarizes (or previews) the session as a whole—or its beginning—instead of the
recent dialogue that actually distinguishes it.

## How Might We (actionable)

How might we present each recent session so that a glance at the newest-first
list answers “what was the latest stretch about?” in one short Chinese blurb?

## JTBD

| Job type | Job |
|----------|-----|
| Functional | Scan ~15 recent sessions and pick the right one to run Todo analysis |
| Social | (weak) Not relevant — solo tool |
| Emotional | Feel oriented, not lost in UUID / early-prompt noise |

**Top pain:** Large sessions produce unrecognizable or opener-heavy summaries.

**Expected gain:** Spot the right session in ≤3 seconds without opening it.

## Proto-persona (待验证)

- **Who:** Same Morning Brief operator; heavy Claude Code / Cursor day.
- **Scene:** Menu bar → Agent lens between tasks or after lunch.
- **Trigger:** Need to attach a session’s outcome to today’s Todo.
- **Current workaround:** Open several sessions / scroll raw JSONL / rely on project path + time and guess.
- **Success moment:** The correct row’s 1–2 lines match “what I was just doing,” and a click starts analysis.

## Success metrics (self-testable)

1. List remains **newest-first** by session mtime.
2. For a session with a clear mid-day topic change, the list blurb reflects the
   **later** topic, not the opening ask (spot-check 3 real sessions).
3. Summary length: roughly **1–2 short Chinese sentences** (soft cap ~80 chars
   preferred; hard refuse multi-paragraph).
4. Agent is **not** re-invoked on reopen when fingerprint + summary recipe version match.
5. Agent failure still shows a scannable fallback from the **last user turn**, not the first.

## Non-goals (this loop)

- Work-ledger timeline / duration / richer edit (next knife)
- Full transcript browser
- Manual rename UI (defer unless trivial)
- Changing the click-through full Todo analyze prompt (separate path)

## Implications for solution (not UI yet)

- Extract last ~8 dialogue turns before summarize
- Prompt: recent stretch only + hard concise
- Cache key must include recipe/window version so old whole-session caches invalidate once
