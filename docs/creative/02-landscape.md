# Morning Brief Todo — Landscape

## Status

- Creative Builder step: 2 / Search and Trending
- Status: Approved by user; problem definition authorized
- Research date: 2026-07-23
- Evidence policy: Current official product documentation and primary project
  sources; product recommendations are marked as inference.

## One-sentence positioning

> A menu-bar daily work ledger maintained jointly by the user and their local
> agent, with an inspectable event history, progress notes, and recent completion
> recall.

Compared with existing tools, it is lighter than a full task manager, more
structured than a daily Markdown note, and more continuous than a meeting-action
extractor.

## Product and workaround landscape

| Reference | What it solves | Pain / limitation for this use case | Interaction worth borrowing | What we should not build |
| --- | --- | --- | --- | --- |
| Things 3 | Personal capture through Inbox, a focused Today list, and permanent Logbook for completed or cancelled work | Its Areas, Projects, tags, dates, deadlines, and multiple time buckets would turn Morning Brief into a GTD product | Progressive disclosure; quick capture before organization; Today as the recurring return point; completed and cancelled work retained indefinitely; stable Shortcuts automation | Projects/Areas hierarchy, scheduling taxonomy, or making every agent update choose a date bucket |
| Apple Reminders | System-wide reminders with Today, Scheduled, Flagged, and Completed smart lists | Optimized for reminders, accounts, dates, and system sync rather than progress history or autonomous agent judgment | A small set of pinned aggregate views; Completed as a first-class destination; notes and metadata behind the compact row | A general Reminders replacement, notification engine, multi-account behavior, or provider compatibility layer |
| Todoist | Cross-project and collaborative task management with filters, integrations, and date-organized Reporting | Query syntax and project/tag/priority matrices are excessive; some reporting history depends on plan/retention | Human-readable activity history; filtering recent work by date and event type; explicit integration surface | A universal integration marketplace, complex filters, collaboration, or paywall-like history limits |
| Taskwarrior | Local CLI task lifecycle, annotations, reports, JSON import/export, and undo | CLI configuration and its broader status model are too complex for a menu-bar daily ledger | Explicit commands for state changes; append-only annotations for intermediate progress; JSON machine interface; undo/recovery; reports derived from task data | Exposing raw CLI complexity; treating cancelled as deleted; copying all native statuses and urgency logic |
| Sunsama | Guided daily review, task selection, integration import, workload review, and re-entry during the day | Strong ritual, time estimates, timeboxing, calendar dependence, and many integration surfaces | Review yesterday's unfinished work; re-enter today's planning when reality changes; treat external systems as candidate inputs | A mandatory morning ceremony, schedule optimizer, calendar planner, or multi-tool synchronization platform |
| Granola / AI meeting notes | Combines transcript, raw user notes, and calendar context; extracts action items and allows follow-up processing | Meeting-centric and often sends work into another task system; not a durable personal work ledger | Keep evidence links; show why AI produced a note; allow human edits and regeneration; reusable extraction recipes | Silently creating or overwriting tasks without inspectable evidence; storing only an AI summary |
| Daily Markdown note | Fast, local, portable, easy to inspect with Git or text tools | Concurrent agent and human edits can overwrite each other; status transitions and history are implicit strings | Always-exportable daily view; readable text snapshot; easy backup | Using Markdown as the transactional source of truth or asking agents to rewrite arbitrary list text |

## Evidence highlights

### Things: Today, Inbox, Logbook, and automation

- Things defines Today as the items the user wants to start before the day ends,
  and recommends returning to the ordered list throughout the day.
- Inbox is explicitly a staging area for rough, incomplete capture.
- Completed and cancelled items enter Logbook indefinitely.
- Shortcuts can create, find, edit, and query items, including status, completion
  date, notes, and stable IDs.

Sources:

