# Loop 3 — Work ledger timeline — Brainstorm

## Status

- Creative Builder step: 1 / Brainstorm
- Status: Approved; landscape authorized
- [x] User verbal OK → step 2 landscape
- Date: 2026-07-27
- Seeded from: `docs/creative/session-scan/07-next-loop.md`

## Idea in one sentence

Replace the work-lens status buckets as the primary mental model with a **day river
of mixed nodes** plus a **per-task timeline** (duration + editable nodes), so
long-running work stays re-enterable without becoming a PM tool.

Confidence: **84%**

## How Might We

How might we make multi-day and in-progress work easy to re-enter by seeing
**duration + what happened along the way**, in both a day-level mixed stream and
a task-owned trail, without turning Morning Brief into a project manager or calendar?

## What we heard

- Need timeline + node records (not only status sections)
- Show each task’s duration
- Expand editable capabilities → **principle: any dynamic content shown in UI should be editable end-to-end**
- **Both** task-internal timeline **and** day-level mixed river (用户确认「两者都要，混排」)

## Explicit non-users / non-goals (this loop)

Not for: teams, Gantt planning, calendar timeboxing, multi-project portfolio.

Will not (unless later approved): Kanban boards, dependency graphs, hard SQL purge,
replacing append-only event law, full rich-text editor.

## Variant divergence

| # | Variant | Note |
|---|---------|------|
| 1 | Day river only (mixed nodes) | Fast scan; weak per-task continuity |
| 2 | Task trail only (detail) | Good for one item; loses “what moved today” |
| 3 | **Both: day river + task trail** (chosen) | Matches ask; scope risk |
| 4 | Gantt / bar duration chart | Visual duration; calendar smell; MenuBarExtra cramped |
| 5 | Status buckets + duration badge only | Minimal; not really a timeline |
| 6 | Invert: hide active list, only river | May lose capture affordances |
| 7 | 10x: river of *today’s mutations only* + tap → task trail | Vertical slice for week |
| 8 | Expert: “ops journal” — time-ordered evidence with task chips | Close to mixed river |

## Directions (converged)

### A — Dual surface, one data model (recommended)

- **Day lens:** chronological **mixed node river** for the viewed day (all tasks’ events interleaved; chip/link to task)
- **Task lens:** same nodes filtered to one item + **duration** readout + edit/add node
- **User value:** “what moved today” + “this long-running thing’s story”
- **Feasibility:** High if nodes = existing ledger events (+ light presentation)
- **Diff:** Status sections demoted or secondary; narrative first
- **Hidden assumption:** Existing `progress_added` / status / edit events are enough “nodes” for v1

### B — New first-class Node type (blocker / decision / milestone)

- Richer semantics than free-text progress
- Heavier schema + agent skill + UI; week risk

### C — Duration-first overview (bars) + optional trails

- Answers “how long” loudly; weak on “what happened”; calendar vibe in 440px panel

## Recommendation

**Direction A**, with week-sized vertical slice from variant 7:

1. Ship **today’s mixed mutation river** as primary overview (keep quick capture)
2. Row/chip → **task trail** with duration + edit existing progress / append node
3. Keep status filters as a thin secondary, not the hero

Park B’s typed node taxonomy and C’s Gantt for later.

## Locked decisions

1. Surfaces: **day mixed river + per-task trail**
2. Duration: **wall clock** from `created_at` → now (active) or → terminal time (completed/cancelled)
3. Edit principle: **内容可编辑，推算只读** — title / detail / status / node body text are editable end-to-end when shown; **derived** displays (wall-clock duration, relative “12 分钟前”) are decorative chrome only.
4. Ledger law unchanged: edits go through append-only mutations (no silent SQL rewrite of history).

## Editable vs chrome (locked)

| Shown | Editable? |
|-------|-----------|
| Title, detail, status | Yes |
| Node / progress / note body text | Yes |
| Reason/evidence if shown as content | Yes (if displayed) |
| Wall-clock duration, relative time | **No** — decoration |
| Section labels, icons | No — chrome |

## Recommendation (final for step 1)

**Direction A** with week slice:

- Primary overview: **today’s mixed node river** + quick capture
- Tap task chip/row → **task trail** with duration (read-only) + full content editing
- Status buckets demoted to thin secondary (or filters), not the hero

## Checklist

- [x] Not-for-whom written
- [x] Recommended direction + rationale
- [x] User verbal OK → step 2 landscape

## Parked

- Typed milestone taxonomy
- Calendar / timeboxing / active-time duration
- Editing absolute event timestamps
- Session-scan further polish (unless P0)
