# Morning Brief Todo — Problem Definition

## Status

- Creative Builder step: 3 / Design Thinking
- Status: Approved by user; prototype design authorized
- Date: 2026-07-23

## Problem statement

A solo knowledge worker receives new commitments continuously through meetings,
requirement discussions, local agents, and external systems. The work is easy to
capture incompletely and hard to reconstruct later: current status becomes stale,
intermediate decisions disappear, and completed work is scattered or forgotten.

They need a low-friction daily working record that both they and their agent can
maintain throughout the day, so they can understand what is pending, what is in
progress, why it changed, and what was completed without rebuilding context from
chat logs, meeting notes, and multiple APIs.

This statement deliberately does not prescribe a menu, database, CLI, MCP server,
or synchronization architecture.

## How Might We

How might we help a user and their local agent continuously turn incoming work
signals into an understandable daily record—preserving status, intermediate
context, and completed history—without requiring the user to become a project
manager?

## Look inward: assumptions we are making

1. **A task is not just a checkbox.** Meaningful work needs state and a sequence
   of progress, decision, blocker, and completion events.
2. **The day is a useful primary lens.** The user primarily asks what is active
   today and what was recently completed, even when an item spans several days.
3. **The agent may exercise judgment.** Human input, API data, meeting content,
   and prior local state are evidence. The user delegates the final update
   decision to their agent.
4. **Autonomy does not remove accountability.** The agent's mutation should be
   visible, attributable, explainable, and reversible.
5. **Capture happens under uncertainty.** A rough sentence from a meeting is
   valid input; required structure can be added later.
6. **Recent recall matters more than permanent project taxonomy.** The first
   version benefits more from accurate daily history than projects, labels,
   priorities, deadlines, or dependencies.
7. **One real external workflow is enough to test the model.** A universal
   connector system is not necessary to validate the core problem.

## Look outward

### Who feels the pain

- A solo builder or technical/product owner whose day is interrupted by meetings,
  requirement changes, and follow-up requests.
- The same person later answering progress questions, writing updates, or
  resuming work after context switches.
- Their local agent, which can retrieve useful external information but lacks one
  safe, structured place to apply its conclusions.

### When the pain is strongest

- During a meeting, when a commitment appears faster than it can be organized.
- Immediately after a meeting, when decisions and owners are still ambiguous.
- During execution, when a task is neither untouched nor complete and needs a
  blocker, result, or next step recorded.
- At the end of the day, when the user tries to remember what actually moved.
- Several days later, when the user or agent needs the reason behind a status
  change or completion.

### Who benefits from the current workaround

Separate meeting, task, chat, and API tools each remain internally simple because
the user performs the reconciliation. The user pays the integration cost through
memory, duplicate entry, and repeated context reconstruction.

## Jobs to Be Done

### Functional jobs

1. When a new commitment appears, capture it before switching context.
2. When work begins, make its active state and current focus visible.
3. While work is progressing, append decisions, blockers, evidence, and next
   steps without replacing earlier context.
4. When new API or meeting information appears, let the agent decide whether to
   create, enrich, transition, cancel, or leave an item unchanged.
5. When work ends, record completion or cancellation while preserving its history.
6. When asked about today or recent days, retrieve both current work and completed
   outcomes without searching several systems.

### Emotional jobs

- Stop holding fragile commitments in working memory.
- Trust that completed work will not disappear.
- Feel comfortable delegating routine maintenance to the agent.
- Avoid the anxiety of an invisible or stale work state.
- Preserve a sense of progress without performing a separate reporting ritual.

### Social jobs

- Answer “what changed?”, “what is blocked?”, and “what did you finish?” accurately
  in a follow-up meeting.
- Produce a concise daily or recent progress summary without reconstructing it
  manually.
- Show the reasoning or evidence behind an agent-applied update when challenged.

## Top pains

1. **Capture friction:** opening and structuring a full task tool during a meeting
   is slower than the work arrives.
