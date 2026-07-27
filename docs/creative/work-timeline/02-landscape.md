# Loop 3 — Work ledger timeline — Landscape

## Status

- Creative Builder step: 2 / Search and Trending
- Status: Confirmed worth doing; problem framing authorized
- Date: 2026-07-27
- Locked from step 1: day mixed river + task trail; wall-clock duration (decorative);
  content editable (title/detail/status/node text); append-only ledger

## One-sentence positioning

> A menu-bar **ops journal for today’s work**: a mixed day river of human/agent
> nodes, each task’s trail + how long it’s been alive—editable content, not a
> roadmap or life diary.

## Landscape

| Name | Solves | Pain for us | Borrow | We don’t build |
|------|--------|-------------|---------|----------------|
| **Linear issue activity / Updates** | Chronological issue history; project Activity page; collapsed noisy history; time-in-status | Team PM surface; Gantt/roadmap; discussion summaries as product | Mixed activity stream; collapse chrome; duration as **hover/decoration** not the edit target | Initiatives, swimlanes, multiplayer comments |
| **Things 3 Logbook** | Completed/cancelled archive by day | Terminal archive only—weak for *in-progress* long tasks; little node narrative | Quiet completion memory; Today as return point | GTD Areas/Projects, scheduling taxonomy |
| **Taskwarrior annotations + start/stop** | Append notes on a task; CLI history; DIY day journal via reports | CLI friction; active-time tracking temptation | Append-only annotations = our progress nodes; task-owned trail | Urgency engine, full report language, kanban tags |
| **Day One / Journey** | Day-ordered personal journal | Life log, not work ledger; no status/agent mutations | **Day as river** mental model; scannable entries | Photos, prompts, encrypted lifelog product |
| **Markdown daily note** (workaround) | Freeform day log + checkboxes | No structured status, weak agent write contract, easy to drift | Zero ceremony capture | Becoming “just another daily note” |

## Trends

1. Issue trackers push **activity feeds** + collapse noise (Linear).
2. “Time in status” is analytics for teams—we only need **wall-clock age** as chrome.
3. Power users still glue **task + annotations + day journal**—Morning Brief can be that glue in one panel.

## Steal / avoid

**Steal**

- Day river of mutations (journal) with task chips
- Task detail = editable content + chronological nodes
- Duration / relative time as decoration
- Collapse pure system noise if the river gets loud

**Avoid**

- Roadmap / Gantt / milestone % complete
- Active-time stopwatch product
- Making derived duration a fake text field
- Replacing append-only with editable SQL history

## Worth-doing check

Current work lens is **status-section first**; long tasks hide their story behind
detail drills. User already has the event rail in data—UI just doesn’t lead with
the day river or duration. This is a **presentation + edit-affordance** knife on
existing ledger law, not a new database product—still a real week of Swift UI +
a few mutation gaps (e.g. edit progress text if missing).