- [Things Today, Inbox, and Logbook](https://culturedcode.com/things/support/articles/4001304/)
- [Things Shortcuts actions](https://culturedcode.com/things/support/articles/9596775/)

### Apple Reminders: small aggregate views

- Standard smart lists include Today, Scheduled, Flagged, All, and Completed.
- The Completed list is a direct aggregate of completed reminders.

Source:

- [Apple Reminders list views](https://support.apple.com/en-gb/guide/reminders/-remnd854fc47/mac)

### Todoist: activity is a product surface

- Reporting is organized by date and can be filtered by project, person, event
  type, workspace, and range.
- Its current developer surface groups APIs, SDKs, CLI, MCP, and webhooks around
  task operations, showing that agent access is becoming a first-class channel.

Sources:

- [Todoist Reporting](https://www.todoist.com/help/articles/view-reporting-in-todoist-oOra6D)
- [Todoist Developers](https://developer.todoist.com/)
- [Todoist CLI and MCP guide](https://www.todoist.com/help/articles/use-claude-code-with-todoist-cli-and-mcp-b1USJ4HB3)

### Taskwarrior: local command model and annotations

- Tasks expose stable lifecycle fields such as status, start, end, entry, and
  modification time.
- Its command surface includes start, stop, annotate, modify, done, undo, export,
  and import.
- JSON export is explicitly intended as a machine-readable interface for other
  programs.

Sources:

- [Taskwarrior task representation](https://taskwarrior.org/docs/task/)
- [Taskwarrior commands](https://taskwarrior.org/docs/commands/)
- [Taskwarrior JSON export](https://taskwarrior.org/docs/commands/export/)
- [Taskwarrior third-party integration](https://taskwarrior.org/docs/3rd-party/)

### Meeting-to-action tools: keep provenance

- Granola combines transcript, raw notes, and calendar context, and exposes where
  an enhanced note came from.
- Granola recipes and similar meeting workflows extract decisions and action
  items from one or multiple meetings.
- Current meeting tools increasingly send action items to downstream task systems
  rather than treating a transcript as the final artifact.

Sources:

- [Granola AI-enhanced notes](https://docs.granola.ai/help-center/taking-notes/ai-enhanced-notes)
- [Granola recipes](https://docs.granola.ai/help-center/getting-more-from-your-notes/recipes)
- [Granola meeting chat](https://docs.granola.ai/help-center/getting-more-from-your-notes/chatting-with-your-meetings)
- [Notion AI Meeting Notes](https://www.notion.com/en-US/product/ai-meeting-notes)
- [Fireflies real-time action items](https://fireflies.ai/product/real-time)

## Current signals

### 1. Agent access is becoming a primary interface

Todoist now presents API, CLI, MCP, and webhook access together. The product
lesson is to give the agent a narrow, structured tool surface rather than let it
edit implementation files.

Recommended Morning Brief operations:

- `list_today`
- `get_work_item`
- `create_work_item`
- `transition_work_item`
- `append_progress`
- `query_recent_archive`
- `undo_change`

### 2. Local files remain valuable, but raw text is not enough

Obsidian demonstrates demand for local files, daily notes, CLI automation, and
agent-operated workflows. Its strengths are portability and inspectability.

Inference: Morning Brief should preserve those benefits through exported daily
Markdown/JSON views, while using a structured store and immutable events for
safe concurrent mutations.

Sources:

- [How Obsidian stores data](https://www.mintlify.com/obsidianmd/obsidian-help/files/how-obsidian-stores-data)
- [Obsidian CLI](https://obsidian.md/cli)
- [Obsidian changelog](https://obsidian.md/changelog/)

### 3. Agent authority increases the need for observability

MCP tools support structured input/output and annotations such as read-only,
destructive, and idempotent hints. The MCP specification also makes clear that
annotations are hints rather than enforcement.

Inference: granting the user's agent final judgment should not mean untraceable
mutation. Every change still needs an event, reason, evidence references,
timestamp, version, and recovery path.

Sources:

- [MCP tools specification](https://modelcontextprotocol.io/specification/draft/server/tools)
- [MCP schema reference](https://modelcontextprotocol.io/specification/2025-11-25/schema)
- [MCP tool annotations](https://blog.modelcontextprotocol.io/posts/2026-03-16-tool-annotations/)

## Patterns to borrow

1. **Capture first, structure later** — accept rough input during meetings.
2. **One recurring Today surface** — the user returns to the same daily ledger.
3. **Progress is appended, not overwritten** — intermediate information becomes
   timestamped events.
4. **Completion stays visible** — recent accomplishments are a first-class view,
   not a hidden database state.
5. **Agent operations are explicit** — structured commands, stable IDs, and
   machine-readable results.
6. **AI output carries evidence** — API object, meeting, or note references remain
   attached to the change.
7. **Autonomy remains reversible** — event history and undo protect against poor
   agent judgment without requiring a source-priority engine.

## Pitfalls to avoid

- Project, tag, priority, deadline, and calendar matrices in the MVP.
- A generic connector framework before one real workflow proves value.
- Direct concurrent edits to generated Markdown or `brief.json`.
- Treating cancellation as deletion.
- Hiding completed work in an inaccessible activity log.
- Letting an agent replace progress history with a new summary.
- Treating MCP annotations or natural-language confirmation as a safety boundary.
- Inventing owners, deadlines, or completion evidence that external inputs do not
  actually contain.

## Updated differentiation

No reviewed product combines all of these as its primary form:

- a quiet macOS menu-bar surface;
- a local daily work ledger;
- explicit pending / in-progress / completed / cancelled lifecycle;
- appendable progress and decision history;
- recent completion recall;
- autonomous local-agent mutations;
- arbitrary external evidence interpreted by the agent;
- inspectable and reversible changes.

That combination is sufficiently distinct to continue.

## Step 2 recommendation

Proceed to problem definition. Use the following product stance:

> Morning Brief Todo is not a lighter Todoist. It is a local daily evidence and
> action ledger whose human surface stays small while the user's agent can safely
> maintain rich, reversible work history behind it.