2. **State decay:** a title and checkbox cannot explain partial progress,
   blockers, or changed understanding.
3. **Completion amnesia:** completed work becomes hidden or scattered, so
   retrospective reporting is unreliable.
4. **Agent mutation risk:** direct file edits or opaque synchronization can lose,
   duplicate, or silently rewrite work history.
5. **Reconciliation overhead:** the user repeatedly decides which meeting note,
   API result, chat statement, or old task status to trust.

## Expected gains

- One glance answers what is pending, active, and completed today.
- New work can be recorded before meeting context is lost.
- Intermediate progress remains appendable and chronological.
- The agent can autonomously maintain the record using bounded operations.
- Every change can be inspected and, when needed, reversed.
- Recent accomplishments can be recalled without a separate end-of-day report.

## Proto-persona

### Yupeng, solo technical/product builder

Status: **Hypothesis persona; to be validated through dogfooding**

- **Context:** Works on macOS across engineering, product requirements, local
  agents, meetings, and several internal or external APIs.
- **Trigger:** A meeting creates a new request; a requirement changes; an API
  reports new information; or an agent discovers progress that should be recorded.
- **Current workaround:** Hold some work in memory, leave traces in chats or
  meeting notes, query external systems again, and reconstruct the day's progress
  when needed.
- **Desired behavior:** Capture roughly, let the agent refine and maintain state,
  add process information during execution, and review today plus recent
  completions from one calm surface.
- **Success moment:** Asking “What am I doing, what is blocked, and what did I
  finish in the last few days?” produces an accurate answer whose underlying
  changes and evidence can be inspected.

## Product principles implied by the problem

1. **Capture before classification.**
2. **Current state and history are both first-class.**
3. **Progress is appended rather than overwritten.**
4. **Agent judgment is permitted; silent mutation is not.**
5. **Daily and recent-history views are projections of work history, not isolated
   copies that drift apart.**
6. **Cancellation is a meaningful terminal outcome, not deletion.**
7. **External data remains evidence, not an automatically dominant authority.**

## Observable success signals

The problem is considered meaningfully solved when dogfooding shows:

1. **Fast capture:** Real meeting or requirement work can be recorded before the
   user switches context, without filling a structured form.
2. **Current clarity:** Opening the product is enough to identify pending,
   in-progress, completed, and cancelled work for today.
3. **Progress continuity:** At least one multi-step work item accumulates useful
   intermediate notes across several updates without losing prior context.
4. **Agent utility:** The local agent creates or updates real work items from one
   external-information workflow without direct data-file editing.
5. **Recent recall:** The user can accurately answer what was completed during a
   recent date range from the stored history.
6. **Trust:** Every agent mutation exposes when it happened, what changed, and why;
   a mistaken mutation can be reversed.
7. **No reporting tax:** The completion archive is useful enough to draft a daily
   progress summary without separately recreating the day.

## MVP validation targets

During a seven-day self-use trial:

- capture at least 10 real work items;
- include at least 3 items created or materially updated by the local agent;
- maintain progress history on at least 3 in-progress items;
- complete or cancel at least 5 items and retrieve them later by date;
- exercise one external-information ingestion flow;
- perform one intentional undo/recovery test;
- observe zero silently lost or duplicated items.

These are validation targets, not permanent product analytics.

## Explicit non-goals

- Team assignment, collaboration, permissions, and shared workflows.
- Project portfolio management, sprint planning, or dependency graphs.
- Calendar scheduling, time estimates, reminders, and time tracking.
- Arbitrary connector installation and bidirectional background synchronization.
- A general knowledge base or full meeting transcription product.
- Automatic invention of owners, deadlines, results, or evidence.

## Step 3 recommendation

Proceed to one core journey:

> A work request arrives during a meeting, is captured immediately, enriched and
> moved into progress by the agent, receives intermediate updates, is completed,
> and later appears in recent history with its full reasoning trail.
