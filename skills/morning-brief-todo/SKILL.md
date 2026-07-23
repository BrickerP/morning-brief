---
name: morning-brief-todo
description: Query and update the local Morning Brief work ledger through briefctl todo.
---

# Morning Brief Todo

Use this skill when work discovered in a meeting, an API, or another authorized
source should become part of the user's local work ledger.

## Rules

1. Read the current item and its `version` with `briefctl todo view` before
   changing an existing item.
2. Use the CLI only. Never edit SQLite or `work.json` directly.
3. The Agent may choose the resulting state. Explain that judgment with
   `--reason`, and attach each external reference with a separate `--evidence`.
4. Give externally triggered mutations a stable `--idempotency-key`. Repeating a
   successful command with the same key returns the original event instead of
   creating a duplicate.
5. Pass `--expected-version VERSION` when changing an existing item. If it
   conflicts, read the latest projection and reconsider the update.
6. Use `todo note` for progress, blockers, decisions, and next steps. Do not
   overwrite earlier progress.
7. Undo a mistaken mutation with its event ID. Undo appends a `reverted` event;
   it does not delete history.

## Commands

```text
briefctl todo view [--date YYYY-MM-DD] [--days 7]
briefctl todo add TITLE [--detail TEXT] [--actor human|agent|system]
  [--reason TEXT] [--evidence VALUE]... [--item-id ID]
  [--idempotency-key KEY]
briefctl todo edit ITEM_ID [--title TEXT] [--detail TEXT] [common mutation flags]
briefctl todo status ITEM_ID pending|in_progress|completed|cancelled
  [common mutation flags]
briefctl todo note ITEM_ID TEXT [common mutation flags]
briefctl todo undo EVENT_ID [--actor human|agent|system] [--reason TEXT]
  [--idempotency-key KEY] [--expected-version VERSION]
briefctl todo history [--date YYYY-MM-DD] [--days 7]
```

Common mutation flags are `--actor`, `--reason`, repeatable `--evidence`,
`--idempotency-key`, and `--expected-version`.

All stdout is JSON. Successful mutations return `event`, the resulting `item`,
and a `duplicate` boolean. `todo view` also atomically publishes the selected
day to:

```text
~/Library/Application Support/MorningBrief/briefs/YYYY-MM-DD/work.json
```

Each event includes a monotonically increasing `sequence`. Use it, rather than
wall-clock timestamps, when deciding which committed mutation happened last.

## External evidence example

```bash
briefctl todo status "$ITEM_ID" in_progress \
  --actor agent \
  --reason "API response shows an unresolved callback failure" \
  --evidence "api:callbacks/request-142" \
  --evidence "meeting:2026-07-23/payment-review" \
  --idempotency-key "callbacks-142-start-v1" \
  --expected-version 1
```

If new evidence contradicts a human note, do not silently erase the note. Append
the new evidence and reasoning, then make the status or detail change the Agent
judges appropriate. The event rail preserves both records and supports undo.
