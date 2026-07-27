# Loop 2 — Session scan readability — Brainstorm

## Status

- Creative Builder step: 1 / Brainstorm
- Status: Approved (Direction A, ~8-turn tail); landscape done
- Date: 2026-07-27
- Priority confirmed: **session summary first**; work-ledger timeline deferred to next knife
- Tail window locked: **last ~8 dialogue turns** (user/assistant pair counts as a turn)

## Idea in one sentence

Make the Agent lens recent-session list scannable: newest-first, with a concise
Chinese summary weighted to the **last few turns**, so huge sessions stay
recognizable without dumping early context.

Confidence: **82%**

## How Might We

How might we let the user glance at ~15 recent Claude sessions and instantly
recognize what the *latest stretch* of each session was about—especially when
transcripts are enormous?

## What we heard

- Current list summaries are still unreadable for large sessions.
- Need newest-time ordering (already intended; must verify in product).
- Weight summary toward the **last few rounds** of dialogue, not whole-session digest.
- Timeline work ledger (duration, nodes, richer edit) is wanted but **second**.

## Explicit non-users and non-goals (this loop)

Not for:

- Team shared session browsers
- Full transcript viewer / search product
- Replacing the click-through full Todo analysis pass

This loop will not:

- Redesign the work ledger into a timeline (parked)
- Re-summarize every open when fingerprint unchanged (keep cache)
- Feed the entire mega-transcript as equal weight to the summarizer

## Variant divergence (then fold)

| # | Variant | Note |
|---|---------|------|
| 1 | Tail-window extract → short agent summary | Give agent only last N user/assistant turns |
| 2 | Prompt-only “prefer ending” on full transcript | Cheap change; huge sessions still drown the model |
| 3 | Two-line card: title (tail) + one-line stale opener | More UI structure; still needs good tail text |
| 4 | Heuristic only (no agent): last user + last assistant | Fast, free; quality may be raw |
| 5 | Invert: show *diff since last visit* | Needs visit state; more product surface |
| 6 | 10x simplify: one line, ≤40 Chinese chars, force | Strong scannability constraint |
| 7 | Expert: “recency-weighted journal entry” | Matches how humans recall sessions |
| 8 | Merge with analyze summary cache | Reuse full analysis; too heavy / wrong shape for list |

## Directions (converged)

### A — Tail-first summarize (recommended)

- **User value:** List answers “what was I just doing in this session?”
- **Feasibility:** High — trim/extract last K turns before agent; keep fingerprint cache; bump cache schema when prompt/window changes
- **Diff:** Not a whole-session essay; a *recent stretch* blurb
- **Hidden assumption:** Last ~K turns contain enough signal; subagents at the end matter more than early setup

### B — Heuristic preview + optional agent polish

- **User value:** Instant list even when agent is slow/offline
- **Feasibility:** Highest for v0 slice
- **Diff:** May look “raw” again if polish deferred
- **Hidden assumption:** Last user message alone is enough to recognize

### C — Structured mini-card (topic / last act / open thread)

- **User value:** Scannable fields, not a paragraph
- **Feasibility:** Medium — needs stricter JSON schema + UI
- **Diff:** More dashboard-like; risk of clutter in MenuBarExtra
- **Hidden assumption:** Three fields beat one sentence for this density

## Recommendation

**Ship Direction A** this loop: extract a **tail window** (last N dialogue turns, optionally including trailing subagent bits), ask agent for **1–2 concise Chinese sentences** (hard length cap), persist under fingerprint (+ window version), list newest-first.

Keep Direction B as fallback when agent fails (show truncated last-user line, not early preview).

Park Direction C and the **work-ledger timeline** for the next creative loop.

## Assumptions to validate

1. Last 6–12 turns (or ~last 8–15k chars of dialogue) beat full-transcript summarize for recognition.
2. User wants **force re-summarize** only when session grows (fingerprint), not manual refresh UI in v1.
3. One short paragraph (or two short lines) beats structured multi-field cards in the menu bar.

## Parked (explicit)

- Work ledger → timeline + nodes + duration + richer edit (**next knife**)
