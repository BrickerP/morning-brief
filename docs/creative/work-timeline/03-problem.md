# Loop 3 — Work ledger timeline — Problem

## Status

- Creative Builder step: 3 / Design Thinking
- Status: Approved; prototype authorized
- Date: 2026-07-27

## Look inward

Assumptions we were stuck on:

- Status sections (进行中 / 待处理 / 今日完成…) are the right primary scan.
- Event trail in detail is “enough history.”
- Some fields can be display-only forever (or only editable via buried menus).

These bind us to a **checkbox board** mental model. Long-running work needs a
**time narrative** you can re-enter and correct.

## Look outward

| Who | When it hurts | Who benefits from status quo |
|-----|---------------|------------------------------|
| Solo operator with multi-day Todos + agent notes | Returning after hours/days: “how long has this been open / what moved today?” | Nobody usefully—status buckets look tidy while the story stays buried |

## Problem statement

When I use Morning Brief’s work lens for work that spans hours or days, I cannot
quickly see what moved across tasks today or how long a given item has been
alive, and several pieces of content I can see are awkward or impossible to
correct in place—so I fall back to memory, chat logs, or re-asking the agent.

## How Might We

How might we make today’s work a **mixed chronological river** and each task a
**trail with wall-clock age**, where every shown content field (title, detail,
status, node text) is editable end-to-end—without becoming a PM tool or calendar?

## JTBD

| Job type | Job |
|----------|-----|
| Functional | Scan what changed today; open one task’s story; fix wrong text/status/nodes |
| Social | (weak) Answer “what’s going on with X?” from the trail |
| Emotional | Feel in control of long-running work; not afraid to leave a note wrong |

**Top pains**

1. Status list hides cross-task day narrative  
2. Duration / age invisible  
3. Seen content not always editable in place  

**Expected gain:** Re-enter any active item in ≤10s with correct story + edits.

## Proto-persona (待验证)

- **Who:** Same Morning Brief solo operator  
- **Scene:** Menu bar → 工作台账 between meetings / end of day  
- **Trigger:** Multi-day item + several agent notes; need to correct a note or see today’s motion  
- **Current workaround:** Drill into detail event list; `briefctl` CLI; re-analyze sessions  
- **Success moment:** Day river shows today’s nodes; task shows “已持续 N”; tap title/note to fix  

## Success metrics (self-testable)

1. Work overview primary scroll is a **time-ordered mixed river** for the viewed day (not only status sections).
2. Each active/terminal task exposes **wall-clock duration** (created → now / terminal) as **read-only chrome**.
3. From UI, user can edit **title, detail, status, and node/progress body text** whenever those are shown (today, non-read-only day).
4. Relative time / duration strings are **not** editable controls.
5. Mutations remain append-only; undo still works for reversible edits.
6. Quick capture still works from the overview.

## Non-goals

- Gantt / roadmap / active-time stopwatch  
- Editing absolute event timestamps as v1 requirement  
- Typed milestone taxonomy  
- Calendar timeboxing  
- Changing Agent lens session-scan (separate loop)

## Implications (not UI yet)

- Projection may need a day-ordered `timeline` / flat event list for the river  
- Progress edit mutation if missing today  
- Swift work lens: river hero; status buckets demoted or filter-only  
