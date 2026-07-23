# Morning Brief Todo — Brainstorm

## Status

- Creative Builder step: 1 / Brainstorm
- Status: Approved by user; landscape research authorized
- Date: 2026-07-23

## Idea in one sentence

Turn Morning Brief into an agent-native daily work ledger where the user and a
local agent can capture work throughout the day, update status, append progress
notes, and review what was completed recently.

Confidence: **96%**

## How Might We

How might we let a user and their local agent continuously maintain today's work
record—from a meeting or new requirement through progress notes to completion—
without turning Morning Brief into a heavyweight project-management product?

## What we heard

- Work arrives throughout the day through meetings and requirement discussions.
- A work item moves through `待处理 → 进行中 → 已完成`, with `取消` as a terminal alternative.
- An in-progress item may accumulate intermediate notes, blockers, decisions, and
  next steps.
- Completed items must remain available as a recent historical archive.
- The local agent must be able to create, edit, annotate, and change status.
- The agent may fetch information from other APIs and use it to update local work
  records.
- There is no fixed source-of-truth hierarchy. Human input, external APIs, and
  existing local state are evidence; the user's agent has final authority to
  decide the resulting local state.

## Explicit non-users and non-goals

This is not primarily for:

- teams coordinating shared work;
- managers assigning work to other people;
- multi-user permissions and approval workflows;
- full project planning, sprint management, or dependency graphs;
- replacing a calendar, issue tracker, or enterprise task system;
- building a universal bidirectional API-sync platform in the first version.

## Divergent variants

1. **Daily checklist** — capture short tasks and mark them done.
2. **Status-based work list** — pending, in progress, completed, or cancelled.
3. **Meeting inbox** — capture first, let the agent organize and enrich later.
4. **Daily work timeline** — emphasize chronological notes, decisions, and state
   transitions.
5. **Mini Kanban** — display the four states as compact columns or groups.
6. **Rollover ledger** — preserve completed work by day and carry unfinished work
   forward.
7. **Agent-operated ledger** — expose stable local operations so an agent can
   reconcile API evidence and maintain the record.
8. **Brief-to-action bridge** — turn a brief item, meeting note, or external event
   into a work item.

## Converged directions

| Direction | User value | Feasibility | Difference | Hidden assumption |
| --- | --- | --- | --- | --- |
| Daily work ledger | Captures what to do, what is happening, and what was completed | High | Daily archive plus lightweight progress history | One day's work is the useful primary view |
| Meeting inbox with agent triage | Fastest possible capture during meetings | High | Agent can structure rough input after capture | The agent can infer intent reliably enough |
| Mini Kanban | Strongest visual status model | Medium | Familiar status movement | A menu-bar panel has enough space and Kanban is not excessive |

## Recommended direction

Build a **local-first, agent-operated daily work ledger**, borrowing fast capture
from the meeting-inbox direction.

The core product object is not a checkbox. It is a work item with:

- a current lifecycle state;
- a short title and optional detail;
- an appendable progress history;
- timestamps for creation, updates, completion, and cancellation;
- recent daily archive visibility;
- provenance/evidence references without a fixed authority hierarchy;
- stable agent operations for create, edit, annotate, transition, and query.

The agent is the final decision-maker for local state. The product should make
the agent's changes observable and reversible rather than trying to encode a
permanent source-of-truth priority.

## One-week scope guard

The first vertical slice should prove:

1. fast human capture;
2. four-state lifecycle;
3. progress-note history;
4. recent completed-work archive;
5. safe local agent operations;
6. one representative external-information ingestion path.

Arbitrary API connectors, background polling, conflict engines, multi-device
sync, reminders, priorities, and project hierarchies are deferred.

## Assumptions to validate

- The menu-bar panel remains the primary human interaction surface.
- A daily view plus a short recent-history view is sufficient for personal use.
- The agent can make autonomous state decisions, but every mutation should remain
  inspectable and reversible.
- External API data is evidence used by the agent, not a separate synchronized
  database that must be mirrored exactly.
- One representative integration is enough to validate the agent workflow in the
  MVP.

## Step 1 recommendation

Proceed to landscape research with the positioning:

> A menu-bar daily work ledger maintained jointly by the user and their local
> agent, with lightweight progress history and recent completion recall.
